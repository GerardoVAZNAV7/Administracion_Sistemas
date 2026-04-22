# Obtener SID
$sid = (New-Object System.Security.Principal.NTAccount("PRACTICA\Administrator")).Translate([System.Security.Principal.SecurityIdentifier]).Value
Write-Host "SID: $sid" -ForegroundColor Cyan

# Exportar politica actual
secedit /export /cfg C:\temp\actual.cfg /areas USER_RIGHTS

# Leer y reemplazar la linea directamente
$contenido = Get-Content C:\temp\actual.cfg -Raw

$lineaActual = ($contenido -split "`n" | Where-Object { $_ -match "SeNetworkLogonRight" }).Trim()
Write-Host "Linea actual: $lineaActual" -ForegroundColor Yellow

$lineaNueva = $lineaActual.TrimEnd() + ",*$sid"
$contenido = $contenido -replace [regex]::Escape($lineaActual), $lineaNueva

$contenido | Out-File "C:\temp\final.cfg" -Encoding Unicode

secedit /configure /db C:\temp\final.sdb /cfg "C:\temp\final.cfg" /areas USER_RIGHTS
gpupdate /force
Restart-Service sshd -Force

# Verificar
Get-Content C:\temp\final.cfg | Select-String "SeNetworkLogonRight"
Write-Host "Listo!" -ForegroundColor Green