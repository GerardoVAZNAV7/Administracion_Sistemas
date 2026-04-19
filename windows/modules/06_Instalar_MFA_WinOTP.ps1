# =============================================================================
# SCRIPT 06 - CONFIGURACION DE MFA (TOTP / Google Authenticator) - CORREGIDO
# Ejecutar en: Windows Server 2022 (como Administrator)
# CORRECCIONES: Eliminados caracteres tipograficos y operadores & en strings
# =============================================================================

Write-Host "=== [06] CONFIGURACION DE MFA (TOTP / Google Authenticator) ===" -ForegroundColor Cyan
Write-Host "NOTA: Este script configura el entorno en el servidor." -ForegroundColor Yellow

# =========================================================
# PASO 1: VERIFICAR REQUISITOS
# =========================================================
Write-Host "`n[+] Verificando requisitos previos..." -ForegroundColor Green

$DotNetKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue
if ($DotNetKey -and $DotNetKey.Release -ge 461808) {
    Write-Host "  .NET Framework 4.7.2+ detectado. OK" -ForegroundColor White
} else {
    Write-Host "  ADVERTENCIA: Se recomienda .NET 4.7.2 o superior." -ForegroundColor Red
}

# =========================================================
# PASO 2: PREPARAR DIRECTORIO DE INSTALACION
# =========================================================
$DownloadPath = "C:\MFA_Setup"
if (-not (Test-Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath | Out-Null
    Write-Host "  Directorio $DownloadPath creado." -ForegroundColor White
}

# =========================================================
# PASO 3: DESCARGAR WinOTP (si hay internet)
# =========================================================
Write-Host "`n[+] Intentando descargar WinOTP Credential Provider..." -ForegroundColor Green

$MsiPath = "$DownloadPath\WinOTP-Setup.msi"
$WinOTPUrl = "https://github.com/nicowillis/WinOTP/releases/latest/download/WinOTP-Setup.msi"

$HayInternet = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet

if ($HayInternet) {
    Write-Host "  Conexion a internet detectada. Descargando..." -ForegroundColor Green
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $WinOTPUrl -OutFile $MsiPath -UseBasicParsing -ErrorAction Stop
        Write-Host "  Descarga completada: $MsiPath" -ForegroundColor Green
    } catch {
        Write-Host "  Error en descarga: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Procediendo con configuracion manual de secretos TOTP." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Sin internet. Saltando descarga." -ForegroundColor Yellow
    Write-Host "  Copia manualmente el instalador WinOTP a: $MsiPath" -ForegroundColor Yellow
}

# =========================================================
# PASO 4: INSTALAR WinOTP (si el .msi existe)
# =========================================================
if (Test-Path $MsiPath) {
    Write-Host "`n[+] Instalando WinOTP Credential Provider..." -ForegroundColor Green
    $InstallArgs = "/i `"$MsiPath`" /qn /norestart ALLUSERS=1"
    $Result = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru
    if ($Result.ExitCode -eq 0) {
        Write-Host "  WinOTP instalado correctamente." -ForegroundColor Green
    } else {
        Write-Host "  Instalacion con codigo: $($Result.ExitCode)" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[!] Archivo .msi no encontrado. WinOTP no instalado." -ForegroundColor Yellow
    Write-Host "    Los secretos TOTP se generaran de todas formas." -ForegroundColor Yellow
}

# =========================================================
# PASO 5: GENERAR SECRETOS TOTP PARA CADA USUARIO ADMIN
# =========================================================
Write-Host "`n[+] Generando secretos TOTP para usuarios administrativos..." -ForegroundColor Green

function New-TOTPSecret {
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
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

$DomainName   = (Get-ADDomain).DNSRoot
$SecretsFile  = "C:\MFA_Setup\TOTP_Secrets.txt"
$AdminUsers   = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")

$SecretsContent  = "=== SECRETOS TOTP GENERADOS - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===`r`n"
$SecretsContent += "GUARDA ESTE ARCHIVO EN LUGAR SEGURO Y ELIMINALO DESPUES DE CONFIGURAR`r`n`r`n"

foreach ($admin in $AdminUsers) {
    $secret = New-TOTPSecret

    # Construir URI sin usar & directamente en el string expandido
    # Se usa concatenacion para evitar que PowerShell interprete & como operador
    $uriBase    = "otpauth://totp/"
    $uriAccount = [Uri]::EscapeDataString("$DomainName`:$admin")
    $uriParams  = "secret=$secret" + "&issuer=$DomainName" + "&algorithm=SHA1" + "&digits=6" + "&period=30"
    $otpAuthUri = $uriBase + $uriAccount + "?" + $uriParams

    $SecretsContent += "Usuario : $admin`r`n"
    $SecretsContent += "Secreto : $secret`r`n"
    $SecretsContent += "URI QR  : $otpAuthUri`r`n"
    $SecretsContent += "---`r`n"

    Write-Host "  Usuario : $admin" -ForegroundColor White
    Write-Host "  Secreto : $secret" -ForegroundColor Yellow
    Write-Host ""

    # Guardar en registro si WinOTP esta instalado
    $RegPath = "HKLM:\SOFTWARE\WinOTP\Users\$admin"
    try {
        if (-not (Test-Path $RegPath)) {
            New-Item -Path $RegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $RegPath -Name "TOTPSecret" -Value $secret
        Set-ItemProperty -Path $RegPath -Name "Enabled"    -Value 1
        Write-Host "  Secreto guardado en registro para: $admin" -ForegroundColor Green
    } catch {
        Write-Host "  (WinOTP no instalado aun - secreto en archivo)" -ForegroundColor Yellow
    }
}

$SecretsContent | Out-File -FilePath $SecretsFile -Encoding UTF8
Write-Host "`n  Secretos guardados en: $SecretsFile" -ForegroundColor Cyan
Write-Host "  IMPORTANTE: Usa estos secretos para configurar Google Authenticator." -ForegroundColor Magenta

# =========================================================
# PASO 6: VERIFICAR POLITICA DE BLOQUEO (3 intentos / 30 min)
# =========================================================
Write-Host "`n[+] Verificando politica de bloqueo (3 intentos / 30 min)..." -ForegroundColor Green

$PSO = Get-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" -ErrorAction SilentlyContinue
if ($PSO) {
    Write-Host "  LockoutThreshold : $($PSO.LockoutThreshold)" -ForegroundColor White
    Write-Host "  LockoutDuration  : $($PSO.LockoutDuration)"  -ForegroundColor White

    if ($PSO.LockoutThreshold -ne 3) {
        Set-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" `
            -LockoutThreshold 3 `
            -LockoutDuration (New-TimeSpan -Minutes 30) `
            -LockoutObservationWindow (New-TimeSpan -Minutes 30)
        Write-Host "  Actualizado a 3 intentos / 30 min." -ForegroundColor Green
    } else {
        Write-Host "  [OK] 3 intentos / 30 min ya configurados." -ForegroundColor Green
    }
} else {
    Write-Host "  PSO no encontrada. Ejecuta primero el Script 03." -ForegroundColor Red
}

# =========================================================
# INSTRUCCIONES PARA GOOGLE AUTHENTICATOR
# =========================================================
Write-Host "`n[+] Como configurar Google Authenticator en tu movil:" -ForegroundColor Cyan
Write-Host "  1. Abre Google Authenticator" -ForegroundColor White
Write-Host "  2. Toca + → Ingresar clave de configuracion" -ForegroundColor White
Write-Host "  3. Nombre de cuenta: admin_identidad@$DomainName" -ForegroundColor White
Write-Host "  4. Secreto: (el que aparece arriba para cada usuario)" -ForegroundColor White
Write-Host "  5. Tipo: Basado en tiempo → Guardar" -ForegroundColor White
Write-Host "  6. Ver el archivo con todos los secretos:" -ForegroundColor White
Write-Host "     Get-Content $SecretsFile" -ForegroundColor Yellow

Write-Host "`n=== [06] CONFIGURACION DE MFA COMPLETADA ===" -ForegroundColor Cyan
Write-Host "REINICIO REQUERIDO para activar el Credential Provider de WinOTP." -ForegroundColor Red
Write-Host "Siguiente paso: Ejecutar 07_Verificar_Tests.ps1" -ForegroundColor Magenta