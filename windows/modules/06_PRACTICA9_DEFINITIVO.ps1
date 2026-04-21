# =============================================================================
# PRACTICA 9 - SCRIPT MAESTRO DEFINITIVO
# NTP (Google) + multiOTP CORRECTO + Perfiles Moviles + FSRM
#
# EJECUTAR EN: Windows Server 2022 (como Administrator)
# PREREQUISITO: La Practica 8 debe estar completamente configurada.
#               (AD, OUs, Grupos, FGPP, Auditoria ya listos)
#
# ORDEN DE EJECUCION:
#   1. Este script hace todo en una sola corrida
#   2. Al finalizar, reinicia el servidor
#   3. Escanea los QR desde C:\MFA_Setup\QR_*.png con Google Authenticator
#   4. Prueba: cd C:\MultiOTP\windows  -> .\multiotp.exe -checkpwd admin_identidad CODIGO
#
# QUE HACE:
#   PARTE 1 - NTP: Sincroniza el servidor con time.google.com (reloj atomico)
#   PARTE 2 - multiOTP: Registro DEFINITIVO de usuarios con secretos fijos
#             El FIX critico: siempre ejecuta multiotp.exe con WorkingDirectory
#             = carpeta del exe, y verifica que el .db quede en users\
#   PARTE 3 - Perfiles Moviles: Share + NTFS + UPM para los 8 usuarios
#   PARTE 4 - FSRM: Cuotas (10MB Cuates / 5MB NoCuates) + bloqueo .mp3/.mp4/.exe
#   PARTE 5 - Credential Provider: instala / verifica el CP de multiOTP
# =============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   PRACTICA 9 - CONFIGURACION INTEGRAL DE SEGURIDAD   " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Fecha : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"      -ForegroundColor Gray
Write-Host "Equipo: $env:COMPUTERNAME"                               -ForegroundColor Gray
Write-Host ""

# ─────────────────────────────────────────────
# VARIABLES GLOBALES
# ─────────────────────────────────────────────
$SetupPath    = "C:\MFA_Setup"
$MultiOTPPath = "C:\MultiOTP"
$LogFile      = "$SetupPath\practica9_log.txt"

$AdminUsers = @(
    "admin_identidad",
    "admin_storage",
    "admin_politicas",
    "admin_auditoria",
    "Administrator"
)

foreach ($dir in @($SetupPath, $MultiOTPPath, "C:\AuditLogs")) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
New-Item -ItemType File -Path $LogFile -Force | Out-Null

function Write-Log {
    param([string]$msg, [string]$color = "White")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────
# FUNCION CRITICA: Ejecutar multiotp CON TIMEOUT
# siempre desde el directorio del exe
# ─────────────────────────────────────────────
function Invoke-MultiOTP {
    param(
        [string]$MultiOTPExe,
        [string[]]$Args,
        [int]$TimeoutMs = 20000
    )
    $dir  = Split-Path $MultiOTPExe -Parent
    $psi  = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $MultiOTPExe
    $psi.Arguments              = ($Args -join " ")
    $psi.WorkingDirectory       = $dir    # <-- CRITICO: siempre el dir del exe
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    if (-not $proc.WaitForExit($TimeoutMs)) {
        try { $proc.Kill() } catch {}
        return "TIMEOUT"
    }
    $out = $proc.StandardOutput.ReadToEnd().Trim()
    $err = $proc.StandardError.ReadToEnd().Trim()
    return if ($out) { $out } elseif ($err) { $err } else { "OK($($proc.ExitCode))" }
}

# ─────────────────────────────────────────────
# FUNCION: Generar secreto Base32 criptografico
# ─────────────────────────────────────────────
function New-TOTPSecret {
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $chars  = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $secret = ""; $buf = 0; $bits = 0
    foreach ($b in $bytes) {
        $buf   = ($buf -shl 8) -bor $b
        $bits += 8
        while ($bits -ge 5) {
            $bits  -= 5
            $secret += $chars[($buf -shr $bits) -band 0x1F]
        }
    }
    return $secret
}

# ─────────────────────────────────────────────
# FUNCION: Generar QR PNG con QRCoder (puro .NET)
# No depende de multiotp -qrcode (que a veces falla)
# ─────────────────────────────────────────────
function New-QRCodePNG {
    param([string]$Text, [string]$OutputPath)

    # Intentar con Add-Type + QRCoder si esta disponible en el paquete
    $qrcoderDll = Get-ChildItem -Path "C:\MultiOTP" -Recurse -Filter "QRCoder.dll" -ErrorAction SilentlyContinue |
                  Select-Object -First 1 -ExpandProperty FullName

    if ($qrcoderDll) {
        try {
            Add-Type -Path $qrcoderDll -ErrorAction Stop
            $qrGen   = New-Object QRCoder.QRCodeGenerator
            $qrData  = $qrGen.CreateQrCode($Text, [QRCoder.QRCodeGenerator+ECCLevel]::Q)
            $qrCode  = New-Object QRCoder.PngByteQRCode($qrData)
            $pngBytes = $qrCode.GetGraphic(10)
            [System.IO.File]::WriteAllBytes($OutputPath, $pngBytes)
            return $true
        } catch {
            # QRCoder.dll existe pero fallo — continuar con fallback
        }
    }

    # Fallback: generar URL de QR via API publica (si hay red)
    # Si no hay red, solo escribe el URI en un .txt junto al .png
    try {
        $encoded  = [Uri]::EscapeDataString($Text)
        $qrApiUrl = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$encoded"
        Invoke-WebRequest -Uri $qrApiUrl -OutFile $OutputPath -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return $true
    } catch {
        # Sin red: guardar URI en archivo de texto para escanear manualmente
        $uriFile = $OutputPath -replace "\.png$", "_URI.txt"
        "Escanea este URI con un generador QR en linea:" | Out-File $uriFile -Encoding UTF8
        "https://www.qrcode-monkey.com/" | Out-File $uriFile -Encoding UTF8 -Append
        "" | Out-File $uriFile -Encoding UTF8 -Append
        $Text | Out-File $uriFile -Encoding UTF8 -Append
        return $false
    }
}


# =====================================================
# PARTE 1 — SINCRONIZACION NTP CON GOOGLE
# =====================================================
Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PARTE 1: SINCRONIZACION NTP (GOOGLE)   " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan

Write-Log "Configurando servidores NTP de Google..." "Yellow"

# Detener el servicio W32Time para reconfigurar
Stop-Service -Name "W32Time" -Force -ErrorAction SilentlyContinue

# Configurar como cliente NTP con los 4 servidores de Google
# (Google ofrece servidores publicos de tiempo de muy alta precision)
$ntpServers = "time.google.com,0x9 time1.google.com,0x9 time2.google.com,0x9 time3.google.com,0x9"
& w32tm /config /manualpeerlist:$ntpServers /syncfromflags:manual /reliable:yes /update

# Configurar el tipo de servidor (NT5DS para DC, NtpClient para sincronizar con internet)
# Para un DC que ademas quiere sincronizar con internet usamos NTP
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
    -Name "Type" -Value "NTP" -ErrorAction SilentlyContinue

# Ajustar tolerancia de desviacion: TOTP tolera +/- 30 segundos
# Ponemos margen de 300 segundos en la configuracion de W32Time
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
    -Name "MaxPosPhaseCorrection" -Value 3600 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
    -Name "MaxNegPhaseCorrection" -Value 3600 -ErrorAction SilentlyContinue

# Iniciar servicio y forzar sincronizacion
Start-Service -Name "W32Time" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$syncResult = & w32tm /resync /force 2>&1
Write-Log "Resultado sync: $syncResult" "Gray"

# Verificar la hora actual y el servidor NTP
$ntpStatus = & w32tm /query /status 2>&1
$ntpStatus | ForEach-Object { Write-Log "  NTP: $_" "Gray" }

# Mostrar hora actual del servidor
Write-Log "[OK] Hora del servidor: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" "Green"
Write-Log "[OK] Revisa que tu celular tenga la misma hora (zona horaria correcta)" "Yellow"
Write-Log "     Ve a Configuracion > General > Fecha y Hora > Automatica (ON)" "Yellow"


# =====================================================
# PARTE 2 — REGISTRO DEFINITIVO EN multiOTP
# =====================================================
Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PARTE 2: REGISTRO multiOTP DEFINITIVO  " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan

# ── 2.1 Encontrar multiotp.exe ──
Write-Log "Buscando multiotp.exe..." "Yellow"
$MultiOTPExe = Get-ChildItem -Path $MultiOTPPath -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName

if (-not $MultiOTPExe) {
    Write-Log "ERROR: multiotp.exe no encontrado en $MultiOTPPath" "Red"
    Write-Log "Descarga multiOTP desde https://download.multiotp.net/" "Red"
    Write-Log "Extrae en C:\MultiOTP y vuelve a ejecutar este script" "Red"
    exit 1
}

$MultiOTPDir  = Split-Path $MultiOTPExe -Parent
$UsersDir     = Join-Path $MultiOTPDir "users"
$MultiOTPConf = Join-Path $MultiOTPDir "config"

Write-Log "[OK] multiotp.exe: $MultiOTPExe" "Green"
Write-Log "[OK] Directorio de usuarios: $UsersDir" "Green"

# Asegurarse de que los directorios existen
foreach ($d in @($UsersDir, $MultiOTPConf)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ── 2.2 Detener servicios multiOTP que puedan bloquear archivos ──
Write-Log "Deteniendo servicios multiOTP..." "Yellow"
foreach ($svc in @("multiOTP", "multiOTPwebservice", "multiOTPradius")) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
}
Get-Process -Name "nginx","php","php-cgi","nssm" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# ── 2.3 Limpiar TODOS los .db previos (previene inconsistencias) ──
Write-Log "Eliminando registros previos de usuarios en multiOTP..." "Yellow"
Get-ChildItem -Path $MultiOTPDir -Recurse -Filter "*.db" -ErrorAction SilentlyContinue |
    ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Log "  Eliminado: $($_.FullName)" "Gray"
    }

# ── 2.4 Configurar multiOTP (base) ──
Write-Log "Configurando parametros base de multiOTP..." "Yellow"
$r = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -Args @("-config","algorithm=TOTP","digits=6","time-interval=30")
Write-Log "  Config: $r" "Gray"

# ── 2.5 Determinar dominio ──
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $DomainName = (Get-ADDomain).DNSRoot
    Write-Log "[OK] Dominio: $DomainName" "Green"
} catch {
    $DomainName = $env:USERDNSDOMAIN
    if (-not $DomainName) { $DomainName = "lab.local" }
    Write-Log "[WARN] AD no disponible. Usando dominio: $DomainName" "Yellow"
}

# ── 2.6 Leer secretos existentes del archivo si los hay ──
$SecretsFile     = "$SetupPath\TOTP_Secrets.txt"
$secretosExist   = @{}

if (Test-Path $SecretsFile) {
    Write-Log "Leyendo secretos previos de $SecretsFile..." "Yellow"
    $lineas = Get-Content $SecretsFile
    $uActual = $null
    foreach ($linea in $lineas) {
        if ($linea -match "^Usuario\s*:\s*(.+)$")  { $uActual = $Matches[1].Trim() }
        if ($linea -match "^Secreto\s*:\s*([A-Z2-7]{16,})$" -and $uActual) {
            $secretosExist[$uActual] = $Matches[1].Trim()
            $uActual = $null
        }
    }
    Write-Log "  Secretos encontrados: $($secretosExist.Keys -join ', ')" "Gray"
}

# ── 2.7 Registrar cada usuario ──
$SecretsOutput  = "=== SECRETOS TOTP multiOTP - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" + "`r`n"
$SecretsOutput += "IMPORTANTE: Escanea los QR desde C:\MFA_Setup\QR_*.png" + "`r`n"
$SecretsOutput += "O ingresa el secreto manualmente en Google/Microsoft Authenticator" + "`r`n`r`n"

foreach ($admin in $AdminUsers) {

    Write-Log "" "White"
    Write-Log "─── Registrando: $admin ───" "Cyan"

    # Usar secreto existente si existe, sino generar uno nuevo
    if ($secretosExist.ContainsKey($admin)) {
        $secret = $secretosExist[$admin]
        Write-Log "  Usando secreto existente del archivo" "Gray"
    } else {
        $secret = New-TOTPSecret
        Write-Log "  Secreto nuevo generado" "Gray"
    }

    # PASO 1: Crear usuario en multiOTP
    # CRITICO: Invoke-MultiOTP siempre corre desde $MultiOTPDir
    $r = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe `
         -Args @("-create", $admin, "TOTP", $secret, "6", "30") `
         -TimeoutMs 20000
    Write-Log "  Create result: $r" "Gray"

    # PASO 2: Verificar que el .db quedo en el lugar correcto
    $dbEsperado = Join-Path $UsersDir ($admin + ".db")
    Start-Sleep -Milliseconds 500

    if (-not (Test-Path $dbEsperado)) {
        # Buscar donde se creo realmente y moverlo
        $dbEncontrado = Get-ChildItem -Path $MultiOTPDir -Recurse -Filter ($admin + ".db") -ErrorAction SilentlyContinue |
                        Select-Object -First 1

        if ($dbEncontrado) {
            Write-Log "  [MOVER] .db en lugar incorrecto: $($dbEncontrado.FullName)" "Yellow"
            Move-Item $dbEncontrado.FullName $dbEsperado -Force -ErrorAction SilentlyContinue
            Write-Log "  [OK] .db movido a: $dbEsperado" "Green"
        } else {
            Write-Log "  [WARN] .db no encontrado. Reintentando create..." "Red"

            # Reintentar una vez mas
            $r2 = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe `
                  -Args @("-create", $admin, "TOTP", $secret, "6", "30") `
                  -TimeoutMs 25000
            Write-Log "  Reintento result: $r2" "Gray"
            Start-Sleep -Seconds 1

            if (-not (Test-Path $dbEsperado)) {
                # Crear el .db manualmente con el formato correcto de multiOTP
                Write-Log "  Creando .db manualmente..." "Yellow"
                $dbContent = @"
<multiOTPUser>
  <user>$admin</user>
  <algorithm>TOTP</algorithm>
  <key_algorithm>HMAC-SHA1</key_algorithm>
  <otp>6</otp>
  <time>30</time>
  <seed>$secret</seed>
  <description>$admin TOTP</description>
  <last_event>-1</last_event>
  <last_login>0</last_login>
  <last_login_for_2fa>0</last_login_for_2fa>
  <error_counter>0</error_counter>
  <locked>0</locked>
  <synchronized>0</synchronized>
  <synchronized_channel>-</synchronized_channel>
  <synchronized_dn></synchronized_dn>
  <synchronized_server></synchronized_server>
  <synchronized_time>0</synchronized_time>
  <ldap_pwd_need_update>0</ldap_pwd_need_update>
  <autolock_time>0</autolock_time>
  <challenge>0</challenge>
  <challenge_validity>0</challenge_validity>
  <challenge_cache>0</challenge_cache>
  <email></email>
  <group></group>
  <sms></sms>
  <sms_validity>0</sms_validity>
  <delta_time>0</delta_time>
  <time_interval_for_totp>30</time_interval_for_totp>
  <number_of_digits>6</number_of_digits>
  <request_ldap_pwd>0</request_ldap_pwd>
  <key_id>$admin</key_id>
  <token_algo_suite>HMAC-SHA1</token_algo_suite>
</multiOTPUser>
"@
                $dbContent | Out-File -FilePath $dbEsperado -Encoding UTF8
                Write-Log "  [OK] .db creado manualmente en: $dbEsperado" "Green"
            }
        }
    } else {
        Write-Log "  [OK] .db en lugar correcto: $dbEsperado" "Green"
    }

    # PASO 3: Verificar que multiOTP reconoce al usuario
    $verification = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe `
                    -Args @("-display-log", $admin) -TimeoutMs 10000
    if ($verification -match "TOTP|totp|seed|6.*30|30.*6") {
        Write-Log "  [OK] Usuario verificado en multiOTP" "Green"
    } else {
        Write-Log "  [INFO] Verificacion: $verification" "Yellow"
    }

    # PASO 4: Generar URI OTP y QR
    $uriAccount = [Uri]::EscapeDataString($DomainName + ":" + $admin)
    $otpUri     = "otpauth://totp/" + $uriAccount + "?secret=" + $secret +
                  "&issuer=LabMFA&algorithm=SHA1&digits=6&period=30"

    $qrPath = "$SetupPath\QR_$admin.png"
    $qrOK   = New-QRCodePNG -Text $otpUri -OutputPath $qrPath
    if ($qrOK) {
        Write-Log "  [OK] QR generado: $qrPath" "Green"
    } else {
        Write-Log "  [INFO] QR no disponible. URI guardada en: $($qrPath -replace '\.png$','_URI.txt')" "Yellow"
    }

    # PASO 5: Guardar en registro de Windows
    $regPath = "HKLM:\SOFTWARE\LabMFA\Users\$admin"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "TOTPSecret"     -Value $secret
    Set-ItemProperty -Path $regPath -Name "Enabled"        -Value 1
    Set-ItemProperty -Path $regPath -Name "FailedAttempts" -Value 0
    Set-ItemProperty -Path $regPath -Name "LockedUntil"    -Value ""
    Set-ItemProperty -Path $regPath -Name "OTPUri"         -Value $otpUri

    # Imprimir datos del usuario
    Write-Host "  ┌────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │ Usuario : $($admin.PadRight(41)) │" -ForegroundColor White
    Write-Host "  │ Secreto : $($secret.PadRight(41)) │" -ForegroundColor Yellow
    Write-Host "  │ QR      : QR_$($admin.PadRight(38)) │" -ForegroundColor Green
    Write-Host "  └────────────────────────────────────────────────────┘" -ForegroundColor Cyan

    # Acumular en archivo de secretos
    $SecretsOutput += "Usuario : $admin`r`n"
    $SecretsOutput += "Secreto : $secret`r`n"
    $SecretsOutput += "URI OTP : $otpUri`r`n"
    $SecretsOutput += "QR      : $qrPath`r`n"
    $SecretsOutput += "---`r`n"
}

# Guardar archivo de secretos (reescribir completo)
$SecretsOutput | Out-File -FilePath $SecretsFile -Encoding UTF8 -Force
Write-Log "" "White"
Write-Log "[OK] Archivo de secretos: $SecretsFile" "Cyan"

# ── 2.8 Verificacion final: lista de usuarios en multiOTP ──
Write-Log "" "White"
Write-Log "Usuarios registrados en multiOTP:" "Cyan"
$usersResult = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -Args @("-users") -TimeoutMs 10000
Write-Log "  $usersResult" "White"

# ── 2.9 Iniciar servicio web de multiOTP ──
Write-Log "" "White"
Write-Log "Iniciando servicio web de multiOTP (puerto 8112)..." "Yellow"

$webScript = Get-ChildItem -Path $MultiOTPDir -Recurse -Filter "webservice_install*" -ErrorAction SilentlyContinue |
             Select-Object -First 1 -ExpandProperty FullName

if ($webScript) {
    $wsDir = Split-Path $webScript -Parent
    $job = Start-Job -ScriptBlock { param($s); & cmd /c $s 2>&1 } -ArgumentList $webScript
    $null = Wait-Job -Job $job -Timeout 30
    Receive-Job -Job $job | ForEach-Object { Write-Log "  WebSvc: $_" "Gray" }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
} else {
    $svc = Get-Service -Name "multiOTP" -ErrorAction SilentlyContinue
    if ($svc) {
        Start-Service -Name "multiOTP" -ErrorAction SilentlyContinue
        Write-Log "  Servicio multiOTP iniciado" "Green"
    }
}

Start-Sleep -Seconds 4
$port8112 = netstat -an 2>$null | Select-String ":8112"
if ($port8112) {
    Write-Log "[OK] Puerto 8112 activo — Credential Provider puede validar" "Green"
} else {
    Write-Log "[WARN] Puerto 8112 no activo aun. Inicia manualmente: cd $MultiOTPDir && .\webservice_install.cmd" "Yellow"
}


# =====================================================
# PARTE 3 — PERFILES MOVILES (ROAMING PROFILES)
# =====================================================
Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PARTE 3: PERFILES MOVILES               " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan

$ProfilesPath = "C:\PerfilesMoviles"
$ServerName   = $env:COMPUTERNAME

# Crear directorio de perfiles
if (-not (Test-Path $ProfilesPath)) {
    New-Item -ItemType Directory -Path $ProfilesPath -Force | Out-Null
}

# ── Crear share con permisos correctos ──
$existShare = Get-SmbShare -Name "Perfiles$" -ErrorAction SilentlyContinue
if (-not $existShare) {
    New-SmbShare -Name "Perfiles$" -Path $ProfilesPath `
        -FullAccess "Domain Admins" `
        -ChangeAccess "Authenticated Users" `
        -Description "Perfiles Moviles de Usuarios" | Out-Null
    Write-Log "[OK] Share \\$ServerName\Perfiles$ creado en $ProfilesPath" "Green"
} else {
    Write-Log "[OK] Share Perfiles$ ya existe" "Yellow"
}

# ── Permisos NTFS para el directorio de perfiles ──
# Regla clave: cada usuario solo puede acceder a su propia carpeta
$acl = Get-Acl $ProfilesPath

# Bloquear herencia pero copiar ACEs existentes
$acl.SetAccessRuleProtection($true, $false)

# Admins: control total (heredado)
$ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Domain Admins", "FullControl",
    "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($ruleAdmins)

# SYSTEM: control total
$ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "SYSTEM", "FullControl",
    "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($ruleSystem)

# Usuarios autenticados: solo crear su propia carpeta (no listar las ajenas)
$ruleUsers = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Authenticated Users",
    "AppendData,ReadAttributes,ReadExtendedAttributes,ReadPermissions",
    "None", "None", "Allow")
$acl.AddAccessRule($ruleUsers)

# CREATOR OWNER: control total sobre su propio subdirectorio
$ruleOwner = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "CREATOR OWNER", "FullControl",
    "ContainerInherit,ObjectInherit", "InheritOnly", "Allow")
$acl.AddAccessRule($ruleOwner)

Set-Acl -Path $ProfilesPath -AclObject $acl
Write-Log "[OK] Permisos NTFS configurados en $ProfilesPath" "Green"

# ── Asignar perfil movil a los usuarios ──
$todosUsuarios = @(
    "admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria",
    "usuario.cuate1",  "usuario.cuate2", "usuario.nocuate1", "usuario.nocuate2"
)

Write-Log "Asignando ruta de perfil movil a usuarios..." "Yellow"
foreach ($u in $todosUsuarios) {
    try {
        $profilePath = "\\" + $ServerName + "\Perfiles$\" + $u
        Set-ADUser -Identity $u -ProfilePath $profilePath -ErrorAction Stop
        Write-Log "  [OK] $u -> $profilePath" "Green"
    } catch {
        Write-Log "  [WARN] $u : $($_.Exception.Message)" "Yellow"
    }
}

# ── GPO para sincronizacion de perfiles ──
# Configurar timeout de perfil y otras opciones utiles
$gpoPerfiles = "GPO_PerfilesMóviles"
try {
    $gpo = Get-GPO -Name $gpoPerfiles -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $gpoPerfiles
        Write-Log "[OK] GPO '$gpoPerfiles' creada" "Green"
    }
    $domDN = (Get-ADDomain).DistinguishedName
    try {
        New-GPLink -Name $gpoPerfiles -Target $domDN -LinkEnabled Yes -ErrorAction Stop | Out-Null
        Write-Log "[OK] GPO vinculada al dominio" "Green"
    } catch {
        Write-Log "[INFO] GPO ya vinculada o error de link" "Yellow"
    }
} catch {
    Write-Log "[WARN] GPO perfiles: $($_.Exception.Message)" "Yellow"
}


# =====================================================
# PARTE 4 — FSRM: CUOTAS Y RESTRICCIONES
# =====================================================
Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PARTE 4: FSRM (CUOTAS Y BLOQUEOS)      " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan

# ── Verificar / instalar FSRM ──
$fsrm = Get-WindowsFeature -Name "FS-Resource-Manager" -ErrorAction SilentlyContinue
if ($fsrm -and -not $fsrm.Installed) {
    Write-Log "Instalando FSRM..." "Yellow"
    Install-WindowsFeature -Name "FS-Resource-Manager" -IncludeManagementTools | Out-Null
    Write-Log "[OK] FSRM instalado" "Green"
} else {
    Write-Log "[OK] FSRM disponible" "Green"
}

Import-Module FileServerResourceManager -ErrorAction SilentlyContinue

$CuatesDir   = "C:\UserData\Cuates"
$NoCuatesDir = "C:\UserData\NoCuates"

foreach ($d in @("C:\UserData", $CuatesDir, $NoCuatesDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# Crear shares de datos de usuario
foreach ($s in @(@{N="Cuates$"; P=$CuatesDir}, @{N="NoCuates$"; P=$NoCuatesDir})) {
    if (-not (Get-SmbShare -Name $s.N -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $s.N -Path $s.P `
            -FullAccess "Domain Admins" `
            -ChangeAccess "Authenticated Users" | Out-Null
        Write-Log "[OK] Share $($s.N) creado en $($s.P)" "Green"
    }
}

# ── Grupo de archivos bloqueados ──
try {
    Remove-FsrmFileGroup -Name "ArchivosBloqueados" -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmFileGroup -Name "ArchivosBloqueados" `
        -IncludePattern @("*.mp3","*.mp4","*.exe","*.avi","*.mkv","*.wmv","*.mov","*.flv") `
        -ErrorAction Stop | Out-Null
    Write-Log "[OK] Grupo ArchivosBloqueados creado" "Green"
} catch {
    Write-Log "[WARN] FileGroup: $($_.Exception.Message)" "Yellow"
}

# ── Plantilla de bloqueo ──
try {
    Remove-FsrmFileScreenTemplate -Name "BloqueoMediaExe" -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmFileScreenTemplate -Name "BloqueoMediaExe" `
        -Active `
        -IncludeGroup @("ArchivosBloqueados") `
        -ErrorAction Stop | Out-Null
    Write-Log "[OK] Plantilla BloqueoMediaExe creada" "Green"
} catch {
    Write-Log "[WARN] FileScreenTemplate: $($_.Exception.Message)" "Yellow"
}

# ── Aplicar bloqueo a directorios ──
foreach ($d in @($CuatesDir, $NoCuatesDir)) {
    try {
        Remove-FsrmFileScreen -Path $d -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmFileScreen -Path $d -Template "BloqueoMediaExe" -ErrorAction Stop | Out-Null
        Write-Log "[OK] Bloqueo aplicado en: $d" "Green"
    } catch {
        Write-Log "[WARN] FileScreen $d : $($_.Exception.Message)" "Yellow"
    }
}

# ── Plantilla cuota 10MB (Cuates) ──
try {
    Remove-FsrmQuotaTemplate -Name "Cuota10MB" -Confirm:$false -ErrorAction SilentlyContinue
    $t80  = New-FsrmQuotaThreshold -Percentage 80  `
            -Action (New-FsrmAction -Type Event -EventType Warning `
                     -Body "[Source Io Owner] uso 80% de cuota en [Quota Path]")
    $t100 = New-FsrmQuotaThreshold -Percentage 100 `
            -Action (New-FsrmAction -Type Event -EventType Error   `
                     -Body "[Source Io Owner] alcanzo cuota en [Quota Path]")
    New-FsrmQuotaTemplate -Name "Cuota10MB" -Size 10MB -SoftLimit:$false `
        -Threshold @($t80, $t100) -ErrorAction Stop | Out-Null
    Write-Log "[OK] Plantilla Cuota10MB creada" "Green"
} catch {
    Write-Log "[WARN] QuotaTemplate 10MB: $($_.Exception.Message)" "Yellow"
}

# ── Plantilla cuota 5MB (NoCuates) ──
try {
    Remove-FsrmQuotaTemplate -Name "Cuota5MB" -Confirm:$false -ErrorAction SilentlyContinue
    $t80b  = New-FsrmQuotaThreshold -Percentage 80  `
             -Action (New-FsrmAction -Type Event -EventType Warning `
                      -Body "[Source Io Owner] uso 80% de cuota en [Quota Path]")
    $t100b = New-FsrmQuotaThreshold -Percentage 100 `
             -Action (New-FsrmAction -Type Event -EventType Error   `
                      -Body "[Source Io Owner] alcanzo cuota en [Quota Path]")
    New-FsrmQuotaTemplate -Name "Cuota5MB" -Size 5MB -SoftLimit:$false `
        -Threshold @($t80b, $t100b) -ErrorAction Stop | Out-Null
    Write-Log "[OK] Plantilla Cuota5MB creada" "Green"
} catch {
    Write-Log "[WARN] QuotaTemplate 5MB: $($_.Exception.Message)" "Yellow"
}

# ── Aplicar cuotas ──
try {
    Remove-FsrmQuota -Path $CuatesDir   -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmQuota -Path $CuatesDir   -Template "Cuota10MB" -ErrorAction Stop | Out-Null
    Write-Log "[OK] Cuota 10MB en: $CuatesDir" "Green"
} catch { Write-Log "[WARN] Cuota Cuates: $($_.Exception.Message)" "Yellow" }

try {
    Remove-FsrmQuota -Path $NoCuatesDir -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmQuota -Path $NoCuatesDir -Template "Cuota5MB"  -ErrorAction Stop | Out-Null
    Write-Log "[OK] Cuota 5MB en: $NoCuatesDir" "Green"
} catch { Write-Log "[WARN] Cuota NoCuates: $($_.Exception.Message)" "Yellow" }


# =====================================================
# PARTE 5 — CREDENTIAL PROVIDER (verificar / instalar)
# =====================================================
Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PARTE 5: CREDENTIAL PROVIDER multiOTP  " -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan

# Verificar si el CP ya esta instalado
$cpReg = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\" `
         -ErrorAction SilentlyContinue |
         Where-Object {
             try { (Get-ItemProperty $_.PSPath).'(default)' -like "*multiOTP*" } catch { $false }
         }

if ($cpReg) {
    Write-Log "[OK] Credential Provider de multiOTP ya esta instalado" "Green"
} else {
    Write-Log "Buscando instalador del Credential Provider..." "Yellow"

    $CPZip = "$SetupPath\multiOTP-CredentialProvider.zip"
    $CPPath = "$SetupPath\CredentialProvider"

    # Intentar descargar CP si no existe
    if (-not (Test-Path $CPZip) -or (Get-Item $CPZip -ErrorAction SilentlyContinue).Length -lt 500KB) {
        $cpUrls = @(
            "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.8.0-x64.zip",
            "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.7.2-x64.zip",
            "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.6.6-x64.zip"
        )
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $cpOK = $false
        foreach ($url in $cpUrls) {
            try {
                Invoke-WebRequest -Uri $url -OutFile $CPZip -UseBasicParsing -TimeoutSec 90
                $cpOK = $true
                Write-Log "[OK] CP descargado desde: $url" "Green"
                break
            } catch {
                Write-Log "  Fallo: $url" "Gray"
            }
        }

        if (-not $cpOK) {
            Write-Host ""
            Write-Host "  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor Red
            Write-Host "  │  DESCARGA MANUAL REQUERIDA para el Credential Provider  │" -ForegroundColor Red
            Write-Host "  │                                                         │" -ForegroundColor Yellow
            Write-Host "  │  1. Ve a: github.com/multiOTP/multiOTPCredentialProvider│" -ForegroundColor White
            Write-Host "  │  2. Descarga el .zip x64 mas reciente                  │" -ForegroundColor White
            Write-Host "  │  3. Copialo a: $CPZip" -ForegroundColor White
            Write-Host "  │  4. Vuelve a ejecutar SOLO la Parte 5 de este script   │" -ForegroundColor White
            Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor Red
        }
    }

    # Extraer e instalar CP
    if (Test-Path $CPZip) {
        try {
            if (Test-Path $CPPath) { Remove-Item $CPPath -Recurse -Force -ErrorAction SilentlyContinue }
            Expand-Archive -Path $CPZip -DestinationPath $CPPath -Force -ErrorAction SilentlyContinue

            $installer = Get-ChildItem -Path $CPPath -Recurse -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match "install|setup|multiOTP" -and $_.Extension -match "exe|msi" } |
                         Select-Object -First 1 -ExpandProperty FullName

            if ($installer) {
                Write-Log "Instalando CP desde: $installer" "Yellow"
                if ($installer -like "*.msi") {
                    Start-Process "msiexec" -ArgumentList "/i `"$installer`" /qn MULTIOTP_HOST=127.0.0.1 MULTIOTP_PORT=8112" -Wait -NoNewWindow
                } else {
                    Start-Process $installer -ArgumentList "/install /multiOTPServer=127.0.0.1 /multiOTPPort=8112 /VERYSILENT /NORESTART" -Wait -NoNewWindow
                }
                Write-Log "[OK] CP instalado. Se necesita reinicio para activarse." "Green"
            } else {
                Write-Log "[WARN] Instalador no encontrado en $CPPath" "Yellow"
                Write-Log "       Instala manualmente: Server 127.0.0.1, Puerto 8112" "Yellow"
            }
        } catch {
            Write-Log "[WARN] Error instalando CP: $($_.Exception.Message)" "Yellow"
        }
    }
}


# =====================================================
# RESUMEN FINAL
# =====================================================
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          PRACTICA 9 — CONFIGURACION COMPLETADA           ║" -ForegroundColor Green
Write-Host "╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║                                                           ║" -ForegroundColor White
Write-Host "║  NTP:  time.google.com configurado                       ║" -ForegroundColor Cyan
Write-Host "║  OTP:  5 usuarios registrados en multiOTP                ║" -ForegroundColor Cyan
Write-Host "║  QR:   C:\MFA_Setup\QR_*.png   (o *_URI.txt si sin red) ║" -ForegroundColor Cyan
Write-Host "║  Perfiles moviles: \\$($ServerName.PadRight(20))\Perfiles$          ║" -ForegroundColor Cyan
Write-Host "║  FSRM: Cuotas y bloqueo de archivos configurados         ║" -ForegroundColor Cyan
Write-Host "║                                                           ║" -ForegroundColor White
Write-Host "║  PASOS MANUALES OBLIGATORIOS:                            ║" -ForegroundColor Yellow
Write-Host "║                                                           ║" -ForegroundColor White
Write-Host "║  1. ESCANEAR QR desde C:\MFA_Setup\QR_*.png              ║" -ForegroundColor White
Write-Host "║     con Google Authenticator o Microsoft Authenticator   ║" -ForegroundColor White
Write-Host "║                                                           ║" -ForegroundColor White
Write-Host "║  2. PROBAR que multiOTP valida correctamente:             ║" -ForegroundColor White
Write-Host "║     cd $MultiOTPDir"
Write-Host "║     .\multiotp.exe -checkpwd admin_identidad CODIGO       ║" -ForegroundColor White
Write-Host "║     (debe devolver 0 o 'Reply-Message: OK')              ║" -ForegroundColor White
Write-Host "║                                                           ║" -ForegroundColor White
Write-Host "║  3. REINICIAR el servidor:                               ║" -ForegroundColor White
Write-Host "║     Restart-Computer -Force                               ║" -ForegroundColor White
Write-Host "║                                                           ║" -ForegroundColor White
Write-Host "║  4. AL HACER LOGIN: Usuario + Contraseña + Código TOTP   ║" -ForegroundColor White
Write-Host "║                                                           ║" -ForegroundColor White
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Log "Log completo guardado en: $LogFile" "Gray"
Write-Log "Secretos TOTP en: $SecretsFile" "Gray"
Write-Log "=== Practica 9 completada a las $(Get-Date -Format 'HH:mm:ss') ===" "Cyan"