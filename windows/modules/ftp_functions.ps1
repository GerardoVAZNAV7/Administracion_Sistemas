# =============================================================================
# ftp_functions.ps1 — Funciones del servidor FTP (IIS) para Windows
# Ubicacion: windows/modules/ftp_functions.ps1
# =============================================================================

# -----------------------------------------------------------------------------
# VALIDACION Y CAPTURA
# -----------------------------------------------------------------------------

function Invoke-ValidarContra {
    param ([string]$contra)

    if ($contra.Length -lt 8) {
        Write-Host "  [!] La contrasena debe tener al menos 8 caracteres." -ForegroundColor Yellow
        return $false
    }
    if ($contra.Length -gt 15) {
        Write-Host "  [!] La contrasena no puede tener mas de 15 caracteres." -ForegroundColor Yellow
        return $false
    }
    if ($contra -notmatch "[A-Z]") {
        Write-Host "  [!] La contrasena debe contener al menos una letra mayuscula." -ForegroundColor Yellow
        return $false
    }
    if ($contra -notmatch "[a-z]") {
        Write-Host "  [!] La contrasena debe contener al menos una letra minuscula." -ForegroundColor Yellow
        return $false
    }
    if ($contra -notmatch "\d") {
        Write-Host "  [!] La contrasena debe contener al menos un numero." -ForegroundColor Yellow
        return $false
    }
    if ($contra -notmatch "[^a-zA-Z0-9]") {
        Write-Host "  [!] La contrasena debe contener al menos un caracter especial." -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Invoke-CapturarContra {
    $esValida = $false
    do {
        $contra = Read-Host "  Contrasena (8-15 chars, May, min, num, especial)"
        $esValida = Invoke-ValidarContra -contra $contra
        if (-not $esValida) {
            Write-Host "  Contrasena no valida. Intentelo de nuevo." -ForegroundColor Red
        }
    } while (-not $esValida)
    return $contra
}

function Invoke-CapturarUsuarioFTPValido {
    param ([string]$mensaje)

    $caracteresPermitidos = '^[a-zA-Z0-9]+$'
    $longitudMaxima = 15
    $cadenaValida = $false

    do {
        $cadena = Read-Host $mensaje

        if (-not $cadena) {
            Write-Host "  [!] El nombre no puede estar vacio." -ForegroundColor Yellow
        }
        elseif ($cadena -notmatch $caracteresPermitidos) {
            Write-Host "  [!] Solo se permiten letras y numeros." -ForegroundColor Yellow
        }
        elseif ($cadena -match '^[0-9]') {
            Write-Host "  [!] El nombre no puede comenzar con un numero." -ForegroundColor Yellow
        }
        elseif ($cadena.Length -gt $longitudMaxima) {
            Write-Host "  [!] El nombre no puede exceder $longitudMaxima caracteres." -ForegroundColor Yellow
        }
        elseif (Invoke-UsuarioExiste -nombreUsuario $cadena) {
            Write-Host "  [!] El usuario '$cadena' ya existe. Elija otro nombre." -ForegroundColor Yellow
        }
        else {
            $cadenaValida = $true
        }
    } while (-not $cadenaValida)

    return $cadena
}

function Invoke-CapturarGrupoFTP {
    do {
        Write-Host ""
        Write-Host "  Seleccione el grupo:" -ForegroundColor Cyan
        Write-Host "    1) reprobados"
        Write-Host "    2) recursadores"
        $grupo = Read-Host "  Opcion"

        switch ($grupo) {
            "1" { return "reprobados"  }
            "2" { return "recursadores" }
            default { Write-Host "  [!] Opcion no valida. Ingrese 1 o 2." -ForegroundColor Yellow }
        }
    } while ($true)
}

# -----------------------------------------------------------------------------
# CONSULTAS
# -----------------------------------------------------------------------------

function Invoke-UsuarioExiste {
    param ([string]$nombreUsuario)
    $adsi = [ADSI]"WinNT://$env:ComputerName"
    $usuario = $adsi.Children | Where-Object {
        $_.SchemaClassName -eq 'User' -and $_.Name -eq $nombreUsuario
    }
    return ($null -ne $usuario)
}

function Get-GrupoActualFTP {
    param ([string]$FTPUserName)
    $userADSI = [ADSI]"WinNT://$env:ComputerName/$FTPUserName,user"
    $grupos = $userADSI.Groups() | ForEach-Object {
        $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
    }
    if ($grupos -contains "reprobados")   { return "reprobados" }
    if ($grupos -contains "recursadores") { return "recursadores" }
    return ""
}

# -----------------------------------------------------------------------------
# HELPER: Aplicar ACL heredable a un directorio (recursiva via InheritanceFlags)
# Todos los permisos usan ContainerInherit+ObjectInherit para cubrir
# subdirectorios y archivos existentes y futuros.
# -----------------------------------------------------------------------------
function Set-AclHeredable {
    param (
        [string]$Ruta,
        [string]$Identidad,
        [string]$Derechos,          # p.ej. "ReadAndExecute" o "Modify"
        [bool]$ProtegerHerencia = $false   # $true = romper herencia del padre
    )

    $acl = Get-Acl $Ruta

    if ($ProtegerHerencia) {
        # Rompe herencia y elimina entradas heredadas
        $acl.SetAccessRuleProtection($true, $false)
    }

    $flags      = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $type       = [System.Security.AccessControl.AccessControlType]::Allow
    $rights     = [System.Security.AccessControl.FileSystemRights]$Derechos

    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identidad, $rights, $flags, $propagation, $type
    )

    $acl.SetAccessRule($rule)
    Set-Acl -Path $Ruta -AclObject $acl

    # Propagar permisos a todos los hijos existentes
    Get-ChildItem -Path $Ruta -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $childAcl = Get-Acl $_.FullName
            $childAcl.SetAccessRule($rule)
            Set-Acl -Path $_.FullName -AclObject $childAcl
        } catch { <# ignorar archivos bloqueados #> }
    }
}

# -----------------------------------------------------------------------------
# CONFIGURACION INICIAL DEL SERVIDOR FTP  (idempotente)
# -----------------------------------------------------------------------------

function Initialize-ServidorFTP {
    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "  CONFIGURACION INICIAL DEL SERVIDOR FTP (IIS)"  -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # 1. Instalar IIS + FTP
    # ------------------------------------------------------------------
    Write-Host "`n[1/8] Instalando IIS y Servicio FTP..." -ForegroundColor White
    Install-WindowsFeature Web-Server, Web-FTP-Server -IncludeManagementTools | Out-Null
    Import-Module WebAdministration -ErrorAction Stop
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 2. Estructura de directorios
    # El aislamiento IIS requiere:
    #   C:\FTP\LocalUser\Public        <- raiz del usuario anonimo (IUSR)
    #   C:\FTP\LocalUser\Public\general <- unico directorio visible para anonimo
    #   C:\FTP\LocalUser\<usuario>     <- raiz del usuario autenticado
    #   C:\FTP\LocalUser\<usuario>\<usuario>  <- carpeta personal de escritura
    # ------------------------------------------------------------------
    Write-Host "[2/8] Creando estructura de directorios..." -ForegroundColor White
    $rutas = @(
        "C:\FTP",
        "C:\FTP\grupos",
        "C:\FTP\grupos\recursadores",
        "C:\FTP\grupos\reprobados",
        "C:\FTP\LocalUser",
        "C:\FTP\LocalUser\Public",
        "C:\FTP\LocalUser\Public\general"
    )
    foreach ($ruta in $rutas) {
        if (-not (Test-Path $ruta)) {
            New-Item -Path $ruta -ItemType Directory -Force | Out-Null
        }
    }
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 3. Permisos NTFS — carpetas de grupo (heredables, recursivos)
    #    Solo los miembros del grupo pueden modificar su carpeta.
    #    Administrators siempre tiene FullControl.
    # ------------------------------------------------------------------
    Write-Host "[3/8] Configurando permisos NTFS en carpetas de grupo..." -ForegroundColor White
    foreach ($g in @("reprobados", "recursadores")) {
        $rutaGrupo = "C:\FTP\grupos\$g"

        $acl = Get-Acl $rutaGrupo
        $acl.SetAccessRuleProtection($true, $false)   # romper herencia

        $flags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
        $prop  = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow

        # Administrators: FullControl
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators",
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $flags, $prop, $allow
        )))

        # Grupo: Modify (leer, escribir, borrar — pero NO cambiar permisos)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $g,
            [System.Security.AccessControl.FileSystemRights]::Modify,
            $flags, $prop, $allow
        )))

        Set-Acl $rutaGrupo $acl

        # Propagar a hijos existentes
        Get-ChildItem -Path $rutaGrupo -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Set-Acl -Path $_.FullName -AclObject $acl } catch {}
        }
    }
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 4. Permisos NTFS — carpeta "general"
    #    IUSR  (anonimo)  : solo lectura + listado (ReadAndExecute)
    #    Users (autenticados): Modify
    # ------------------------------------------------------------------
    Write-Host "[4/8] Configurando permisos de carpeta general..." -ForegroundColor White
    $generalPath = "C:\FTP\LocalUser\Public\general"
    $aclGen = Get-Acl $generalPath
    $aclGen.SetAccessRuleProtection($true, $false)

    $flags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $prop  = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow

    $aclGen.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators",
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $flags, $prop, $allow
    )))
    # IUSR = usuario que IIS usa para el acceso anonimo -> solo lectura
    $aclGen.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR",
        [System.Security.AccessControl.FileSystemRights]"ReadAndExecute, ListDirectory",
        $flags, $prop, $allow
    )))
    # Usuarios autenticados del sistema pueden modificar
    $aclGen.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Users",
        [System.Security.AccessControl.FileSystemRights]::Modify,
        $flags, $prop, $allow
    )))
    Set-Acl $generalPath $aclGen

    Get-ChildItem -Path $generalPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Set-Acl -Path $_.FullName -AclObject $aclGen } catch {}
    }
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 5. Permisos NTFS — raiz del aislamiento (C:\FTP\LocalUser\Public)
    #    IUSR debe poder "entrar" a la raiz para llegar a general,
    #    pero NO debe ver ni acceder a otras subcarpetas.
    #    Usamos solo "ThisFolderOnly" para IUSR en la raiz.
    # ------------------------------------------------------------------
    Write-Host "[5/8] Configurando raiz de aislamiento anonimo..." -ForegroundColor White
    $publicRoot = "C:\FTP\LocalUser\Public"
    $aclPub = Get-Acl $publicRoot
    $aclPub.SetAccessRuleProtection($true, $false)

    $noInherit = [System.Security.AccessControl.InheritanceFlags]::None
    $noProp    = [System.Security.AccessControl.PropagationFlags]::None
    $allow     = [System.Security.AccessControl.AccessControlType]::Allow

    $aclPub.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators",
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit",
        $noProp, $allow
    )))
    # IUSR: solo puede listar esta carpeta (no hereda a subdirectorios distintos de general)
    $aclPub.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR",
        [System.Security.AccessControl.FileSystemRights]"ReadAndExecute, ListDirectory",
        $noInherit, $noProp, $allow
    )))
    Set-Acl $publicRoot $aclPub
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 6. Firewall
    # ------------------------------------------------------------------
    Write-Host "[6/8] Configurando Firewall (puerto 21)..." -ForegroundColor White
    if (-not (Get-NetFirewallRule -DisplayName "FTP_Practica" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP_Practica" -Direction Inbound `
            -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
    }
    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 7. Sitio FTP en IIS con aislamiento estricto por usuario
    # ------------------------------------------------------------------
    Write-Host "[7/8] Configurando Sitio FTP en IIS..." -ForegroundColor White

    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP\LocalUser" -Force | Out-Null
    } else {
        # Asegurar que la ruta fisica sea la correcta para el aislamiento
        Set-ItemProperty "IIS:\Sites\FTP" -Name physicalPath -Value "C:\FTP\LocalUser"
    }

    # Modo de aislamiento: cada usuario autenticado queda encerrado
    # en C:\FTP\LocalUser\<Usuario> y no puede salir.
    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateAllDirectories"

    # Autenticacion: anonima (IUSR) + basica
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.userName -Value "IUSR"
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.password -Value ""
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.basicAuthentication.enabled -Value $true

    # SSL: deshabilitar completamente en el sitio Y en siteDefaults globales
    # El error "534 Policy requires SSL" viene de siteDefaults cuando el sitio
    # no tiene valor explicito — hay que sobreescribir AMBOS lugares.
    $appcmd  = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
    $cfgPath = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"

    # Paso 1: appcmd sobre el sitio especifico
    & $appcmd set site "FTP" /ftpServer.security.ssl.controlChannelPolicy:SslAllow | Out-Null
    & $appcmd set site "FTP" /ftpServer.security.ssl.dataChannelPolicy:SslAllow    | Out-Null

    # Paso 2: appcmd sobre siteDefaults (configuracion global que hereda el sitio)
    & $appcmd set config /section:system.applicationHost/sites `
        /siteDefaults.ftpServer.security.ssl.controlChannelPolicy:SslAllow | Out-Null
    & $appcmd set config /section:system.applicationHost/sites `
        /siteDefaults.ftpServer.security.ssl.dataChannelPolicy:SslAllow    | Out-Null

    # Paso 3: Set-ItemProperty como respaldo adicional
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name "ftpServer.security.ssl.dataChannelPolicy"    -Value 0

    # Paso 4: edicion directa del XML — reemplaza CUALQUIER variante de SslRequire
    # en todo el archivo, tanto en <site> como en <siteDefaults>
    [xml]$xml = Get-Content $cfgPath
    $ns = @{}

    # Parchear siteDefaults
    $sitesNode = $xml.configuration."system.applicationHost".sites
    if ($sitesNode.siteDefaults.ftpServer.security.ssl) {
        $sitesNode.siteDefaults.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
        $sitesNode.siteDefaults.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
    }

    # Parchear el sitio FTP especifico
    $ftpSite = $sitesNode.site | Where-Object { $_.name -eq "FTP" }
    if ($ftpSite -and $ftpSite.ftpServer.security.ssl) {
        $ftpSite.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
        $ftpSite.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
    }
    $xml.Save($cfgPath)

    # Paso 5: reemplazo de texto como ultimo recurso (cubre cualquier caso restante)
    $raw = Get-Content $cfgPath -Raw
    $raw = $raw -replace 'controlChannelPolicy="SslRequire[^"]*"', 'controlChannelPolicy="SslAllow"'
    $raw = $raw -replace 'dataChannelPolicy="SslRequire[^"]*"',    'dataChannelPolicy="SslAllow"'
    Set-Content $cfgPath $raw -Encoding UTF8

    Write-Host "  SSL configurado como SslAllow (sin cifrado requerido)." -ForegroundColor Green

    Write-Host "  OK" -ForegroundColor Green

    # ------------------------------------------------------------------
    # 8. Autorizacion IIS-FTP
    #    - Anonimo (IUSR): solo lectura (permissions=1) — ve unicamente
    #      C:\FTP\LocalUser\Public que gracias al aislamiento IIS
    #      corresponde a la carpeta "Public" del usuario anonimo.
    #    - Grupos reprobados/recursadores: lectura+escritura (permissions=3)
    # ------------------------------------------------------------------
    Write-Host "[8/8] Aplicando reglas de autorizacion IIS-FTP..." -ForegroundColor White

    # Limpiar y recrear reglas de autorizacion via appcmd
    # appcmd no lanza excepcion si la regla no existe (a diferencia de los cmdlets IIS)
    $appcmdPath = "$env:SystemRoot\System32\inetsrv\appcmd.exe"

    # Eliminar reglas existentes (2>$null suprime el error si no existen)
    & $appcmdPath set config "FTP" -section:system.ftpServer/security/authorization `
        /-"[accessType='Allow',users='?']" /commit:apphost 2>$null
    & $appcmdPath set config "FTP" -section:system.ftpServer/security/authorization `
        /-"[accessType='Allow',roles='reprobados,recursadores']" /commit:apphost 2>$null
    & $appcmdPath set config "FTP" -section:system.ftpServer/security/authorization `
        /-"[accessType='Deny',users='*']" /commit:apphost 2>$null

    # Agregar reglas limpias
    # Anonimo "?": solo lectura
    & $appcmdPath set config "FTP" -section:system.ftpServer/security/authorization `
        /+"[accessType='Allow',users='?',permissions='Read']" /commit:apphost 2>$null

    # Grupos autenticados: lectura + escritura
    & $appcmdPath set config "FTP" -section:system.ftpServer/security/authorization `
        /+"[accessType='Allow',roles='reprobados,recursadores',permissions='Read,Write']" /commit:apphost 2>$null

    # Denegar al resto de autenticados
    & $appcmdPath set config "FTP" -section:system.ftpServer/security/authorization `
        /+"[accessType='Deny',users='*',permissions='Read,Write']" /commit:apphost 2>$null

    # Grupos locales de Windows
    $adsi = [ADSI]"WinNT://$env:ComputerName"
    foreach ($g in @("reprobados", "recursadores")) {
        if (-not ($adsi.Children | Where-Object {
            $_.SchemaClassName -eq 'Group' -and $_.Name -eq $g
        })) {
            $ng = $adsi.Create("Group", $g)
            $ng.SetInfo()
        }
    }

    # Reiniciar sitio FTP y servicio para aplicar cambios de SSL
    Restart-WebItem "IIS:\Sites\FTP"
    Restart-Service ftpsvc -Force
    Write-Host "  OK" -ForegroundColor Green

    Write-Host ""
    Write-Host "  Servidor FTP configurado exitosamente." -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  RESUMEN DE ACCESOS:" -ForegroundColor White
    Write-Host "  - Anonimo (anonymous/sin password): solo lectura en /general" -ForegroundColor DarkGray
    Write-Host "  - Usuario autenticado: ve su carpeta personal, /general y /grupo" -ForegroundColor DarkGray
    Write-Host "  - Carpeta personal del usuario: lectura+escritura" -ForegroundColor DarkGray
    Write-Host "  - Carpeta de grupo: lectura+escritura (compartida con el grupo)" -ForegroundColor DarkGray
    Write-Host "  - Carpeta general: lectura+escritura para autenticados" -ForegroundColor DarkGray
    Write-Host "=================================================" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# CRUD DE USUARIOS
# -----------------------------------------------------------------------------

function New-UsuarioFTP {
    param (
        [string]$FTPUserName,
        [string]$FTPPassword,
        [string]$FTPUserGroupName
    )

    $adsi = [ADSI]"WinNT://$env:ComputerName"

    # Crear usuario en Windows
    $newUser = $adsi.Create("User", $FTPUserName)
    $newUser.SetPassword($FTPPassword)
    $newUser.SetInfo()

    # Asignar al grupo
    $group = [ADSI]"WinNT://$env:ComputerName/$FTPUserGroupName,group"
    $group.Invoke("Add", "WinNT://$env:ComputerName/$FTPUserName,user")

    # ------------------------------------------------------------------
    # Estructura de carpetas para aislamiento IIS:
    #   C:\FTP\LocalUser\<usuario>              <- raiz de aislamiento (no visible para el usuario)
    #   C:\FTP\LocalUser\<usuario>\<usuario>    <- carpeta personal (escritura)
    #   C:\FTP\LocalUser\<usuario>\general      <- symlink a carpeta publica
    #   C:\FTP\LocalUser\<usuario>\<grupo>      <- symlink a carpeta del grupo
    # ------------------------------------------------------------------
    $userRoot = "C:\FTP\LocalUser\$FTPUserName"
    $userHome = "$userRoot\$FTPUserName"
    New-Item -Path $userRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $userHome -ItemType Directory -Force | Out-Null

    # Permisos NTFS sobre la raiz del usuario: solo Administrators tiene control
    # El usuario NO debe poder ver ni modificar la raiz, solo entrar.
    $aclRoot = Get-Acl $userRoot
    $aclRoot.SetAccessRuleProtection($true, $false)
    $flags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $prop  = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow

    $aclRoot.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators",
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $flags, $prop, $allow
    )))
    # El usuario puede "atravesar" la raiz pero no listarla ni escribir en ella
    $aclRoot.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $FTPUserName,
        [System.Security.AccessControl.FileSystemRights]"ReadAndExecute",
        [System.Security.AccessControl.InheritanceFlags]::None,
        $prop, $allow
    )))
    Set-Acl $userRoot $aclRoot

    # Permisos NTFS sobre la carpeta personal: Modify recursivo
    $aclHome = Get-Acl $userHome
    $aclHome.SetAccessRuleProtection($true, $false)
    $aclHome.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators",
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $flags, $prop, $allow
    )))
    $aclHome.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $FTPUserName,
        [System.Security.AccessControl.FileSystemRights]::Modify,
        $flags, $prop, $allow
    )))
    Set-Acl $userHome $aclHome

    # Propagar permisos a hijos existentes de la carpeta personal
    Get-ChildItem -Path $userHome -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Set-Acl -Path $_.FullName -AclObject $aclHome } catch {}
    }

    # Enlaces simbolicos visibles para el usuario al entrar por FTP
    cmd /c "mklink /D `"$userRoot\general`" `"C:\FTP\LocalUser\Public\general`"" | Out-Null
    cmd /c "mklink /D `"$userRoot\$FTPUserGroupName`" `"C:\FTP\grupos\$FTPUserGroupName`"" | Out-Null

    Write-Host "  [OK] Usuario '$FTPUserName' creado en el grupo '$FTPUserGroupName'." -ForegroundColor Green
}

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

    # Quitar del grupo anterior
    if ($viejoGrupo -ne "") {
        $oldGroup = [ADSI]"WinNT://$env:ComputerName/$viejoGrupo,group"
        $oldGroup.Invoke("Remove", "WinNT://$env:ComputerName/$FTPUserName,user")
    }

    # Agregar al nuevo grupo
    $newGroup = [ADSI]"WinNT://$env:ComputerName/$NuevoGrupo,group"
    $newGroup.Invoke("Add", "WinNT://$env:ComputerName/$FTPUserName,user")

    # Actualizar enlace simbolico del grupo
    $userRoot = "C:\FTP\LocalUser\$FTPUserName"
    if ($viejoGrupo -ne "") {
        cmd /c "rmdir /S /Q `"$userRoot\$viejoGrupo`"" 2>$null
    }
    cmd /c "mklink /D `"$userRoot\$NuevoGrupo`" `"C:\FTP\grupos\$NuevoGrupo`"" | Out-Null

    # Reiniciar servicio FTP para aplicar cambio de grupo en tiempo real
    Write-Host "  Actualizando permisos en tiempo real..." -ForegroundColor White
    Restart-Service ftpsvc -Force

    Write-Host "  [OK] '$FTPUserName' movido de '$viejoGrupo' a '$NuevoGrupo'." -ForegroundColor Green
}

function Remove-UsuarioFTP {
    param ([string]$FTPUserName)

    # Primero quitar de grupos para evitar referencias huerfanas
    foreach ($g in @("reprobados", "recursadores")) {
        try {
            $grp = [ADSI]"WinNT://$env:ComputerName/$g,group"
            $grp.Invoke("Remove", "WinNT://$env:ComputerName/$FTPUserName,user")
        } catch { <# el usuario puede no estar en el grupo #> }
    }

    # Eliminar usuario de Windows
    $adsi = [ADSI]"WinNT://$env:ComputerName"
    $adsi.Delete("User", $FTPUserName)

    # Eliminar carpeta raiz del usuario y todos sus enlaces/subdirectorios
    $userRoot = "C:\FTP\LocalUser\$FTPUserName"
    if (Test-Path $userRoot) {
        # Los symlinks de directorio deben eliminarse con rmdir, no con Remove-Item
        Get-ChildItem -Path $userRoot -Force | Where-Object {
            $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint
        } | ForEach-Object {
            cmd /c "rmdir /Q `"$($_.FullName)`"" 2>$null
        }
        Remove-Item $userRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "  [OK] Usuario '$FTPUserName' eliminado del servidor." -ForegroundColor Green
}