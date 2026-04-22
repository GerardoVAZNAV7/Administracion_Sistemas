# Crear la carpeta temp
New-Item -ItemType Directory -Path "C:\temp" -Force

# Exportar politica
secedit /export /cfg C:\temp\sec.cfg /areas USER_RIGHTS

# Ver el derecho actual
Get-Content C:\temp\sec.cfg | Select-String "SeNetworkLogonRight"