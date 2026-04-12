$ruta = "C:\Users\Administrator\Administracion_Sistemas\windows\modules\Ad_otro.ps1"
$script = Get-Content $ruta -Raw
$script = $script -replace [char]0x201C, '"'
$script = $script -replace [char]0x201D, '"'
$script = $script -replace [char]0x2018, "'"
$script = $script -replace [char]0x2019, "'"
$script | Set-Content $ruta -Encoding UTF8
Write-Host "Listo, comillas corregidas." -ForegroundColor Green