# =============================================================================
# ftp_functions.ps1
# Ubicacion: windows/modules/ftp_functions.ps1
# =============================================================================

# -----------------------------------------------------------------------------
# VALIDACION Y CAPTURA
# -----------------------------------------------------------------------------

function Invoke-ValidarContra {
    param ([string]$contra)
    if ($contra.Length -lt 8)            { Write-Host "  [!] Minimo 8 caracteres."          -ForegroundColor Yellow; return $false }
    if ($contra.Length -gt 15)           { Write-Host "  [!] Maximo 15 caracteres."          -ForegroundColor Yellow; return $false }
    if ($contra -notmatch "[A-Z]")       { Write-Host "  [!] Necesita una mayuscula."        -ForegroundColor Yellow; return $false }
    if ($contra -notmatch "[a-z]")       { Write-Host "  [!] Necesita una minuscula."        -ForegroundColor Yellow; return $false }
    if ($contra -notmatch "\d")          { Write-Host "  [!] Necesita un numero."            -ForegroundColor Yellow; return $false }
    if ($contra -notmatch "[^a-zA-Z0-9]"){ Write-Host "  [!] Necesita un caracter especial."-ForegroundColor Yellow; return $false }
    return $true
}

function Invoke-CapturarContra {
    do {
        $c = Read-Host "  Contrasena (8-15, May, min, num, especial)"
        $ok = Invoke-ValidarContra -contra $c
        if (-not $ok) { Write-Host "  Intentelo de nuevo." -ForegroundColor Red }
    } while (-not $ok)
    return $c
}

function Invoke-UsuarioExiste {
    param ([string]$nombre)
    $adsi = [ADSI]"WinNT://$env:ComputerName"
    $u = $adsi.Children | Where-Object { $_.SchemaClassName -eq 'User' -and $_.Name -eq $nombre }
    return ($null -ne $u)
}

function Invoke-CapturarUsuarioFTPValido {
    param ([string]$mensaje)
    do {
        $c = Read-Host "  $mensaje"
        if (-not $c)                          { Write-Host "  [!] No puede estar vacio."           -ForegroundColor Yellow }
        elseif ($c -notmatch '^[a-zA-Z0-9]+$'){ Write-Host "  [!] Solo letras y numeros."         -ForegroundColor Yellow }
        elseif ($c -match    '^[0-9]')        { Write-Host "  [!] No puede empezar con numero."   -ForegroundColor Yellow }
        elseif ($c.Length -gt 15)             { Write-Host "  [!] Maximo 15 caracteres."           -ForegroundColor Yellow }
        elseif (Invoke-UsuarioExiste $c)      { Write-Host "  [!] El usuario '$c' ya existe."     -ForegroundColor Yellow }
        else { return $c }
    } while ($true)
}

function Invoke-CapturarGrupoFTP {
    do {
        Write-Host "  Seleccione grupo:"
        Write-Host "    1) reprobados"
        Write-Host "    2) recursadores"
        $g = Read-Host "  Opcion"
        if ($g -eq "1") { return "reprobados"   }
        if ($g -eq "2") { return "recursadores" }
        Write-Host "  [!] Ingrese 1 o 2." -ForegroundColor Yellow
    } while ($true)
}

function Get-GrupoActualFTP {
    param ([string]$FTPUserName)
    $u = [ADSI]"WinNT://$env:ComputerName/$FTPUserName,user"
    $grupos = $u.Groups() | ForEach-Object {
        $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
    }
    if ($grupos -contains "reprobados")   { return "reprobados"   }
    if ($grupos -contains "recursadores") { return "recursadores" }
    return ""
}

# -----------------------------------------------------------------------------
# HELPER NTFS: asigna permisos heredables (ContainerInherit + ObjectInherit)
# y los propaga a todos los hijos existentes
# -----------------------------------------------------------------------------
function Set-PermisoRecursivo {
    param (
        [string]$Ruta,
        [string]$Identidad,
        [string]$Derechos,
        [bool]$RomperHerencia = $false
    )
    $acl   = Get-Acl $Ruta
    if ($RomperHerencia) { $acl.SetAccessRuleProtection($true, $false) }

    $flags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $prop  = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $rule  = New-Object System.Security.AccessControl.FileSystemAccessRule(
                 $Identidad, $Derechos, $flags, $prop, $allow)
    $acl.SetAccessRule($rule)
    Set-Acl -Path $Ruta -AclObject $acl

    Get-ChildItem -Path $Ruta -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $ca = Get-Acl $_.FullName
            $ca.SetAccessRule($rule)
            Set-Acl -Path $_.FullName -AclObject $ca
        } catch {}
    }
}

# -----------------------------------------------------------------------------
# INICIALIZACION DEL SERVIDOR FTP  (idempotente)
# Estrategia SSL: editar applicationHost.config con los servicios DETENIDOS
# para evitar el error "file in use" y el "534 Policy requires SSL"
# -----------------------------------------------------------------------------
function Initialize-ServidorFTP {

    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "   CONFIGURACION INICIAL DEL SERVIDOR FTP (IIS)" -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # 1. Instalar IIS + FTP
    # ------------------------------------------------------------------
    Write-Host "[1/7] Instalando IIS y FTP..." -ForegroundColor White
    Install-WindowsFeature Web-Server, Web-FTP-Server -IncludeManagementTools | Out-Null
    Import-Module WebAdministration -ErrorAction Stop
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 2. Estructura de directorios
    # Con IsolateAllDirectories IIS mapea cada usuario a:
    #   C:\FTP\LocalUser\<usuario>   <- chroot del usuario
    # El anonimo se mapea a:
    #   C:\FTP\LocalUser\Public      <- chroot del anonimo
    # ------------------------------------------------------------------
    Write-Host "[2/7] Creando directorios..." -ForegroundColor White
    @(
        "C:\FTP",
        "C:\FTP\grupos\reprobados",
        "C:\FTP\grupos\recursadores",
        "C:\FTP\LocalUser",
        "C:\FTP\LocalUser\Public",
        "C:\FTP\LocalUser\Public\general"
    ) | ForEach-Object {
        if (-not (Test-Path $_)) { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
    }
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 3. Grupos locales de Windows
    # ------------------------------------------------------------------
    Write-Host "[3/7] Verificando grupos del sistema..." -ForegroundColor White
    $adsi = [ADSI]"WinNT://$env:ComputerName"
    foreach ($g in @("reprobados","recursadores")) {
        $existe = $adsi.Children | Where-Object { $_.SchemaClassName -eq 'Group' -and $_.Name -eq $g }
        if (-not $existe) { $ng = $adsi.Create("Group",$g); $ng.SetInfo() }
    }
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 4. Permisos NTFS recursivos
    # ------------------------------------------------------------------
    Write-Host "[4/7] Configurando permisos NTFS..." -ForegroundColor White

    # Carpetas de grupo: solo el grupo puede modificar
    foreach ($g in @("reprobados","recursadores")) {
        $ruta = "C:\FTP\grupos\$g"
        $acl  = Get-Acl $ruta
        $acl.SetAccessRuleProtection($true, $false)
        $flags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
        $prop  = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators","FullControl",$flags,$prop,$allow)))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $g,"Modify",$flags,$prop,$allow)))
        Set-Acl $ruta $acl
        Get-ChildItem $ruta -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { Set-Acl $_.FullName $acl } catch {} }
    }

    # Carpeta general: IUSR solo lectura, Users (autenticados) modificar
    $gPath = "C:\FTP\LocalUser\Public\general"
    $aclG  = Get-Acl $gPath
    $aclG.SetAccessRuleProtection($true, $false)
    $flags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $prop  = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $aclG.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators","FullControl",$flags,$prop,$allow)))
    $aclG.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR","ReadAndExecute",$flags,$prop,$allow)))
    $aclG.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Users","Modify",$flags,$prop,$allow)))
    Set-Acl $gPath $aclG
    Get-ChildItem $gPath -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { Set-Acl $_.FullName $aclG } catch {} }

    # Raiz Public (chroot anonimo): IUSR puede entrar pero no listar raiz
    $pPath = "C:\FTP\LocalUser\Public"
    $aclP  = Get-Acl $pPath
    $aclP.SetAccessRuleProtection($true, $false)
    $noInh = [System.Security.AccessControl.InheritanceFlags]::None
    $aclP.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators","FullControl",
        [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit",
        $prop,$allow)))
    $aclP.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR","ReadAndExecute",$noInh,$prop,$allow)))
    Set-Acl $pPath $aclP
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 5. Firewall
    # ------------------------------------------------------------------
    Write-Host "[5/7] Configurando Firewall..." -ForegroundColor White
    if (-not (Get-NetFirewallRule -DisplayName "FTP_Practica" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP_Practica" -Direction Inbound `
            -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
    }
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 6. Sitio FTP en IIS
    # ------------------------------------------------------------------
    Write-Host "[6/7] Configurando sitio FTP en IIS..." -ForegroundColor White

    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP\LocalUser" -Force | Out-Null
    } else {
        Set-ItemProperty "IIS:\Sites\FTP" -Name physicalPath -Value "C:\FTP\LocalUser"
    }

    # Aislamiento por usuario
    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateAllDirectories"

    # Autenticacion anonima + basica
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.userName -Value "IUSR"
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.password -Value ""
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.basicAuthentication.enabled -Value $true

    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 7. SSL y autorizacion — editar applicationHost.config directamente
    #    Detenemos los servicios para que el archivo no este bloqueado
    # ------------------------------------------------------------------
    Write-Host "[7/7] Aplicando SSL y reglas de autorizacion..." -ForegroundColor White

    Write-Host "  Deteniendo servicios IIS..." -ForegroundColor DarkGray
    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Stop-Service W3SVC  -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $cfg = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
    [xml]$xml = Get-Content $cfg -Encoding UTF8

    $sitesNode = $xml.configuration."system.applicationHost".sites

    # --- SSL en siteDefaults (herencia global) ---
    if ($sitesNode.siteDefaults.ftpServer.security.ssl) {
        $sitesNode.siteDefaults.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
        $sitesNode.siteDefaults.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
    }

    # --- SSL en el sitio FTP especifico ---
    $ftpSite = $sitesNode.site | Where-Object { $_.name -eq "FTP" }
    if ($ftpSite -and $ftpSite.ftpServer.security.ssl) {
        $ftpSite.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
        $ftpSite.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
    }

    # --- Reglas de autorizacion en <location path="FTP"> ---
    # Buscar o crear el nodo location
    $locNode = $xml.configuration.location | Where-Object { $_.path -eq "FTP" }
    if (-not $locNode) {
        $locNode = $xml.CreateElement("location")
        $locNode.SetAttribute("path", "FTP")
        $xml.configuration.AppendChild($locNode) | Out-Null
    }

    # Navegar/crear la jerarquia system.ftpServer/security/authorization
    if (-not $locNode."system.ftpServer") {
        $n = $xml.CreateElement("system.ftpServer"); $locNode.AppendChild($n) | Out-Null
    }
    if (-not $locNode."system.ftpServer".security) {
        $n = $xml.CreateElement("security")
        $locNode."system.ftpServer".AppendChild($n) | Out-Null
    }
    $authNode = $locNode."system.ftpServer".security.authorization
    if ($authNode) {
        $authNode.RemoveAll()   # borrar reglas duplicadas
    } else {
        $authNode = $xml.CreateElement("authorization")
        $locNode."system.ftpServer".security.AppendChild($authNode) | Out-Null
    }

    # Funcion local para crear una regla <add>
    function _Regla($accessType, $users, $roles, $perms) {
        $r = $xml.CreateElement("add")
        $r.SetAttribute("accessType",  $accessType)
        $r.SetAttribute("users",       $users)
        $r.SetAttribute("roles",       $roles)
        $r.SetAttribute("permissions", $perms)
        return $r
    }

    # Anonimo (users="?") solo lectura
    $authNode.AppendChild((_Regla "Allow" "?" "" "Read")) | Out-Null
    # Grupos autenticados lectura+escritura
    $authNode.AppendChild((_Regla "Allow" "" "reprobados,recursadores" "Read, Write")) | Out-Null
    # Denegar al resto
    $authNode.AppendChild((_Regla "Deny"  "*" "" "Read, Write")) | Out-Null

    # Guardar el XML
    $xml.Save($cfg)
    Write-Host "  Configuracion guardada." -ForegroundColor DarkGray

    Write-Host "  Iniciando servicios IIS..." -ForegroundColor DarkGray
    Start-Service W3SVC  -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    Write-Host "  OK" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Servidor FTP listo." -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "  ACCESOS:" -ForegroundColor White
    Write-Host "  - anonymous / sin password : solo lectura en /general" -ForegroundColor DarkGray
    Write-Host "  - usuario autenticado      : /personal + /general + /grupo" -ForegroundColor DarkGray
    Write-Host "  - Permisos recursivos en todos los subdirectorios" -ForegroundColor DarkGray
    Write-Host "=================================================" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# CREAR USUARIO
# -----------------------------------------------------------------------------
function New-UsuarioFTP {
    param (
        [string]$FTPUserName,
        [string]$FTPPassword,
        [string]$FTPUserGroupName
    )

    # Crear usuario Windows
    $adsi    = [ADSI]"WinNT://$env:ComputerName"
    $newUser = $adsi.Create("User", $FTPUserName)
    $newUser.SetPassword($FTPPassword)
    $newUser.SetInfo()

    # Agregar al grupo
    $grp = [ADSI]"WinNT://$env:ComputerName/$FTPUserGroupName,group"
    $grp.Invoke("Add", "WinNT://$env:ComputerName/$FTPUserName,user")

    # Estructura de carpetas:
    #   C:\FTP\LocalUser\<user>           <- raiz chroot (root la posee)
    #   C:\FTP\LocalUser\<user>\<user>    <- carpeta personal (escritura)
    #   C:\FTP\LocalUser\<user>\general   <- symlink a Public\general
    #   C:\FTP\LocalUser\<user>\<grupo>   <- symlink a grupos\<grupo>
    $userRoot = "C:\FTP\LocalUser\$FTPUserName"
    $userHome = "$userRoot\$FTPUserName"
    New-Item -Path $userRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $userHome -ItemType Directory -Force | Out-Null

    # Raiz del chroot: Administrators full, usuario solo traverse (sin heredar)
    $flags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $prop  = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow

    $aclRoot = Get-Acl $userRoot
    $aclRoot.SetAccessRuleProtection($true, $false)
    $aclRoot.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators","FullControl",$flags,$prop,$allow)))
    $aclRoot.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $FTPUserName,"ReadAndExecute",
        [System.Security.AccessControl.InheritanceFlags]::None,$prop,$allow)))
    Set-Acl $userRoot $aclRoot

    # Carpeta personal: Modify recursivo (usuario puede crear subdirectorios sin limite)
    $aclHome = Get-Acl $userHome
    $aclHome.SetAccessRuleProtection($true, $false)
    $aclHome.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators","FullControl",$flags,$prop,$allow)))
    $aclHome.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $FTPUserName,"Modify",$flags,$prop,$allow)))
    Set-Acl $userHome $aclHome

    # Symlinks
    cmd /c "mklink /D `"$userRoot\general`" `"C:\FTP\LocalUser\Public\general`"" | Out-Null
    cmd /c "mklink /D `"$userRoot\$FTPUserGroupName`" `"C:\FTP\grupos\$FTPUserGroupName`"" | Out-Null

    Write-Host "  [OK] Usuario '$FTPUserName' creado en grupo '$FTPUserGroupName'." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# CAMBIAR GRUPO
# -----------------------------------------------------------------------------
function Set-GrupoFTP {
    param (
        [string]$FTPUserName,
        [string]$NuevoGrupo
    )

    $viejoGrupo = Get-GrupoActualFTP -FTPUserName $FTPUserName

    if ($viejoGrupo -eq $NuevoGrupo) {
        Write-Host "  [!] El usuario ya pertenece al grupo '$NuevoGrupo'." -ForegroundColor Yellow
        return
    }

    if ($viejoGrupo -ne "") {
        $og = [ADSI]"WinNT://$env:ComputerName/$viejoGrupo,group"
        $og.Invoke("Remove", "WinNT://$env:ComputerName/$FTPUserName,user")
    }

    $ng = [ADSI]"WinNT://$env:ComputerName/$NuevoGrupo,group"
    $ng.Invoke("Add", "WinNT://$env:ComputerName/$FTPUserName,user")

    $userRoot = "C:\FTP\LocalUser\$FTPUserName"
    if ($viejoGrupo -ne "") {
        cmd /c "rmdir /S /Q `"$userRoot\$viejoGrupo`"" 2>$null
    }
    cmd /c "mklink /D `"$userRoot\$NuevoGrupo`" `"C:\FTP\grupos\$NuevoGrupo`"" | Out-Null

    Stop-Service  ftpsvc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Service ftpsvc -ErrorAction SilentlyContinue

    Write-Host "  [OK] '$FTPUserName' movido de '$viejoGrupo' a '$NuevoGrupo'." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# ELIMINAR USUARIO
# -----------------------------------------------------------------------------
function Remove-UsuarioFTP {
    param ([string]$FTPUserName)

    foreach ($g in @("reprobados","recursadores")) {
        try {
            $grp = [ADSI]"WinNT://$env:ComputerName/$g,group"
            $grp.Invoke("Remove", "WinNT://$env:ComputerName/$FTPUserName,user")
        } catch {}
    }

    $adsi = [ADSI]"WinNT://$env:ComputerName"
    $adsi.Delete("User", $FTPUserName)

    $userRoot = "C:\FTP\LocalUser\$FTPUserName"
    if (Test-Path $userRoot) {
        # Eliminar symlinks primero (rmdir), luego la carpeta
        Get-ChildItem $userRoot -Force |
            Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } |
            ForEach-Object { cmd /c "rmdir /Q `"$($_.FullName)`"" 2>$null }
        Remove-Item $userRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "  [OK] Usuario '$FTPUserName' eliminado." -ForegroundColor Green
}