# parche_fsrm_auditoria.ps1

Write-Host "1. Creando la accion de auditoria para el Visor de Eventos..." -ForegroundColor Cyan
$MensajeLog = "FSRM BLOQUEO: El usuario [Source Io Owner] intento guardar el archivo prohibido [Source File Path] en el servidor."

$AccionAuditoria = New-FsrmAction -Type Event -EventType Warning -Body $MensajeLog -RunLimitInterval 0

Write-Host "2. Aplicando la accion a la plantilla existente..." -ForegroundColor Cyan
Set-FsrmFileScreenTemplate -Name "Plantilla_Bloqueo_Total" -Notification $AccionAuditoria

Write-Host "[+] Listo. FSRM ahora dejara un registro cada vez que bloquee un archivo." -ForegroundColor Green
