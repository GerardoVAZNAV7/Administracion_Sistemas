# diagnostico_ftp.ps1
# Ejecutar en PowerShell del servidor como Administrador

Import-Module WebAdministration -ErrorAction SilentlyContinue

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTICO FTP" -ForegroundColor Cyan
Write-Host "================================================="

# 1. Sitio FTP
Write-Host "`n[1] SITIO FTP EN IIS" -ForegroundColor Yellow
$site = Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue
if ($site) {
    Write-Host "  PhysicalPath : $($site.physicalPath)"
    Write-Host "  Estado       : $($site.State)"
    Write-Host "  Puerto       : $($site.Bindings.Collection[0].bindingInformation)"
} else {
    Write-Host "  [ERROR] Sitio FTP no existe" -ForegroundColor Red
}

# 2. Aislamiento
Write-Host "`n[2] AISLAMIENTO DE USUARIOS" -ForegroundColor Yellow
$iso = Get-WebConfigurationProperty `
    -Filter "system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
    -Name "mode" -ErrorAction SilentlyContinue
Write-Host "  Modo: $iso"

# 3. Autenticacion
Write-Host "`n[3] AUTENTICACION" -ForegroundColor Yellow
$anon = Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -ErrorAction SilentlyContinue
$basic= Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -ErrorAction SilentlyContinue
$usr  = Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.username -ErrorAction SilentlyContinue
Write-Host "  Anonima habilitada : $($anon.Value)"
Write-Host "  Anonima usuario    : $($usr.Value)"
Write-Host "  Basica habilitada  : $($basic.Value)"

# 4. SSL
Write-Host "`n[4] SSL" -ForegroundColor Yellow
$sslCtrl = Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -ErrorAction SilentlyContinue
$sslData = Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -ErrorAction SilentlyContinue
Write-Host "  controlChannelPolicy: $($sslCtrl.Value)  (0=SslAllow, 1=SslRequire)"
Write-Host "  dataChannelPolicy   : $($sslData.Value)  (0=SslAllow, 1=SslRequire)"

# 5. Reglas de autorizacion
Write-Host "`n[5] REGLAS DE AUTORIZACION" -ForegroundColor Yellow
$rules = Get-WebConfiguration "/system.ftpServer/security/authorization" -PSPath IIS:\ -Location "FTP" -ErrorAction SilentlyContinue
if ($rules) {
    $rules | ForEach-Object {
        Write-Host "  accessType=$($_.accessType) users='$($_.users)' roles='$($_.roles)' permissions=$($_.permissions)"
    }
} else {
    Write-Host "  [!] Sin reglas de autorizacion" -ForegroundColor Red
}

# 6. Permisos de carpetas clave
Write-Host "`n[6] PERMISOS NTFS" -ForegroundColor Yellow
$paths = @(
    "C:\FTP",
    "C:\FTP\LocalUser",
    "C:\FTP\LocalUser\Public",
    "C:\FTP\LocalUser\Public\General"
)
foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Host "  $p" -ForegroundColor Cyan
        (Get-Acl $p).Access | ForEach-Object {
            Write-Host ("    {0,-40} {1,-20} {2}" -f $_.IdentityReference, $_.FileSystemRights, $_.AccessControlType)
        }
    } else {
        Write-Host "  [FALTA] $p" -ForegroundColor Red
    }
}

# 7. Estructura de directorios
Write-Host "`n[7] ESTRUCTURA C:\FTP" -ForegroundColor Yellow
Get-ChildItem "C:\FTP" -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $tipo = if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { "[LINK]" }
            elseif ($_.PSIsContainer) { "[DIR] " } else { "[FILE]" }
    Write-Host "  $tipo $($_.Name)"
}
Write-Host "  LocalUser\"
Get-ChildItem "C:\FTP\LocalUser" -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $tipo = if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { "[LINK]" }
            elseif ($_.PSIsContainer) { "[DIR] " } else { "[FILE]" }
    Write-Host "    $tipo $($_.Name)"
}

# 8. applicationHost.config — SSL en siteDefaults
Write-Host "`n[8] SSL EN applicationHost.config" -ForegroundColor Yellow
$cfg = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
[xml]$xml = Get-Content $cfg -Encoding UTF8
$sd = $xml.configuration."system.applicationHost".sites.siteDefaults.ftpServer.security.ssl
Write-Host "  siteDefaults controlChannelPolicy: $($sd.controlChannelPolicy)"
Write-Host "  siteDefaults dataChannelPolicy   : $($sd.dataChannelPolicy)"
$ftpSite = $xml.configuration."system.applicationHost".sites.site | Where-Object { $_.name -eq "FTP" }
if ($ftpSite.ftpServer.security.ssl) {
    Write-Host "  FTP site controlChannelPolicy    : $($ftpSite.ftpServer.security.ssl.controlChannelPolicy)"
    Write-Host "  FTP site dataChannelPolicy       : $($ftpSite.ftpServer.security.ssl.dataChannelPolicy)"
}

Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host "  FIN DIAGNOSTICO" -ForegroundColor Cyan
Write-Host "================================================="