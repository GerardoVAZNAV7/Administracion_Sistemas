# =============================================================================
# SCRIPT 02 - DELEGACIÓN DE CONTROL Y ACL (RBAC)
# Ejecutar en: Windows Server 2022 (como Administrator / Domain Admin)
# Descripción: Configura permisos granulares para cada rol usando dsacls y Set-Acl
# =============================================================================

$DomainDN   = (Get-ADDomain).DistinguishedName
$DomainName = (Get-ADDomain).DNSRoot
$DomainNBIOS= (Get-ADDomain).NetBIOSName   # Ej: LAB

Write-Host "=== [02] CONFIGURANDO DELEGACIÓN DE CONTROL Y ACLs ===" -ForegroundColor Cyan
Write-Host "Dominio NETBIOS: $DomainNBIOS" -ForegroundColor Yellow

# =========================================================
# ROL 1 — admin_identidad: IAM Operator
# Permisos sobre OU=Cuates y OU=NoCuates
# Puede: Crear/Eliminar usuarios, Reset Password, Modificar atributos básicos
# NO puede: Modificar grupos Domain Admin ni GPOs
# =========================================================
Write-Host "`n[ROL 1] Delegando permisos a admin_identidad (IAM Operator)..." -ForegroundColor Green

$TargetOUs_IAM = @(
    "OU=Cuates,$DomainDN",
    "OU=NoCuates,$DomainDN"
)

foreach ($ouDN in $TargetOUs_IAM) {
    Write-Host "  Aplicando sobre: $ouDN" -ForegroundColor White

    # Crear usuarios (CreateChild para objetos tipo user)
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:CC;user"

    # Eliminar usuarios (DeleteChild para objetos tipo user)
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:DC;user"

    # Permisos de escritura sobre atributos básicos (telefono, mail, oficina)
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:WP;telephoneNumber;user"
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:WP;mail;user"
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:WP;physicalDeliveryOfficeName;user"

    # Reset Password (permiso extendido)
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:CA;Reset Password;user"

    # Desbloqueo de cuentas (lockoutTime y userAccountControl)
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:WP;lockoutTime;user"
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:WP;userAccountControl;user"

    # Lectura general de objetos en la OU
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_identidad:GR;;user"
}
Write-Host "  [OK] Delegacion ROL 1 completada." -ForegroundColor Green

# =========================================================
# ROL 2 — admin_storage: Storage Operator
# Permisos sobre FSRM (se configuran localmente, ver Script 03)
# RESTRICCION CRITICA: DENEGAR Reset Password en todo el dominio
# =========================================================
Write-Host "`n[ROL 2] Aplicando DENEGACION de Reset Password a admin_storage..." -ForegroundColor Green

# Denegar Reset Password sobre TODA la OU=Cuates (cubre el caso del test)
$TargetOUs_DenyStorage = @(
    "OU=Cuates,$DomainDN",
    "OU=NoCuates,$DomainDN",
    "OU=AdminsDelegados,$DomainDN"
)

foreach ($ouDN in $TargetOUs_DenyStorage) {
    # Denegar el permiso extendido Reset Password
    dsacls $ouDN /I:S /D "$DomainNBIOS\admin_storage:CA;Reset Password;user"
    Write-Host "  [DENY] Reset Password denegado para admin_storage en: $ouDN" -ForegroundColor Red
}

Write-Host "  [OK] Restriccion critica ROL 2 aplicada." -ForegroundColor Green

# =========================================================
# ROL 3 — admin_politicas: GPO Compliance
# Permiso de LECTURA en todo el dominio
# Permiso de ESCRITURA solo sobre objetos tipo groupPolicyContainer (GPO)
# =========================================================
Write-Host "`n[ROL 3] Delegando permisos a admin_politicas (GPO Compliance)..." -ForegroundColor Green

# Lectura en todo el dominio
dsacls $DomainDN /I:T /G "$DomainNBIOS\admin_politicas:GR"
Write-Host "  Lectura global aplicada en el dominio." -ForegroundColor White

# Escritura sobre GPOs (groupPolicyContainer) en System\Policies
$GPOPath = "CN=Policies,CN=System,$DomainDN"
dsacls $GPOPath /I:S /G "$DomainNBIOS\admin_politicas:GA;;groupPolicyContainer"
Write-Host "  Escritura sobre GPOs (groupPolicyContainer) aplicada." -ForegroundColor White

# Permiso para vincular GPOs a OUs (gpLink y gpOptions en las OUs)
$OUsParaVincular = @(
    "OU=Cuates,$DomainDN",
    "OU=NoCuates,$DomainDN"
)
foreach ($ouDN in $OUsParaVincular) {
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_politicas:WP;gpLink"
    dsacls $ouDN /I:S /G "$DomainNBIOS\admin_politicas:WP;gpOptions"
    Write-Host "  Permiso gpLink/gpOptions sobre $ouDN concedido." -ForegroundColor White
}

Write-Host "  [OK] Delegacion ROL 3 completada." -ForegroundColor Green

# =========================================================
# ROL 4 — admin_auditoria: Security Auditor (READ ONLY)
# Solo lectura en todo el dominio
# Acceso al Visor de Eventos (configurado via Group Policy en Script 04)
# =========================================================
Write-Host "`n[ROL 4] Delegando permisos de SOLO LECTURA a admin_auditoria..." -ForegroundColor Green

# Lectura en todo el dominio (no escritura)
dsacls $DomainDN /I:T /G "$DomainNBIOS\admin_auditoria:GR"
Write-Host "  Lectura global (Read-Only) aplicada para admin_auditoria." -ForegroundColor White

# Agregar al grupo Event Log Readers para acceso al Visor de Eventos
try {
    Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction Stop
    Write-Host "  admin_auditoria agregado al grupo 'Event Log Readers'." -ForegroundColor White
} catch {
    Write-Host "  Error al agregar a Event Log Readers: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "  [OK] Delegacion ROL 4 (Read-Only) completada." -ForegroundColor Green

# =========================================================
# VERIFICACIÓN FINAL
# =========================================================
Write-Host "`n[+] Resumen de permisos delegados:" -ForegroundColor Cyan
Write-Host "  admin_identidad -> Create/Delete/Reset users en OU=Cuates y OU=NoCuates"
Write-Host "  admin_storage   -> DENY Reset Password en todas las OUs"
Write-Host "  admin_politicas -> READ dominio + WRITE GPOs + vincular GPOs a OUs"
Write-Host "  admin_auditoria -> READ ONLY dominio + Event Log Readers"

Write-Host "`n=== [02] DELEGACION Y ACL COMPLETADA ===" -ForegroundColor Cyan
Write-Host "Siguiente paso: Ejecutar 03_Configurar_FGPP.ps1" -ForegroundColor Magenta
