# =============================================================================
# SCRIPT 03 - FINE-GRAINED PASSWORD POLICY (FGPP)
# Ejecutar en: Windows Server 2022 (como Administrator / Domain Admin)
# Descripción: Crea políticas de contraseña diferenciadas:
#   - Admins: mínimo 12 caracteres, complejidad alta
#   - Usuarios estándar: mínimo 8 caracteres
# =============================================================================

Write-Host "=== [03] CONFIGURANDO FINE-GRAINED PASSWORD POLICIES (FGPP) ===" -ForegroundColor Cyan

# =========================================================
# POLÍTICA 1: Administradores con privilegios → 12 caracteres mínimo
# Aplica al grupo: GRP_AdminsPrivilegio
# =========================================================
Write-Host "`n[+] Creando FGPP para Administradores (12 caracteres minimo)..." -ForegroundColor Green

try {
    New-ADFineGrainedPasswordPolicy `
        -Name "PSO_AdminsPrivilegiados" `
        -DisplayName "Politica Admins Privilegiados" `
        -Precedence 10 `
        -MinPasswordLength 12 `
        -PasswordHistoryCount 10 `
        -ComplexityEnabled $true `
        -ReversibleEncryptionEnabled $false `
        -MinPasswordAge (New-TimeSpan -Days 1) `
        -MaxPasswordAge (New-TimeSpan -Days 60) `
        -LockoutDuration (New-TimeSpan -Minutes 30) `
        -LockoutObservationWindow (New-TimeSpan -Minutes 30) `
        -LockoutThreshold 3 `
        -ErrorAction Stop

    Write-Host "  PSO 'PSO_AdminsPrivilegiados' creada correctamente." -ForegroundColor White
} catch {
    Write-Host "  PSO ya existe o error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Aplicar la FGPP al grupo de administradores
try {
    Add-ADFineGrainedPasswordPolicySubject `
        -Identity "PSO_AdminsPrivilegiados" `
        -Subjects "GRP_AdminsPrivilegio" `
        -ErrorAction Stop

    Write-Host "  PSO aplicada al grupo 'GRP_AdminsPrivilegio'." -ForegroundColor White
} catch {
    Write-Host "  Error al aplicar PSO al grupo: $($_.Exception.Message)" -ForegroundColor Yellow
}

# =========================================================
# POLÍTICA 2: Usuarios estándar → 8 caracteres mínimo
# Aplica al dominio completo (via Default Domain Policy)
# También creamos una PSO explícita para usuarios normales
# =========================================================
Write-Host "`n[+] Creando FGPP para Usuarios Estandar (8 caracteres minimo)..." -ForegroundColor Green

try {
    New-ADFineGrainedPasswordPolicy `
        -Name "PSO_UsuariosEstandar" `
        -DisplayName "Politica Usuarios Estandar" `
        -Precedence 50 `
        -MinPasswordLength 8 `
        -PasswordHistoryCount 5 `
        -ComplexityEnabled $true `
        -ReversibleEncryptionEnabled $false `
        -MinPasswordAge (New-TimeSpan -Days 0) `
        -MaxPasswordAge (New-TimeSpan -Days 90) `
        -LockoutDuration (New-TimeSpan -Minutes 15) `
        -LockoutObservationWindow (New-TimeSpan -Minutes 15) `
        -LockoutThreshold 5 `
        -ErrorAction Stop

    Write-Host "  PSO 'PSO_UsuariosEstandar' creada correctamente." -ForegroundColor White
} catch {
    Write-Host "  PSO ya existe o error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Nota: La política de usuarios estándar se aplica por Default Domain Policy.
# La PSO de admins tiene precedencia menor (10 < 50) por lo que GANA sobre la estándar.
Write-Host "  Nota: PSO_AdminsPrivilegiados tiene precedencia 10 (mas baja = mayor prioridad)." -ForegroundColor Yellow
Write-Host "  Los usuarios en GRP_AdminsPrivilegio recibiran la politica de 12 chars." -ForegroundColor Yellow

# =========================================================
# VERIFICACIÓN
# =========================================================
Write-Host "`n[+] Verificando FGPPs creadas:" -ForegroundColor Cyan
Get-ADFineGrainedPasswordPolicy -Filter * | Format-Table Name, Precedence, MinPasswordLength, LockoutThreshold, LockoutDuration -AutoSize

Write-Host "`n[+] Verificando sujetos de PSO_AdminsPrivilegiados:" -ForegroundColor Cyan
Get-ADFineGrainedPasswordPolicySubject -Identity "PSO_AdminsPrivilegiados" | Format-Table Name, ObjectClass -AutoSize

# =========================================================
# PRUEBA DE VERIFICACIÓN MANUAL (TEST 2)
# Intenta asignar contraseña de 8 chars a admin_identidad (debe fallar)
# =========================================================
Write-Host "`n[TEST 2] Probando rechazo de contrasena corta para admin_identidad..." -ForegroundColor Cyan
$ShortPassword = ConvertTo-SecureString "Pass123!" -AsPlainText -Force   # 8 chars - debe fallar

try {
    Set-ADAccountPassword -Identity "admin_identidad" -NewPassword $ShortPassword -Reset -ErrorAction Stop
    Write-Host "  [FALLO] La contrasena fue aceptada - revise la configuracion de FGPP!" -ForegroundColor Red
} catch {
    Write-Host "  [CORRECTO] La contrasena de 8 caracteres fue RECHAZADA para admin_identidad." -ForegroundColor Green
    Write-Host "  Error recibido: $($_.Exception.Message)" -ForegroundColor White
    Write-Host "  --> Este resultado es el esperado para el TEST 2." -ForegroundColor Magenta
}

Write-Host "`n=== [03] FGPP COMPLETADA ===" -ForegroundColor Cyan
Write-Host "Siguiente paso: Ejecutar 04_Configurar_Auditoria.ps1" -ForegroundColor Magenta
