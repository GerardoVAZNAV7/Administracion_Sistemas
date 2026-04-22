# Ver logs de SSH en tiempo real
Get-Content "C:\ProgramData\ssh\logs\sshd.log" -Tail 30



# Verificar que el script fix.ps1 se ejecuto correctamente
secedit /export /cfg C:\temp\sec_check.cfg /areas USER_RIGHTS
Get-Content C:\temp\sec_check.cfg | Select-String "SeNetworkLogonRight"