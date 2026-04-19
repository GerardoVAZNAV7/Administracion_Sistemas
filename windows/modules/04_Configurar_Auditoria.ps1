# =============================================================================
# SCRIPT 04 - HARDENING DE AUDITORÍA DE EVENTOS
# Ejecutar en: Windows Server 2022 (como Administrator / Domain Admin)
# Descripción: Habilita auditoría de éxito y fallo en categorías críticas
# =============================================================================

Write-Host "=== [04] CONFIGURANDO HARDENING DE AUDITORÍA ===" -ForegroundColor Cyan

# =========================================================
# CONFIGURAR AUDIT POLICY CON auditpol
# Habilita: Logon, Account Logon, Object Access, Account Management
# =========================================================

Write-Host "`n[+] Habilitando auditorias de inicio de sesion..." -ForegroundColor Green

# Inicio de sesión (Login/Logoff)
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Logoff" /success:enable /failure:disable

# Autenticación de cuentas (Kerberos, NTLM)
auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable

# Administración de cuentas
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable
auditpol /set /subcategory:"Computer Account Management" /success:enable /failure:enable

# Acceso a objetos (necesario para ACL y FSRM)
auditpol /set /subcategory:"File System" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Changes" /success:enable /failure:enable

# Cambios de política
auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable

# Uso de privilegios
auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable

Write-Host "`n[+] Politicas de auditoria habilitadas correctamente." -ForegroundColor Green

# =========================================================
# VERIFICAR CONFIGURACIÓN ACTUAL
# =========================================================
Write-Host "`n[+] Estado actual de auditorias configuradas:" -ForegroundColor Cyan
auditpol /get /category:*

# =========================================================
# CONFIGURAR VÍA GROUP POLICY (también para los clientes Windows 10)
# =========================================================
Write-Host "`n[+] Configurando GPO de auditoria avanzada..." -ForegroundColor Green

# Crear GPO de auditoría si no existe
$GPOName = "GPO_HardeningAuditoria"
try {
    $ExistingGPO = Get-GPO -Name $GPOName -ErrorAction Stop
    Write-Host "  GPO '$GPOName' ya existe." -ForegroundColor Yellow
} catch {
    $NewGPO = New-GPO -Name $GPOName
    Write-Host "  GPO '$GPOName' creada." -ForegroundColor White
}

# Configurar parámetros de auditoría en la GPO
# Audit Account Logon Events = Success, Failure
Set-GPRegistryValue -Name $GPOName -Key "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security" `
    -ValueName "MaxSize" -Type DWord -Value 52428800   # 50 MB para el log de seguridad

Write-Host "  Tamaño máximo del Security Log configurado a 50 MB." -ForegroundColor White

# Vincular GPO al dominio
$DomainDN = (Get-ADDomain).DistinguishedName
try {
    New-GPLink -Name $GPOName -Target $DomainDN -LinkEnabled Yes -ErrorAction Stop
    Write-Host "  GPO '$GPOName' vinculada al dominio." -ForegroundColor White
} catch {
    Write-Host "  GPO ya esta vinculada o error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Forzar actualización de políticas
Write-Host "`n[+] Forzando actualizacion de politicas de grupo..." -ForegroundColor Green
gpupdate /force

Write-Host "`n=== [04] HARDENING DE AUDITORIA COMPLETADO ===" -ForegroundColor Cyan
Write-Host "Siguiente paso: Ejecutar 05_Script_Monitoreo_Eventos.ps1" -ForegroundColor Magenta
