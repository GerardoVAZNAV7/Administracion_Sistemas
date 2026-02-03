Write-Host "*******************************************"
Write-Host "   PRACTICA 1 ADMINISTRACIOIN DE SISTEMAS"
Write-Host "*******************************************"

Write-Host "`Nombre del equipo:"
hostname


Write-Host "`Dirección IP:"
ipconfig | Select-String "IPv4"


Write-Host "`nEspacio en disco:"
Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" |
Select-Object DeviceID,
@{Name="Tamaño(GB)";Expression={[math]::Round($_.Size/1GB,2)}},
@{Name="Libre(GB)";Expression={[math]::Round($_.FreeSpace/1GB,2)}}

Write-Host "********************************************"
Write-Host "                FIN DE                      "
Write-Host "    PRACTICA 1 ADMINISTRACION DE SISTEMAS   "
Write-Host "********************************************"
