# Obtener SID de Administrator del dominio
$sid = (New-Object System.Security.Principal.NTAccount("PRACTICA\Administrator")).Translate([System.Security.Principal.SecurityIdentifier]).Value

Write-Host "SID encontrado: $sid" -ForegroundColor Cyan

# Crear configuracion con el SID agregado
$cfg = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeNetworkLogonRight = *S-1-1-0,*S-1-5-11,*S-1-5-32-544,*S-1-5-32-554,*S-1-5-9,*$sid
"@

$cfg | Out-File "C:\temp\fix_logon.cfg" -Encoding Unicode

secedit /configure /db C:\temp\secedit.sdb /cfg "C:\temp\fix_logon.cfg" /areas USER_RIGHTS

gpupdate /force

Restart-Service sshd -Force

Write-Host "Listo! Prueba conectarte con: ssh administrator@192.168.56.102" -ForegroundColor Green