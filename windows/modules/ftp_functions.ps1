# =============================================================================
# ftp_functions.ps1
# Ubicacion: windows/modules/ftp_functions.ps1
# =============================================================================

$script:ServiceName      = "FTP Daemon IIS"
$script:FtpRootPath      = "C:\FTP"
$script:LocalUserPath    = "C:\FTP\LocalUser"
$script:PublicPath       = "C:\FTP\LocalUser\Public"
$script:GeneralPath      = "C:\FTP\LocalUser\Public\General"
$script:ReprobadosPath   = "C:\FTP\Reprobados"
$script:RecursadoresPath = "C:\FTP\Recursadores"
$script:UserListPath     = "C:\FTP\ftp_user_list.txt"
$global:ADSI             = $null


# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────

# Resuelve el nombre real del grupo local para icacls
# Evita "No mapping between account names and security IDs"
Function Get-LocalGroupName {
    param([string]$Name)
    try {
        return (Get-LocalGroup -Name $Name -ErrorAction Stop).Name
    } catch {
        return $Name
    }
}

# Nombre del grupo Administrators resuelto por SID (funciona en cualquier idioma)
Function Get-AdminGroupName {
    return (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate(
        [System.Security.Principal.NTAccount]).Value
}

# Crea symlink de directorio con fallback a cmd mklink si New-Item falla
Function New-SymbolicLink {
    param(
        [string]$Path,
        [string]$Target,
        [switch]$Directory
    )

    if (Test-Path $Path) {
        $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$Path`"" 2>$null | Out-Null
        } else {
            Remove-Item $Path -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  [Warn] New-Item fallo, usando mklink como fallback..." -ForegroundColor Yellow
        if ($Directory) {
            cmd /c "mklink /D `"$Path`" `"$Target`"" | Out-Null
        } else {
            cmd /c "mklink `"$Path`" `"$Target`"" | Out-Null
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [Error] mklink tambien fallo: $Path -> $Target" -ForegroundColor Red
        }
    }
}

# Escribe reglas de autorizacion FTP directamente en applicationHost.config
# Detiene W3SVC/ftpsvc para evitar el lock "file in use" y el error 534 SSL
Function Set-FtpAuthRules {
    Write-Host "  Aplicando reglas de autorizacion (edicion directa XML)..." -ForegroundColor DarkGray

    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Stop-Service W3SVC  -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $cfg = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"
    [xml]$xml = Get-Content $cfg -Encoding UTF8

    # ── SSL: parchear siteDefaults y el sitio FTP especifico ──
    $sitesNode = $xml.configuration."system.applicationHost".sites

    if ($sitesNode.siteDefaults.ftpServer.security.ssl) {
        $sitesNode.siteDefaults.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
        $sitesNode.siteDefaults.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
    }

    $ftpSite = $sitesNode.site | Where-Object { $_.name -eq "FTP" }
    if ($ftpSite -and $ftpSite.ftpServer.security.ssl) {
        $ftpSite.ftpServer.security.ssl.controlChannelPolicy = "SslAllow"
        $ftpSite.ftpServer.security.ssl.dataChannelPolicy    = "SslAllow"
    }

    # ── Autorizacion: buscar/crear <location path="FTP"> ──
    $locNode = $xml.configuration.location | Where-Object { $_.path -eq "FTP" }
    if (-not $locNode) {
        $locNode = $xml.CreateElement("location")
        $locNode.SetAttribute("path", "FTP")
        $xml.configuration.AppendChild($locNode) | Out-Null
    }

    # Asegurar jerarquia system.ftpServer/security/authorization
    if (-not $locNode."system.ftpServer") {
        $locNode.AppendChild($xml.CreateElement("system.ftpServer")) | Out-Null
    }
    if (-not $locNode."system.ftpServer".security) {
        $locNode."system.ftpServer".AppendChild($xml.CreateElement("security")) | Out-Null
    }

    $authNode = $locNode."system.ftpServer".security.authorization
    if ($authNode) {
        $authNode.RemoveAll()   # borrar reglas duplicadas/residuales
    } else {
        $authNode = $xml.CreateElement("authorization")
        $locNode."system.ftpServer".security.AppendChild($authNode) | Out-Null
    }

    # Helper local para construir una regla <add ... />
    function _Rule($aType, $users, $roles, $perms) {
        $r = $xml.CreateElement("add")
        $r.SetAttribute("accessType",  $aType)
        $r.SetAttribute("users",       $users)
        $r.SetAttribute("roles",       $roles)
        $r.SetAttribute("permissions", $perms)
        return $r
    }

    # users="?" = anonimo en IIS-FTP (solo lectura)
    $authNode.AppendChild((_Rule "Allow" "?" ""                       "Read"))       | Out-Null
    # Grupos autenticados: lectura + escritura
    $authNode.AppendChild((_Rule "Allow" "" "reprobados,recursadores" "Read, Write")) | Out-Null
    # Denegar al resto
    $authNode.AppendChild((_Rule "Deny"  "*" ""                       "Read, Write")) | Out-Null

    $xml.Save($cfg)
    Write-Host "  Configuracion guardada." -ForegroundColor DarkGray

    Start-Service W3SVC  -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    Write-Host "  [OK] SSL y autorizacion aplicados." -ForegroundColor Green
}


# ─────────────────────────────────────────────
#  INSTALACION
# ─────────────────────────────────────────────

Function Install-FtpDaemon {
    Write-Host "Instalando dependencias de FTP..."

    # Features de Windows
    foreach ($f in @("Web-Server","Web-FTP-Service","Web-FTP-Server","Web-Basic-Auth")) {
        $feat = Get-WindowsFeature -Name $f
        if (-not $feat.Installed) {
            Install-WindowsFeature $f -IncludeAllSubFeature | Out-Null
            Write-Host "  [OK] $f instalado." -ForegroundColor Green
        } else {
            Write-Host "  [OK] $f ya estaba instalado." -ForegroundColor DarkGray
        }
    }

    Import-Module WebAdministration -ErrorAction Stop

    # Firewall
    foreach ($rule in @(
        @{Name="FTP Control Port";  Port="21"},
        @{Name="FTP Passive Ports"; Port="50000-50100"}
    )) {
        if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound `
                -Protocol TCP -LocalPort $rule.Port -Action Allow | Out-Null
            Write-Host "  [OK] Regla firewall '$($rule.Name)' creada." -ForegroundColor Green
        } else {
            Write-Host "  [OK] Regla firewall '$($rule.Name)' ya existe." -ForegroundColor DarkGray
        }
    }

    # Directorios
    @(
        $script:FtpRootPath,
        $script:LocalUserPath,
        $script:PublicPath,
        $script:GeneralPath,
        $script:ReprobadosPath,
        $script:RecursadoresPath
    ) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Host "  [OK] Directorio creado: $_" -ForegroundColor Green
        }
    }

    if (-not (Test-Path $script:UserListPath)) {
        New-Item -ItemType File -Path $script:UserListPath | Out-Null
    }

    $adminGroup = Get-AdminGroupName

    # Permisos NTFS con icacls (OI)(CI) = herencia recursiva en subdirectorios y archivos
    # FtpRootPath — acceso basico para que IIS pueda navegar
    icacls $script:FtpRootPath /grant "Users:(RX)"                     | Out-Null
    icacls $script:FtpRootPath /grant "${adminGroup}:(OI)(CI)F"        | Out-Null

    # LocalUserPath
    icacls $script:LocalUserPath /inheritance:r                        | Out-Null
    icacls $script:LocalUserPath /grant "Users:(RX)"                   | Out-Null
    icacls $script:LocalUserPath /grant "${adminGroup}:(OI)(CI)F"      | Out-Null
    icacls $script:LocalUserPath /grant "SYSTEM:(OI)(CI)F"             | Out-Null
    icacls $script:LocalUserPath /grant "IUSR:(OI)(CI)RX"              | Out-Null
    icacls $script:LocalUserPath /grant "IIS_IUSRS:(OI)(CI)RX"         | Out-Null

    # PublicPath (chroot del anonimo)
    icacls $script:PublicPath /inheritance:r                           | Out-Null
    icacls $script:PublicPath /grant "${adminGroup}:(OI)(CI)F"         | Out-Null
    icacls $script:PublicPath /grant "SYSTEM:(OI)(CI)F"                | Out-Null
    icacls $script:PublicPath /grant "IUSR:(OI)(CI)RX"                 | Out-Null
    icacls $script:PublicPath /grant "IIS_IUSRS:(OI)(CI)RX"            | Out-Null

    # GeneralPath: anonimo lectura, grupos autenticados modificar
    icacls $script:GeneralPath /inheritance:r                          | Out-Null
    icacls $script:GeneralPath /grant "${adminGroup}:(OI)(CI)F"        | Out-Null
    icacls $script:GeneralPath /grant "SYSTEM:(OI)(CI)F"               | Out-Null
    icacls $script:GeneralPath /grant "IUSR:(OI)(CI)RX"                | Out-Null
    icacls $script:GeneralPath /grant "IIS_IUSRS:(OI)(CI)RX"           | Out-Null
    icacls $script:GeneralPath /grant "Users:(OI)(CI)M"                | Out-Null

    Write-Host "  [OK] Permisos NTFS aplicados." -ForegroundColor Green

    # Sitio FTP en IIS
    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath $script:FtpRootPath -Force | Out-Null
        Write-Host "  [OK] Sitio FTP creado." -ForegroundColor Green
    } else {
        Set-ItemProperty "IIS:\Sites\FTP" -Name physicalPath -Value $script:FtpRootPath
        Write-Host "  [OK] Sitio FTP ya existe, ruta actualizada." -ForegroundColor DarkGray
    }

    # Aislamiento por usuario (IIS busca C:\FTP\LocalUser\<usuario>\ como chroot)
    Set-WebConfigurationProperty `
        -Filter "/system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateAllDirectories"

    # Autenticacion anonima + basica
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled  -Value $true
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.authentication.anonymousAuthentication.username -Value "IUSR"
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.authentication.anonymousAuthentication.password -Value ""
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled      -Value $true

    # SSL desactivado (valor 0 = SslAllow via property)
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0

    Write-Host "  [OK] Sitio FTP configurado." -ForegroundColor Green

    # Reglas de autorizacion + parche SSL en applicationHost.config
    Set-FtpAuthRules

    Write-Host ""
    Write-Host "  [OK] Servidor FTP listo." -ForegroundColor Green
}


# ─────────────────────────────────────────────
#  GRUPOS
# ─────────────────────────────────────────────

Function Initialize-FtpGroups {
    Write-Host "Configurando grupos FTP..."

    $global:ADSI = [ADSI]"WinNT://$env:ComputerName"

    $groups = @{
        "Reprobados"   = @{ Desc = "Grupo de reprobados";   Path = $script:ReprobadosPath }
        "Recursadores" = @{ Desc = "Grupo de recursadores"; Path = $script:RecursadoresPath }
    }

    foreach ($gName in $groups.Keys) {
        $gInfo  = $groups[$gName]
        $gPath  = $gInfo.Path
        $existe = $global:ADSI.Children |
            Where-Object { $_.SchemaClassName -eq "Group" -and $_.Name -eq $gName }
        if (-not $existe) {
            $grp = $global:ADSI.Create("Group", $gName)
            $grp.SetInfo()
            $grp.Description = $gInfo.Desc
            $grp.SetInfo()
            Write-Host "  [OK] Grupo '$gName' creado." -ForegroundColor Green
        } else {
            Write-Host "  [OK] Grupo '$gName' ya existe." -ForegroundColor DarkGray
        }

        if (-not (Test-Path $gPath)) {
            New-Item -ItemType Directory -Path $gPath -Force | Out-Null
        }

        $resolvedGroup = Get-LocalGroupName $gName
        icacls $gPath /inheritance:r                             | Out-Null
        icacls $gPath /grant "$(Get-AdminGroupName):(OI)(CI)F"  | Out-Null
        icacls $gPath /grant "SYSTEM:(OI)(CI)F"                 | Out-Null
        icacls $gPath /grant "IIS_IUSRS:(OI)(CI)RX"             | Out-Null
        icacls $gPath /grant "${resolvedGroup}:(OI)(CI)M"        | Out-Null
        Write-Host "  [OK] Permisos aplicados a: $gPath" -ForegroundColor DarkGray
    }

    # General: ambos grupos pueden modificar + IUSR solo lectura
    $rep = Get-LocalGroupName "Reprobados"
    $rec = Get-LocalGroupName "Recursadores"
    icacls $script:GeneralPath /grant "${rep}:(OI)(CI)M"   | Out-Null
    icacls $script:GeneralPath /grant "${rec}:(OI)(CI)M"   | Out-Null
    icacls $script:GeneralPath /grant "IUSR:(OI)(CI)RX"    | Out-Null
}


# ─────────────────────────────────────────────
#  VERIFICACION
# ─────────────────────────────────────────────

Function Get-FtpInstallation {
    Write-Host "Verificando instalacion de FTP Server..."

    $feature = Get-WindowsFeature -Name "Web-FTP-Service"
    if ($feature.Installed) {
        Write-Host "  [OK] $script:ServiceName esta instalado." -ForegroundColor Green
    } else {
        Write-Host "  [Error] $script:ServiceName NO esta instalado." -ForegroundColor Red
    }

    Get-FtpConfiguration
}

Function Get-FtpConfiguration {
    Write-Host ""
    Write-Host "Verificando configuracion del $script:ServiceName..."

    $site = Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue
    if ($site) {
        Write-Host "  [OK] Sitio FTP existe. Estado: $($site.State)" -ForegroundColor Green
    } else {
        Write-Host "  [Error] Sitio FTP NO existe." -ForegroundColor Red
    }

    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "  [OK] Servicio ftpsvc en ejecucion." -ForegroundColor Green
    } else {
        Write-Host "  [!] Servicio ftpsvc detenido o no existe." -ForegroundColor Yellow
    }

    foreach ($path in @($script:GeneralPath, $script:ReprobadosPath, $script:RecursadoresPath)) {
        if (Test-Path $path) {
            Write-Host "  [OK] Directorio existe: $path" -ForegroundColor Green
        } else {
            Write-Host "  [Error] Directorio faltante: $path" -ForegroundColor Red
        }
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback" } |
        Select-Object -First 1).IPAddress
    Write-Host "  IP del servidor : $ip" -ForegroundColor Cyan
    Write-Host "  Puerto FTP      : 21"  -ForegroundColor Cyan
}


# ─────────────────────────────────────────────
#  CREAR USUARIO (interno)
# ─────────────────────────────────────────────

Function New-FtpUser {
    param(
        [string]$Username,
        [string]$Password,
        [string]$Group
    )

    if ($null -eq $global:ADSI) {
        $global:ADSI = [ADSI]"WinNT://$env:ComputerName"
    }

    # Crear usuario Windows via ADSI
    try {
        $user = $global:ADSI.Create("User", $Username)
        $user.SetInfo()
        $user.SetPassword($Password)
        # 0x200 = NORMAL_ACCOUNT | 0x10000 = DONT_EXPIRE_PASSWD
        $user.psbase.InvokeSet("UserFlags", 0x10200)
        $user.SetInfo()
        Write-Host "  [OK] Usuario '$Username' creado." -ForegroundColor Green
    } catch {
        Write-Host "  [Error] No se pudo crear '$Username': $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    try {
        Set-LocalUser -Name $Username -PasswordNeverExpires $true -ErrorAction Stop
    } catch {}

    # Agregar al grupo
    Add-LocalGroupMember -Group $Group -Member $Username -ErrorAction SilentlyContinue

    $adminGroup = Get-AdminGroupName

    # Garantizar permisos en LocalUserPath antes de crear subdirectorios
    takeown /F $script:LocalUserPath /R /D Y 2>$null | Out-Null
    icacls $script:LocalUserPath /inheritance:r                          | Out-Null
    icacls $script:LocalUserPath /grant "${adminGroup}:(OI)(CI)F"    /T | Out-Null
    icacls $script:LocalUserPath /grant "SYSTEM:(OI)(CI)F"           /T | Out-Null
    icacls $script:LocalUserPath /grant "IUSR:(OI)(CI)RX"            /T | Out-Null
    icacls $script:LocalUserPath /grant "IIS_IUSRS:(OI)(CI)RX"       /T | Out-Null

    # Estructura:
    #   C:\FTP\LocalUser\<user>          <- chroot IIS (IsolateAllDirectories)
    #   C:\FTP\LocalUser\<user>\<user>   <- carpeta personal (Modify recursivo)
    #   C:\FTP\LocalUser\<user>\General  <- symlink a Public\General
    #   C:\FTP\LocalUser\<user>\<grupo>  <- symlink a grupos\<grupo>
    $userRoot    = "$script:LocalUserPath\$Username"
    $personalDir = "$userRoot\$Username"

    New-Item -Path $userRoot    -ItemType Directory -Force | Out-Null
    New-Item -Path $personalDir -ItemType Directory -Force | Out-Null

    # userRoot: IUSR e IIS_IUSRS necesitan RX para que IIS verifique el home (fix error 530)
    icacls $userRoot /inheritance:r                              | Out-Null
    icacls $userRoot /grant "SYSTEM:(OI)(CI)F"                  | Out-Null
    icacls $userRoot /grant "${adminGroup}:(OI)(CI)F"           | Out-Null
    icacls $userRoot /grant "IUSR:(OI)(CI)RX"                   | Out-Null
    icacls $userRoot /grant "IIS_IUSRS:(OI)(CI)RX"              | Out-Null
    icacls $userRoot /grant "${Username}:(OI)(CI)RX"            | Out-Null

    # Carpeta personal: Modify recursivo (usuario puede crear subdirectorios sin limite)
    icacls $personalDir /grant "${Username}:(OI)(CI)M"          | Out-Null
    Write-Host "  [OK] Permisos asignados a $userRoot" -ForegroundColor Green

    # Symlinks
    New-SymbolicLink -Path "$userRoot\General" -Target $script:GeneralPath -Directory
    New-SymbolicLink -Path "$userRoot\$Group"  -Target "$script:FtpRootPath\$Group" -Directory

    # Registrar en lista
    if (-not (Select-String -Path $script:UserListPath -Pattern "^$Username$" -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -Path $script:UserListPath -Value $Username
    }

    Write-Host "  [OK] Usuario '$Username' registrado en grupo '$Group'." -ForegroundColor Green
}


# ─────────────────────────────────────────────
#  AGREGAR USUARIOS (interactivo)
# ─────────────────────────────────────────────

Function Add-FtpUsers {
    Write-Host "Agregar usuarios FTP"

    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        Write-Host "  [Error] El sitio FTP no existe. Ejecuta primero --install." -ForegroundColor Red
        return
    }

    $rawN = Read-Host "  Cuantos usuarios deseas crear?"
    $n = 0
    if (-not [int]::TryParse($rawN, [ref]$n) -or $n -lt 1) {
        Write-Host "  [Error] Numero invalido." -ForegroundColor Red
        return
    }

    $regex = "^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[^a-zA-Z0-9]).{8,15}$"

    for ($i = 1; $i -le $n; $i++) {
        Write-Host ""
        Write-Host "  --- Usuario $i de $n ---" -ForegroundColor Cyan

        # Nombre de usuario
        do {
            $username = Read-Host "  Nombre de usuario"
            if (-not $username) {
                Write-Host "  [!] No puede estar vacio." -ForegroundColor Yellow
            } elseif ($username -notmatch '^[a-zA-Z][a-zA-Z0-9]{0,14}$') {
                Write-Host "  [!] Solo letras/numeros, empieza con letra, max 15 chars." -ForegroundColor Yellow
                $username = ""
            } elseif (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
                Write-Host "  [!] El usuario '$username' ya existe." -ForegroundColor Yellow
                $username = ""
            }
        } while (-not $username)

        # Contrasena
        do {
            $pwd = Read-Host "  Contrasena (8-15, May, min, num, especial)"
            if ($pwd -notmatch $regex) {
                Write-Host "  [!] Debe tener mayuscula, minuscula, numero, caracter especial y 8-15 chars." -ForegroundColor Yellow
                $pwd = ""
            } elseif ($pwd -match [regex]::Escape($username)) {
                Write-Host "  [!] No puede contener el nombre de usuario." -ForegroundColor Yellow
                $pwd = ""
            }
        } while (-not $pwd)

        # Grupo
        Write-Host "  Rol:"
        Write-Host "    1) Reprobados"
        Write-Host "    2) Recursadores"
        do {
            $rol = Read-Host "  Opcion [1/2]"
            switch ($rol) {
                "1" { $group = "Reprobados";   $ok = $true }
                "2" { $group = "Recursadores"; $ok = $true }
                default { Write-Host "  [!] Ingrese 1 o 2." -ForegroundColor Yellow; $ok = $false }
            }
        } while (-not $ok)

        New-FtpUser -Username $username -Password $pwd -Group $group
    }

    Restart-WebItem "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
    Write-Host ""
    Get-FtpUsers
}


# ─────────────────────────────────────────────
#  CAMBIAR GRUPO
# ─────────────────────────────────────────────

Function Set-FtpUserGroup {
    Write-Host "Cambiar grupo de usuario FTP"
    Get-FtpUsers

    $username = Read-Host "  Usuario a cambiar"

    if (-not (Get-LocalUser -Name $username -ErrorAction SilentlyContinue)) {
        Write-Host "  [Error] El usuario '$username' no existe." -ForegroundColor Red
        return
    }

    $currentGroup = $null
    $newGroup     = $null

    if (Get-LocalGroupMember -Group "Reprobados" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$username" }) {
        $currentGroup = "reprobados"
        $newGroup     = "recursadores"
    } elseif (Get-LocalGroupMember -Group "Recursadores" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$username" }) {
        $currentGroup = "recursadores"
        $newGroup     = "reprobados"
    } else {
        Write-Host "  [Error] '$username' no pertenece a ningun grupo FTP valido." -ForegroundColor Red
        return
    }

    Write-Host "  Grupo actual: $currentGroup -> nuevo: $newGroup" -ForegroundColor Cyan
    $confirm = Read-Host "  Confirmar cambio? [s/N]"
    if ($confirm -ne "s" -and $confirm -ne "S") {
        Write-Host "  Cancelado." -ForegroundColor DarkGray
        return
    }

    Update-FtpUserGroup -Username $username -CurrentGroup $currentGroup -NewGroup $newGroup

    Restart-WebItem "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Cambio completado." -ForegroundColor Green
}

Function Update-FtpUserGroup {
    param(
        [string]$Username,
        [string]$CurrentGroup,
        [string]$NewGroup
    )

    $userRoot = "$script:LocalUserPath\$Username"

    Remove-LocalGroupMember -Group $CurrentGroup -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $NewGroup     -Member $Username -ErrorAction SilentlyContinue

    # Eliminar symlink del grupo anterior
    $oldLink = "$userRoot\$CurrentGroup"
    if (Test-Path $oldLink) {
        cmd /c "rmdir `"$oldLink`"" 2>$null | Out-Null
        Write-Host "  [OK] Symlink '$CurrentGroup' eliminado." -ForegroundColor DarkGray
    }

    # Crear symlink del nuevo grupo
    New-SymbolicLink -Path "$userRoot\$NewGroup" `
                     -Target "$script:FtpRootPath\$NewGroup" -Directory
    Write-Host "  [OK] Symlink '$NewGroup' creado." -ForegroundColor DarkGray

    # Confirmar permisos en carpeta personal
    $personalDir = "$userRoot\$Username"
    icacls $personalDir /grant "${Username}:(OI)(CI)M" | Out-Null

    Write-Host "  [OK] '$Username' cambiado de '$CurrentGroup' a '$NewGroup'." -ForegroundColor Green
}


# ─────────────────────────────────────────────
#  LISTAR USUARIOS
# ─────────────────────────────────────────────

Function Get-FtpUsers {
    Write-Host ""
    Write-Host "Usuarios en FTP:"
    Write-Host "**********************"

    if (-not (Test-Path $script:UserListPath)) {
        Write-Host "  (sin usuarios registrados)"
        Write-Host "**********************"
        return
    }

    $users = Get-Content $script:UserListPath | Where-Object { $_ -ne "" }
    if (-not $users) {
        Write-Host "  (sin usuarios registrados)"
        Write-Host "**********************"
        return
    }

    foreach ($u in $users) {
        $group = "sin grupo"
        try {
            if (Get-LocalGroupMember -Group "Reprobados"   -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$u" }) { $group = "reprobados" }
            elseif (Get-LocalGroupMember -Group "recursadores" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$u" }) { $group = "recursadores" }
        } catch {}
        Write-Host ("  usuario {0,-20} -> {1}" -f $u, $group)
    }

    Write-Host "**********************"
}