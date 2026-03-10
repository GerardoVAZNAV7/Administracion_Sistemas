# fix_ftp_v2.ps1
# Ejecutar como Administrador
# Estrategia: limpiar XML PRIMERO con servicios detenidos, luego configurar IIS

Import-Module WebAdministration -ErrorAction Stop

$adminGroup = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate(
    [System.Security.Principal.NTAccount]).Value

Write-Host "=================================================" 
Write-Host "  FIX FTP v2" 
Write-Host "================================================="

# ─────────────────────────────────────────────────────────────────
# PASO 0: Detener servicios PRIMERO para liberar el lock del XML
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[0] Deteniendo servicios..." -ForegroundColor White
Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
Stop-Service W3SVC  -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# PASO 1: Limpiar XML — eliminar TODOS los <location path="FTP">
# y reescribir uno solo limpio
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[1] Limpiando applicationHost.config..." -ForegroundColor White

$cfg = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
[xml]$xml = Get-Content $cfg -Encoding UTF8

# Recolectar todos los nodos location con path="FTP"
$toRemove = New-Object System.Collections.ArrayList
foreach ($node in $xml.configuration.ChildNodes) {
    if ($node.LocalName -eq "location" -and $node.GetAttribute("path") -eq "FTP") {
        [void]$toRemove.Add($node)
    }
}
Write-Host "  Nodos <location path=FTP> encontrados: $($toRemove.Count)" -ForegroundColor DarkGray
foreach ($node in $toRemove) {
    $xml.configuration.RemoveChild($node) | Out-Null
}

# Parchear SSL en siteDefaults
$sd = $xml.configuration."system.applicationHost".sites.siteDefaults.ftpServer.security.ssl
if ($sd) {
    $sd.controlChannelPolicy = "SslAllow"
    $sd.dataChannelPolicy    = "SslAllow"
}

# Parchear SSL en el sitio FTP
$ftpSiteNode = $xml.configuration."system.applicationHost".sites.site |
    Where-Object { $_.name -eq "FTP" }
if ($ftpSiteNode -and $ftpSiteNode.ftpServer.security.ssl) {
    $ftpSiteNode.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
    $ftpSiteNode.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
}

# Parchear physicalPath del sitio FTP directamente en el XML
if ($ftpSiteNode) {
    $ftpSiteNode.application.virtualDirectory.physicalPath = "C:\FTP\LocalUser"
    Write-Host "  physicalPath -> C:\FTP\LocalUser" -ForegroundColor DarkGray
}

# Crear un unico <location path="FTP"> limpio con las 3 reglas
$locNode  = $xml.CreateElement("location")
$locNode.SetAttribute("path", "FTP")

$ftpNode  = $xml.CreateElement("system.ftpServer")
$secNode  = $xml.CreateElement("security")
$authNode = $xml.CreateElement("authorization")

function New-Rule($aType, $users, $roles, $perms) {
    $r = $xml.CreateElement("add")
    $r.SetAttribute("accessType",  $aType)
    $r.SetAttribute("users",       $users)
    $r.SetAttribute("roles",       $roles)
    $r.SetAttribute("permissions", $perms)
    return $r
}

$authNode.AppendChild((New-Rule "Allow" "?" ""                       "Read"))       | Out-Null
$authNode.AppendChild((New-Rule "Allow" "" "reprobados,recursadores" "Read, Write")) | Out-Null
$authNode.AppendChild((New-Rule "Deny"  "*" ""                       "Read, Write")) | Out-Null

$secNode.AppendChild($authNode)  | Out-Null
$ftpNode.AppendChild($secNode)   | Out-Null
$locNode.AppendChild($ftpNode)   | Out-Null
$xml.configuration.AppendChild($locNode) | Out-Null

$xml.Save($cfg)
Write-Host "  XML guardado OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# PASO 2: Iniciar servicios
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[2] Iniciando servicios..." -ForegroundColor White
Start-Service W3SVC  -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-Service ftpsvc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# PASO 3: Configurar IIS via cmdlets (ahora que el XML esta limpio)
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[3] Configurando IIS..." -ForegroundColor White

# Autenticacion
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name ftpServer.security.authentication.anonymousAuthentication.enabled  -Value $true
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name ftpServer.security.authentication.anonymousAuthentication.username -Value "IUSR"
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name ftpServer.security.authentication.anonymousAuthentication.password -Value ""
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name ftpServer.security.authentication.basicAuthentication.enabled      -Value $true

# SSL
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0

# Aislamiento
Set-WebConfigurationProperty `
    -Filter "system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
    -Name "mode" -Value "IsolateAllDirectories"

Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# PASO 4: Permisos NTFS
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[4] Aplicando permisos NTFS..." -ForegroundColor White

# Directorios
@(
    "C:\FTP\LocalUser\Public\General",
    "C:\FTP\grupos\reprobados",
    "C:\FTP\grupos\recursadores"
) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
}

# LocalUser
icacls "C:\FTP\LocalUser" /inheritance:r                             | Out-Null
icacls "C:\FTP\LocalUser" /grant "${adminGroup}:(OI)(CI)F"          | Out-Null
icacls "C:\FTP\LocalUser" /grant "SYSTEM:(OI)(CI)F"                 | Out-Null
icacls "C:\FTP\LocalUser" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"     | Out-Null
icacls "C:\FTP\LocalUser" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"     | Out-Null
icacls "C:\FTP\LocalUser" /grant "BUILTIN\Users:(RX)"               | Out-Null

# Public
icacls "C:\FTP\LocalUser\Public" /inheritance:r                      | Out-Null
icacls "C:\FTP\LocalUser\Public" /grant "${adminGroup}:(OI)(CI)F"   | Out-Null
icacls "C:\FTP\LocalUser\Public" /grant "SYSTEM:(OI)(CI)F"          | Out-Null
icacls "C:\FTP\LocalUser\Public" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"    | Out-Null
icacls "C:\FTP\LocalUser\Public" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"    | Out-Null

# General
icacls "C:\FTP\LocalUser\Public\General" /inheritance:r                         | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "${adminGroup}:(OI)(CI)F"      | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "SYSTEM:(OI)(CI)F"             | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX" | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX" | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "BUILTIN\Users:(OI)(CI)M"      | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "SRV-WINDOW\reprobados:(OI)(CI)M"   | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "SRV-WINDOW\recursadores:(OI)(CI)M" | Out-Null

# Grupos
foreach ($g in @("reprobados","recursadores")) {
    icacls "C:\FTP\grupos\$g" /inheritance:r                              | Out-Null
    icacls "C:\FTP\grupos\$g" /grant "${adminGroup}:(OI)(CI)F"           | Out-Null
    icacls "C:\FTP\grupos\$g" /grant "SYSTEM:(OI)(CI)F"                  | Out-Null
    icacls "C:\FTP\grupos\$g" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"      | Out-Null
    icacls "C:\FTP\grupos\$g" /grant "SRV-WINDOW\$g`:(OI)(CI)M"          | Out-Null
}

Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# PASO 5: Recrear symlinks de todos los usuarios
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[5] Recreando symlinks de usuarios..." -ForegroundColor White

Get-ChildItem "C:\FTP\LocalUser" -Directory |
  Where-Object { $_.Name -ne "Public" } | ForEach-Object {

    $user     = $_.Name
    $userRoot = $_.FullName

    # Detectar grupo
    $grupo = ""
    try {
        if (Get-LocalGroupMember -Group "reprobados"   -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$user" }) { $grupo = "reprobados" }
        elseif (Get-LocalGroupMember -Group "recursadores" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$user" }) { $grupo = "recursadores" }
        elseif (Get-LocalGroupMember -Group "Reprobados"   -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$user" }) { $grupo = "reprobados" }
        elseif (Get-LocalGroupMember -Group "Recursadores" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$user" }) { $grupo = "recursadores" }
    } catch {}

    # Borrar todos los symlinks existentes
    Get-ChildItem $userRoot -Force |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
        ForEach-Object { cmd /c "rmdir `"$($_.FullName)`"" 2>$null | Out-Null }

    # Carpeta personal
    $personalDir = "$userRoot\$user"
    if (-not (Test-Path $personalDir)) {
        New-Item -Path $personalDir -ItemType Directory -Force | Out-Null
    }

    # Permisos userRoot
    icacls $userRoot /inheritance:r                                | Out-Null
    icacls $userRoot /grant "${adminGroup}:(OI)(CI)F"             | Out-Null
    icacls $userRoot /grant "SYSTEM:(OI)(CI)F"                    | Out-Null
    icacls $userRoot /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"        | Out-Null
    icacls $userRoot /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"        | Out-Null
    icacls $userRoot /grant "${user}:(OI)(CI)RX"                  | Out-Null
    icacls $personalDir /grant "${user}:(OI)(CI)M"                | Out-Null

    # Symlink General -> C:\FTP\LocalUser\Public\General
    cmd /c "mklink /D `"$userRoot\General`" `"C:\FTP\LocalUser\Public\General`"" | Out-Null

    # Symlink grupo -> C:\FTP\grupos\<grupo>
    if ($grupo -ne "") {
        cmd /c "mklink /D `"$userRoot\$grupo`" `"C:\FTP\grupos\$grupo`"" | Out-Null
        Write-Host ("  {0,-15} -> General + {1}" -f $user, $grupo) -ForegroundColor DarkGray
    } else {
        Write-Host ("  {0,-15} -> General (sin grupo)" -f $user) -ForegroundColor Yellow
    }
}
Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# PASO 6: Arrancar el sitio FTP
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[6] Arrancando sitio FTP..." -ForegroundColor White

$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
& $appcmd start site /site.name:"FTP" | Out-Null
Start-Sleep -Seconds 2

$site = Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue
$color = if ($site.State -eq "Started") { "Green" } else { "Red" }
Write-Host "  Estado del sitio: $($site.State)" -ForegroundColor $color

Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host "  LISTO — Conexion desde FileZilla:" -ForegroundColor White
Write-Host "  Protocolo : FTP (no SFTP)"
Write-Host "  Cifrado   : FTP plano (inseguro)"
Write-Host "  Anonimo   : usuario=anonymous  password=(vacio)"
Write-Host "  Autenticado: tu usuario y password normales"
Write-Host "=================================================" -ForegroundColor Cyan