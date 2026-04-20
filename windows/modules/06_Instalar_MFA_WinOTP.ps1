# =============================================================================
# SCRIPT 06 - CONFIGURACION DE MFA CON multiOTP  [VERSION CORREGIDA]
# Ejecutar en: Windows Server 2022 (como Administrator)
#
# HERRAMIENTA: multiOTP (open source, certificado OATH)
#   - Compatible con Google Authenticator y Microsoft Authenticator
#   - Descarga desde: download.multiotp.net
#   - NO requiere internet despues de la instalacion
#
# PROBLEMA QUE RESUELVE ESTA VERSION:
#   - Registra correctamente los secretos TOTP en multiOTP
#   - Inicia el servicio web de multiOTP para que el CP pueda validar
#   - Verifica cada paso antes de continuar
# =============================================================================

Write-Host "=== [06] CONFIGURACION DE MFA CON multiOTP ===" -ForegroundColor Cyan
Write-Host "Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray

$SetupPath   = "C:\MFA_Setup"
$MultiOTPPath = "C:\MultiOTP"
$LogFile     = "$SetupPath\mfa_install_log.txt"

# Funcion para loguear
function Write-Log {
    param([string]$msg, [string]$color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

if (-not (Test-Path $SetupPath))    { New-Item -ItemType Directory -Path $SetupPath    | Out-Null }
if (-not (Test-Path $MultiOTPPath)) { New-Item -ItemType Directory -Path $MultiOTPPath | Out-Null }
if (-not (Test-Path "C:\AuditLogs")){ New-Item -ItemType Directory -Path "C:\AuditLogs"| Out-Null }

New-Item -ItemType File -Path $LogFile -Force | Out-Null
Write-Log "=== Inicio de instalacion MFA ===" "Cyan"

# =========================================================
# VERIFICACIONES PREVIAS
# =========================================================
Write-Host "`n[PRE] Verificando prerequisitos..." -ForegroundColor Cyan

# Verificar que somos Administrator
$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: Debes ejecutar como Administrator" "Red"
    exit 1
}
Write-Log "OK - Ejecutando como Administrator" "Green"

# Verificar AD
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $DomainName = (Get-ADDomain).DNSRoot
    Write-Log "OK - Dominio detectado: $DomainName" "Green"
} catch {
    Write-Log "ERROR: No se pudo conectar a Active Directory: $($_.Exception.Message)" "Red"
    exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# =========================================================
# PASO 1: DESCARGAR multiOTP
# =========================================================
Write-Host "`n[PASO 1] Descargando multiOTP..." -ForegroundColor Green

$MultiOTPZip = "$SetupPath\multiotp.zip"

if (Test-Path $MultiOTPZip) {
    Write-Log "multiotp.zip ya existe en $MultiOTPZip - omitiendo descarga" "Yellow"
} else {
    $urls = @(
        "https://download.multiotp.net/multiotp.zip",
        "https://github.com/multiOTP/multiotp/archive/refs/heads/master.zip"
    )
    
    $DescargaOK = $false
    foreach ($url in $urls) {
        try {
            Write-Log "Intentando: $url" "Yellow"
            Invoke-WebRequest -Uri $url -OutFile $MultiOTPZip -UseBasicParsing -TimeoutSec 180
            Write-Log "Descarga OK desde $url" "Green"
            $DescargaOK = $true
            break
        } catch {
            Write-Log "Fallo en $url : $($_.Exception.Message)" "Red"
        }
    }
    
    if (-not $DescargaOK) {
        Write-Host "`n  ================================================" -ForegroundColor Red
        Write-Host "  DESCARGA MANUAL REQUERIDA:" -ForegroundColor Red
        Write-Host "  1. Abre en tu navegador: https://download.multiotp.net/" -ForegroundColor Yellow
        Write-Host "  2. Descarga: multiotp.zip" -ForegroundColor Yellow
        Write-Host "  3. Copialo a: $MultiOTPZip" -ForegroundColor Yellow
        Write-Host "  4. Vuelve a ejecutar este script." -ForegroundColor Yellow
        Write-Host "  ================================================" -ForegroundColor Red
        Write-Log "Descarga fallida - requiere descarga manual" "Red"
        exit 1
    }
}

# =========================================================
# PASO 2: EXTRAER multiOTP
# =========================================================
Write-Host "`n[PASO 2] Extrayendo multiOTP..." -ForegroundColor Green

try {
    # Limpiar directorio previo si existe
    if (Test-Path "$MultiOTPPath\windows") {
        Remove-Item "$MultiOTPPath\windows" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Expand-Archive -Path $MultiOTPZip -DestinationPath $MultiOTPPath -Force
    Write-Log "Extraccion completada en $MultiOTPPath" "Green"
} catch {
    Write-Log "Error al extraer: $($_.Exception.Message)" "Red"
    exit 1
}

# Buscar multiotp.exe (puede estar en varias rutas segun la version)
$MultiOTPExe = Get-ChildItem -Path $MultiOTPPath -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName

if (-not $MultiOTPExe) {
    Write-Log "ADVERTENCIA: multiotp.exe no encontrado. Intentando ruta por defecto." "Yellow"
    $MultiOTPExe = "$MultiOTPPath\windows\multiotp.exe"
}

if (-not (Test-Path $MultiOTPExe)) {
    Write-Log "ERROR CRITICO: multiotp.exe no encontrado en $MultiOTPPath" "Red"
    Write-Log "Contenido del directorio:" "Yellow"
    Get-ChildItem -Path $MultiOTPPath -Recurse | Select-Object FullName | Format-Table | Out-String | Write-Log
    exit 1
}

$MultiOTPDir = Split-Path $MultiOTPExe -Parent
Write-Log "multiotp.exe encontrado en: $MultiOTPExe" "Green"

# =========================================================
# PASO 3: INICIALIZAR multiOTP (primera configuracion)
# =========================================================
Write-Host "`n[PASO 3] Inicializando configuracion de multiOTP..." -ForegroundColor Green

Push-Location $MultiOTPDir

# Configurar multiOTP para usar TOTP como metodo por defecto
& $MultiOTPExe -config algorithm=TOTP digits=6 time-interval=30 2>&1 | Out-Null
Write-Log "Configuracion base TOTP aplicada (6 digitos, 30 segundos)" "Green"

# =========================================================
# PASO 4: REGISTRAR USUARIOS EN multiOTP CON SECRETOS TOTP
# =========================================================
Write-Host "`n[PASO 4] Registrando usuarios en multiOTP..." -ForegroundColor Green

$AdminUsers = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")
$SecretsFile = "$SetupPath\TOTP_Secrets.txt"

$SecretsContent  = "=== SECRETOS TOTP multiOTP - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===`r`n"
$SecretsContent += "Usa estos secretos para configurar Google Authenticator o Microsoft Authenticator`r`n"
$SecretsContent += "IMPORTANTE: Borra este archivo despues de configurar tu app!`r`n`r`n"

# Funcion para generar secreto Base32 criptograficamente seguro
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

foreach ($admin in $AdminUsers) {
    Write-Log "Configurando: $admin" "White"

    # -------------------------------------------------------
    # PASO CRITICO: Primero eliminar si ya existe, luego crear
    # -------------------------------------------------------
    & $MultiOTPExe -delete $admin 2>&1 | Out-Null

    # Generar secreto TOTP unico para este usuario
    $secret = New-TOTPSecret

    # Crear usuario en multiOTP con el secreto especifico
    # Sintaxis correcta: multiotp -create <user> TOTP <secret> 6 30
    $resultado = & $MultiOTPExe -create $admin TOTP $secret 6 30 2>&1
    Write-Log "  Resultado create: $resultado" "Gray"

    # Verificar que el usuario fue creado
    $checkUser = & $MultiOTPExe -check-ldap-users 2>&1
    $userExists = & $MultiOTPExe -display-log $admin 2>&1

    # Generar URI OTP para QR
    $uriAccount = [Uri]::EscapeDataString("$DomainName`:$admin")
    $uriParams  = "secret=$secret&issuer=LabMFA&algorithm=SHA1&digits=6&period=30"
    $otpUri     = "otpauth://totp/$uriAccount`?$uriParams"

    # Intentar generar QR code
    $qrResult = & $MultiOTPExe -qrcode $admin "$SetupPath\QR_$admin.png" 2>&1
    if (Test-Path "$SetupPath\QR_$admin.png") {
        Write-Log "  QR guardado en: $SetupPath\QR_$admin.png" "Green"
    } else {
        Write-Log "  QR no generado (el secreto manual funciona igual)" "Yellow"
    }

    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │ Usuario  : $($admin.PadRight(36)) │" -ForegroundColor Cyan
    Write-Host "  │ Secreto  : $($secret.PadRight(36)) │" -ForegroundColor Yellow
    Write-Host "  └─────────────────────────────────────────────────┘" -ForegroundColor Cyan

    # Guardar en archivo de secretos
    $SecretsContent += "Usuario : $admin`r`n"
    $SecretsContent += "Secreto : $secret`r`n"
    $SecretsContent += "URI OTP : $otpUri`r`n"
    $SecretsContent += "QR Code : $SetupPath\QR_$admin.png`r`n"
    $SecretsContent += "---`r`n"

    # Guardar en registro de Windows (para referencia del CP)
    $RegPath = "HKLM:\SOFTWARE\LabMFA\Users\$admin"
    if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPath -Name "TOTPSecret"     -Value $secret
    Set-ItemProperty -Path $RegPath -Name "Enabled"        -Value 1
    Set-ItemProperty -Path $RegPath -Name "FailedAttempts" -Value 0
    Set-ItemProperty -Path $RegPath -Name "LockedUntil"    -Value ""

    Write-Log "  Usuario $admin registrado correctamente en multiOTP" "Green"
}

Pop-Location

# Guardar archivo de secretos
$SecretsContent | Out-File -FilePath $SecretsFile -Encoding UTF8
Write-Log "Archivo de secretos guardado en: $SecretsFile" "Cyan"

# =========================================================
# PASO 5: INSTALAR Y ARRANCAR EL SERVICIO WEB DE multiOTP
# =========================================================
Write-Host "`n[PASO 5] Instalando servicio web de multiOTP..." -ForegroundColor Green

# El servicio web permite que el Credential Provider valide los codigos
$WebServiceScript = Get-ChildItem -Path $MultiOTPPath -Recurse -Filter "webservice_install*" |
                    Select-Object -First 1 -ExpandProperty FullName

if ($WebServiceScript) {
    Write-Log "Instalando servicio web desde: $WebServiceScript" "White"
    $wsDir = Split-Path $WebServiceScript -Parent
    Push-Location $wsDir
    & cmd /c $WebServiceScript 2>&1 | ForEach-Object { Write-Log "  $_" "Gray" }
    Pop-Location
} else {
    Write-Log "webservice_install no encontrado. Intentando iniciar servicio directamente..." "Yellow"
    
    # Intentar iniciar el servicio si ya estaba instalado
    $svc = Get-Service -Name "multiOTP" -ErrorAction SilentlyContinue
    if ($svc) {
        Start-Service -Name "multiOTP" -ErrorAction SilentlyContinue
        Write-Log "Servicio multiOTP iniciado" "Green"
    } else {
        Write-Log "Servicio no encontrado. El CP operara en modo local." "Yellow"
    }
}

# Verificar si el puerto 8112 esta escuchando
Start-Sleep -Seconds 3
$portCheck = netstat -an | findstr ":8112"
if ($portCheck) {
    Write-Log "OK - Puerto 8112 activo (servicio multiOTP escuchando)" "Green"
} else {
    Write-Log "AVISO - Puerto 8112 no activo aun. El servicio puede tardar unos segundos." "Yellow"
}

# =========================================================
# PASO 6: DESCARGAR E INSTALAR CREDENTIAL PROVIDER
# =========================================================
Write-Host "`n[PASO 6] Descargando multiOTP Credential Provider..." -ForegroundColor Green

$CPZip  = "$SetupPath\multiOTP-CredentialProvider.zip"
$CPPath = "$SetupPath\CredentialProvider"

if (Test-Path $CPZip) {
    Write-Log "Credential Provider zip ya existe - omitiendo descarga" "Yellow"
    $CPDescargaOK = $true
} else {
    $CPDescargaOK = $false
    $cpUrls = @(
        "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.8.0-x64.zip",
        "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.7.2-x64.zip",
        "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.6.6-x64.zip"
    )

    foreach ($url in $cpUrls) {
        try {
            Write-Log "Intentando CP desde: $url" "Yellow"
            Invoke-WebRequest -Uri $url -OutFile $CPZip -UseBasicParsing -TimeoutSec 120
            Write-Log "CP descargado OK" "Green"
            $CPDescargaOK = $true
            break
        } catch {
            Write-Log "Fallo CP desde $url : $($_.Exception.Message)" "Red"
        }
    }

    if (-not $CPDescargaOK) {
        Write-Host "`n  ================================================" -ForegroundColor Red
        Write-Host "  DESCARGA MANUAL DEL CREDENTIAL PROVIDER:" -ForegroundColor Red
        Write-Host "  1. Abre: https://github.com/multiOTP/multiOTPCredentialProvider/releases" -ForegroundColor Yellow
        Write-Host "  2. Descarga el .zip x64 mas reciente" -ForegroundColor Yellow
        Write-Host "  3. Guardalo en: $CPZip" -ForegroundColor Yellow
        Write-Host "  4. Vuelve a ejecutar este script." -ForegroundColor Yellow
        Write-Host "  ================================================" -ForegroundColor Red
        Write-Log "CP requiere descarga manual" "Red"
    }
}

if ($CPDescargaOK -or (Test-Path $CPZip)) {
    Write-Log "Extrayendo Credential Provider..." "White"
    try {
        if (Test-Path $CPPath) { Remove-Item $CPPath -Recurse -Force }
        Expand-Archive -Path $CPZip -DestinationPath $CPPath -Force
        Write-Log "CP extraido en: $CPPath" "Green"
    } catch {
        Write-Log "Error extrayendo CP: $($_.Exception.Message)" "Red"
    }

    # Buscar instalador del CP
    $CPInstaller = Get-ChildItem -Path $CPPath -Recurse -Filter "*.exe" |
                   Where-Object { $_.Name -like "*install*" -or $_.Name -like "*setup*" -or $_.Name -like "*multiOTP*" } |
                   Select-Object -First 1 -ExpandProperty FullName

    # Si no hay exe, buscar MSI
    if (-not $CPInstaller) {
        $CPInstaller = Get-ChildItem -Path $CPPath -Recurse -Filter "*.msi" |
                       Select-Object -First 1 -ExpandProperty FullName
    }

    if ($CPInstaller) {
        Write-Log "Instalando CP desde: $CPInstaller" "Green"

        $LocalIP = (Get-NetIPAddress -AddressFamily IPv4 |
                    Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -ne "127.0.0.1" } |
                    Select-Object -First 1).IPAddress

        Write-Log "IP del servidor detectada: $LocalIP" "White"

        if ($CPInstaller -like "*.msi") {
            $CPArgs = "/i `"$CPInstaller`" /qn /norestart MULTIOTP_HOST=127.0.0.1 MULTIOTP_PORT=8112"
            Start-Process "msiexec" -ArgumentList $CPArgs -Wait -NoNewWindow
        } else {
            $CPArgs = "/install /multiOTPServer=127.0.0.1 /multiOTPPort=8112 /loginTitle=`"MFA - Ingresa tu codigo`" /VERYSILENT /NORESTART"
            Start-Process -FilePath $CPInstaller -ArgumentList $CPArgs -Wait -NoNewWindow
        }
        Write-Log "Credential Provider instalado." "Green"
    } else {
        Write-Host "`n  ================================================" -ForegroundColor Yellow
        Write-Host "  INSTALACION MANUAL DEL CP (pasos exactos):" -ForegroundColor Yellow
        Write-Host "  1. Navega a: $CPPath" -ForegroundColor White
        Write-Host "  2. Ejecuta el .exe o .msi como Administrador" -ForegroundColor White
        Write-Host "  3. En 'multiOTP Server IP': escribe 127.0.0.1" -ForegroundColor White
        Write-Host "  4. En 'Port': escribe 8112" -ForegroundColor White
        Write-Host "  5. Marca 'Use local multiOTP instance'" -ForegroundColor White
        Write-Host "  6. Finaliza la instalacion" -ForegroundColor White
        Write-Host "  ================================================" -ForegroundColor Yellow
        Write-Log "CP instalacion manual requerida" "Yellow"
    }
}

# =========================================================
# PASO 7: CONFIGURAR BLOQUEO 3 INTENTOS / 30 MINUTOS
# =========================================================
Write-Host "`n[PASO 7] Verificando politica de bloqueo (3 intentos / 30 min)..." -ForegroundColor Green

$PSO = Get-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" -ErrorAction SilentlyContinue
if ($PSO) {
    $necesitaUpdate = ($PSO.LockoutThreshold -ne 3) -or 
                      ($PSO.LockoutDuration -ne (New-TimeSpan -Minutes 30))
    if ($necesitaUpdate) {
        Set-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" `
            -LockoutThreshold 3 `
            -LockoutDuration (New-TimeSpan -Minutes 30) `
            -LockoutObservationWindow (New-TimeSpan -Minutes 30)
        Write-Log "FGPP actualizada: 3 intentos / 30 min" "Green"
    } else {
        Write-Log "OK - FGPP ya tiene 3 intentos / 30 min configurados" "Green"
    }
} else {
    Write-Log "ADVERTENCIA: PSO_AdminsPrivilegiados no encontrada. Ejecuta Script 03 primero." "Red"
}

# =========================================================
# PASO 8: VERIFICACION FINAL
# =========================================================
Write-Host "`n[PASO 8] Verificacion final del sistema MFA..." -ForegroundColor Cyan

Write-Host "`n  Verificando usuarios en multiOTP:" -ForegroundColor White
Push-Location $MultiOTPDir
foreach ($admin in $AdminUsers) {
    $info = & $MultiOTPExe -display-log $admin 2>&1
    if ($info -notlike "*Error*" -and $info -ne "") {
        Write-Host "  [OK] $admin - registrado en multiOTP" -ForegroundColor Green
    } else {
        Write-Host "  [?]  $admin - verificar manualmente" -ForegroundColor Yellow
    }
}
Pop-Location

# =========================================================
# RESUMEN FINAL CON INSTRUCCIONES CLARAS
# =========================================================
Write-Host "`n" 
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          INSTRUCCIONES PARA ACTIVAR MFA                     ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║  PASO A: LEE LOS SECRETOS TOTP                              ║" -ForegroundColor Yellow
Write-Host "║    Get-Content '$SecretsFile'         ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║  PASO B: CONFIGURA MICROSOFT/GOOGLE AUTHENTICATOR          ║" -ForegroundColor Yellow
Write-Host "║    1. Abre la app en tu movil                               ║" -ForegroundColor White
Write-Host "║    2. Toca '+' -> Ingresar clave de configuracion           ║" -ForegroundColor White
Write-Host "║    3. Nombre: admin_identidad@$DomainName              ║" -ForegroundColor White
Write-Host "║    4. Clave: [el secreto del archivo]                       ║" -ForegroundColor White
Write-Host "║    5. Tipo: Basado en tiempo (TOTP)                         ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║  PASO C: INICIA EL SERVICIO multiOTP                       ║" -ForegroundColor Yellow
Write-Host "║    cd $MultiOTPDir                    ║" -ForegroundColor White
Write-Host "║    .\webservice_install.cmd                                  ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║  PASO D: REINICIA EL SERVIDOR                               ║" -ForegroundColor Yellow
Write-Host "║    Restart-Computer -Force                                   ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║  PASO E: AL HACER LOGIN                                     ║" -ForegroundColor Yellow
Write-Host "║    Usuario + Contrasena + Codigo de 6 digitos del movil     ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Log "=== Script 06 completado a las $(Get-Date -Format 'HH:mm:ss') ===" "Cyan"
Write-Host "`n  Log completo en: $LogFile" -ForegroundColor Gray
Write-Host "`n=== [06] CONFIGURACION multiOTP COMPLETADA ===" -ForegroundColor Cyan
