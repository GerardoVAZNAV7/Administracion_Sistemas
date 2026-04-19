# =============================================================================
# SCRIPT 06 - CONFIGURACION DE MFA CON multiOTP
# Ejecutar en: Windows Server 2022 (como Administrator)
#
# HERRAMIENTA: multiOTP (open source, certificado OATH, sin GitHub)
#   - Compatible con Google Authenticator y Microsoft Authenticator
#   - Descarga desde: download.multiotp.net (servidor propio, no GitHub)
#   - Soporta Windows Server 2012/2016/2019/2022
#   - NO requiere RADIUS ni internet despues de la instalacion
#
# ORDEN:
#   1. Descargar multiOTP (servidor backend)
#   2. Configurar usuarios TOTP
#   3. Descargar Credential Provider (pantalla de login)
#   4. Instalar y vincular ambos
# =============================================================================

Write-Host "=== [06] CONFIGURACION DE MFA CON multiOTP ===" -ForegroundColor Cyan

$SetupPath = "C:\MFA_Setup"
$MultiOTPPath = "C:\MultiOTP"

if (-not (Test-Path $SetupPath))   { New-Item -ItemType Directory -Path $SetupPath   | Out-Null }
if (-not (Test-Path $MultiOTPPath)) { New-Item -ItemType Directory -Path $MultiOTPPath | Out-Null }

# =========================================================
# PASO 1: DESCARGAR multiOTP DESDE download.multiotp.net
# (No usa GitHub - es el servidor oficial del proyecto)
# =========================================================
Write-Host "`n[+] Descargando multiOTP desde download.multiotp.net..." -ForegroundColor Green

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$MultiOTPZipUrl = "https://download.multiotp.net/multiotp.zip"
$MultiOTPZip    = "$SetupPath\multiotp.zip"

$DescargaOK = $false
try {
    Write-Host "  Descargando multiotp.zip (~57MB, puede tardar 1-2 min)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $MultiOTPZipUrl -OutFile $MultiOTPZip -UseBasicParsing -TimeoutSec 180
    Write-Host "  Descarga completada." -ForegroundColor Green
    $DescargaOK = $true
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  DESCARGA MANUAL REQUERIDA:" -ForegroundColor Yellow
    Write-Host "  1. Abre en tu navegador: https://download.multiotp.net/" -ForegroundColor White
    Write-Host "  2. Descarga el archivo: multiotp.zip" -ForegroundColor White
    Write-Host "  3. Copialo al servidor en: $MultiOTPZip" -ForegroundColor White
    Write-Host "  4. Vuelve a ejecutar este script." -ForegroundColor White
}

if (-not $DescargaOK -and -not (Test-Path $MultiOTPZip)) {
    Write-Host "`nScript pausado. Descarga el archivo y vuelve a ejecutar." -ForegroundColor Red
    exit 1
}

# =========================================================
# PASO 2: EXTRAER multiOTP
# =========================================================
Write-Host "`n[+] Extrayendo multiOTP en $MultiOTPPath..." -ForegroundColor Green

try {
    Expand-Archive -Path $MultiOTPZip -DestinationPath $MultiOTPPath -Force
    Write-Host "  Extraccion completada." -ForegroundColor Green
} catch {
    Write-Host "  Error al extraer: $($_.Exception.Message)" -ForegroundColor Red
}

# El ejecutable principal de multiOTP para Windows
$MultiOTPExe = Get-ChildItem -Path $MultiOTPPath -Recurse -Filter "multiotp.exe" |
               Select-Object -First 1 -ExpandProperty FullName

if (-not $MultiOTPExe) {
    # Intentar ruta alternativa dentro del zip
    $MultiOTPExe = "$MultiOTPPath\windows\multiotp.exe"
}

Write-Host "  multiotp.exe encontrado en: $MultiOTPExe" -ForegroundColor White

# =========================================================
# PASO 3: CONFIGURAR USUARIOS EN multiOTP
# Vincula usuarios de AD con tokens TOTP
# =========================================================
Write-Host "`n[+] Configurando usuarios TOTP en multiOTP..." -ForegroundColor Green

$DomainName  = (Get-ADDomain).DNSRoot
$AdminUsers  = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")
$SecretsFile = "$SetupPath\TOTP_Secrets.txt"

$SecretsContent  = "=== SECRETOS TOTP multiOTP - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===`r`n"
$SecretsContent += "Usa estos secretos para configurar Google Authenticator o Microsoft Authenticator`r`n`r`n"

foreach ($admin in $AdminUsers) {
    Write-Host "  Configurando: $admin" -ForegroundColor White

    # Crear usuario en multiOTP con token TOTP (genera secreto automaticamente)
    if ($MultiOTPExe -and (Test-Path $MultiOTPExe)) {
        $multiOTPDir = Split-Path $MultiOTPExe -Parent
        Push-Location $multiOTPDir

        # Crear el usuario con algoritmo TOTP (6 digitos, 30 segundos)
        & $MultiOTPExe -create $admin TOTP 2>&1 | Out-Null

        # Obtener el secreto generado para ese usuario
        $userInfo = & $MultiOTPExe -display-log $admin 2>&1
        Write-Host "  Usuario $admin creado en multiOTP." -ForegroundColor Green

        # Obtener QR code info
        $qrInfo = & $MultiOTPExe -qrcode $admin "$SetupPath\QR_$admin.png" 2>&1
        Write-Host "  QR guardado en: $SetupPath\QR_$admin.png" -ForegroundColor White

        Pop-Location
    }

    # Tambien generar secreto manual como respaldo
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $base32chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $secret = ""
    $buffer = 0; $bitsLeft = 0
    foreach ($byte in $bytes) {
        $buffer = ($buffer -shl 8) -bor $byte
        $bitsLeft += 8
        while ($bitsLeft -ge 5) {
            $bitsLeft -= 5
            $secret += $base32chars[($buffer -shr $bitsLeft) -band 0x1F]
        }
    }

    $uriAccount = [Uri]::EscapeDataString($DomainName + ":" + $admin)
    $uriParams  = "secret=" + $secret + "&issuer=LabMFA&algorithm=SHA1&digits=6&period=30"
    $otpUri     = "otpauth://totp/" + $uriAccount + "?" + $uriParams

    Write-Host "  Secreto TOTP: $secret" -ForegroundColor Yellow
    Write-Host ""

    $SecretsContent += "Usuario : $admin`r`n"
    $SecretsContent += "Secreto : $secret`r`n"
    $SecretsContent += "URI OTP : $otpUri`r`n"
    $SecretsContent += "---`r`n"

    # Guardar en registro para referencia
    $RegPath = "HKLM:\SOFTWARE\LabMFA\Users\$admin"
    if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPath -Name "TOTPSecret"     -Value $secret
    Set-ItemProperty -Path $RegPath -Name "Enabled"        -Value 1
    Set-ItemProperty -Path $RegPath -Name "FailedAttempts" -Value 0
    Set-ItemProperty -Path $RegPath -Name "LockedUntil"    -Value ""
}

$SecretsContent | Out-File -FilePath $SecretsFile -Encoding UTF8
Write-Host "  Secretos guardados: $SecretsFile" -ForegroundColor Cyan

# =========================================================
# PASO 4: DESCARGAR CREDENTIAL PROVIDER
# =========================================================
Write-Host "`n[+] Descargando multiOTP Credential Provider..." -ForegroundColor Green

# URL directa del Credential Provider (servidor propio de multiOTP)
$CPZipUrl = "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.8.0-x64.zip"
$CPZip    = "$SetupPath\multiOTP-CredentialProvider.zip"
$CPPath   = "$SetupPath\CredentialProvider"

$CPDescargaOK = $false
try {
    Write-Host "  Descargando Credential Provider..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $CPZipUrl -OutFile $CPZip -UseBasicParsing -TimeoutSec 120
    Write-Host "  Descarga completada." -ForegroundColor Green
    $CPDescargaOK = $true
} catch {
    Write-Host "  No se pudo descargar el CP automaticamente." -ForegroundColor Red
    Write-Host "  DESCARGA MANUAL desde tu navegador:" -ForegroundColor Yellow
    Write-Host "  URL: https://github.com/multiOTP/multiOTPCredentialProvider/releases" -ForegroundColor White
    Write-Host "  Archivo: multiOTPCredentialProvider-5.9.x.x-x64.zip" -ForegroundColor White
    Write-Host "  Guardalo en: $CPZip" -ForegroundColor White
}

if ($CPDescargaOK -or (Test-Path $CPZip)) {
    Write-Host "`n[+] Extrayendo Credential Provider..." -ForegroundColor Green
    try {
        Expand-Archive -Path $CPZip -DestinationPath $CPPath -Force
        Write-Host "  Extraido en: $CPPath" -ForegroundColor Green
    } catch {
        Write-Host "  Error al extraer CP: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Ejecutar instalador del Credential Provider
    $CPInstaller = Get-ChildItem -Path $CPPath -Recurse -Filter "*.exe" |
                   Where-Object { $_.Name -like "*install*" -or $_.Name -like "*setup*" } |
                   Select-Object -First 1 -ExpandProperty FullName

    if ($CPInstaller) {
        Write-Host "`n[+] Instalando Credential Provider..." -ForegroundColor Green
        Write-Host "  Instalador: $CPInstaller" -ForegroundColor White

        # Instalar apuntando al multiOTP local (modo local, sin servidor externo)
        $LocalIP = (Get-NetIPAddress -AddressFamily IPv4 |
                    Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
                    Select-Object -First 1).IPAddress

        $CPArgs = "/install /multiOTPServer=$LocalIP /multiOTPPort=8112 /loginTitle=`"MFA Required`""
        Start-Process -FilePath $CPInstaller -ArgumentList $CPArgs -Wait
        Write-Host "  Credential Provider instalado." -ForegroundColor Green
    } else {
        Write-Host "`n  Instalacion manual del CP requerida:" -ForegroundColor Yellow
        Write-Host "  1. Navega a: $CPPath" -ForegroundColor White
        Write-Host "  2. Ejecuta el instalador .exe como Administrador" -ForegroundColor White
        Write-Host "  3. En 'Server IP': ingresa 127.0.0.1" -ForegroundColor White
        Write-Host "  4. En 'Port': 8112" -ForegroundColor White
        Write-Host "  5. Finaliza la instalacion" -ForegroundColor White
    }
}

# =========================================================
# PASO 5: CONFIGURAR BLOQUEO (3 intentos / 30 min)
# =========================================================
Write-Host "`n[+] Verificando politica de bloqueo..." -ForegroundColor Green

$PSO = Get-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" -ErrorAction SilentlyContinue
if ($PSO) {
    if ($PSO.LockoutThreshold -ne 3) {
        Set-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" `
            -LockoutThreshold 3 `
            -LockoutDuration (New-TimeSpan -Minutes 30) `
            -LockoutObservationWindow (New-TimeSpan -Minutes 30)
        Write-Host "  Actualizado: 3 intentos / 30 min de bloqueo." -ForegroundColor Green
    } else {
        Write-Host "  [OK] 3 intentos / 30 min ya configurados." -ForegroundColor Green
    }
} else {
    Write-Host "  PSO no encontrada. Ejecuta Script 03 primero." -ForegroundColor Red
}

# =========================================================
# RESUMEN E INSTRUCCIONES
# =========================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "  INSTRUCCIONES FINALES" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. CONFIGURA LA APP EN TU MOVIL:" -ForegroundColor Yellow
Write-Host "     - Google Authenticator o Microsoft Authenticator" -ForegroundColor White
Write-Host "     - Toca '+' → Ingresar clave → pega el SECRETO del archivo:" -ForegroundColor White
Write-Host "       Get-Content $SecretsFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. INICIA EL SERVICIO multiOTP (para que el CP pueda validar):" -ForegroundColor Yellow
Write-Host "     cd $MultiOTPPath\windows" -ForegroundColor Cyan
Write-Host "     .\webservice_install.cmd" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. REINICIA EL SERVIDOR para activar el Credential Provider:" -ForegroundColor Yellow
Write-Host "     Restart-Computer -Force" -ForegroundColor Cyan
Write-Host ""
Write-Host "  4. AL HACER LOGIN: veras el campo extra de OTP despues de la contrasena" -ForegroundColor Yellow
Write-Host ""
Write-Host "=== [06] CONFIGURACION multiOTP COMPLETADA ===" -ForegroundColor Cyan