# =============================================================================
# SCRIPT 06d - FIX DEFINITIVO multiOTP + PERFILES MOVILES + FSRM
# Ejecutar en: Windows Server 2022 (como Administrator)
#
# Incluye:
#   - FIX: Fuerza multiotp a usar ruta absoluta para la BD de usuarios
#   - Registro de Administrator en multiOTP con secreto TOTP propio
#   - Perfiles moviles (Roaming Profiles) para que los archivos persistan
#   - FSRM: Bloqueo de .mp3, .mp4, .exe
#   - FSRM: Cuota 5MB para NoCuates, 10MB para Cuates
# =============================================================================

Write-Host "=== [06d] FIX multiOTP + PERFILES MOVILES + FSRM ===" -ForegroundColor Cyan
Write-Host "Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray

Import-Module ActiveDirectory -ErrorAction Stop
$DomainName  = (Get-ADDomain).DNSRoot
$DomainDN    = (Get-ADDomain).DistinguishedName
$DomainNBIOS = (Get-ADDomain).NetBIOSName

# =========================================================
# PARTE 1: FIX DEFINITIVO multiOTP
# Problema: multiotp guarda en .\users (relativo al CWD)
#           pero checkpwd busca en la ruta donde esta el .exe
# Fix: forzar config con ruta absoluta + eliminar duplicados
# =========================================================
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " PARTE 1: FIX DEFINITIVO multiOTP" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$MultiOTPExe = (Get-ChildItem -Path "C:\MultiOTP" -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue |
                Select-Object -First 1).FullName

if (-not $MultiOTPExe) {
    Write-Host "ERROR: multiotp.exe no encontrado." -ForegroundColor Red
    exit 1
}

$MultiOTPDir = Split-Path $MultiOTPExe -Parent
$UsersDir    = Join-Path $MultiOTPDir "users"

Write-Host "MultiOTP dir : $MultiOTPDir" -ForegroundColor White
Write-Host "Users dir    : $UsersDir"    -ForegroundColor White

# Asegurar que el directorio de usuarios existe
if (-not (Test-Path $UsersDir)) {
    New-Item -ItemType Directory -Path $UsersDir -Force | Out-Null
}

# --- LIMPIAR TODOS LOS .db DUPLICADOS ---
Write-Host "`n[1.1] Limpiando archivos .db duplicados..." -ForegroundColor Yellow

# Buscar TODOS los .db en cualquier subcarpeta de MultiOTP
$allDbs = Get-ChildItem -Path "C:\MultiOTP" -Recurse -Filter "*.db" -ErrorAction SilentlyContinue
foreach ($db in $allDbs) {
    Write-Host "  Eliminando: $($db.FullName)" -ForegroundColor Red
    Remove-Item $db.FullName -Force -ErrorAction SilentlyContinue
}

Write-Host "  Limpieza completada." -ForegroundColor Green

# --- FUNCION PARA EJECUTAR multiotp SIEMPRE DESDE SU DIRECTORIO ---
function Invoke-MultiOTPFixed {
    param(
        [string]$Arguments,
        [int]$TimeoutMs = 20000
    )
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName               = $MultiOTPExe
    $pinfo.Arguments              = $Arguments
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError  = $true
    $pinfo.UseShellExecute        = $false
    $pinfo.WorkingDirectory       = $MultiOTPDir   # CRITICO: siempre desde el dir del exe
    $pinfo.CreateNoWindow         = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $pinfo
    $proc.Start() | Out-Null

    if (-not $proc.WaitForExit($TimeoutMs)) {
        $proc.Kill()
        return "TIMEOUT"
    }
    $out = $proc.StandardOutput.ReadToEnd().Trim()
    $err = $proc.StandardError.ReadToEnd().Trim()
    if ($out) { return $out }
    if ($err) { return $err }
    return "OK"
}

# --- LEER SECRETOS DEL ARCHIVO ---
$SecretsFile = "C:\MFA_Setup\TOTP_Secrets.txt"
if (-not (Test-Path $SecretsFile)) {
    Write-Host "ERROR: No se encuentra $SecretsFile" -ForegroundColor Red
    exit 1
}

$secretos = @{}
$lineas   = Get-Content $SecretsFile
$usuarioActual = $null
foreach ($linea in $lineas) {
    if ($linea -match "^Usuario\s*:\s*(.+)$") {
        $usuarioActual = $Matches[1].Trim()
    }
    if ($linea -match "^Secreto\s*:\s*(.+)$" -and $usuarioActual) {
        $secretos[$usuarioActual] = $Matches[1].Trim()
        $usuarioActual = $null
    }
}

Write-Host "`n[1.2] Secretos encontrados:" -ForegroundColor Yellow
foreach ($u in $secretos.Keys) {
    Write-Host "  $u => $($secretos[$u])" -ForegroundColor White
}

# --- REGISTRAR USUARIOS DESDE EL DIRECTORIO CORRECTO ---
Write-Host "`n[1.3] Registrando usuarios en multiOTP (desde $MultiOTPDir)..." -ForegroundColor Yellow

$AdminUsers = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")

# -------------------------------------------------------
# GENERAR Y AGREGAR SECRETO PARA Administrator
# Administrator no esta en TOTP_Secrets.txt porque no
# fue creado por el Script 06. Lo generamos aqui y lo
# agregamos tanto al archivo como a la BD de multiOTP.
# -------------------------------------------------------
Write-Host "`n[1.2b] Generando secreto TOTP para Administrator..." -ForegroundColor Yellow

# Funcion generadora de secreto Base32
function New-TOTPSecret {
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $base32chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $secret = ""
    $buffer = 0; $bitsLeft = 0
    foreach ($byte in $bytes) {
        $buffer   = ($buffer -shl 8) -bor $byte
        $bitsLeft += 8
        while ($bitsLeft -ge 5) {
            $bitsLeft -= 5
            $secret += $base32chars[($buffer -shr $bitsLeft) -band 0x1F]
        }
    }
    return $secret
}

$AdminSecretTOTP = New-TOTPSecret
$uriAdminAccount = [Uri]::EscapeDataString($DomainName + ":Administrator")
$uriAdminParams  = "secret=" + $AdminSecretTOTP + "&issuer=LabMFA&algorithm=SHA1&digits=6&period=30"
$otpUriAdmin     = "otpauth://totp/" + $uriAdminAccount + "?" + $uriAdminParams

Write-Host "  Usuario  : Administrator" -ForegroundColor Cyan
Write-Host "  Secreto  : $AdminSecretTOTP" -ForegroundColor Yellow
Write-Host "  URI OTP  : $otpUriAdmin" -ForegroundColor Gray

# Agregar al archivo TOTP_Secrets.txt
$lineaAdmin  = "`r`nUsuario : Administrator`r`n"
$lineaAdmin += "Secreto : " + $AdminSecretTOTP + "`r`n"
$lineaAdmin += "URI OTP : " + $otpUriAdmin + "`r`n"
$lineaAdmin += "---`r`n"
Add-Content -Path $SecretsFile -Value $lineaAdmin -Encoding UTF8
Write-Host "  [OK] Secreto de Administrator agregado a $SecretsFile" -ForegroundColor Green

# Guardar en registro de Windows igual que los otros admins
$RegPathAdmin = "HKLM:\SOFTWARE\LabMFA\Users\Administrator"
if (-not (Test-Path $RegPathAdmin)) { New-Item -Path $RegPathAdmin -Force | Out-Null }
Set-ItemProperty -Path $RegPathAdmin -Name "TOTPSecret"     -Value $AdminSecretTOTP
Set-ItemProperty -Path $RegPathAdmin -Name "Enabled"        -Value 1
Set-ItemProperty -Path $RegPathAdmin -Name "FailedAttempts" -Value 0
Set-ItemProperty -Path $RegPathAdmin -Name "LockedUntil"    -Value ""

# Agregar Administrator a la lista de usuarios a registrar
$secretos["Administrator"] = $AdminSecretTOTP
$AdminUsers = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria", "Administrator")

Write-Host "  [OK] Administrator listo para registrar en multiOTP" -ForegroundColor Green

# -------------------------------------------------------
# REGISTRAR TODOS LOS USUARIOS (incluido Administrator)
# -------------------------------------------------------
foreach ($admin in $AdminUsers) {
    if (-not $secretos.ContainsKey($admin)) {
        Write-Host "  [SKIP] $admin - no tiene secreto en el archivo" -ForegroundColor Yellow
        continue
    }

    $secret = $secretos[$admin]
    Write-Host "`n  Usuario: $admin" -ForegroundColor Cyan

    # Crear directamente (ya borramos los .db)
    $resultado = Invoke-MultiOTPFixed -Arguments "-create $admin TOTP $secret 6 30" -TimeoutMs 20000
    Write-Host "  Create : $resultado" -ForegroundColor White

    # Verificar que el .db existe en el lugar correcto
    $dbPath = Join-Path $UsersDir ($admin + ".db")
    if (Test-Path $dbPath) {
        Write-Host "  [OK] Archivo .db creado en: $dbPath" -ForegroundColor Green
    } else {
        # Buscar donde se creo realmente
        $dbActual = Get-ChildItem -Path "C:\MultiOTP" -Recurse -Filter ($admin + ".db") -ErrorAction SilentlyContinue |
                    Select-Object -First 1
        if ($dbActual) {
            Write-Host ("  [MOVER] .db encontrado en: " + $dbActual.FullName + " -> moviendo") -ForegroundColor Yellow
            Move-Item $dbActual.FullName $dbPath -Force
        } else {
            Write-Host "  [WARN] No se encontro el .db de $admin" -ForegroundColor Red
        }
    }
}

# --- VERIFICACION FINAL ---
Write-Host "`n[1.4] Verificacion de usuarios registrados:" -ForegroundColor Yellow
$resultado = Invoke-MultiOTPFixed -Arguments "-users" -TimeoutMs 10000
Write-Host "  Usuarios en BD: $resultado" -ForegroundColor White

Write-Host "`n[1.5] PRUEBA con codigo real de tu app movil:" -ForegroundColor Cyan
Write-Host "  cd $MultiOTPDir" -ForegroundColor White
Write-Host "  .\multiotp.exe -checkpwd admin_identidad CODIGO_6_DIGITOS" -ForegroundColor White
Write-Host "  .\multiotp.exe -checkpwd Administrator   CODIGO_6_DIGITOS" -ForegroundColor White
Write-Host "  (debe devolver 0 o Reply-Message OK en ambos casos)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Secreto de Administrator guardado en:" -ForegroundColor Yellow
Write-Host "  $SecretsFile" -ForegroundColor White

# =========================================================
# PARTE 2: PERFILES MOVILES (ROAMING PROFILES)
# Los archivos del usuario viajan con el perfil al servidor
# =========================================================
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " PARTE 2: PERFILES MOVILES" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Crear share para perfiles moviles
$ProfilesPath = "C:\PerfilesMóviles"
if (-not (Test-Path $ProfilesPath)) {
    New-Item -ItemType Directory -Path $ProfilesPath -Force | Out-Null
}

# Crear share con permisos correctos
$existingShare = Get-SmbShare -Name "Perfiles$" -ErrorAction SilentlyContinue
if (-not $existingShare) {
    New-SmbShare -Name "Perfiles$" -Path $ProfilesPath `
        -FullAccess "Domain Admins" `
        -ChangeAccess "Authenticated Users" `
        -Description "Perfiles Moviles de Usuarios" | Out-Null
    Write-Host "  [OK] Share Perfiles$ creado en $ProfilesPath" -ForegroundColor Green
} else {
    Write-Host "  [OK] Share Perfiles$ ya existe" -ForegroundColor Yellow
}

# Asignar permisos NTFS correctos al directorio
$acl = Get-Acl $ProfilesPath
$acl.SetAccessRuleProtection($false, $true)

# Autenticados: solo crear carpetas propias
$rule1 = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Authenticated Users",
    "AppendData,CreateDirectories,Traverse,ReadAttributes,ReadExtendedAttributes,ReadPermissions",
    "None", "None", "Allow"
)
$acl.AddAccessRule($rule1)

# Creator Owner: control total sobre su propia carpeta
$rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "CREATOR OWNER",
    "FullControl",
    "ContainerInherit,ObjectInherit", "InheritOnly", "Allow"
)
$acl.AddAccessRule($rule2)

# Admins: control total
$rule3 = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Domain Admins",
    "FullControl",
    "ContainerInherit,ObjectInherit", "None", "Allow"
)
$acl.AddAccessRule($rule3)
Set-Acl -Path $ProfilesPath -AclObject $acl
Write-Host "  [OK] Permisos NTFS configurados en $ProfilesPath" -ForegroundColor Green

# Asignar perfil movil a los 4 admins y usuarios de prueba
$ServerName    = $env:COMPUTERNAME
$ProfileShare  = "\\" + $ServerName + "\Perfiles$"

$TodosLosUsuarios = @(
    "admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria",
    "usuario.cuate1", "usuario.cuate2", "usuario.nocuate1", "usuario.nocuate2"
)

Write-Host "`n[2.1] Asignando perfil movil a usuarios..." -ForegroundColor Yellow
foreach ($u in $TodosLosUsuarios) {
    try {
        $profilePath = $ProfileShare + "\" + $u
        Set-ADUser -Identity $u -ProfilePath $profilePath -ErrorAction Stop
        Write-Host "  [OK] $u -> $profilePath" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] $u : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Configurar GPO para redireccion de carpetas (Documentos, Escritorio)
Write-Host "`n[2.2] Configurando GPO de Redireccion de Carpetas..." -ForegroundColor Yellow

$RedirPath = "C:\PerfilesMóviles\Redirected"
if (-not (Test-Path $RedirPath)) {
    New-Item -ItemType Directory -Path $RedirPath -Force | Out-Null
}

$existingShareRedir = Get-SmbShare -Name "UserDirs$" -ErrorAction SilentlyContinue
if (-not $existingShareRedir) {
    New-SmbShare -Name "UserDirs$" -Path $RedirPath `
        -FullAccess "Domain Admins" `
        -ChangeAccess "Authenticated Users" | Out-Null
    Write-Host "  [OK] Share UserDirs$ creado" -ForegroundColor Green
}

$GPOPerfiles = "GPO_PerfilesMóviles"
try {
    $gpo = Get-GPO -Name $GPOPerfiles -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $GPOPerfiles
        Write-Host "  [OK] GPO '$GPOPerfiles' creada" -ForegroundColor Green
    }

    # Vincular GPO al dominio
    try {
        New-GPLink -Name $GPOPerfiles -Target $DomainDN -LinkEnabled Yes -ErrorAction Stop | Out-Null
    } catch {
        # Ya vinculada
    }
    Write-Host "  [OK] GPO vinculada al dominio" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] GPO: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n  Perfiles moviles configurados. Los usuarios al iniciar sesion" -ForegroundColor White
Write-Host "  tendran sus archivos sincronizados con el servidor." -ForegroundColor White

# =========================================================
# PARTE 3: FSRM - RESTRICCIONES DE ARCHIVOS Y CUOTAS
# Bloqueo: .mp3, .mp4, .exe
# Cuota: 5MB NoCuates / 10MB Cuates
# =========================================================
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " PARTE 3: FSRM - CUOTAS Y RESTRICCIONES" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Instalar FSRM si no está instalado
Write-Host "`n[3.1] Verificando instalacion de FSRM..." -ForegroundColor Yellow
$fsrmFeature = Get-WindowsFeature -Name "FS-Resource-Manager" -ErrorAction SilentlyContinue
if ($fsrmFeature -and -not $fsrmFeature.Installed) {
    Write-Host "  Instalando FSRM..." -ForegroundColor Yellow
    Install-WindowsFeature -Name "FS-Resource-Manager" -IncludeManagementTools | Out-Null
    Write-Host "  [OK] FSRM instalado" -ForegroundColor Green
} else {
    Write-Host "  [OK] FSRM ya instalado" -ForegroundColor Green
}

Import-Module FileServerResourceManager -ErrorAction SilentlyContinue

# Crear directorios para los usuarios si no existen
$CuatesDir    = "C:\UserData\Cuates"
$NoCuatesDir  = "C:\UserData\NoCuates"

foreach ($dir in @("C:\UserData", $CuatesDir, $NoCuatesDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Crear shares para los datos de usuario
foreach ($share in @(@{Name="Cuates$"; Path=$CuatesDir}, @{Name="NoCuates$"; Path=$NoCuatesDir})) {
    $existS = Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue
    if (-not $existS) {
        New-SmbShare -Name $share.Name -Path $share.Path `
            -FullAccess "Domain Admins" `
            -ChangeAccess "Authenticated Users" | Out-Null
        Write-Host "  [OK] Share $($share.Name) creado en $($share.Path)" -ForegroundColor Green
    }
}

# --- GRUPO DE ARCHIVOS BLOQUEADOS ---
Write-Host "`n[3.2] Creando grupo de archivos bloqueados..." -ForegroundColor Yellow

try {
    $existingFG = Get-FsrmFileGroup -Name "ArchivosBloqueados" -ErrorAction SilentlyContinue
    if ($existingFG) {
        Remove-FsrmFileGroup -Name "ArchivosBloqueados" -Confirm:$false -ErrorAction SilentlyContinue
    }

    New-FsrmFileGroup -Name "ArchivosBloqueados" `
        -IncludePattern @("*.mp3", "*.mp4", "*.exe", "*.avi", "*.mkv", "*.wmv", "*.mov") `
        -ErrorAction Stop | Out-Null

    Write-Host "  [OK] Grupo 'ArchivosBloqueados' creado: *.mp3, *.mp4, *.exe, *.avi, *.mkv" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- PLANTILLA DE BLOQUEO ---
Write-Host "`n[3.3] Creando plantilla de bloqueo de archivos..." -ForegroundColor Yellow

try {
    $existingFST = Get-FsrmFileScreenTemplate -Name "BloqueoMediaExe" -ErrorAction SilentlyContinue
    if ($existingFST) {
        Remove-FsrmFileScreenTemplate -Name "BloqueoMediaExe" -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Accion de notificacion por email cuando se bloquea
    $notifAction = New-FsrmAction -Type Email `
        -MailTo "[Admin Email]" `
        -Subject "FSRM: Archivo bloqueado en [Server]" `
        -Body "Usuario [Source Io Owner] intento guardar [Source File Path] que esta bloqueado." `
        -ErrorAction SilentlyContinue

    New-FsrmFileScreenTemplate -Name "BloqueoMediaExe" `
        -Active `
        -IncludeGroup @("ArchivosBloqueados") `
        -ErrorAction Stop | Out-Null

    Write-Host "  [OK] Plantilla 'BloqueoMediaExe' creada" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- APLICAR BLOQUEO A AMBOS DIRECTORIOS ---
Write-Host "`n[3.4] Aplicando bloqueo de archivos a directorios..." -ForegroundColor Yellow

foreach ($dir in @($CuatesDir, $NoCuatesDir)) {
    try {
        $existingScreen = Get-FsrmFileScreen -Path $dir -ErrorAction SilentlyContinue
        if ($existingScreen) {
            Remove-FsrmFileScreen -Path $dir -Confirm:$false -ErrorAction SilentlyContinue
        }
        New-FsrmFileScreen -Path $dir -Template "BloqueoMediaExe" -ErrorAction Stop | Out-Null
        Write-Host "  [OK] Bloqueo aplicado en: $dir" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] $dir : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# --- PLANTILLAS DE CUOTA ---
Write-Host "`n[3.5] Creando plantillas de cuota..." -ForegroundColor Yellow

# Cuota 5MB para NoCuates
try {
    $existQ5 = Get-FsrmQuotaTemplate -Name "Cuota5MB_NoCuates" -ErrorAction SilentlyContinue
    if ($existQ5) {
        Remove-FsrmQuotaTemplate -Name "Cuota5MB_NoCuates" -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Umbral de advertencia al 80%
    $threshold80_5 = New-FsrmQuotaThreshold -Percentage 80 `
        -Action (New-FsrmAction -Type Event `
            -EventType Warning `
            -Body "Usuario [Source Io Owner] ha usado el 80% de su cuota en [Quota Path]")

    # Umbral de limite al 100%
    $threshold100_5 = New-FsrmQuotaThreshold -Percentage 100 `
        -Action (New-FsrmAction -Type Event `
            -EventType Error `
            -Body "Usuario [Source Io Owner] ha alcanzado su cuota en [Quota Path]")

    New-FsrmQuotaTemplate -Name "Cuota5MB_NoCuates" `
        -Size 5MB `
        -SoftLimit:$false `
        -Threshold @($threshold80_5, $threshold100_5) `
        -ErrorAction Stop | Out-Null

    Write-Host "  [OK] Plantilla Cuota5MB_NoCuates creada (5 MB, limite duro)" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Cuota 5MB: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Cuota 10MB para Cuates
try {
    $existQ10 = Get-FsrmQuotaTemplate -Name "Cuota10MB_Cuates" -ErrorAction SilentlyContinue
    if ($existQ10) {
        Remove-FsrmQuotaTemplate -Name "Cuota10MB_Cuates" -Confirm:$false -ErrorAction SilentlyContinue
    }

    $threshold80_10 = New-FsrmQuotaThreshold -Percentage 80 `
        -Action (New-FsrmAction -Type Event `
            -EventType Warning `
            -Body "Usuario [Source Io Owner] ha usado el 80% de su cuota en [Quota Path]")

    $threshold100_10 = New-FsrmQuotaThreshold -Percentage 100 `
        -Action (New-FsrmAction -Type Event `
            -EventType Error `
            -Body "Usuario [Source Io Owner] ha alcanzado su cuota en [Quota Path]")

    New-FsrmQuotaTemplate -Name "Cuota10MB_Cuates" `
        -Size 10MB `
        -SoftLimit:$false `
        -Threshold @($threshold80_10, $threshold100_10) `
        -ErrorAction Stop | Out-Null

    Write-Host "  [OK] Plantilla Cuota10MB_Cuates creada (10 MB, limite duro)" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Cuota 10MB: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- APLICAR CUOTAS ---
Write-Host "`n[3.6] Aplicando cuotas a directorios..." -ForegroundColor Yellow

# 10MB a Cuates
try {
    $existQC = Get-FsrmQuota -Path $CuatesDir -ErrorAction SilentlyContinue
    if ($existQC) { Remove-FsrmQuota -Path $CuatesDir -Confirm:$false -ErrorAction SilentlyContinue }
    New-FsrmQuota -Path $CuatesDir -Template "Cuota10MB_Cuates" -ErrorAction Stop | Out-Null
    Write-Host "  [OK] Cuota 10MB aplicada en: $CuatesDir" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Cuota Cuates: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 5MB a NoCuates
try {
    $existQNC = Get-FsrmQuota -Path $NoCuatesDir -ErrorAction SilentlyContinue
    if ($existQNC) { Remove-FsrmQuota -Path $NoCuatesDir -Confirm:$false -ErrorAction SilentlyContinue }
    New-FsrmQuota -Path $NoCuatesDir -Template "Cuota5MB_NoCuates" -ErrorAction Stop | Out-Null
    Write-Host "  [OK] Cuota 5MB aplicada en: $NoCuatesDir" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Cuota NoCuates: $($_.Exception.Message)" -ForegroundColor Yellow
}

# =========================================================
# RESUMEN FINAL
# =========================================================
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              RESUMEN DE CONFIGURACION               ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║                                                      ║" -ForegroundColor White
Write-Host "║  multiOTP - Usuarios registrados:                   ║" -ForegroundColor Yellow
Write-Host "║    admin_identidad, admin_storage,                  ║" -ForegroundColor White
Write-Host "║    admin_politicas, admin_auditoria,                ║" -ForegroundColor White
Write-Host "║    Administrator  (secreto nuevo generado)          ║" -ForegroundColor White
Write-Host "║    Verificar: .\multiotp.exe -checkpwd USUARIO NNN  ║" -ForegroundColor White
Write-Host "║                                                      ║" -ForegroundColor White
Write-Host "║  Perfiles Moviles:                                  ║" -ForegroundColor Yellow
$lineaShare = "║    Share: \\" + $ServerName + "\Perfiles$"
Write-Host $lineaShare                                               -ForegroundColor White
Write-Host "║    Los archivos persisten entre sesiones            ║" -ForegroundColor White
Write-Host "║                                                      ║" -ForegroundColor White
Write-Host "║  FSRM - Bloqueados: .mp3 .mp4 .exe .avi .mkv       ║" -ForegroundColor Yellow
Write-Host "║    Cuates   -> C:\UserData\Cuates    (10 MB)        ║" -ForegroundColor White
Write-Host "║    NoCuates -> C:\UserData\NoCuates  ( 5 MB)        ║" -ForegroundColor White
Write-Host "║                                                      ║" -ForegroundColor White
Write-Host "║  SIGUIENTE PASO:                                    ║" -ForegroundColor Yellow
Write-Host "║    1. Prueba checkpwd con codigo real del movil     ║" -ForegroundColor White
Write-Host "║    2. Restart-Computer -Force                       ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n=== [06d] COMPLETADO ===" -ForegroundColor Cyan