# Obtener SID correcto
$sid = (New-Object System.Security.Principal.NTAccount("PRACTICA\Administrator")).Translate([System.Security.Principal.SecurityIdentifier]).Value

Write-Host "SID: $sid" -ForegroundColor Cyan

# Escribir cfg con SID en formato correcto
$cfg = "[Unicode]`r`nUnicode=yes`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1`r`n[Privilege Rights]`r`nSeNetworkLogonRight = *S-1-1-0,*S-1-5-11,*S-1-5-32-544,*S-1-5-32-554,*S-1-5-9,*$sid"

$cfg | Out-File "C:\temp\fix2.cfg" -Encoding Unicode

secedit /configure /db C:\temp\secedit2.sdb /cfg "C:\temp\fix2.cfg" /areas USER_RIGHTS

gpupdate /force
Restart-Service sshd -Force

# Verificar que quedo bien
secedit /export /cfg C:\temp\verify.cfg /areas USER_RIGHTS
Get-Content C:\temp\verify.cfg | Select-String "SeNetworkLogonRight"

Write-Host "Listo!" -ForegroundColor Green