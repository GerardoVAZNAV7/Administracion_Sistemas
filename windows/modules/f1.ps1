$tempCfg = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeNetworkLogonRight = *S-1-5-32-544,*S-1-5-11,administrator
"@

$tempCfg | Out-File "C:\temp\fix_logon.cfg" -Encoding Unicode
secedit /configure /db secedit.sdb /cfg "C:\temp\fix_logon.cfg" /areas USER_RIGHTS
gpupdate /force