# =============================================================
# fix_ssl_ftp.ps1 — Deshabilitar SSL obligatorio en sitio FTP
# Pegar y ejecutar en PowerShell del servidor Windows (como Admin)
# =============================================================

Import-Module WebAdministration -ErrorAction Stop

Write-Host "Deshabilitando SSL requerido en sitio FTP..." -ForegroundColor Cyan

# Metodo 1: Set-ItemProperty
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name "ftpServer.security.ssl.dataChannelPolicy" -Value 0

# Metodo 2: appcmd (el mas confiable para SSL en IIS-FTP)
$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
& $appcmd set site "FTP" /ftpServer.security.ssl.controlChannelPolicy:SslAllow
& $appcmd set site "FTP" /ftpServer.security.ssl.dataChannelPolicy:SslAllow

# Metodo 3: editar applicationHost.config directamente
$configPath = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
[xml]$xml = Get-Content $configPath
$site = $xml.configuration."system.applicationHost".sites.site |
    Where-Object { $_.name -eq "FTP" }
if ($site -and $site.ftpServer.security.ssl) {
    $site.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
    $site.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
    $xml.Save($configPath)
    Write-Host "  applicationHost.config actualizado." -ForegroundColor Green
}

# Reiniciar servicio FTP
Restart-Service ftpsvc -Force
Write-Host ""
Write-Host "Listo. Verifica en FileZilla:" -ForegroundColor Green
Write-Host "  - Protocolo: FTP (no SFTP, no FTPS)" -ForegroundColor White
Write-Host "  - Cifrado:   Usar FTP plano (sin TLS)" -ForegroundColor White
Write-Host "  - Puerto:    21" -ForegroundColor White