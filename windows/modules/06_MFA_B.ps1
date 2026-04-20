# =============================================================================
# SCRIPT 06b - DIAGNOSTICO Y REPARACION DE MFA  [EJECUTAR SI EL LOGIN FALLA]
# Ejecutar en: Windows Server 2022 (como Administrator)
#
# Usa este script si:
#   - Ya instalaste multiOTP pero el codigo del movil no funciona al hacer login
#   - La pantalla de login acepta cualquier codigo (no valida)
#   - La pantalla de login rechaza todos los codigos (aunque sean correctos)
# =============================================================================

Write-Host "=== [06b] DIAGNOSTICO Y REPARACION DE MFA ===" -ForegroundColor Cyan
Write-Host "Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray

# =========================================================
# DIAGNOSTICO 1: Encontrar multiOTP
# =========================================================
Write-Host "`n[DIAG 1] Buscando instalacion de multiOTP..." -ForegroundColor Yellow

$MultiOTPExe = Get-ChildItem -Path "C:\" -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName

if (-not $MultiOTPExe) {
    Write-Host "  [FAIL] multiotp.exe NO encontrado." -ForegroundColor Red
    Write-Host "  Solución: Ejecuta primero el Script 06 completo." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "  [OK] multiotp.exe en: $MultiOTPExe" -ForegroundColor Green
}

$MultiOTPDir = Split-Path $MultiOTPExe -Parent

# =========================================================
# DIAGNOSTICO 2: Verificar usuarios registrados
# =========================================================
Write-Host "`n[DIAG 2] Verificando usuarios en multiOTP..." -ForegroundColor Yellow

Push-Location $MultiOTPDir

$AdminUsers = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")
$UsuariosOK = 0

foreach ($admin in $AdminUsers) {
    $info = & $MultiOTPExe -display-log $admin 2>&1
    if ($info -match "TOTP|totp|token|secret") {
        Write-Host "  [OK] $admin - tiene token TOTP" -ForegroundColor Green
        $UsuariosOK++
    } elseif ($info -match "Error|not found|inexistant") {
        Write-Host "  [FAIL] $admin - NO registrado en multiOTP" -ForegroundColor Red
    } else {
        Write-Host "  [?] $admin - estado desconocido: $info" -ForegroundColor Yellow
    }
}

# =========================================================
# DIAGNOSTICO 3: Probar un codigo TOTP manualmente
# =========================================================
Write-Host "`n[DIAG 3] Prueba de validacion TOTP manual..." -ForegroundColor Yellow
Write-Host "  Abre Microsoft Authenticator y obtén el codigo actual para admin_identidad." -ForegroundColor White
$codigoTest = Read-Host "  Ingresa el codigo de 6 digitos (o presiona Enter para omitir)"

if ($codigoTest -and $codigoTest.Length -eq 6) {
    $resultado = & $MultiOTPExe -checkpwd admin_identidad $codigoTest 2>&1
    Write-Host "  Resultado: $resultado" -ForegroundColor White
    if ($resultado -match "0" -or $resultado -match "OK" -or $resultado -match "success") {
        Write-Host "  [OK] Codigo VALIDO - multiOTP funciona correctamente" -ForegroundColor Green
        Write-Host "  Si el login aun falla, el problema es el Credential Provider." -ForegroundColor Yellow
    } else {
        Write-Host "  [FAIL] Codigo invalido o error de multiOTP" -ForegroundColor Red
        Write-Host "  Posible causa: El secreto en el movil no coincide con el de multiOTP" -ForegroundColor Yellow
        Write-Host "  Solucion: Re-registrar el usuario (ver REPARACION mas abajo)" -ForegroundColor Yellow
    }
}

# =========================================================
# DIAGNOSTICO 4: Verificar servicio web de multiOTP
# =========================================================
Write-Host "`n[DIAG 4] Verificando servicio web de multiOTP (puerto 8112)..." -ForegroundColor Yellow

$portCheck = netstat -an | findstr ":8112"
if ($portCheck) {
    Write-Host "  [OK] Puerto 8112 activo: $portCheck" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Puerto 8112 NO activo. El Credential Provider no puede validar." -ForegroundColor Red
    Write-Host "  Iniciando servicio..." -ForegroundColor Yellow
    
    $webServiceScript = Get-ChildItem -Path (Split-Path $MultiOTPDir) -Recurse -Filter "webservice_install*" |
                        Select-Object -First 1 -ExpandProperty FullName
    if ($webServiceScript) {
        & cmd /c $webServiceScript 2>&1
        Start-Sleep -Seconds 3
        $portCheck2 = netstat -an | findstr ":8112"
        if ($portCheck2) {
            Write-Host "  [OK] Servicio iniciado correctamente" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] No se pudo iniciar el servicio. Intenta manualmente:" -ForegroundColor Red
            Write-Host "  cd $MultiOTPDir" -ForegroundColor White
            Write-Host "  .\webservice_install.cmd" -ForegroundColor White
        }
    }
}

# =========================================================
# DIAGNOSTICO 5: Verificar Credential Provider en registro
# =========================================================
Write-Host "`n[DIAG 5] Verificando Credential Provider de Windows..." -ForegroundColor Yellow

$cpProviders = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\" |
               Get-ItemProperty | Where-Object { $_.PSChildName -or $_ } |
               Select-Object -ExpandProperty "(default)" -ErrorAction SilentlyContinue

$multiOTPCP = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\" |
              Where-Object { (Get-ItemProperty $_.PSPath).'(default)' -like "*multiOTP*" -or 
                             (Get-ItemProperty $_.PSPath).'(default)' -like "*WinOTP*" }

if ($multiOTPCP) {
    Write-Host "  [OK] Credential Provider de multiOTP encontrado en el registro" -ForegroundColor Green
    $multiOTPCP | Format-List
} else {
    Write-Host "  [WARN] Credential Provider NO encontrado en registro de Windows" -ForegroundColor Red
    Write-Host "  Esto significa que el CP no esta instalado." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  SOLUCION - Instalar CP manualmente:" -ForegroundColor Cyan
    Write-Host "  1. Busca el instalador en: C:\MFA_Setup\CredentialProvider\" -ForegroundColor White
    Write-Host "  2. Si no existe, descarga desde:" -ForegroundColor White
    Write-Host "     https://github.com/multiOTP/multiOTPCredentialProvider/releases" -ForegroundColor White
    Write-Host "  3. Ejecuta el instalador como Administrador" -ForegroundColor White
    Write-Host "  4. En 'Server': 127.0.0.1  Puerto: 8112" -ForegroundColor White
    Write-Host "  5. Reinicia el servidor" -ForegroundColor White
}

# =========================================================
# REPARACION: Re-registrar un usuario con nuevo secreto
# =========================================================
Write-Host "`n[REPARACION] ¿Deseas re-registrar los secretos TOTP?" -ForegroundColor Cyan
Write-Host "  Esto genera nuevos secretos y debes re-escanear en tu movil." -ForegroundColor Yellow
$respuesta = Read-Host "  ¿Continuar? (S/N)"

if ($respuesta -eq "S" -or $respuesta -eq "s") {
    
    # Funcion para generar secreto Base32
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
    
    $DomainName   = (Get-ADDomain).DNSRoot
    $SecretsFile  = "C:\MFA_Setup\TOTP_Secrets_NUEVO_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $SecretsOutput = "=== SECRETOS TOTP REGENERADOS - $(Get-Date) ===`r`n`r`n"
    
    foreach ($admin in $AdminUsers) {
        # Borrar usuario existente en multiOTP
        & $MultiOTPExe -delete $admin 2>&1 | Out-Null
        
        # Generar nuevo secreto
        $secret = New-TOTPSecret
        
        # Crear con nuevo secreto
        $resultado = & $MultiOTPExe -create $admin TOTP $secret 6 30 2>&1
        
        $uriAccount = [Uri]::EscapeDataString("$DomainName`:$admin")
        $otpUri     = "otpauth://totp/$uriAccount`?secret=$secret&issuer=LabMFA&algorithm=SHA1&digits=6&period=30"
        
        Write-Host "`n  ========================================" -ForegroundColor Cyan
        Write-Host "  Usuario : $admin" -ForegroundColor White
        Write-Host "  Secreto : $secret" -ForegroundColor Yellow
        Write-Host "  URI     : $otpUri" -ForegroundColor Gray
        Write-Host "  ========================================" -ForegroundColor Cyan
        
        $SecretsOutput += "Usuario : $admin`r`n"
        $SecretsOutput += "Secreto : $secret`r`n"
        $SecretsOutput += "URI OTP : $otpUri`r`n`r`n"
        
        # Actualizar registro de Windows
        $RegPath = "HKLM:\SOFTWARE\LabMFA\Users\$admin"
        if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
        Set-ItemProperty -Path $RegPath -Name "TOTPSecret" -Value $secret
    }
    
    $SecretsOutput | Out-File -FilePath $SecretsFile -Encoding UTF8
    Write-Host "`n[OK] Nuevos secretos guardados en: $SecretsFile" -ForegroundColor Green
    Write-Host "[!] Debes re-escanear o ingresar el nuevo secreto en tu app movil" -ForegroundColor Red
}

Pop-Location

# =========================================================
# RESUMEN DEL DIAGNOSTICO
# =========================================================
Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              RESUMEN DE DIAGNOSTICO                 ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║ Si el problema persiste, verifica:                  ║" -ForegroundColor White
Write-Host "║                                                      ║" -ForegroundColor White
Write-Host "║ 1. La hora del servidor y del movil esten           ║" -ForegroundColor Yellow
Write-Host "║    sincronizadas (TOTP es sensible al tiempo)       ║" -ForegroundColor White
Write-Host "║    w32tm /query /status                             ║" -ForegroundColor Cyan
Write-Host "║    w32tm /resync /force                             ║" -ForegroundColor Cyan
Write-Host "║                                                      ║" -ForegroundColor White
Write-Host "║ 2. El secreto en el movil = secreto en multiOTP    ║" -ForegroundColor Yellow
Write-Host "║    Get-Content C:\MFA_Setup\TOTP_Secrets.txt        ║" -ForegroundColor Cyan
Write-Host "║                                                      ║" -ForegroundColor White
Write-Host "║ 3. El servicio multiOTP esta corriendo              ║" -ForegroundColor Yellow
Write-Host "║    netstat -an | findstr ':8112'                    ║" -ForegroundColor Cyan
Write-Host "║                                                      ║" -ForegroundColor White
Write-Host "║ 4. Reiniciar servidor despues de instalar CP        ║" -ForegroundColor Yellow
Write-Host "║    Restart-Computer -Force                          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n=== [06b] DIAGNOSTICO COMPLETADO ===" -ForegroundColor Cyan
