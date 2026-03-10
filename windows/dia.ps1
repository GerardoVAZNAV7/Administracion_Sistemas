# DIAGNOSTICO — pega en PowerShell del servidor

# 1. Ver si existe la carpeta del usuario
$user = "leo"
Write-Host "=== Carpetas de $user ===" -ForegroundColor Cyan
Test-Path "C:\FTP\LocalUser\$user"
Get-ChildItem "C:\FTP\LocalUser\$user" -Force -ErrorAction SilentlyContinue

# 2. Ver permisos de la carpeta
Write-Host "=== Permisos ===" -ForegroundColor Cyan
(Get-Acl "C:\FTP\LocalUser\$user").Access | 
    Select-Object IdentityReference, FileSystemRights | Format-Table

# 3. Ver si el usuario existe en Windows
Write-Host "=== Usuario en Windows ===" -ForegroundColor Cyan
net user $user

# 4. Ver el log de IIS-FTP
Write-Host "=== Ultimas lineas del log FTP ===" -ForegroundColor Cyan
$logPath = "C:\inetpub\logs\LogFiles"
$lastLog = Get-ChildItem $logPath -Recurse -Filter "*.log" | 
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($lastLog) { Get-Content $lastLog.FullName -Tail 20 }