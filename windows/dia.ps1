# # diagnostico_ftp.ps1
# # Ejecutar en PowerShell del servidor como Administrador

# Import-Module WebAdministration -ErrorAction SilentlyContinue

# Write-Host "=================================================" -ForegroundColor Cyan
# Write-Host "  DIAGNOSTICO FTP" -ForegroundColor Cyan
# Write-Host "================================================="

# # 1. Sitio FTP
# Write-Host "`n[1] SITIO FTP EN IIS" -ForegroundColor Yellow
# $site = Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue
# if ($site) {
#     Write-Host "  PhysicalPath : $($site.physicalPath)"
#     Write-Host "  Estado       : $($site.State)"
#     Write-Host "  Puerto       : $($site.Bindings.Collection[0].bindingInformation)"
# } else {
#     Write-Host "  [ERROR] Sitio FTP no existe" -ForegroundColor Red
# }

# # 2. Aislamiento
# Write-Host "`n[2] AISLAMIENTO DE USUARIOS" -ForegroundColor Yellow
# $iso = Get-WebConfigurationProperty `
#     -Filter "system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
#     -Name "mode" -ErrorAction SilentlyContinue
# Write-Host "  Modo: $iso"

# # 3. Autenticacion
# Write-Host "`n[3] AUTENTICACION" -ForegroundColor Yellow
# $anon = Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -ErrorAction SilentlyContinue
# $basic= Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -ErrorAction SilentlyContinue
# $usr  = Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.username -ErrorAction SilentlyContinue
# Write-Host "  Anonima habilitada : $($anon.Value)"
# Write-Host "  Anonima usuario    : $($usr.Value)"
# Write-Host "  Basica habilitada  : $($basic.Value)"

# # 4. SSL
# Write-Host "`n[4] SSL" -ForegroundColor Yellow
# $sslCtrl = Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -ErrorAction SilentlyContinue
# $sslData = Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -ErrorAction SilentlyContinue
# Write-Host "  controlChannelPolicy: $($sslCtrl.Value)  (0=SslAllow, 1=SslRequire)"
# Write-Host "  dataChannelPolicy   : $($sslData.Value)  (0=SslAllow, 1=SslRequire)"

# # 5. Reglas de autorizacion
# Write-Host "`n[5] REGLAS DE AUTORIZACION" -ForegroundColor Yellow
# $rules = Get-WebConfiguration "/system.ftpServer/security/authorization" -PSPath IIS:\ -Location "FTP" -ErrorAction SilentlyContinue
# if ($rules) {
#     $rules | ForEach-Object {
#         Write-Host "  accessType=$($_.accessType) users='$($_.users)' roles='$($_.roles)' permissions=$($_.permissions)"
#     }
# } else {
#     Write-Host "  [!] Sin reglas de autorizacion" -ForegroundColor Red
# }

# # 6. Permisos de carpetas clave
# Write-Host "`n[6] PERMISOS NTFS" -ForegroundColor Yellow
# $paths = @(
#     "C:\FTP",
#     "C:\FTP\LocalUser",
#     "C:\FTP\LocalUser\Public",
#     "C:\FTP\LocalUser\Public\General"
# )
# foreach ($p in $paths) {
#     if (Test-Path $p) {
#         Write-Host "  $p" -ForegroundColor Cyan
#         (Get-Acl $p).Access | ForEach-Object {
#             Write-Host ("    {0,-40} {1,-20} {2}" -f $_.IdentityReference, $_.FileSystemRights, $_.AccessControlType)
#         }
#     } else {
#         Write-Host "  [FALTA] $p" -ForegroundColor Red
#     }
# }

# # 7. Estructura de directorios
# Write-Host "`n[7] ESTRUCTURA C:\FTP" -ForegroundColor Yellow
# Get-ChildItem "C:\FTP" -Force -ErrorAction SilentlyContinue | ForEach-Object {
#     $tipo = if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { "[LINK]" }
#             elseif ($_.PSIsContainer) { "[DIR] " } else { "[FILE]" }
#     Write-Host "  $tipo $($_.Name)"
# }
# Write-Host "  LocalUser\"
# Get-ChildItem "C:\FTP\LocalUser" -Force -ErrorAction SilentlyContinue | ForEach-Object {
#     $tipo = if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { "[LINK]" }
#             elseif ($_.PSIsContainer) { "[DIR] " } else { "[FILE]" }
#     Write-Host "    $tipo $($_.Name)"
# }

# # 8. applicationHost.config — SSL en siteDefaults
# Write-Host "`n[8] SSL EN applicationHost.config" -ForegroundColor Yellow
# $cfg = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
# [xml]$xml = Get-Content $cfg -Encoding UTF8
# $sd = $xml.configuration."system.applicationHost".sites.siteDefaults.ftpServer.security.ssl
# Write-Host "  siteDefaults controlChannelPolicy: $($sd.controlChannelPolicy)"
# Write-Host "  siteDefaults dataChannelPolicy   : $($sd.dataChannelPolicy)"
# $ftpSite = $xml.configuration."system.applicationHost".sites.site | Where-Object { $_.name -eq "FTP" }
# if ($ftpSite.ftpServer.security.ssl) {
#     Write-Host "  FTP site controlChannelPolicy    : $($ftpSite.ftpServer.security.ssl.controlChannelPolicy)"
#     Write-Host "  FTP site dataChannelPolicy       : $($ftpSite.ftpServer.security.ssl.dataChannelPolicy)"
# }

# Write-Host "`n=================================================" -ForegroundColor Cyan
# Write-Host "  FIN DIAGNOSTICO" -ForegroundColor Cyan
# Write-Host "================================================="


# fix_ftp.ps1
# Ejecutar como Administrador en el servidor
# Corrige todos los problemas detectados en el diagnostico

# fix_ftp.ps1
# Ejecutar como Administrador en el servidor
# Corrige todos los problemas detectados en el diagnostico

Import-Module WebAdministration -ErrorAction Stop

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  FIX FTP - Basado en diagnostico real"          -ForegroundColor Cyan
Write-Host "================================================="

$adminGroup = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate(
    [System.Security.Principal.NTAccount]).Value

# ─────────────────────────────────────────────────────────────────
# FIX 1: Limpiar carpetas duplicadas
# Existe C:\FTP\grupos\reprobados Y C:\FTP\Reprobados
# Usaremos C:\FTP\LocalUser como raiz del sitio con grupos en C:\FTP\grupos
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[1/6] Normalizando estructura de carpetas..." -ForegroundColor White

# Asegurar que existen los directorios correctos
@(
    "C:\FTP\LocalUser\Public\General",
    "C:\FTP\grupos\reprobados",
    "C:\FTP\grupos\recursadores"
) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
}
Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# FIX 2: Permisos NTFS correctos
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[2/6] Aplicando permisos NTFS..." -ForegroundColor White

# C:\FTP\LocalUser — base, IUSR e IIS_IUSRS necesitan RX para que IIS navegue
icacls "C:\FTP\LocalUser" /inheritance:r                       | Out-Null
icacls "C:\FTP\LocalUser" /grant "${adminGroup}:(OI)(CI)F"    | Out-Null
icacls "C:\FTP\LocalUser" /grant "SYSTEM:(OI)(CI)F"           | Out-Null
icacls "C:\FTP\LocalUser" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"      | Out-Null
icacls "C:\FTP\LocalUser" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"      | Out-Null
icacls "C:\FTP\LocalUser" /grant "BUILTIN\Users:(RX)"         | Out-Null

# C:\FTP\LocalUser\Public — chroot del anonimo, IUSR RX solo esta carpeta
icacls "C:\FTP\LocalUser\Public" /inheritance:r                        | Out-Null
icacls "C:\FTP\LocalUser\Public" /grant "${adminGroup}:(OI)(CI)F"     | Out-Null
icacls "C:\FTP\LocalUser\Public" /grant "SYSTEM:(OI)(CI)F"            | Out-Null
icacls "C:\FTP\LocalUser\Public" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"       | Out-Null
icacls "C:\FTP\LocalUser\Public" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"       | Out-Null

# C:\FTP\LocalUser\Public\General — anonimo lectura, usuarios autenticados modificar
icacls "C:\FTP\LocalUser\Public\General" /inheritance:r                       | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "${adminGroup}:(OI)(CI)F"    | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "SYSTEM:(OI)(CI)F"           | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"      | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"      | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "BUILTIN\Users:(OI)(CI)M"    | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "SRV-WINDOW\reprobados:(OI)(CI)M"   | Out-Null
icacls "C:\FTP\LocalUser\Public\General" /grant "SRV-WINDOW\recursadores:(OI)(CI)M" | Out-Null

# Grupos
foreach ($g in @("reprobados","recursadores")) {
    icacls "C:\FTP\grupos\$g" /inheritance:r                          | Out-Null
    icacls "C:\FTP\grupos\$g" /grant "${adminGroup}:(OI)(CI)F"       | Out-Null
    icacls "C:\FTP\grupos\$g" /grant "SYSTEM:(OI)(CI)F"              | Out-Null
    icacls "C:\FTP\grupos\$g" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"  | Out-Null
    icacls "C:\FTP\grupos\$g" /grant "SRV-WINDOW\$g`:(OI)(CI)M"      | Out-Null
}

Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# FIX 3: Recrear symlinks de todos los usuarios apuntando a rutas correctas
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[3/6] Recreando symlinks de usuarios..." -ForegroundColor White

Get-ChildItem "C:\FTP\LocalUser" -Directory | Where-Object { $_.Name -ne "Public" } | ForEach-Object {
    $user     = $_.Name
    $userRoot = $_.FullName

    # Detectar grupo actual del usuario
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

    # Borrar symlinks existentes (cualquier nombre de grupo)
    Get-ChildItem $userRoot -Force | Where-Object {
        $_.Attributes -band [IO.FileAttributes]::ReparsePoint
    } | ForEach-Object {
        cmd /c "rmdir `"$($_.FullName)`"" 2>$null | Out-Null
    }

    # Crear carpeta personal si no existe
    $personalDir = "$userRoot\$user"
    if (-not (Test-Path $personalDir)) {
        New-Item -Path $personalDir -ItemType Directory -Force | Out-Null
    }

    # Permisos userRoot: IUSR e IIS_IUSRS RX para que IIS verifique el home (fix 530)
    icacls $userRoot /inheritance:r                                    | Out-Null
    icacls $userRoot /grant "${adminGroup}:(OI)(CI)F"                 | Out-Null
    icacls $userRoot /grant "SYSTEM:(OI)(CI)F"                        | Out-Null
    icacls $userRoot /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"            | Out-Null
    icacls $userRoot /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"            | Out-Null
    icacls $userRoot /grant "${user}:(OI)(CI)RX"                      | Out-Null

    # Permisos carpeta personal: Modify recursivo
    icacls $personalDir /grant "${user}:(OI)(CI)M"                    | Out-Null

    # Symlink General
    cmd /c "mklink /D `"$userRoot\General`" `"C:\FTP\LocalUser\Public\General`"" | Out-Null

    # Symlink grupo
    if ($grupo -ne "") {
        cmd /c "mklink /D `"$userRoot\$grupo`" `"C:\FTP\grupos\$grupo`"" | Out-Null
        Write-Host "  $user -> General + $grupo" -ForegroundColor DarkGray
    } else {
        Write-Host "  $user -> General (sin grupo detectado)" -ForegroundColor Yellow
    }
}

Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# FIX 4: Sitio FTP — apuntar a C:\FTP\LocalUser y verificar config
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[4/6] Configurando sitio FTP en IIS..." -ForegroundColor White

Set-ItemProperty "IIS:\Sites\FTP" -Name physicalPath -Value "C:\FTP\LocalUser"

Set-WebConfigurationProperty `
    -Filter "system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
    -Name "mode" -Value "IsolateAllDirectories"

Set-ItemProperty "IIS:\Sites\FTP" `
    -Name ftpServer.security.authentication.anonymousAuthentication.enabled  -Value $true
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name ftpServer.security.authentication.anonymousAuthentication.username -Value "IUSR"
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name ftpServer.security.authentication.anonymousAuthentication.password -Value ""
Set-ItemProperty "IIS:\Sites\FTP" `
    -Name ftpServer.security.authentication.basicAuthentication.enabled      -Value $true

Write-Host "  OK" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# FIX 5: SSL y reglas de autorizacion — editar XML con servicios detenidos
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[5/6] Aplicando SSL y autorizacion en applicationHost.config..." -ForegroundColor White

Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
Stop-Service W3SVC  -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$cfg = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
[xml]$xml = Get-Content $cfg -Encoding UTF8

# SSL en siteDefaults
$sd = $xml.configuration."system.applicationHost".sites.siteDefaults.ftpServer.security.ssl
if ($sd) {
    $sd.controlChannelPolicy = "SslAllow"
    $sd.dataChannelPolicy    = "SslAllow"
}

# SSL en sitio FTP
$ftpSite = $xml.configuration."system.applicationHost".sites.site | Where-Object { $_.name -eq "FTP" }
if ($ftpSite -and $ftpSite.ftpServer.security.ssl) {
    $ftpSite.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
    $ftpSite.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
}

# Limpiar TODAS las reglas de autorizacion duplicadas del XML directamente
# (Get-WebConfiguration falla porque hay duplicados — los borramos a mano)
$allLocations = $xml.configuration.location
foreach ($loc in $allLocations) {
    if ($loc.path -eq "FTP") {
        $ftpNode = $loc."system.ftpServer"
        if ($ftpNode) {
            $secNode = $ftpNode.security
            if ($secNode) {
                $authNode = $secNode.authorization
                if ($authNode) { $authNode.RemoveAll() }
            }
        }
    }
}

# Buscar o crear <location path="FTP">
$locNode = $xml.configuration.location | Where-Object { $_.path -eq "FTP" }
if (-not $locNode) {
    $locNode = $xml.CreateElement("location")
    $locNode.SetAttribute("path", "FTP")
    $xml.configuration.AppendChild($locNode) | Out-Null
}

# Asegurar jerarquia
if (-not $locNode."system.ftpServer") {
    $locNode.AppendChild($xml.CreateElement("system.ftpServer")) | Out-Null
}
if (-not $locNode."system.ftpServer".security) {
    $locNode."system.ftpServer".AppendChild($xml.CreateElement("security")) | Out-Null
}

$authNode = $locNode."system.ftpServer".security.authorization
if ($authNode) {
    $authNode.RemoveAll()
} else {
    $authNode = $xml.CreateElement("authorization")
    $locNode."system.ftpServer".security.AppendChild($authNode) | Out-Null
}

function New-AuthRule($aType, $users, $roles, $perms) {
    $r = $xml.CreateElement("add")
    $r.SetAttribute("accessType",  $aType)
    $r.SetAttribute("users",       $users)
    $r.SetAttribute("roles",       $roles)
    $r.SetAttribute("permissions", $perms)
    return $r
}

# users="?" = anonimo en IIS-FTP
$authNode.AppendChild((New-AuthRule "Allow" "?" ""                        "Read"))       | Out-Null
$authNode.AppendChild((New-AuthRule "Allow" "" "reprobados,recursadores"  "Read, Write")) | Out-Null
$authNode.AppendChild((New-AuthRule "Deny"  "*" ""                        "Read, Write")) | Out-Null

$xml.Save($cfg)
Write-Host "  Config guardada." -ForegroundColor DarkGray

# ─────────────────────────────────────────────────────────────────
# FIX 6: Arrancar el sitio
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[6/6] Iniciando servicios..." -ForegroundColor White

Start-Service W3SVC  -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service ftpsvc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Arrancar el sitio FTP (estaba Stopped)
Start-WebItem "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$site = Get-WebSite -Name "FTP"
Write-Host "  Estado del sitio: $($site.State)" -ForegroundColor $(if ($site.State -eq "Started") { "Green" } else { "Red" })

Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host "  RESUMEN DE ACCESOS" -ForegroundColor Cyan
Write-Host "================================================="
Write-Host "  - Anonimo  : usuario 'anonymous', sin password, cifrado FTP plano"
Write-Host "               Ve: /General (solo lectura)"
Write-Host "  - Autenticado: usuario y password normales, cifrado FTP plano"  
Write-Host "               Ve: /<usuario>  /General  /<grupo>"
Write-Host "=================================================" -ForegroundColor Cyan