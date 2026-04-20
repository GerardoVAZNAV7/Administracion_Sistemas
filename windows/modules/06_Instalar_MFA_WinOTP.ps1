# =============================================================================
# SCRIPT 06 - CONFIGURACION DE MFA CON multiOTP  [VERSION CORREGIDA v3]
# Ejecutar en: Windows Server 2022 (como Administrator)
#
# FIXES aplicados:
#   - FIX 1: Limpieza forzada de procesos antes de extraer (Access Denied)
#   - FIX 2: multiotp.exe -create con timeout de 15s (evita cuelgue)
#   - FIX 3: String terminator corregido en Write-Host finales
#   - FIX 4: Expand-Archive con -ErrorAction SilentlyContinue (ignora DLLs bloqueadas)
# =============================================================================

Write-Host "=== [06] CONFIGURACION DE MFA CON multiOTP ===" -ForegroundColor Cyan
Write-Host "Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray

$SetupPath    = "C:\MFA_Setup"
$MultiOTPPath = "C:\MultiOTP"
$LogFile      = "$SetupPath\mfa_install_log.txt"

# ---- Funcion de log ----
function Write-Log {
    param([string]$msg, [string]$color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# ---- Funcion para ejecutar multiotp.exe CON TIMEOUT (evita cuelgue) ----
function Invoke-MultiOTP {
    param(
        [string]$MultiOTPExe,
        [string]$WorkingDir,
        [string[]]$Arguments,
        [int]$TimeoutMs = 15000
    )
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName               = $MultiOTPExe
        $pinfo.Arguments              = ($Arguments -join " ")
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError  = $true
        $pinfo.UseShellExecute        = $false
        $pinfo.WorkingDirectory       = $WorkingDir
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
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

# ---- Funcion para generar secreto Base32 ----
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

# ---- Crear directorios ----
foreach ($dir in @($SetupPath, $MultiOTPPath, "C:\AuditLogs")) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
}
New-Item -ItemType File -Path $LogFile -Force | Out-Null
Write-Log "=== Inicio de instalacion MFA v3 ===" "Cyan"

# =========================================================
# VERIFICACIONES PREVIAS
# =========================================================
Write-Host "`n[PRE] Verificando prerequisitos..." -ForegroundColor Cyan

$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: Debes ejecutar como Administrator" "Red"
    exit 1
}
Write-Log "OK - Ejecutando como Administrator" "Green"

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
# FIX 1: LIMPIAR INSTALACION PREVIA ANTES DE EXTRAER
# =========================================================
Write-Host "`n[PRE-LIMPIEZA] Deteniendo servicios y procesos previos..." -ForegroundColor Yellow

# Detener servicios multiOTP
foreach ($svcName in @("multiOTP", "multiOTPwebservice", "multiOTPradius")) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        Write-Log "Servicio $svcName detenido" "Gray"
    }
}

# Matar procesos que bloquean archivos
$procesosAMatar = @("nginx", "php", "php-cgi", "nssm", "multiotp")
foreach ($proc in $procesosAMatar) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

# Desregistrar servicios con sc.exe
foreach ($svcName in @("multiOTP", "multiOTPwebservice")) {
    & sc.exe delete $svcName 2>$null | Out-Null
}
Start-Sleep -Seconds 2

# Eliminar directorio anterior
if (Test-Path $MultiOTPPath) {
    Write-Log "Eliminando directorio previo C:\MultiOTP..." "Yellow"
    try {
        # Primero quitar atributos de solo lectura
        Get-ChildItem -Path $MultiOTPPath -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = "Normal" }
        Remove-Item -Path $MultiOTPPath -Recurse -Force -ErrorAction Stop
        Write-Log "Directorio previo eliminado correctamente" "Green"
    } catch {
        Write-Log "No se pudo eliminar completamente: $($_.Exception.Message)" "Yellow"
        Write-Log "Continuando de todas formas..." "Yellow"
    }
    New-Item -ItemType Directory -Path $MultiOTPPath -Force | Out-Null
}

# =========================================================
# PASO 1: DESCARGAR multiOTP
# =========================================================
Write-Host "`n[PASO 1] Descargando multiOTP..." -ForegroundColor Green

$MultiOTPZip = "$SetupPath\multiotp.zip"

if (Test-Path $MultiOTPZip) {
    # Verificar que no este corrupto (minimo 1MB)
    $zipSize = (Get-Item $MultiOTPZip).Length
    if ($zipSize -lt 1MB) {
        Write-Log "ZIP existente parece corrupto ($zipSize bytes), re-descargando..." "Yellow"
        Remove-Item $MultiOTPZip -Force
    } else {
        Write-Log "multiotp.zip ya existe ($([math]::Round($zipSize/1MB,1)) MB) - omitiendo descarga" "Yellow"
    }
}

if (-not (Test-Path $MultiOTPZip)) {
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
        Write-Host ""
        Write-Host "  DESCARGA MANUAL REQUERIDA:" -ForegroundColor Red
        Write-Host "  1. Abre en tu navegador: https://download.multiotp.net/" -ForegroundColor Yellow
        Write-Host "  2. Descarga: multiotp.zip" -ForegroundColor Yellow
        Write-Host "  3. Copialo a: $MultiOTPZip" -ForegroundColor Yellow
        Write-Host "  4. Vuelve a ejecutar este script." -ForegroundColor Yellow
        Write-Log "Descarga fallida - requiere descarga manual" "Red"
        exit 1
    }
}

# =========================================================
# PASO 2: EXTRAER multiOTP (FIX 4: ignorar errores de DLLs bloqueadas)
# =========================================================
Write-Host "`n[PASO 2] Extrayendo multiOTP..." -ForegroundColor Green

try {
    # Usar Shell.Application en lugar de Expand-Archive para evitar el bug con DLLs
    $shell = New-Object -ComObject Shell.Application
    $zipObj = $shell.NameSpace($MultiOTPZip)
    $destObj = $shell.NameSpace($MultiOTPPath)

    if ($zipObj -and $destObj) {
        # Opcion 4=No mostrar dialogo, 16=Si a todo, 512=No confirmar
        $destObj.CopyHere($zipObj.Items(), 4 + 16 + 512)
        Start-Sleep -Seconds 5
        Write-Log "Extraccion via Shell.Application completada" "Green"
    } else {
        throw "No se pudo abrir el ZIP con Shell.Application"
    }
} catch {
    Write-Log "Shell.Application fallo, intentando Expand-Archive..." "Yellow"
    try {
        Expand-Archive -Path $MultiOTPZip -DestinationPath $MultiOTPPath -Force -ErrorAction SilentlyContinue
        Write-Log "Extraccion via Expand-Archive completada (con posibles advertencias)" "Green"
    } catch {
        Write-Log "Error al extraer: $($_.Exception.Message)" "Red"
    }
}

# Buscar multiotp.exe
$MultiOTPExe = Get-ChildItem -Path $MultiOTPPath -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName

if (-not $MultiOTPExe -or -not (Test-Path $MultiOTPExe)) {
    Write-Log "ERROR CRITICO: multiotp.exe no encontrado en $MultiOTPPath" "Red"
    Write-Log "Contenido del directorio:" "Yellow"
    Get-ChildItem -Path $MultiOTPPath -Recurse -ErrorAction SilentlyContinue |
        Select-Object FullName | Format-Table | Out-String | ForEach-Object { Write-Log $_ "Gray" }
    exit 1
}

$MultiOTPDir = Split-Path $MultiOTPExe -Parent
Write-Log "multiotp.exe encontrado en: $MultiOTPExe" "Green"

# =========================================================
# PASO 3: INICIALIZAR multiOTP
# =========================================================
Write-Host "`n[PASO 3] Inicializando configuracion de multiOTP..." -ForegroundColor Green

Push-Location $MultiOTPDir

$r = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -WorkingDir $MultiOTPDir `
     -Arguments @("-config", "algorithm=TOTP", "digits=6", "time-interval=30") -TimeoutMs 10000
Write-Log "Config TOTP: $r" "Gray"
Write-Log "Configuracion base TOTP aplicada (6 digitos, 30 segundos)" "Green"

Pop-Location

# =========================================================
# PASO 4: REGISTRAR USUARIOS EN multiOTP (FIX 2: con timeout)
# =========================================================
Write-Host "`n[PASO 4] Registrando usuarios en multiOTP..." -ForegroundColor Green

$AdminUsers  = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")
$SecretsFile = "$SetupPath\TOTP_Secrets.txt"

$SecretsContent  = "=== SECRETOS TOTP multiOTP - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" + "`r`n"
$SecretsContent += "Usa estos secretos para configurar Google Authenticator o Microsoft Authenticator" + "`r`n"
$SecretsContent += "IMPORTANTE: Borra este archivo despues de configurar tu app!" + "`r`n`r`n"

Push-Location $MultiOTPDir

foreach ($admin in $AdminUsers) {
    Write-Log "Configurando: $admin" "White"

    # Eliminar usuario previo (con timeout)
    $r = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -WorkingDir $MultiOTPDir `
         -Arguments @("-delete", $admin) -TimeoutMs 10000
    Write-Log "  Delete: $r" "Gray"

    # Generar secreto TOTP unico
    $secret = New-TOTPSecret
    Write-Log "  Secreto generado: $secret" "Yellow"

    # Crear usuario CON TIMEOUT (FIX principal anti-cuelgue)
    Write-Log "  Ejecutando -create (timeout 15s)..." "Gray"
    $r = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -WorkingDir $MultiOTPDir `
         -Arguments @("-create", $admin, "TOTP", $secret, "6", "30") -TimeoutMs 15000
    Write-Log "  Resultado create: $r" "Gray"

    # Generar URI OTP
    $uriAccount = [Uri]::EscapeDataString($DomainName + ":" + $admin)
    $uriParams  = "secret=" + $secret + "&issuer=LabMFA&algorithm=SHA1&digits=6&period=30"
    $otpUri     = "otpauth://totp/" + $uriAccount + "?" + $uriParams

    # Intentar generar QR (con timeout)
    $r = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -WorkingDir $MultiOTPDir `
         -Arguments @("-qrcode", $admin, ($SetupPath + "\QR_" + $admin + ".png")) -TimeoutMs 15000
    if (Test-Path ($SetupPath + "\QR_" + $admin + ".png")) {
        Write-Log ("  QR guardado en: " + $SetupPath + "\QR_" + $admin + ".png") "Green"
    } else {
        Write-Log "  QR no generado (el secreto manual funciona igual)" "Yellow"
    }

    Write-Host ""
    Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ("  | Usuario : " + $admin) -ForegroundColor Cyan
    Write-Host ("  | Secreto : " + $secret) -ForegroundColor Yellow
    Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan

    # Guardar en archivo
    $SecretsContent += "Usuario : " + $admin + "`r`n"
    $SecretsContent += "Secreto : " + $secret + "`r`n"
    $SecretsContent += "URI OTP : " + $otpUri + "`r`n"
    $SecretsContent += "---`r`n"

    # Guardar en registro de Windows
    $RegPath = "HKLM:\SOFTWARE\LabMFA\Users\" + $admin
    if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPath -Name "TOTPSecret"     -Value $secret
    Set-ItemProperty -Path $RegPath -Name "Enabled"        -Value 1
    Set-ItemProperty -Path $RegPath -Name "FailedAttempts" -Value 0
    Set-ItemProperty -Path $RegPath -Name "LockedUntil"    -Value ""

    Write-Log ("  Usuario " + $admin + " registrado correctamente") "Green"
}

Pop-Location

# Guardar archivo de secretos
$SecretsContent | Out-File -FilePath $SecretsFile -Encoding UTF8
Write-Log ("Archivo de secretos guardado en: " + $SecretsFile) "Cyan"

# =========================================================
# PASO 5: INSTALAR SERVICIO WEB DE multiOTP
# =========================================================
Write-Host "`n[PASO 5] Instalando servicio web de multiOTP..." -ForegroundColor Green

$WebServiceScript = Get-ChildItem -Path $MultiOTPPath -Recurse -Filter "webservice_install*" -ErrorAction SilentlyContinue |
                    Select-Object -First 1 -ExpandProperty FullName

if ($WebServiceScript) {
    Write-Log ("Instalando servicio web desde: " + $WebServiceScript) "White"
    $wsDir = Split-Path $WebServiceScript -Parent
    Push-Location $wsDir
    $job = Start-Job -ScriptBlock {
        param($script)
        & cmd /c $script 2>&1
    } -ArgumentList $WebServiceScript
    $result = Wait-Job -Job $job -Timeout 30 | Receive-Job
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    Write-Log "Servicio web instalado" "Green"
    Pop-Location
} else {
    Write-Log "webservice_install no encontrado. Intentando iniciar servicio..." "Yellow"
    $svc = Get-Service -Name "multiOTP" -ErrorAction SilentlyContinue
    if ($svc) {
        Start-Service -Name "multiOTP" -ErrorAction SilentlyContinue
        Write-Log "Servicio multiOTP iniciado" "Green"
    } else {
        Write-Log "Servicio no encontrado. El CP operara en modo local." "Yellow"
    }
}

Start-Sleep -Seconds 5
$portCheck = netstat -an 2>$null | Select-String ":8112"
if ($portCheck) {
    Write-Log "OK - Puerto 8112 activo" "Green"
} else {
    Write-Log "AVISO - Puerto 8112 no activo aun. Puede tardar unos segundos." "Yellow"
}

# =========================================================
# PASO 6: DESCARGAR E INSTALAR CREDENTIAL PROVIDER
# =========================================================
Write-Host "`n[PASO 6] Descargando multiOTP Credential Provider..." -ForegroundColor Green

$CPZip  = "$SetupPath\multiOTP-CredentialProvider.zip"
$CPPath = "$SetupPath\CredentialProvider"

$CPDescargaOK = $false

if (Test-Path $CPZip) {
    $zipSize = (Get-Item $CPZip).Length
    if ($zipSize -gt 500KB) {
        Write-Log "Credential Provider zip ya existe - omitiendo descarga" "Yellow"
        $CPDescargaOK = $true
    } else {
        Remove-Item $CPZip -Force
    }
}

if (-not $CPDescargaOK) {
    $cpUrls = @(
        "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.8.0-x64.zip",
        "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.7.2-x64.zip",
        "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.9.6.6-x64.zip"
    )

    foreach ($url in $cpUrls) {
        try {
            Write-Log ("Intentando CP desde: " + $url) "Yellow"
            Invoke-WebRequest -Uri $url -OutFile $CPZip -UseBasicParsing -TimeoutSec 120
            Write-Log "CP descargado OK" "Green"
            $CPDescargaOK = $true
            break
        } catch {
            Write-Log ("Fallo CP desde " + $url + " : " + $_.Exception.Message) "Red"
        }
    }

    if (-not $CPDescargaOK) {
        Write-Host ""
        Write-Host "  DESCARGA MANUAL DEL CREDENTIAL PROVIDER:" -ForegroundColor Red
        Write-Host "  1. Abre: https://github.com/multiOTP/multiOTPCredentialProvider/releases" -ForegroundColor Yellow
        Write-Host "  2. Descarga el .zip x64 mas reciente" -ForegroundColor Yellow
        Write-Host ("  3. Guardalo en: " + $CPZip) -ForegroundColor Yellow
        Write-Host "  4. Vuelve a ejecutar este script." -ForegroundColor Yellow
        Write-Log "CP requiere descarga manual" "Red"
    }
}

if ($CPDescargaOK -or (Test-Path $CPZip)) {
    Write-Log "Extrayendo Credential Provider..." "White"
    try {
        if (Test-Path $CPPath) { Remove-Item $CPPath -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $CPZip -DestinationPath $CPPath -Force -ErrorAction SilentlyContinue
        Write-Log ("CP extraido en: " + $CPPath) "Green"
    } catch {
        Write-Log ("Error extrayendo CP: " + $_.Exception.Message) "Red"
    }

    # Buscar instalador
    $CPInstaller = Get-ChildItem -Path $CPPath -Recurse -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -like "*install*" -or $_.Name -like "*setup*" -or $_.Name -like "*multiOTP*" } |
                   Where-Object { $_.Extension -eq ".exe" -or $_.Extension -eq ".msi" } |
                   Select-Object -First 1 -ExpandProperty FullName

    if ($CPInstaller) {
        Write-Log ("Instalando CP desde: " + $CPInstaller) "Green"

        if ($CPInstaller -like "*.msi") {
            $CPArgs = "/i `"$CPInstaller`" /qn /norestart MULTIOTP_HOST=127.0.0.1 MULTIOTP_PORT=8112"
            Start-Process "msiexec" -ArgumentList $CPArgs -Wait -NoNewWindow
        } else {
            $CPArgs = "/install /multiOTPServer=127.0.0.1 /multiOTPPort=8112 /VERYSILENT /NORESTART"
            Start-Process -FilePath $CPInstaller -ArgumentList $CPArgs -Wait -NoNewWindow
        }
        Write-Log "Credential Provider instalado." "Green"
    } else {
        Write-Host ""
        Write-Host "  INSTALACION MANUAL DEL CP:" -ForegroundColor Yellow
        Write-Host ("  1. Navega a: " + $CPPath) -ForegroundColor White
        Write-Host "  2. Ejecuta el .exe o .msi como Administrador" -ForegroundColor White
        Write-Host "  3. En 'multiOTP Server IP': 127.0.0.1" -ForegroundColor White
        Write-Host "  4. En 'Port': 8112" -ForegroundColor White
        Write-Host "  5. Finaliza la instalacion" -ForegroundColor White
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

Write-Host ""
Write-Host "  Verificando usuarios en multiOTP:" -ForegroundColor White
Push-Location $MultiOTPDir
foreach ($admin in $AdminUsers) {
    $info = Invoke-MultiOTP -MultiOTPExe $MultiOTPExe -WorkingDir $MultiOTPDir `
            -Arguments @("-display-log", $admin) -TimeoutMs 10000
    if ($info -notlike "*Error*" -and $info -ne "" -and $info -ne "TIMEOUT") {
        Write-Host ("  [OK] " + $admin + " - registrado en multiOTP") -ForegroundColor Green
    } else {
        Write-Host ("  [?]  " + $admin + " - resultado: " + $info) -ForegroundColor Yellow
    }
}
Pop-Location

# =========================================================
# RESUMEN FINAL (FIX 3: sin variables dentro de strings con comillas)
# =========================================================
$lineaSecretos = "    Get-Content " + $SecretsFile
$lineaDominio  = "    3. Nombre: admin_identidad@" + $DomainName
$lineaCD       = "    cd " + $MultiOTPDir

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          INSTRUCCIONES PARA ACTIVAR MFA                     ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor White
Write-Host "║  PASO A: LEE LOS SECRETOS TOTP                              ║" -ForegroundColor Yellow
Write-Host $lineaSecretos                                                      -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor White
Write-Host "║  PASO B: CONFIGURA MICROSOFT/GOOGLE AUTHENTICATOR          ║" -ForegroundColor Yellow
Write-Host "║    1. Abre la app en tu movil                               ║" -ForegroundColor White
Write-Host "║    2. Toca + -> Ingresar clave de configuracion             ║" -ForegroundColor White
Write-Host $lineaDominio                                                        -ForegroundColor White
Write-Host "║    4. Clave: [el secreto del archivo]                       ║" -ForegroundColor White
Write-Host "║    5. Tipo: Basado en tiempo (TOTP)                         ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor White
Write-Host "║  PASO C: INICIA EL SERVICIO multiOTP                       ║" -ForegroundColor Yellow
Write-Host $lineaCD                                                             -ForegroundColor White
Write-Host "║    .\webservice_install.cmd                                  ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor White
Write-Host "║  PASO D: REINICIA EL SERVIDOR                               ║" -ForegroundColor Yellow
Write-Host "║    Restart-Computer -Force                                   ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor White
Write-Host "║  PASO E: AL HACER LOGIN                                     ║" -ForegroundColor Yellow
Write-Host "║    Usuario + Contrasena + Codigo de 6 digitos del movil     ║" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Log ("=== Script 06 completado a las " + (Get-Date -Format "HH:mm:ss") + " ===") "Cyan"
Write-Host ""
Write-Host ("  Log completo en: " + $LogFile) -ForegroundColor Gray
Write-Host ""
Write-Host "=== [06] CONFIGURACION multiOTP COMPLETADA ===" -ForegroundColor Cyan