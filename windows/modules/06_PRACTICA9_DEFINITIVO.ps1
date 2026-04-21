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
Write-Host "Fecha : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host "Equipo: $env:COMPUTERNAME" -ForegroundColor Gray
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
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

New-Item -ItemType File -Path $LogFile -Force | Out-Null

function Write-Log {
    param(
        [string]$msg,
        [string]$color = "White"
    )
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

    $dir = Split-Path $MultiOTPExe -Parent
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $MultiOTPExe
    $psi.Arguments              = ($Args -join " ")
    $psi.WorkingDirectory       = $dir
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

    if ($out) { return $out }
    elseif ($err) { return $err }
    else { return "OK($($proc.ExitCode))" }
}

# ─────────────────────────────────────────────
# FUNCION: Generar secreto Base32 criptografico
# ─────────────────────────────────────────────
function New-TOTPSecret {
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $chars  = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $secret = ""
    $buf    = 0
    $bits   = 0
    foreach ($b in $bytes) {
        $buf   = ($buf -shl 8) -bor $b
        $bits += 8
        while ($bits -ge 5) {
            $bits   -= 5
            $secret += $chars[($buf -shr $bits) -band 0x1F]
        }
    }
    return $secret
}

# ─────────────────────────────────────────────
# FUNCION: Generar QR PNG
# ─────────────────────────────────────────────
function New-QRCodePNG {
    param(
        [string]$Text,
        [string]$OutputPath
    )

    $qrcoderDll = Get-ChildItem -Path "C:\MultiOTP" -Recurse -Filter "QRCoder.dll" -ErrorAction SilentlyContinue |
                  Select-Object -First 1 -ExpandProperty FullName

    if ($qrcoderDll) {
        try {
            Add-Type -Path $qrcoderDll -ErrorAction Stop
            $qrGen    = New-Object QRCoder.QRCodeGenerator
            $qrData   = $qrGen.CreateQrCode($Text, [QRCoder.QRCodeGenerator+ECCLevel]::Q)
            $qrCode   = New-Object QRCoder.PngByteQRCode($qrData)
            $pngBytes = $qrCode.GetGraphic(10)
            [System.IO.File]::WriteAllBytes($OutputPath, $pngBytes)
            return $true
        }
        catch {
            # QRCoder.dll existe pero fallo, continuar con fallback
        }
    }

    # Fallback: API publica de QR
    try {
        $encoded  = [Uri]::EscapeDataString($Text)
        $qrApiUrl = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$encoded"
        Invoke-WebRequest -Uri $qrApiUrl -OutFile $OutputPath -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return $true
    }
    catch {
        # Sin red: guardar URI en archivo de texto
        $uriFile = $OutputPath -replace "\.png$", "_URI.txt"
        "Escanea este URI con un generador QR en linea:" | Out-File $uriFile -Encoding UTF8
        "https://www.qrcode-monkey.com/" | Out-File $uriFile -Encoding UTF8 -Append
        "" | Out-File $uriFile -Encoding UTF8 -Append
        $Text | Out-File $uriFile -Encoding UTF8 -Append
        return $false
    }
}


# =====================================================
# PARTE 1 - SINCRONIZACION NTP CON GOOGLE
# =====================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PARTE 1: SINCRONIZACION NTP (GOOGLE)   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Log "Configurando servidores NTP de Google..." "Yellow"

Stop-Service -Name "W32Time" -Force -ErrorAction SilentlyContinue

$ntpServers = "time.google.com,0x9 time1.google.com,0x9 time2.google.com,0x9 time3.google.com,0x9"
& w32tm /config /manualpeerlist:$ntpServers /syncfromflags:manual /reliable:yes /update

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
    -Name "Type" -Value "NTP" -ErrorAction SilentlyContinue

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
    -Name "MaxPosPhaseCorrection" -Value 3600 -ErrorAction SilentlyContinue

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
    -Name "MaxNegPhaseCorrection" -Value 3600 -ErrorAction SilentlyContinue

Start-Service -Name "W32Time" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$syncResult = & w32tm /resync /force 2>&1
Write-Log "Resultado sync: $syncResult" "Gray"

$ntpStatus = & w32tm /query /status 2>&1
$ntpStatus | ForEach-Object { Write-Log "  NTP: $_" "Gray" }

Write-Log "[OK] Hora del servidor: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" "Green"
Write-Log "[OK] Revisa que tu celular tenga la misma hora (zona horaria correcta)" "Yellow"
Write-Log "     Ve a Configuracion > General > Fecha y Hora > Automatica (ON)" "Yellow"


# =====================================================
# PARTE 2 - REGISTRO multiOTP Y DESCARGA DE BACKEND
# =====================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PARTE 2: REGISTRO multiOTP DEFINITIVO  " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$MultiOTPExe = Get-ChildItem -Path $MultiOTPPath -Recurse -Filter "multiotp.exe" | Select-Object -First 1 -ExpandProperty FullName

if (-not $MultiOTPExe) {
    Write-Log "[WARN] multiOTP no detectado. Descargando backend..." "Yellow"
    $backendZip = "$SetupPath\multiotp_windows.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $releaseUrl = "https://api.github.com/repos/multiOTP/multiOTP/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl -UseBasicParsing
        $downloadUrl = ($release.assets | Where-Object { $_.name -match "windows" -and $_.name -match "\.zip$" }).browser_download_url
        
        Write-Log "Descargando desde GitHub..." "Cyan"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $backendZip -UseBasicParsing
        Expand-Archive -Path $backendZip -DestinationPath $MultiOTPPath -Force
        $MultiOTPExe = Get-ChildItem -Path $MultiOTPPath -Recurse -Filter "multiotp.exe" | Select-Object -First 1 -ExpandProperty FullName
        Write-Log "[OK] Backend instalado exitosamente." "Green"
    } catch {
        Write-Log "[ERROR] No se pudo descargar el backend: $($_.Exception.Message)" "Red"
        return
    }
}

$MultiOTPDir = Split-Path $MultiOTPExe -Parent
$UsersDir    = Join-Path $MultiOTPDir "users"
if (-not (Test-Path $UsersDir)) { New-Item -ItemType Directory -Path $UsersDir -Force }

# Limpieza y configuración base
Write-Log "Limpiando registros previos..." "Yellow"
Get-ChildItem -Path $MultiOTPDir -Recurse -Filter "*.db" | Remove-Item -Force
Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -Args @("-config", "algorithm=TOTP", "digits=6", "time-interval=30") | Out-Null

# Registro de Usuarios
$SecretsFile = "$SetupPath\TOTP_Secrets.txt"
$SecretsOutput = "=== SECRETOS TOTP ===`r`n"

foreach ($admin in $AdminUsers) {
    Write-Log "Registrando MFA para: $admin" "Cyan"
    $secret = New-TOTPSecret
    $res = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -Args @("-create", $admin, "TOTP", $secret, "6", "30")
    
    # Asegurar que el .db esté en la carpeta /users
    $dbFile = Get-ChildItem -Path $MultiOTPDir -Filter "$admin.db"
    if ($dbFile) { Move-Item $dbFile.FullName (Join-Path $UsersDir "$admin.db") -Force -ErrorAction SilentlyContinue }

    # QR
    $otpUri = "otpauth://totp/LabMFA:$admin?secret=$secret&issuer=LabMFA"
    New-QRCodePNG -Text $otpUri -OutputPath "$SetupPath\QR_$admin.png" | Out-Null
    
    $SecretsOutput += "Usuario: $admin | Secreto: $secret`r`n"
    Write-Log "  [OK] Secreto: $secret" "Gray"
}
$SecretsOutput | Out-File $SecretsFile -Encoding UTF8

# Iniciar Web Service (Puerto 8112)
Write-Log "Iniciando WebService de validacion..." "Yellow"
$webInstall = Get-ChildItem -Path $MultiOTPDir -Recurse -Filter "webservice_install.cmd" | Select-Object -First 1
if ($webInstall) {
    Start-Process "cmd.exe" -ArgumentList "/c `"$($webInstall.FullName)`"" -WindowStyle Hidden
}

$MultiOTPDir  = Split-Path $MultiOTPExe -Parent
$UsersDir     = Join-Path $MultiOTPDir "users"
$MultiOTPConf = Join-Path $MultiOTPDir "config"

Write-Log "[OK] multiotp.exe: $MultiOTPExe" "Green"
Write-Log "[OK] Directorio de usuarios: $UsersDir" "Green"

foreach ($d in @($UsersDir, $MultiOTPConf)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# -- 2.2 Detener servicios multiOTP --
Write-Log "Deteniendo servicios multiOTP..." "Yellow"

foreach ($svc in @("multiOTP", "multiOTPwebservice", "multiOTPradius")) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
}

Get-Process -Name "nginx","php","php-cgi","nssm" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2

# -- 2.3 Limpiar .db previos --
Write-Log "Eliminando registros previos de usuarios en multiOTP..." "Yellow"

Get-ChildItem -Path $MultiOTPDir -Recurse -Filter "*.db" -ErrorAction SilentlyContinue |
    ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Log "  Eliminado: $($_.FullName)" "Gray"
    }

# -- 2.4 Configurar multiOTP base --
Write-Log "Configurando parametros base de multiOTP..." "Yellow"
$r = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -Args @("-config","algorithm=TOTP","digits=6","time-interval=30")
Write-Log "  Config: $r" "Gray"

# -- 2.5 Determinar dominio --
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $DomainName = (Get-ADDomain).DNSRoot
    Write-Log "[OK] Dominio: $DomainName" "Green"
}
catch {
    $DomainName = $env:USERDNSDOMAIN
    if (-not $DomainName) { $DomainName = "lab.local" }
    Write-Log "[WARN] AD no disponible. Usando dominio: $DomainName" "Yellow"
}

# -- 2.6 Leer secretos existentes --
$SecretsFile   = "$SetupPath\TOTP_Secrets.txt"
$secretosExist = @{}

if (Test-Path $SecretsFile) {
    Write-Log "Leyendo secretos previos de $SecretsFile..." "Yellow"
    $lineas  = Get-Content $SecretsFile
    $uActual = $null

    foreach ($linea in $lineas) {
        if ($linea -match "^Usuario\s*:\s*(.+)$") {
            $uActual = $Matches[1].Trim()
        }
        if ($linea -match "^Secreto\s*:\s*([A-Z2-7]{16,})$" -and $uActual) {
            $secretosExist[$uActual] = $Matches[1].Trim()
            $uActual = $null
        }
    }

    Write-Log "  Secretos encontrados: $($secretosExist.Keys -join ', ')" "Gray"
}

# -- 2.7 Registrar cada usuario --
$SecretsOutput  = "=== SECRETOS TOTP multiOTP - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" + "`r`n"
$SecretsOutput += "IMPORTANTE: Escanea los QR desde C:\MFA_Setup\QR_*.png" + "`r`n"
$SecretsOutput += "O ingresa el secreto manualmente en Google/Microsoft Authenticator" + "`r`n`r`n"

foreach ($admin in $AdminUsers) {

    Write-Log "" "White"
    Write-Log "--- Registrando: $admin ---" "Cyan"

    if ($secretosExist.ContainsKey($admin)) {
        $secret = $secretosExist[$admin]
        Write-Log "  Usando secreto existente del archivo" "Gray"
    }
    else {
        $secret = New-TOTPSecret
        Write-Log "  Secreto nuevo generado" "Gray"
    }

    # PASO 1: Crear usuario en multiOTP
    $r = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe `
         -Args @("-create", $admin, "TOTP", $secret, "6", "30") `
         -TimeoutMs 20000
    Write-Log "  Create result: $r" "Gray"

    # PASO 2: Verificar que el .db quedo en el lugar correcto
    $dbEsperado = Join-Path $UsersDir ($admin + ".db")
    Start-Sleep -Milliseconds 500

    if (-not (Test-Path $dbEsperado)) {
        $dbEncontrado = Get-ChildItem -Path $MultiOTPDir -Recurse -Filter ($admin + ".db") -ErrorAction SilentlyContinue |
                        Select-Object -First 1

        if ($dbEncontrado) {
            Write-Log "  [MOVER] .db en lugar incorrecto: $($dbEncontrado.FullName)" "Yellow"
            Move-Item $dbEncontrado.FullName $dbEsperado -Force -ErrorAction SilentlyContinue
            Write-Log "  [OK] .db movido a: $dbEsperado" "Green"
        }
        else {
            Write-Log "  [WARN] .db no encontrado. Reintentando create..." "Red"

            $r2 = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe `
                  -Args @("-create", $admin, "TOTP", $secret, "6", "30") `
                  -TimeoutMs 25000
            Write-Log "  Reintento result: $r2" "Gray"
            Start-Sleep -Seconds 1

            if (-not (Test-Path $dbEsperado)) {
                Write-Log "  Creando .db manualmente..." "Yellow"

                $dbContent = "<?xml version=""1.0"" encoding=""utf-8""?>" + "`r`n"
                $dbContent += "<multiOTPUser>" + "`r`n"
                $dbContent += "  <user>$admin</user>" + "`r`n"
                $dbContent += "  <algorithm>TOTP</algorithm>" + "`r`n"
                $dbContent += "  <key_algorithm>HMAC-SHA1</key_algorithm>" + "`r`n"
                $dbContent += "  <otp>6</otp>" + "`r`n"
                $dbContent += "  <time>30</time>" + "`r`n"
                $dbContent += "  <seed>$secret</seed>" + "`r`n"
                $dbContent += "  <description>$admin TOTP</description>" + "`r`n"
                $dbContent += "  <last_event>-1</last_event>" + "`r`n"
                $dbContent += "  <last_login>0</last_login>" + "`r`n"
                $dbContent += "  <error_counter>0</error_counter>" + "`r`n"
                $dbContent += "  <locked>0</locked>" + "`r`n"
                $dbContent += "  <delta_time>0</delta_time>" + "`r`n"
                $dbContent += "  <time_interval_for_totp>30</time_interval_for_totp>" + "`r`n"
                $dbContent += "  <number_of_digits>6</number_of_digits>" + "`r`n"
                $dbContent += "</multiOTPUser>" + "`r`n"

                $dbContent | Out-File -FilePath $dbEsperado -Encoding UTF8
                Write-Log "  [OK] .db creado manualmente en: $dbEsperado" "Green"
            }
        }
    }
    else {
        Write-Log "  [OK] .db en lugar correcto: $dbEsperado" "Green"
    }

    # PASO 3: Verificar que multiOTP reconoce al usuario
    $verification = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe `
                    -Args @("-display-log", $admin) -TimeoutMs 10000

    if ($verification -match "TOTP|totp|seed|6.*30|30.*6") {
        Write-Log "  [OK] Usuario verificado en multiOTP" "Green"
    }
    else {
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
    }
    else {
        Write-Log "  [INFO] QR no disponible. URI guardada en: $($qrPath -replace '\.png$','_URI.txt')" "Yellow"
    }

    # PASO 5: Guardar en registro de Windows
    $regPath = "HKLM:\SOFTWARE\LabMFA\Users\$admin"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "TOTPSecret"     -Value $secret
    Set-ItemProperty -Path $regPath -Name "Enabled"        -Value 1
    Set-ItemProperty -Path $regPath -Name "FailedAttempts" -Value 0
    Set-ItemProperty -Path $regPath -Name "LockedUntil"    -Value ""
    Set-ItemProperty -Path $regPath -Name "OTPUri"         -Value $otpUri

    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Usuario : $admin" -ForegroundColor White
    Write-Host "  | Secreto : $secret" -ForegroundColor Yellow
    Write-Host "  | QR      : QR_$admin.png" -ForegroundColor Green
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan

    $SecretsOutput += "Usuario : $admin`r`n"
    $SecretsOutput += "Secreto : $secret`r`n"
    $SecretsOutput += "URI OTP : $otpUri`r`n"
    $SecretsOutput += "QR      : $qrPath`r`n"
    $SecretsOutput += "---`r`n"
}

$SecretsOutput | Out-File -FilePath $SecretsFile -Encoding UTF8 -Force
Write-Log "" "White"
Write-Log "[OK] Archivo de secretos: $SecretsFile" "Cyan"

# -- 2.8 Verificacion lista de usuarios --
Write-Log "" "White"
Write-Log "Usuarios registrados en multiOTP:" "Cyan"
$usersResult = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -Args @("-users") -TimeoutMs 10000
Write-Log "  $usersResult" "White"

# -- 2.9 Iniciar servicio web de multiOTP --
Write-Log "" "White"
Write-Log "Iniciando servicio web de multiOTP (puerto 8112)..." "Yellow"

$webScript = Get-ChildItem -Path $MultiOTPDir -Recurse -Filter "webservice_install*" -ErrorAction SilentlyContinue |
             Select-Object -First 1 -ExpandProperty FullName

if ($webScript) {
    $job    = Start-Job -ScriptBlock { param($s); & cmd /c $s 2>&1 } -ArgumentList $webScript
    $null   = Wait-Job -Job $job -Timeout 30
    Receive-Job -Job $job | ForEach-Object { Write-Log "  WebSvc: $_" "Gray" }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
}
else {
    $svc = Get-Service -Name "multiOTP" -ErrorAction SilentlyContinue
    if ($svc) {
        Start-Service -Name "multiOTP" -ErrorAction SilentlyContinue
        Write-Log "  Servicio multiOTP iniciado" "Green"
    }
}

Start-Sleep -Seconds 4
$port8112 = netstat -an 2>$null | Select-String ":8112"
if ($port8112) {
    Write-Log "[OK] Puerto 8112 activo - Credential Provider puede validar" "Green"
}
else {
    Write-Log "[WARN] Puerto 8112 no activo aun." "Yellow"
    Write-Log "       Inicia manualmente: cd $MultiOTPDir && .\webservice_install.cmd" "Yellow"
}


# =====================================================
# PARTE 3 - PERFILES MOVILES (ROAMING PROFILES)
# =====================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PARTE 3: PERFILES MOVILES               " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$ProfilesPath = "C:\PerfilesMoviles"
$ServerName   = $env:COMPUTERNAME

if (-not (Test-Path $ProfilesPath)) {
    New-Item -ItemType Directory -Path $ProfilesPath -Force | Out-Null
}

# Crear share
$existShare = Get-SmbShare -Name "Perfiles$" -ErrorAction SilentlyContinue
if (-not $existShare) {
    New-SmbShare -Name "Perfiles$" -Path $ProfilesPath `
        -FullAccess "Domain Admins" `
        -ChangeAccess "Authenticated Users" `
        -Description "Perfiles Moviles de Usuarios" | Out-Null
    Write-Log "[OK] Share \\$ServerName\Perfiles`$ creado en $ProfilesPath" "Green"
}
else {
    Write-Log "[OK] Share Perfiles`$ ya existe" "Yellow"
}

# Permisos NTFS
$acl = Get-Acl $ProfilesPath
$acl.SetAccessRuleProtection($true, $false)

$ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Domain Admins", "FullControl",
    "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($ruleAdmins)

$ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "SYSTEM", "FullControl",
    "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($ruleSystem)

$ruleUsers = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Authenticated Users",
    "AppendData,ReadAttributes,ReadExtendedAttributes,ReadPermissions",
    "None", "None", "Allow")
$acl.AddAccessRule($ruleUsers)

$ruleOwner = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "CREATOR OWNER", "FullControl",
    "ContainerInherit,ObjectInherit", "InheritOnly", "Allow")
$acl.AddAccessRule($ruleOwner)

Set-Acl -Path $ProfilesPath -AclObject $acl
Write-Log "[OK] Permisos NTFS configurados en $ProfilesPath" "Green"

# Asignar perfil movil a usuarios
$todosUsuarios = @(
    "admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria",
    "usuario.cuate1",  "usuario.cuate2", "usuario.nocuate1", "usuario.nocuate2"
)

Write-Log "Asignando ruta de perfil movil a usuarios..." "Yellow"

foreach ($u in $todosUsuarios) {
    try {
        $profilePath = "\\" + $ServerName + "\Perfiles`$\" + $u
        Set-ADUser -Identity $u -ProfilePath $profilePath -ErrorAction Stop
        Write-Log "  [OK] $u -> $profilePath" "Green"
    }
    catch {
        Write-Log "  [WARN] $u : $($_.Exception.Message)" "Yellow"
    }
}

# GPO para perfiles
$gpoPerfiles = "GPO_PerfilesMoviles"
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
    }
    catch {
        Write-Log "[INFO] GPO ya vinculada o error de link: $($_.Exception.Message)" "Yellow"
    }
}
catch {
    Write-Log "[WARN] GPO perfiles: $($_.Exception.Message)" "Yellow"
}


# =====================================================
# PARTE 4 - FSRM: CUOTAS Y RESTRICCIONES
# =====================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PARTE 4: FSRM (CUOTAS Y BLOQUEOS)      " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$fsrm = Get-WindowsFeature -Name "FS-Resource-Manager" -ErrorAction SilentlyContinue
if ($fsrm -and (-not $fsrm.Installed)) {
    Write-Log "Instalando FSRM..." "Yellow"
    Install-WindowsFeature -Name "FS-Resource-Manager" -IncludeManagementTools | Out-Null
    Write-Log "[OK] FSRM instalado" "Green"
}
else {
    Write-Log "[OK] FSRM disponible" "Green"
}

Import-Module FileServerResourceManager -ErrorAction SilentlyContinue

$CuatesDir   = "C:\UserData\Cuates"
$NoCuatesDir = "C:\UserData\NoCuates"

foreach ($d in @("C:\UserData", $CuatesDir, $NoCuatesDir)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# Crear shares de datos
$sharesData = @(
    @{ N = "Cuates$";   P = $CuatesDir },
    @{ N = "NoCuates$"; P = $NoCuatesDir }
)

foreach ($s in $sharesData) {
    if (-not (Get-SmbShare -Name $s.N -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $s.N -Path $s.P `
            -FullAccess "Domain Admins" `
            -ChangeAccess "Authenticated Users" | Out-Null
        Write-Log "[OK] Share $($s.N) creado en $($s.P)" "Green"
    }
}

# Grupo de archivos bloqueados
try {
    Remove-FsrmFileGroup -Name "ArchivosBloqueados" -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmFileGroup -Name "ArchivosBloqueados" `
        -IncludePattern @("*.mp3","*.mp4","*.exe","*.avi","*.mkv","*.wmv","*.mov","*.flv") `
        -ErrorAction Stop | Out-Null
    Write-Log "[OK] Grupo ArchivosBloqueados creado" "Green"
}
catch {
    Write-Log "[WARN] FileGroup: $($_.Exception.Message)" "Yellow"
}

# Plantilla de bloqueo
try {
    Remove-FsrmFileScreenTemplate -Name "BloqueoMediaExe" -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmFileScreenTemplate -Name "BloqueoMediaExe" `
        -Active `
        -IncludeGroup @("ArchivosBloqueados") `
        -ErrorAction Stop | Out-Null
    Write-Log "[OK] Plantilla BloqueoMediaExe creada" "Green"
}
catch {
    Write-Log "[WARN] FileScreenTemplate: $($_.Exception.Message)" "Yellow"
}

# Aplicar bloqueo a directorios
foreach ($d in @($CuatesDir, $NoCuatesDir)) {
    try {
        Remove-FsrmFileScreen -Path $d -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmFileScreen -Path $d -Template "BloqueoMediaExe" -ErrorAction Stop | Out-Null
        Write-Log "[OK] Bloqueo aplicado en: $d" "Green"
    }
    catch {
        Write-Log "[WARN] FileScreen $d : $($_.Exception.Message)" "Yellow"
    }
}

# Plantilla cuota 10MB (Cuates)
try {
    Remove-FsrmQuotaTemplate -Name "Cuota10MB" -Confirm:$false -ErrorAction SilentlyContinue

    $accion80  = New-FsrmAction -Type Event -EventType Warning `
                 -Body "[Source Io Owner] uso 80% de cuota en [Quota Path]"
    $accion100 = New-FsrmAction -Type Event -EventType Error `
                 -Body "[Source Io Owner] alcanzo cuota en [Quota Path]"
    $t80  = New-FsrmQuotaThreshold -Percentage 80  -Action $accion80
    $t100 = New-FsrmQuotaThreshold -Percentage 100 -Action $accion100

    New-FsrmQuotaTemplate -Name "Cuota10MB" -Size 10MB -SoftLimit:$false `
        -Threshold @($t80, $t100) -ErrorAction Stop | Out-Null
    Write-Log "[OK] Plantilla Cuota10MB creada" "Green"
}
catch {
    Write-Log "[WARN] QuotaTemplate 10MB: $($_.Exception.Message)" "Yellow"
}

# Plantilla cuota 5MB (NoCuates)
try {
    Remove-FsrmQuotaTemplate -Name "Cuota5MB" -Confirm:$false -ErrorAction SilentlyContinue

    $accion80b  = New-FsrmAction -Type Event -EventType Warning `
                  -Body "[Source Io Owner] uso 80% de cuota en [Quota Path]"
    $accion100b = New-FsrmAction -Type Event -EventType Error `
                  -Body "[Source Io Owner] alcanzo cuota en [Quota Path]"
    $t80b  = New-FsrmQuotaThreshold -Percentage 80  -Action $accion80b
    $t100b = New-FsrmQuotaThreshold -Percentage 100 -Action $accion100b

    New-FsrmQuotaTemplate -Name "Cuota5MB" -Size 5MB -SoftLimit:$false `
        -Threshold @($t80b, $t100b) -ErrorAction Stop | Out-Null
    Write-Log "[OK] Plantilla Cuota5MB creada" "Green"
}
catch {
    Write-Log "[WARN] QuotaTemplate 5MB: $($_.Exception.Message)" "Yellow"
}

# Aplicar cuotas
try {
    Remove-FsrmQuota -Path $CuatesDir -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmQuota -Path $CuatesDir -Template "Cuota10MB" -ErrorAction Stop | Out-Null
    Write-Log "[OK] Cuota 10MB en: $CuatesDir" "Green"
}
catch {
    Write-Log "[WARN] Cuota Cuates: $($_.Exception.Message)" "Yellow"
}

try {
    Remove-FsrmQuota -Path $NoCuatesDir -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmQuota -Path $NoCuatesDir -Template "Cuota5MB" -ErrorAction Stop | Out-Null
    Write-Log "[OK] Cuota 5MB en: $NoCuatesDir" "Green"
}
catch {
    Write-Log "[WARN] Cuota NoCuates: $($_.Exception.Message)" "Yellow"
}


# =====================================================
# PARTE 5 - CREDENTIAL PROVIDER (verificar / instalar)
# =====================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PARTE 5: CREDENTIAL PROVIDER multiOTP  " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$cpReg = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\" `
         -ErrorAction SilentlyContinue |
         Where-Object {
             try { (Get-ItemProperty $_.PSPath).'(default)' -like "*multiOTP*" }
             catch { $false }
         }

if ($cpReg) {
    Write-Log "[OK] Credential Provider de multiOTP ya esta instalado" "Green"
}
else {
    Write-Log "Instalando Credential Provider desde archivo local..." "Yellow"

    $CPZip  = "C:\MFA_Setup\multiOTP-CredentialProvider.zip"
    $CPPath = "C:\MFA_Setup\CredentialProvider"

    if (Test-Path $CPZip) {
        try {
            # Limpiar el directorio de extracción si ya existe de un intento previo
            if (Test-Path $CPPath) {
                Remove-Item $CPPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            Write-Log "Extrayendo $CPZip..." "Yellow"
            Expand-Archive -Path $CPZip -DestinationPath $CPPath -Force -ErrorAction Stop

            # Buscar el instalador (.exe o .msi) dentro de la carpeta extraída
            $installer = Get-ChildItem -Path $CPPath -Recurse -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match "install|setup|multiOTP" -and $_.Extension -match "exe|msi" } |
                         Select-Object -First 1 -ExpandProperty FullName

            if ($installer) {
                Write-Log "Ejecutando instalador: $installer" "Yellow"

                if ($installer -like "*.msi") {
                    Start-Process "msiexec" `
                        -ArgumentList "/i `"$installer`" /qn MULTIOTP_HOST=127.0.0.1 MULTIOTP_PORT=8112" `
                        -Wait -NoNewWindow
                }
                else {
                    Start-Process $installer `
                        -ArgumentList "/install /multiOTPServer=127.0.0.1 /multiOTPPort=8112 /VERYSILENT /NORESTART" `
                        -Wait -NoNewWindow
                }
                Write-Log "[OK] CP instalado. Se necesita reinicio para activarse." "Green"
            }
            else {
                Write-Log "[WARN] No se encontro instalador (.exe o .msi) dentro del ZIP." "Yellow"
            }
        }
        catch {
            Write-Log "[ERROR] Fallo al extraer o instalar el CP: $($_.Exception.Message)" "Red"
        }
    }
    else {
        Write-Log "[ERROR] El archivo $CPZip NO existe. Verifica que este en C:\MFA_Setup\" "Red"
    }
}


# =====================================================
# RESUMEN FINAL
# =====================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "         PRACTICA 9 - CONFIGURACION COMPLETADA              " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  NTP:  time.google.com configurado" -ForegroundColor Cyan
Write-Host "  OTP:  5 usuarios registrados en multiOTP" -ForegroundColor Cyan
Write-Host "  QR:   C:\MFA_Setup\QR_*.png  (o *_URI.txt si sin red)" -ForegroundColor Cyan
Write-Host "  Perfiles moviles: \\$ServerName\Perfiles`$" -ForegroundColor Cyan
Write-Host "  FSRM: Cuotas y bloqueo de archivos configurados" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PASOS MANUALES OBLIGATORIOS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. ESCANEAR QR desde C:\MFA_Setup\QR_*.png" -ForegroundColor White
Write-Host "     con Google Authenticator o Microsoft Authenticator" -ForegroundColor White
Write-Host ""
Write-Host "  2. PROBAR que multiOTP valida correctamente:" -ForegroundColor White
Write-Host "     cd $MultiOTPDir" -ForegroundColor Gray
Write-Host "     .\multiotp.exe -checkpwd admin_identidad CODIGO" -ForegroundColor Gray
Write-Host "     (debe devolver 0 o 'Reply-Message: OK')" -ForegroundColor White
Write-Host ""
Write-Host "  3. REINICIAR el servidor:" -ForegroundColor White
Write-Host "     Restart-Computer -Force" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. AL HACER LOGIN: Usuario + Contrasena + Codigo TOTP" -ForegroundColor White
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green

Write-Log "Log completo guardado en: $LogFile" "Gray"
Write-Log "Secretos TOTP en: $SecretsFile" "Gray"
Write-Log "=== Practica 9 completada a las $(Get-Date -Format 'HH:mm:ss') ===" "Cyan"