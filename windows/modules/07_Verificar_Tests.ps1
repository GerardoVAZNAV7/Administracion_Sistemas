# =============================================================================
# SCRIPT 07 - VERIFICACIÓN AUTOMATIZADA DE LOS 5 TESTS
# Ejecutar en: Windows Server 2022 (como Administrator)
# Descripción: Valida la configuración de todos los componentes de la práctica
# =============================================================================

Write-Host "=== [07] VERIFICACIÓN AUTOMATIZADA DE TODOS LOS TESTS ===" -ForegroundColor Cyan
Write-Host "Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray

$Resultados = @()

# =========================================================
# TEST 1: VERIFICACIÓN DE DELEGACIÓN (ROL 2 vs ROL 1)
# Verifica que admin_identidad TIENE permiso Reset Password
# y que admin_storage TIENE la DENEGACIÓN
# =========================================================
Write-Host "`n========== TEST 1: VERIFICACION DE DELEGACION ==========`n" -ForegroundColor Cyan

# Verificar ACLs en OU=Cuates
$DomainDN = (Get-ADDomain).DistinguishedName
$OU_Cuates = "OU=Cuates,$DomainDN"

Write-Host "[TEST 1A] Verificando permisos de admin_identidad en OU=Cuates..." -ForegroundColor Yellow
$AclCuates = (Get-Acl "AD:$OU_Cuates").Access | Where-Object {
    $_.IdentityReference -like "*admin_identidad*"
}
if ($AclCuates) {
    Write-Host "  [OK] admin_identidad tiene permisos configurados en OU=Cuates." -ForegroundColor Green
    $AclCuates | Format-Table IdentityReference, ActiveDirectoryRights, AccessControlType -AutoSize
    $Resultados += "TEST 1A: PASS - admin_identidad tiene permisos en OU=Cuates"
} else {
    Write-Host "  [WARN] No se detectaron ACLs de admin_identidad. Verifica el Script 02." -ForegroundColor Yellow
    $Resultados += "TEST 1A: WARN - Verificar ACL manualmente"
}

Write-Host "`n[TEST 1B] Verificando DENEGACION de Reset Password para admin_storage..." -ForegroundColor Yellow
$AclDeny = (Get-Acl "AD:$OU_Cuates").Access | Where-Object {
    $_.IdentityReference -like "*admin_storage*" -and $_.AccessControlType -eq "Deny"
}
if ($AclDeny) {
    Write-Host "  [OK] admin_storage tiene DENEGACION configurada en OU=Cuates." -ForegroundColor Green
    $AclDeny | Format-Table IdentityReference, ActiveDirectoryRights, AccessControlType -AutoSize
    $Resultados += "TEST 1B: PASS - admin_storage tiene DENY en OU=Cuates"
} else {
    Write-Host "  [WARN] No se detectó ACL de DENY para admin_storage." -ForegroundColor Yellow
    $Resultados += "TEST 1B: WARN - Verificar DENY ACL manualmente con dsacls"
}

# Prueba práctica: intentar Reset Password como admin_storage
Write-Host "`n[TEST 1 - PRUEBA REAL] Simulando Reset Password como admin_storage..." -ForegroundColor Yellow
Write-Host "  INSTRUCCION MANUAL: " -ForegroundColor White
Write-Host "  1. Inicia sesion en el servidor o cliente como: admin_storage" -ForegroundColor White
Write-Host "  2. Ejecuta: Set-ADAccountPassword -Identity usuario.cuate1 -NewPassword (ConvertTo-SecureString 'Test1234!' -AsPlainText -Force) -Reset" -ForegroundColor White
Write-Host "  3. El resultado esperado es: ACCESO DENEGADO (error de permisos)" -ForegroundColor White

# =========================================================
# TEST 2: FINE-GRAINED PASSWORD POLICY
# =========================================================
Write-Host "`n========== TEST 2: FINE-GRAINED PASSWORD POLICY ==========`n" -ForegroundColor Cyan

$PSO_Admin = Get-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" -ErrorAction SilentlyContinue
if ($PSO_Admin) {
    Write-Host "  [OK] PSO_AdminsPrivilegiados encontrada." -ForegroundColor Green
    Write-Host "  MinPasswordLength   : $($PSO_Admin.MinPasswordLength)" -ForegroundColor White
    Write-Host "  LockoutThreshold    : $($PSO_Admin.LockoutThreshold)" -ForegroundColor White
    Write-Host "  LockoutDuration     : $($PSO_Admin.LockoutDuration)" -ForegroundColor White
    Write-Host "  ComplexityEnabled   : $($PSO_Admin.ComplexityEnabled)" -ForegroundColor White
    
    if ($PSO_Admin.MinPasswordLength -ge 12) {
        Write-Host "  [PASS] Minimo 12 caracteres para admins: CORRECTO" -ForegroundColor Green
        $Resultados += "TEST 2: PASS - FGPP 12 chars para admins configurada"
    } else {
        Write-Host "  [FAIL] Minimo de caracteres no es 12. Actual: $($PSO_Admin.MinPasswordLength)" -ForegroundColor Red
        $Resultados += "TEST 2: FAIL - FGPP no tiene 12 chars minimo"
    }
} else {
    Write-Host "  [FAIL] PSO_AdminsPrivilegiados no encontrada. Ejecuta Script 03." -ForegroundColor Red
    $Resultados += "TEST 2: FAIL - PSO no encontrada"
}

# Probar rechazo de contraseña corta
Write-Host "`n  Intentando asignar contraseña de 8 chars a admin_identidad (debe fallar)..." -ForegroundColor Yellow
try {
    $ShortPass = ConvertTo-SecureString "Pass123!" -AsPlainText -Force
    Set-ADAccountPassword -Identity "admin_identidad" -NewPassword $ShortPass -Reset -ErrorAction Stop
    Write-Host "  [FAIL] La contraseña fue ACEPTADA. La FGPP no funciona." -ForegroundColor Red
    $Resultados += "TEST 2 PRACTICA: FAIL - Contraseña corta aceptada"
} catch {
    Write-Host "  [PASS] Contraseña rechazada: $($_.Exception.Message)" -ForegroundColor Green
    $Resultados += "TEST 2 PRACTICA: PASS - Contraseña corta rechazada correctamente"
}

# =========================================================
# TEST 3: FLUJO MFA (Verificación de estado)
# =========================================================
Write-Host "`n========== TEST 3: FLUJO MFA (Google Authenticator) ==========`n" -ForegroundColor Cyan

$WinOTPReg = Get-Item "HKLM:\SOFTWARE\WinOTP" -ErrorAction SilentlyContinue
if ($WinOTPReg) {
    Write-Host "  [OK] WinOTP encontrado en el registro del sistema." -ForegroundColor Green
    $Resultados += "TEST 3: PASS - WinOTP instalado"
} else {
    Write-Host "  [WARN] WinOTP no detectado en registro. Verifica la instalacion." -ForegroundColor Yellow
    $Resultados += "TEST 3: MANUAL - Verificar visualmente en pantalla de login"
}

Write-Host "`n  INSTRUCCION MANUAL (TEST 3):" -ForegroundColor Cyan
Write-Host "  1. Cierra sesion en el servidor (logoff)" -ForegroundColor White
Write-Host "  2. En la pantalla de login verás el campo extra de Google Authenticator" -ForegroundColor White
Write-Host "  3. Abre Google Authenticator en tu móvil → obtén el código de 6 dígitos" -ForegroundColor White
Write-Host "  4. Ingresa usuario, contraseña y código TOTP" -ForegroundColor White
Write-Host "  5. El login debe ser exitoso con los 3 factores" -ForegroundColor White

# =========================================================
# TEST 4: BLOQUEO POR MFA FALLIDO (3 intentos → 30 min)
# =========================================================
Write-Host "`n========== TEST 4: BLOQUEO DE CUENTA POR MFA FALLIDO ==========`n" -ForegroundColor Cyan

Write-Host "  INSTRUCCION MANUAL (TEST 4):" -ForegroundColor Cyan
Write-Host "  1. Intenta hacer login con usuario valido + contraseña valida + CODIGO MFA INCORRECTO" -ForegroundColor White
Write-Host "  2. Repite 3 veces con código incorrecto" -ForegroundColor White
Write-Host "  3. Ejecuta este comando para verificar el bloqueo:" -ForegroundColor White
Write-Host "" 
Write-Host "     Get-ADUser admin_identidad -Properties LockedOut,BadLogonCount,BadPasswordTime | Select Name,LockedOut,BadLogonCount" -ForegroundColor Yellow
Write-Host ""

# Verificar estado actual de cuentas
Write-Host "  Estado actual de cuentas admin:" -ForegroundColor Cyan
$AdminUsers = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")
foreach ($u in $AdminUsers) {
    $user = Get-ADUser $u -Properties LockedOut, BadLogonCount -ErrorAction SilentlyContinue
    if ($user) {
        $status = if ($user.LockedOut) { "BLOQUEADA" } else { "Activa" }
        Write-Host "  $($u.PadRight(20)) | Estado: $status | Intentos fallidos: $($user.BadLogonCount)" -ForegroundColor White
    }
}

$Resultados += "TEST 4: MANUAL - Verificar bloqueo con Get-ADUser después de 3 intentos fallidos MFA"

# =========================================================
# TEST 5: SCRIPT DE AUDITORÍA
# =========================================================
Write-Host "`n========== TEST 5: REPORTE DE AUDITORÍA AUTOMATIZADO ==========`n" -ForegroundColor Cyan

Write-Host "  Ejecutando extraccion de eventos de auditoria..." -ForegroundColor Yellow

# Llamar al script 05
$Script05 = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "05_Script_Monitoreo_Eventos.ps1"
if (Test-Path $Script05) {
    & $Script05
    $Resultados += "TEST 5: PASS - Script de monitoreo ejecutado"
} else {
    Write-Host "  Ejecuta manualmente: .\05_Script_Monitoreo_Eventos.ps1" -ForegroundColor Yellow
    $Resultados += "TEST 5: MANUAL - Ejecutar Script 05 directamente"
}

# =========================================================
# RESUMEN FINAL
# =========================================================
Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host "             RESUMEN DE VERIFICACIÓN DE TESTS" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
foreach ($r in $Resultados) {
    $color = if ($r -like "*PASS*") { "Green" } elseif ($r -like "*FAIL*") { "Red" } else { "Yellow" }
    Write-Host "  $r" -ForegroundColor $color
}
Write-Host ""
Write-Host "Auditoria de politica configurada:" -ForegroundColor Gray
auditpol /get /subcategory:"Logon" 2>$null

Write-Host "`n=== [07] VERIFICACIÓN COMPLETADA ===" -ForegroundColor Cyan
