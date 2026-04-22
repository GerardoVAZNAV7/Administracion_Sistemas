# Abrir politica local
secedit /export /cfg C:\temp\sec.cfg /areas USER_RIGHTS

# Ver quien tiene el derecho de red actualmente
Get-Content C:\temp\sec.cfg | Select-String "SeNetworkLogonRight"