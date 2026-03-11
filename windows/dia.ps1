# # # # # # # fix_ftp_v2.ps1
# # # # # # # Ejecutar como Administrador
# # # # # # # Estrategia: limpiar XML PRIMERO con servicios detenidos, luego configurar IIS

# # # # # # Import-Module WebAdministration -ErrorAction Stop

# # # # # # $adminGroup = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate(
# # # # # #     [System.Security.Principal.NTAccount]).Value

# # # # # # Write-Host "=================================================" -ForegroundColor Cyan
# # # # # # Write-Host "  FIX FTP v2" -ForegroundColor Cyan
# # # # # # Write-Host "================================================="

# # # # # # # -----------------------------------------------------------------
# # # # # # # PASO 0: Detener servicios PRIMERO para liberar el lock del XML
# # # # # # # -----------------------------------------------------------------
# # # # # # Write-Host "`n[0] Deteniendo servicios..." -ForegroundColor White
# # # # # # Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
# # # # # # Stop-Service W3SVC  -Force -ErrorAction SilentlyContinue
# # # # # # Start-Sleep -Seconds 4
# # # # # # Write-Host "  OK" -ForegroundColor Green

# # # # # # # -----------------------------------------------------------------
# # # # # # # PASO 1: Limpiar XML - eliminar TODOS los <location path="FTP">
# # # # # # # y reescribir uno solo limpio
# # # # # # # -----------------------------------------------------------------
# # # # # # Write-Host "`n[1] Limpiando applicationHost.config..." -ForegroundColor White

# # # # # # $cfg = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
# # # # # # [xml]$xml = Get-Content $cfg -Encoding UTF8

# # # # # # # Recolectar todos los nodos location con path="FTP"
# # # # # # $toRemove = New-Object System.Collections.ArrayList
# # # # # # foreach ($node in $xml.configuration.ChildNodes) {
# # # # # #     if ($node.LocalName -eq "location" -and $node.GetAttribute("path") -eq "FTP") {
# # # # # #         [void]$toRemove.Add($node)
# # # # # #     }
# # # # # # }
# # # # # # Write-Host "  Nodos <location path=FTP> encontrados: $($toRemove.Count)" -ForegroundColor DarkGray
# # # # # # foreach ($node in $toRemove) {
# # # # # #     $xml.configuration.RemoveChild($node) | Out-Null
# # # # # # }

# # # # # # # Parchear SSL en siteDefaults
# # # # # # $sd = $xml.configuration."system.applicationHost".sites.siteDefaults.ftpServer.security.ssl
# # # # # # if ($sd) {
# # # # # #     $sd.controlChannelPolicy = "SslAllow"
# # # # # #     $sd.dataChannelPolicy    = "SslAllow"
# # # # # # }

# # # # # # # Parchear SSL en el sitio FTP
# # # # # # $ftpSiteNode = $xml.configuration."system.applicationHost".sites.site |
# # # # # #     Where-Object { $_.name -eq "FTP" }
# # # # # # if ($ftpSiteNode -and $ftpSiteNode.ftpServer.security.ssl) {
# # # # # #     $ftpSiteNode.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
# # # # # #     $ftpSiteNode.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
# # # # # # }

# # # # # # # Parchear physicalPath del sitio FTP directamente en el XML
# # # # # # if ($ftpSiteNode) {
# # # # # #     $ftpSiteNode.application.virtualDirectory.physicalPath = "C:\FTP\LocalUser"
# # # # # #     Write-Host "  physicalPath -> C:\FTP\LocalUser" -ForegroundColor DarkGray
# # # # # # }

# # # # # # # Crear un unico <location path="FTP"> limpio con las 3 reglas
# # # # # # $locNode  = $xml.CreateElement("location")
# # # # # # $locNode.SetAttribute("path", "FTP")

# # # # # # $ftpNode  = $xml.CreateElement("system.ftpServer")
# # # # # # $secNode  = $xml.CreateElement("security")
# # # # # # $authNode = $xml.CreateElement("authorization")

# # # # # # function New-Rule($aType, $users, $roles, $perms) {
# # # # # #     $r = $xml.CreateElement("add")
# # # # # #     $r.SetAttribute("accessType",  $aType)
# # # # # #     $r.SetAttribute("users",       $users)
# # # # # #     $r.SetAttribute("roles",       $roles)
# # # # # #     $r.SetAttribute("permissions", $perms)
# # # # # #     return $r
# # # # # # }

# # # # # # $authNode.AppendChild((New-Rule "Allow" "?" ""                       "Read"))       | Out-Null
# # # # # # $authNode.AppendChild((New-Rule "Allow" "" "reprobados,recursadores" "Read, Write")) | Out-Null
# # # # # # $authNode.AppendChild((New-Rule "Deny"  "*" ""                       "Read, Write")) | Out-Null

# # # # # # $secNode.AppendChild($authNode)  | Out-Null
# # # # # # $ftpNode.AppendChild($secNode)   | Out-Null
# # # # # # $locNode.AppendChild($ftpNode)   | Out-Null
# # # # # # $xml.configuration.AppendChild($locNode) | Out-Null

# # # # # # $xml.Save($cfg)
# # # # # # Write-Host "  XML guardado OK" -ForegroundColor Green

# # # # # # # -----------------------------------------------------------------
# # # # # # # PASO 2: Iniciar servicios
# # # # # # # -----------------------------------------------------------------
# # # # # # Write-Host "`n[2] Iniciando servicios..." -ForegroundColor White
# # # # # # Start-Service W3SVC  -ErrorAction SilentlyContinue
# # # # # # Start-Sleep -Seconds 3
# # # # # # Start-Service ftpsvc -ErrorAction SilentlyContinue
# # # # # # Start-Sleep -Seconds 2
# # # # # # Write-Host "  OK" -ForegroundColor Green

# # # # # # # -----------------------------------------------------------------
# # # # # # # PASO 3: Configurar IIS via cmdlets (ahora que el XML esta limpio)
# # # # # # # -----------------------------------------------------------------
# # # # # # Write-Host "`n[3] Configurando IIS..." -ForegroundColor White

# # # # # # # Autenticacion
# # # # # # Set-ItemProperty "IIS:\Sites\FTP" `
# # # # # #     -Name ftpServer.security.authentication.anonymousAuthentication.enabled  -Value $true
# # # # # # Set-ItemProperty "IIS:\Sites\FTP" `
# # # # # #     -Name ftpServer.security.authentication.anonymousAuthentication.username -Value "IUSR"
# # # # # # Set-ItemProperty "IIS:\Sites\FTP" `
# # # # # #     -Name ftpServer.security.authentication.anonymousAuthentication.password -Value ""
# # # # # # Set-ItemProperty "IIS:\Sites\FTP" `
# # # # # #     -Name ftpServer.security.authentication.basicAuthentication.enabled      -Value $true

# # # # # # # SSL
# # # # # # Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
# # # # # # Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0

# # # # # # # Aislamiento
# # # # # # Set-WebConfigurationProperty `
# # # # # #     -Filter "system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
# # # # # #     -Name "mode" -Value "IsolateAllDirectories"

# # # # # # Write-Host "  OK" -ForegroundColor Green

# # # # # # # -----------------------------------------------------------------
# # # # # # # PASO 4: Permisos NTFS
# # # # # # # -----------------------------------------------------------------
# # # # # # Write-Host "`n[4] Aplicando permisos NTFS..." -ForegroundColor White

# # # # # # # Directorios
# # # # # # @(
# # # # # #     "C:\FTP\LocalUser\Public\General",
# # # # # #     "C:\FTP\grupos\reprobados",
# # # # # #     "C:\FTP\grupos\recursadores"
# # # # # # ) | ForEach-Object {
# # # # # #     if (-not (Test-Path $_)) { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
# # # # # # }

# # # # # # # LocalUser
# # # # # # icacls "C:\FTP\LocalUser" /inheritance:r                             | Out-Null
# # # # # # icacls "C:\FTP\LocalUser" /grant "${adminGroup}:(OI)(CI)F"          | Out-Null
# # # # # # icacls "C:\FTP\LocalUser" /grant "SYSTEM:(OI)(CI)F"                 | Out-Null
# # # # # # icacls "C:\FTP\LocalUser" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"     | Out-Null
# # # # # # icacls "C:\FTP\LocalUser" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"     | Out-Null
# # # # # # icacls "C:\FTP\LocalUser" /grant "BUILTIN\Users:(RX)"               | Out-Null

# # # # # # # Public
# # # # # # icacls "C:\FTP\LocalUser\Public" /inheritance:r                      | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public" /grant "${adminGroup}:(OI)(CI)F"   | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public" /grant "SYSTEM:(OI)(CI)F"          | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"    | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"    | Out-Null

# # # # # # # General
# # # # # # icacls "C:\FTP\LocalUser\Public\General" /inheritance:r                         | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public\General" /grant "${adminGroup}:(OI)(CI)F"      | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public\General" /grant "SYSTEM:(OI)(CI)F"             | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public\General" /grant "NT AUTHORITY\IUSR:(OI)(CI)RX" | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public\General" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX" | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public\General" /grant "BUILTIN\Users:(OI)(CI)M"      | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public\General" /grant "SRV-WINDOW\reprobados:(OI)(CI)M"   | Out-Null
# # # # # # icacls "C:\FTP\LocalUser\Public\General" /grant "SRV-WINDOW\recursadores:(OI)(CI)M" | Out-Null

# # # # # # # Grupos
# # # # # # foreach ($g in @("reprobados","recursadores")) {
# # # # # #     icacls "C:\FTP\grupos\$g" /inheritance:r                              | Out-Null
# # # # # #     icacls "C:\FTP\grupos\$g" /grant "${adminGroup}:(OI)(CI)F"           | Out-Null
# # # # # #     icacls "C:\FTP\grupos\$g" /grant "SYSTEM:(OI)(CI)F"                  | Out-Null
# # # # # #     icacls "C:\FTP\grupos\$g" /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"      | Out-Null
# # # # # #     icacls "C:\FTP\grupos\$g" /grant "SRV-WINDOW\$g`:(OI)(CI)M"          | Out-Null
# # # # # # }

# # # # # # Write-Host "  OK" -ForegroundColor Green

# # # # # # # -----------------------------------------------------------------
# # # # # # # PASO 5: Recrear symlinks de todos los usuarios
# # # # # # # -----------------------------------------------------------------
# # # # # # Write-Host "`n[5] Recreando symlinks de usuarios..." -ForegroundColor White

# # # # # # Get-ChildItem "C:\FTP\LocalUser" -Directory |
# # # # # #   Where-Object { $_.Name -ne "Public" } | ForEach-Object {

# # # # # #     $user     = $_.Name
# # # # # #     $userRoot = $_.FullName

# # # # # #     # Detectar grupo
# # # # # #     $grupo = ""
# # # # # #     try {
# # # # # #         if (Get-LocalGroupMember -Group "reprobados"   -ErrorAction SilentlyContinue |
# # # # # #             Where-Object { $_.Name -like "*$user" }) { $grupo = "reprobados" }
# # # # # #         elseif (Get-LocalGroupMember -Group "recursadores" -ErrorAction SilentlyContinue |
# # # # # #             Where-Object { $_.Name -like "*$user" }) { $grupo = "recursadores" }
# # # # # #         elseif (Get-LocalGroupMember -Group "Reprobados"   -ErrorAction SilentlyContinue |
# # # # # #             Where-Object { $_.Name -like "*$user" }) { $grupo = "reprobados" }
# # # # # #         elseif (Get-LocalGroupMember -Group "Recursadores" -ErrorAction SilentlyContinue |
# # # # # #             Where-Object { $_.Name -like "*$user" }) { $grupo = "recursadores" }
# # # # # #     } catch {}

# # # # # #     # Borrar todos los symlinks existentes
# # # # # #     Get-ChildItem $userRoot -Force |
# # # # # #         Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
# # # # # #         ForEach-Object { cmd /c "rmdir `"$($_.FullName)`"" 2>$null | Out-Null }

# # # # # #     # Carpeta personal
# # # # # #     $personalDir = "$userRoot\$user"
# # # # # #     if (-not (Test-Path $personalDir)) {
# # # # # #         New-Item -Path $personalDir -ItemType Directory -Force | Out-Null
# # # # # #     }

# # # # # #     # Permisos userRoot
# # # # # #     icacls $userRoot /inheritance:r                                | Out-Null
# # # # # #     icacls $userRoot /grant "${adminGroup}:(OI)(CI)F"             | Out-Null
# # # # # #     icacls $userRoot /grant "SYSTEM:(OI)(CI)F"                    | Out-Null
# # # # # #     icacls $userRoot /grant "NT AUTHORITY\IUSR:(OI)(CI)RX"        | Out-Null
# # # # # #     icacls $userRoot /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX"        | Out-Null
# # # # # #     icacls $userRoot /grant "${user}:(OI)(CI)RX"                  | Out-Null
# # # # # #     icacls $personalDir /grant "${user}:(OI)(CI)M"                | Out-Null

# # # # # #     # Symlink General -> C:\FTP\LocalUser\Public\General
# # # # # #     cmd /c "mklink /D `"$userRoot\General`" `"C:\FTP\LocalUser\Public\General`"" | Out-Null

# # # # # #     # Symlink grupo -> C:\FTP\grupos\<grupo>
# # # # # #     if ($grupo -ne "") {
# # # # # #         cmd /c "mklink /D `"$userRoot\$grupo`" `"C:\FTP\grupos\$grupo`"" | Out-Null
# # # # # #         Write-Host ("  {0,-15} -> General + {1}" -f $user, $grupo) -ForegroundColor DarkGray
# # # # # #     } else {
# # # # # #         Write-Host ("  {0,-15} -> General (sin grupo)" -f $user) -ForegroundColor Yellow
# # # # # #     }
# # # # # # }
# # # # # # Write-Host "  OK" -ForegroundColor Green

# # # # # # # -----------------------------------------------------------------
# # # # # # # PASO 6: Arrancar el sitio FTP
# # # # # # # -----------------------------------------------------------------
# # # # # # Write-Host "`n[6] Arrancando sitio FTP..." -ForegroundColor White

# # # # # # $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
# # # # # # & $appcmd start site /site.name:"FTP" | Out-Null
# # # # # # Start-Sleep -Seconds 2

# # # # # # $site = Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue
# # # # # # $color = if ($site.State -eq "Started") { "Green" } else { "Red" }
# # # # # # Write-Host "  Estado del sitio: $($site.State)" -ForegroundColor $color

# # # # # # Write-Host "`n=================================================" -ForegroundColor Cyan
# # # # # # Write-Host "  LISTO - Conexion desde FileZilla:" -ForegroundColor White
# # # # # # Write-Host "  Protocolo : FTP (no SFTP)"
# # # # # # Write-Host "  Cifrado   : FTP plano (inseguro)"
# # # # # # Write-Host "  Anonimo   : usuario=anonymous  password=(vacio)"
# # # # # # Write-Host "  Autenticado: tu usuario y password normales"
# # # # # # Write-Host "=================================================" -ForegroundColor Cyan
# # # # # # Pega esto en PowerShell del servidor

# # # # # # 1. Ver por que falla al arrancar
# # # # # # $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
# # # # # # & $appcmd start site /site.name:"FTP"

# # # # # # # 2. Ver el log de eventos de IIS
# # # # # # Get-EventLog -LogName System -Source "*IIS*","*ftpsvc*","*W3SVC*" -Newest 10 |
# # # # # #     Select-Object TimeGenerated, EntryType, Message | Format-List

# # # # # # # 3. Ver el log de eventos de aplicacion
# # # # # # Get-EventLog -LogName Application -Source "*IIS*","*ftp*" -Newest 5 |
# # # # # #     Select-Object TimeGenerated, EntryType, Message | Format-List

# # # # # # # 4. Ver el ultimo log FTP
# # # # # # $logPath = "C:\inetpub\logs\LogFiles"
# # # # # # $lastLog = Get-ChildItem $logPath -Recurse -Filter "*.log" -ErrorAction SilentlyContinue |
# # # # # #     Sort-Object LastWriteTime -Descending | Select-Object -First 1
# # # # # # if ($lastLog) {
# # # # # #     Write-Host "Log: $($lastLog.FullName)"
# # # # # #     Get-Content $lastLog.FullName -Tail 20
# # # # # # }

# # # # # # # 5. Estado de los servicios
# # # # # # Get-Service W3SVC, ftpsvc | Select-Object Name, Status, StartType
# # # # # # Ver TODOS los sitios en IIS y sus bindings
# # # # # # Import-Module WebAdministration
# # # # # # Get-WebSite | Select-Object Name, State, PhysicalPath, 
# # # # # #     @{N="Bindings";E={($_.Bindings.Collection | ForEach-Object {$_.bindingInformation}) -join ", "}} |
# # # # # #     Format-List

# # # # # # # Ver todos los sitios FTP especificamente
# # # # # # Get-WebSite | Where-Object { $_.Bindings.Collection.protocol -eq "ftp" } | Format-List
# # # # # # Detener y eliminar el sitio que roba el puerto 21
# # # # # Import-Module WebAdministration

# # # # # # Detener FTPServer_Practica
# # # # # Stop-WebSite -Name "FTPServer_Practica" -ErrorAction SilentlyContinue
# # # # # Write-Host "Detenido FTPServer_Practica"

# # # # # # Eliminarlo
# # # # # Remove-WebSite -Name "FTPServer_Practica" -ErrorAction SilentlyContinue
# # # # # Write-Host "Eliminado FTPServer_Practica"

# # # # # # Arrancar tu sitio FTP
# # # # # $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
# # # # # & $appcmd start site /site.name:"FTP"
# # # # # Start-Sleep -Seconds 2

# # # # # # Verificar
# # # # # $site = Get-WebSite -Name "FTP"
# # # # # Write-Host "Estado FTP: $($site.State)" -ForegroundColor $(if ($site.State -eq "Started") {"Green"} else {"Red"})

# # # # # Verificar estructura y permisos de los homes
# # # # Import-Module WebAdministration

# # # # # Ver physicalPath actual del sitio
# # # # Write-Host "PhysicalPath del sitio FTP:"
# # # # (Get-WebSite -Name "FTP").physicalPath

# # # # # Ver contenido de LocalUser
# # # # Write-Host "`nContenido de C:\FTP\LocalUser:"
# # # # Get-ChildItem "C:\FTP\LocalUser" -Force | Select-Object Name, Attributes

# # # # # Ver symlinks dentro de bayer
# # # # Write-Host "`nContenido de C:\FTP\LocalUser\bayer:"
# # # # Get-ChildItem "C:\FTP\LocalUser\bayer" -Force | Select-Object Name, Attributes, Target

# # # # # Ver permisos de C:\FTP\LocalUser\Public
# # # # Write-Host "`nPermisos de Public:"
# # # # icacls "C:\FTP\LocalUser\Public"

# # # # # Ver permisos de C:\FTP\LocalUser\bayer
# # # # # Write-Host "`nPermisos de bayer:"
# # # # # icacls "C:\FTP\LocalUser\bayer"

# # # # Import-Module WebAdministration

# # # # # Detener sitio
# # # # Stop-WebSite -Name "FTP" -ErrorAction SilentlyContinue
# # # # Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
# # # # Stop-Service W3SVC  -Force -ErrorAction SilentlyContinue
# # # # Start-Sleep -Seconds 3

# # # # # Cambiar physicalPath directamente en el XML
# # # # $cfg = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
# # # # [xml]$xml = Get-Content $cfg -Encoding UTF8
# # # # $ftpSite = $xml.configuration."system.applicationHost".sites.site |
# # # #     Where-Object { $_.name -eq "FTP" }
# # # # $ftpSite.application.virtualDirectory.physicalPath = "C:\FTP\LocalUser"
# # # # $xml.Save($cfg)
# # # # Write-Host "physicalPath -> C:\FTP\LocalUser"

# # # # # Arrancar
# # # # Start-Service W3SVC  -ErrorAction SilentlyContinue
# # # # Start-Sleep -Seconds 2
# # # # Start-Service ftpsvc -ErrorAction SilentlyContinue
# # # # Start-Sleep -Seconds 2

# # # # $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
# # # # & $appcmd start site /site.name:"FTP" 2>$null
# # # # Start-Sleep -Seconds 1

# # # # # Verificar
# # # # $site = Get-WebSite -Name "FTP"
# # # # Write-Host "Estado: $($site.State)" -ForegroundColor $(if ($site.State -eq "Started") {"Green"} else {"Red"})
# # # # Write-Host "Path  : $($site.physicalPath)"

# # # # Ver quien escucha en puerto 21 y 22
# # # netstat -ano | findstr ":21 "
# # # netstat -ano | findstr ":22 "

# # # # Confirmar estado final
# # # (Get-WebSite -Name "FTP") | Select-Object Name, State, physicalPath

# # # Fix directo para anonymous 530
# # $localUser = "C:\FTP\LocalUser"
# # $public    = "C:\FTP\LocalUser\Public"
# # $general   = "C:\FTP\LocalUser\Public\General"

# # # Crear si no existen
# # @($public, $general) | ForEach-Object {
# #     if (-not (Test-Path $_)) {
# #         New-Item -Path $_ -ItemType Directory -Force | Out-Null
# #         Write-Host "Creado: $_"
# #     }
# # }

# # # Permisos para que IUSR pueda entrar al chroot
# # icacls $localUser /grant "NT AUTHORITY\IUSR:(OI)(CI)(RX)" /T | Out-Null
# # icacls $localUser /grant "BUILTIN\IIS_IUSRS:(OI)(CI)(RX)" /T | Out-Null
# # icacls $public    /grant "NT AUTHORITY\IUSR:(OI)(CI)(RX)"    | Out-Null
# # icacls $public    /grant "BUILTIN\IIS_IUSRS:(OI)(CI)(RX)"    | Out-Null
# # icacls $general   /grant "NT AUTHORITY\IUSR:(OI)(CI)(RX)"    | Out-Null
# # icacls $general   /grant "BUILTIN\IIS_IUSRS:(OI)(CI)(RX)"    | Out-Null

# # # Reiniciar solo ftpsvc (no W3SVC para no perder estado)
# # Restart-Service ftpsvc -Force
# # Start-Sleep -Seconds 2

# # Write-Host "Permisos:"
# # icacls $public


# # Diagnostico profundo del 530
# Import-Module WebAdministration

# # 1. Modo de aislamiento actual
# Write-Host "=== AISLAMIENTO ===" -ForegroundColor Cyan
# Get-WebConfigurationProperty `
#     -Filter "system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
#     -Name "mode"

# # 2. Estructura real de LocalUser
# Write-Host "`n=== ESTRUCTURA C:\FTP\LocalUser ===" -ForegroundColor Cyan
# Get-ChildItem "C:\FTP\LocalUser" -Force | Select-Object Name, Attributes

# # 3. Estructura dentro de Public
# Write-Host "`n=== ESTRUCTURA C:\FTP\LocalUser\Public ===" -ForegroundColor Cyan
# if (Test-Path "C:\FTP\LocalUser\Public") {
#     Get-ChildItem "C:\FTP\LocalUser\Public" -Force | Select-Object Name, Attributes
# } else {
#     Write-Host "NO EXISTE" -ForegroundColor Red
# }

# # 4. Permisos exactos de LocalUser (sin /T)
# Write-Host "`n=== PERMISOS LocalUser ===" -ForegroundColor Cyan
# icacls "C:\FTP\LocalUser"

# # 5. Permisos de bayer
# Write-Host "`n=== PERMISOS bayer ===" -ForegroundColor Cyan
# icacls "C:\FTP\LocalUser\bayer"

# # 6. Autenticacion anonima en IIS
# Write-Host "`n=== AUTH ANONIMA ===" -ForegroundColor Cyan
# Get-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication

Import-Module WebAdministration

# CREAR Public\General correctamente
$public  = "C:\FTP\LocalUser\Public"
$general = "C:\FTP\LocalUser\Public\General"

New-Item -Path $public  -ItemType Directory -Force | Out-Null
New-Item -Path $general -ItemType Directory -Force | Out-Null

# Mover contenido de la carpeta "general" suelta si existe
if (Test-Path "C:\FTP\LocalUser\general") {
    Get-ChildItem "C:\FTP\LocalUser\general" -Force |
        Move-Item -Destination $general -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\FTP\LocalUser\general" -Force -Recurse -ErrorAction SilentlyContinue
}

# Permisos Public y General
icacls $public  /inheritance:r | Out-Null
icacls $public  /grant "BUILTIN\Administrators:(OI)(CI)(F)" | Out-Null
icacls $public  /grant "NT AUTHORITY\SYSTEM:(OI)(CI)(F)"   | Out-Null
icacls $public  /grant "NT AUTHORITY\IUSR:(OI)(CI)(RX)"    | Out-Null
icacls $public  /grant "BUILTIN\IIS_IUSRS:(OI)(CI)(RX)"    | Out-Null

icacls $general /inheritance:r | Out-Null
icacls $general /grant "BUILTIN\Administrators:(OI)(CI)(F)" | Out-Null
icacls $general /grant "NT AUTHORITY\SYSTEM:(OI)(CI)(F)"   | Out-Null
icacls $general /grant "NT AUTHORITY\IUSR:(OI)(CI)(RX)"    | Out-Null
icacls $general /grant "BUILTIN\IIS_IUSRS:(OI)(CI)(RX)"    | Out-Null
icacls $general /grant "BUILTIN\Users:(OI)(CI)(M)"         | Out-Null

# Recrear symlinks General en cada usuario
Get-ChildItem "C:\FTP\LocalUser" -Directory |
  Where-Object { $_.Name -notin @("Public") } | ForEach-Object {
    $link = "$($_.FullName)\General"
    if (Test-Path $link) {
        cmd /c "rmdir `"$link`"" 2>$null | Out-Null
    }
    cmd /c "mklink /D `"$link`" `"$general`"" | Out-Null
    Write-Host "  Symlink General -> $($_.Name)" -ForegroundColor DarkGray
}

# Reiniciar
Restart-Service ftpsvc -Force
Start-Sleep 2

Write-Host "`nEstructura Public:" -ForegroundColor Cyan
Get-ChildItem "C:\FTP\LocalUser\Public" -Force | Select-Object Name, Attributes
Write-Host "`nSitio: $((Get-WebSite -Name 'FTP').State)" -ForegroundColor Green