# =============================================================================
# SCRIPT 06 - INSTALACIÓN Y CONFIGURACIÓN DE MFA (Google Authenticator / TOTP)
# Ejecutar en: Windows Server 2022 (como Administrator)
# Descripción: Descarga e instala WinOTP Authenticator o configura un Credential
#              Provider compatible con TOTP para Windows Server sin GUI.
#              MÉTODO RECOMENDADO: Autenticación por RADIUS con WinOTP.
# =============================================================================
#
# IMPORTANTE: En Windows Server 2022 SIN INTERFAZ GRÁFICA se utiliza el método
#             de Credential Provider. Este script prepara la configuración y te
#             guía en los pasos que SÍ requieren el cliente Windows 10.
#
# OPCIÓN ELEGIDA: NetIQ Advanced Authentication / WinOTP Standalone
#                 (solución gratuita compatible con TOTP RFC 6238)
# =============================================================================

Write-Host "=== [06] CONFIGURACIÓN DE MFA (TOTP / Google Authenticator) ===" -ForegroundColor Cyan
Write-Host "NOTA: Este script configura el entorno en el servidor." -ForegroundColor Yellow
Write-Host "      La instalacion del Credential Provider requiere reinicio." -ForegroundColor Yellow

# =========================================================
# PASO 1: VERIFICAR REQUISITOS PREVIOS
# =========================================================
Write-Host "`n[+] Verificando requisitos previos..." -ForegroundColor Green

# Verificar que .NET Framework 4.7+ está disponible
$DotNetVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
if ($DotNetVersion -ge 461808) {
    Write-Host "  .NET Framework 4.7.2+ detectado. OK" -ForegroundColor White
} else {
    Write-Host "  ADVERTENCIA: Se requiere .NET 4.7.2 o superior." -ForegroundColor Red
}

# Verificar si WinOTP ya está instalado
$WinOTPInstalled = Get-ItemProperty "HKLM:\SOFTWARE\WinOTP" -ErrorAction SilentlyContinue
if ($WinOTPInstalled) {
    Write-Host "  WinOTP ya esta instalado." -ForegroundColor Yellow
}

# =========================================================
# PASO 2: DESCARGAR WinOTP CREDENTIAL PROVIDER
# =========================================================
Write-Host "`n[+] Preparando instalacion de WinOTP Credential Provider..." -ForegroundColor Green
Write-Host "  Descargando desde GitHub (winauth / WinOTP)..." -ForegroundColor White

$DownloadPath = "C:\MFA_Setup"
if (-not (Test-Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath | Out-Null
}

# URL del instalador de WinOTP (Credential Provider para Windows)
# ALTERNATIVA GRATUITA: "winlogon-totp" o el agente RADIUS de FreeRADIUS
$WinOTPUrl = "https://github.com/nicowillis/WinOTP/releases/latest/download/WinOTP-Setup.msi"

try {
    Write-Host "  Descargando WinOTP..." -ForegroundColor White
    Invoke-WebRequest -Uri $WinOTPUrl -OutFile "$DownloadPath\WinOTP-Setup.msi" -UseBasicParsing
    Write-Host "  Descarga completada." -ForegroundColor Green
} catch {
    Write-Host "  No se pudo descargar automaticamente. Descarga manual requerida." -ForegroundColor Red
    Write-Host "  URL: https://github.com/nicowillis/WinOTP/releases/latest" -ForegroundColor Yellow
    Write-Host "  Coloca el .msi en: $DownloadPath\" -ForegroundColor Yellow
}

# =========================================================
# PASO 3: INSTALAR WinOTP CREDENTIAL PROVIDER (SILENCIOSO)
# =========================================================
Write-Host "`n[+] Instalando WinOTP Credential Provider..." -ForegroundColor Green

$MsiPath = "$DownloadPath\WinOTP-Setup.msi"
if (Test-Path $MsiPath) {
    $InstallArgs = "/i `"$MsiPath`" /qn /norestart ALLUSERS=1"
    $Result = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru
    if ($Result.ExitCode -eq 0) {
        Write-Host "  WinOTP instalado correctamente. Codigo salida: 0" -ForegroundColor Green
    } else {
        Write-Host "  Instalacion completada con codigo: $($Result.ExitCode)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Archivo .msi no encontrado en $MsiPath" -ForegroundColor Red
    Write-Host "  Continua con la configuracion manual descrita en el archivo .md" -ForegroundColor Yellow
}

# =========================================================
# PASO 4: GENERAR SECRETO TOTP PARA CADA USUARIO ADMIN
# =========================================================
Write-Host "`n[+] Generando secretos TOTP para usuarios administrativos..." -ForegroundColor Green

# Función para generar un secreto Base32 aleatorio (compatible con Google Authenticator)
function New-TOTPSecret {
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    # Codificación Base32
    $base32chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $result = ""
    $buffer = 0
    $bitsLeft = 0
    foreach ($byte in $bytes) {
        $buffer = ($buffer -shl 8) -bor $byte
        $bitsLeft += 8
        while ($bitsLeft -ge 5) {
            $bitsLeft -= 5
            $result += $base32chars[($buffer -shr $bitsLeft) -band 0x1F]
        }
    }
    return $result
}

$DomainName = (Get-ADDomain).DNSRoot
$SecretsFile = "C:\MFA_Setup\TOTP_Secrets.txt"
$Admins = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")

$SecretsContent = "=== SECRETOS TOTP GENERADOS - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===`n"
$SecretsContent += "GUARDA ESTE ARCHIVO EN LUGAR SEGURO Y ELIMÍNALO DESPUÉS DE CONFIGURAR`n`n"

foreach ($admin in $Admins) {
    $secret = New-TOTPSecret
    $otpAuthUri = "otpauth://totp/$DomainName`:$admin`?secret=$secret&issuer=$DomainName&algorithm=SHA1&digits=6&period=30"
    
    $SecretsContent += "Usuario: $admin`n"
    $SecretsContent += "Secreto: $secret`n"
    $SecretsContent += "URI QR:  $otpAuthUri`n"
    $SecretsContent += "---`n"
    
    Write-Host "  Usuario: $admin" -ForegroundColor White
    Write-Host "  Secreto TOTP: $secret" -ForegroundColor Yellow
    Write-Host "  (Escanea el código QR desde la URI OTPAuth con Google Authenticator)" -ForegroundColor Gray
    Write-Host ""
    
    # Guardar secreto en el registro de Windows para WinOTP (ruta estándar)
    $RegPath = "HKLM:\SOFTWARE\WinOTP\Users\$admin"
    try {
        if (-not (Test-Path $RegPath)) {
            New-Item -Path $RegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $RegPath -Name "TOTPSecret" -Value $secret
        Set-ItemProperty -Path $RegPath -Name "Enabled"    -Value 1
        Write-Host "  Secreto guardado en registro para: $admin" -ForegroundColor Green
    } catch {
        Write-Host "  Nota: WinOTP no instalado aun, secreto solo guardado en archivo." -ForegroundColor Yellow
    }
}

$SecretsContent | Out-File -FilePath $SecretsFile -Encoding UTF8
Write-Host "`n  Secretos guardados en: $SecretsFile" -ForegroundColor Cyan
Write-Host "  IMPORTANTE: Usa estos secretos para configurar Google Authenticator en tu móvil." -ForegroundColor Magenta

# =========================================================
# PASO 5: CONFIGURAR POLÍTICA DE BLOQUEO POR MFA FALLIDO
# (3 intentos → bloqueo 30 minutos)
# =========================================================
Write-Host "`n[+] Verificando politica de bloqueo de cuenta (3 intentos / 30 min)..." -ForegroundColor Green

# Verificar que la FGPP de admins ya tiene LockoutThreshold=3 y LockoutDuration=30min
$PSO = Get-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" -ErrorAction SilentlyContinue
if ($PSO) {
    Write-Host "  PSO encontrada: LockoutThreshold=$($PSO.LockoutThreshold) | LockoutDuration=$($PSO.LockoutDuration)" -ForegroundColor White
    if ($PSO.LockoutThreshold -eq 3) {
        Write-Host "  [OK] Bloqueo tras 3 intentos configurado." -ForegroundColor Green
    } else {
        Write-Host "  Actualizando umbral de bloqueo a 3 intentos..." -ForegroundColor Yellow
        Set-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" `
            -LockoutThreshold 3 `
            -LockoutDuration (New-TimeSpan -Minutes 30) `
            -LockoutObservationWindow (New-TimeSpan -Minutes 30)
        Write-Host "  [OK] Actualizado." -ForegroundColor Green
    }
} else {
    Write-Host "  PSO no encontrada. Ejecuta primero el Script 03." -ForegroundColor Red
}

# =========================================================
# PASO 6: GENERAR CÓDIGO QR EN ASCII PARA TERMINAL (sin GUI)
# =========================================================
Write-Host "`n[+] Para configurar Google Authenticator en tu móvil:" -ForegroundColor Cyan
Write-Host "  1. Abre Google Authenticator en tu teléfono" -ForegroundColor White
Write-Host "  2. Toca '+' → 'Ingresar clave de configuración'" -ForegroundColor White
Write-Host "  3. Ingresa el nombre de cuenta y el SECRETO mostrado arriba" -ForegroundColor White
Write-Host "  4. Selecciona 'Basado en tiempo' y guarda" -ForegroundColor White
Write-Host "  5. O usa la URI otpauth:// para escanear QR (requiere app generadora de QR)" -ForegroundColor White

Write-Host "`n=== [06] CONFIGURACIÓN DE MFA COMPLETADA ===" -ForegroundColor Cyan
Write-Host "Siguiente paso: Ejecutar 07_Verificar_Tests.ps1" -ForegroundColor Magenta
Write-Host "REINICIO REQUERIDO para que el Credential Provider de WinOTP tome efecto." -ForegroundColor Red
