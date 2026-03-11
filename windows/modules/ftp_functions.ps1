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

Function Get-LocalGroupName {
    param([string]$Name)
    try { return (Get-LocalGroup -Name $Name -ErrorAction Stop).Name }
    catch { return $Name }
}

Function Get-AdminGroupName {
    return (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate(
        [System.Security.Principal.NTAccount]).Value
}

Function New-SymbolicLink {
    param([string]$Path, [string]$Target, [switch]$Directory)

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
        Write-Host "  [OK] Symlink: $Path -> $Target" -ForegroundColor DarkGray
    } catch {
        Write-Host "  [Warn] New-Item fallo, usando mklink..." -ForegroundColor Yellow
        if ($Directory) { cmd /c "mklink /D `"$Path`" `"$Target`"" | Out-Null }
        else            { cmd /c "mklink `"$Path`" `"$Target`"" | Out-Null }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [Error] mklink fallo: $Path -> $Target" -ForegroundColor Red
        }
    }
}

# Aplica permisos NTFS correctos al userRoot de un usuario
# SIN tocar LocalUserPath ni carpetas de otros usuarios
Function Set-UserRootPermissions {
    param([string]$Username, [string]$UserRoot, [string]$PersonalDir)

    $adminGroup = Get-AdminGroupName

    # Tomar ownership solo de las carpetas del usuario
    takeown /F $UserRoot    /D Y 2>$null | Out-Null
    takeown /F $PersonalDir /D Y 2>$null | Out-Null

    # userRoot: IIS necesita RX aqui para resolver el chroot (fix 530 home inaccessible)
    # /inheritance:r rompe herencia para control total
    icacls $UserRoot /inheritance:r                        | Out-Null
    icacls $UserRoot /grant "SYSTEM:(OI)(CI)F"             | Out-Null
    icacls $UserRoot /grant "${adminGroup}:(OI)(CI)F"      | Out-Null
    icacls $UserRoot /grant "IUSR:(OI)(CI)RX"              | Out-Null
    icacls $UserRoot /grant "IIS_IUSRS:(OI)(CI)RX"         | Out-Null
    icacls $UserRoot /grant "${Username}:(OI)(CI)RX"       | Out-Null

    # personalDir: usuario puede modificar (crear/borrar archivos y subcarpetas)
    # IIS tambien necesita RX aqui para servir el directorio
    icacls $PersonalDir /inheritance:r                     | Out-Null
    icacls $PersonalDir /grant "SYSTEM:(OI)(CI)F"          | Out-Null
    icacls $PersonalDir /grant "${adminGroup}:(OI)(CI)F"   | Out-Null
    icacls $PersonalDir /grant "IUSR:(OI)(CI)RX"           | Out-Null
    icacls $PersonalDir /grant "IIS_IUSRS:(OI)(CI)RX"      | Out-Null
    icacls $PersonalDir /grant "${Username}:(OI)(CI)M"     | Out-Null
}

Function Set-FtpAuthRules {
    Write-Host "  Configurando reglas de autorizacion..." -ForegroundColor Cyan
    $Filter = "/system.ftpServer/security/authorization"
    $Path = "IIS:\Sites\FTP"

    $Reglas = @(
        @{accessType="Allow"; users="anonimo"; roles=""; permissions="Read"},
        @{accessType="Allow"; users=""; roles="Reprobados,Recursadores"; permissions="Read,Write"},
        @{accessType="Deny";  users="*"; roles=""; permissions="Read,Write"}
    )

    foreach ($r in $Reglas) {
        # Buscamos si ya existe una regla con esos mismos usuarios o roles
        $existe = Get-WebConfiguration -Filter $Filter -PSPath $Path | Where-Object { 
            ($_.users -eq $r.users) -and ($_.roles -eq $r.roles) 
        }

        if (-not $existe) {
            try {
                Add-WebConfiguration -Filter $Filter -PSPath $Path -Value $r -ErrorAction Stop
                Write-Host "    [+] Regla añadida: $($r.users)$($r.roles)" -ForegroundColor Gray
            } catch {
                Write-Host "    [!] Error al añadir regla: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "    [~] Regla ya existe, omitiendo..." -ForegroundColor DarkGray
        }
    }
    Restart-WebItem $Path
}

# ─────────────────────────────────────────────
#  INSTALACION
# ─────────────────────────────────────────────

Function Install-FtpDaemon {
    Write-Host "Instalando dependencias de FTP..."

    foreach ($f in @("Web-Server","Web-FTP-Service","Web-FTP-Server","Web-Basic-Auth")) {
        $feat = Get-WindowsFeature -Name $f
        if (-not $feat.Installed) {
            Install-WindowsFeature $f -IncludeAllSubFeature | Out-Null
            Write-Host "  [OK] $f instalado." -ForegroundColor Green
        } else {
            Write-Host "  [OK] $f ya instalado." -ForegroundColor DarkGray
        }
    }

    Import-Module WebAdministration -ErrorAction Stop

    foreach ($rule in @(
        @{Name="FTP Control Port";  Port="21"},
        @{Name="FTP Passive Ports"; Port="50000-50100"}
    )) {
        if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound `
                -Protocol TCP -LocalPort $rule.Port -Action Allow | Out-Null
            Write-Host "  [OK] Firewall '$($rule.Name)' creado." -ForegroundColor Green
        } else {
            Write-Host "  [OK] Firewall '$($rule.Name)' ya existe." -ForegroundColor DarkGray
        }
        # Dar permiso de lectura/ejecución al motor de IIS en la raíz y LocalUser
# FtpRootPath — IIS necesita "entrar" aqui (RX sin recursividad profunda)
    icacls $script:FtpRootPath /grant "IIS_IUSRS:(RX)" | Out-Null
    
    # LocalUserPath — Carpeta contenedora de usuarios
    icacls $script:LocalUserPath /grant "IIS_IUSRS:(RX)" | Out-Null
    icacls $script:LocalUserPath /grant "Users:(RX)" | Out-Null

    # Importante: Asegurarse que el modo de aislamiento este bien aplicado
    Set-WebConfigurationProperty `
        -Filter "/system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateAllDirectories"
# MUY IMPORTANTE: Para IsolateAllDirectories, la carpeta debe llamarse EXACTAMENTE igual al usuario
# Asegúrate de que C:\FTP\LocalUser\pedro exista.
    }

    # Crear estructura de directorios
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
            Write-Host "  [OK] Dir creado: $_" -ForegroundColor Green
        }
    }

    if (-not (Test-Path $script:UserListPath)) {
        New-Item -ItemType File -Path $script:UserListPath | Out-Null
    }

    $adminGroup = Get-AdminGroupName

    # FtpRootPath — IIS necesita traversar esta carpeta
    icacls $script:FtpRootPath /grant "SYSTEM:(OI)(CI)F"          | Out-Null
    icacls $script:FtpRootPath /grant "${adminGroup}:(OI)(CI)F"   | Out-Null
    icacls $script:FtpRootPath /grant "IUSR:(OI)(CI)RX"           | Out-Null
    icacls $script:FtpRootPath /grant "IIS_IUSRS:(OI)(CI)RX"      | Out-Null

    # LocalUserPath — IIS traversa aqui para encontrar el home de cada usuario
    # NO usar /inheritance:r aqui para no romper permisos de subdirectorios existentes
    icacls $script:LocalUserPath /grant "SYSTEM:(OI)(CI)F"         | Out-Null
    icacls $script:LocalUserPath /grant "${adminGroup}:(OI)(CI)F"  | Out-Null
    icacls $script:LocalUserPath /grant "IUSR:(OI)(CI)RX"          | Out-Null
    icacls $script:LocalUserPath /grant "IIS_IUSRS:(OI)(CI)RX"     | Out-Null
    icacls $script:LocalUserPath /grant "Users:(RX)"               | Out-Null

    # PublicPath — chroot del usuario "anonimo"
    icacls $script:PublicPath /inheritance:r                       | Out-Null
    icacls $script:PublicPath /grant "SYSTEM:(OI)(CI)F"            | Out-Null
    icacls $script:PublicPath /grant "${adminGroup}:(OI)(CI)F"     | Out-Null
    icacls $script:PublicPath /grant "IUSR:(OI)(CI)RX"             | Out-Null
    icacls $script:PublicPath /grant "IIS_IUSRS:(OI)(CI)RX"        | Out-Null

    # GeneralPath — lectura para todos, escritura para grupos
    icacls $script:GeneralPath /inheritance:r                      | Out-Null
    icacls $script:GeneralPath /grant "SYSTEM:(OI)(CI)F"           | Out-Null
    icacls $script:GeneralPath /grant "${adminGroup}:(OI)(CI)F"    | Out-Null
    icacls $script:GeneralPath /grant "IUSR:(OI)(CI)RX"            | Out-Null
    icacls $script:GeneralPath /grant "IIS_IUSRS:(OI)(CI)RX"       | Out-Null
    icacls $script:GeneralPath /grant "Users:(OI)(CI)M"            | Out-Null

    Write-Host "  [OK] Permisos NTFS base aplicados." -ForegroundColor Green

    # Sitio FTP
    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath $script:FtpRootPath -Force | Out-Null
        Write-Host "  [OK] Sitio FTP creado." -ForegroundColor Green
    } else {
        Set-ItemProperty "IIS:\Sites\FTP" -Name physicalPath -Value $script:FtpRootPath
        Write-Host "  [OK] Sitio FTP actualizado." -ForegroundColor DarkGray
    }

    # Aislamiento por usuario
    Set-WebConfigurationProperty `
        -Filter "/system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateAllDirectories"

    # Solo Basic Auth (todos los usuarios se autentican con usuario+contraseña)
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $false
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled     -Value $true

    # SSL desactivado
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\FTP" `
        -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0

    # Puertos pasivos
    Set-WebConfigurationProperty `
        -Filter "system.ftpServer/firewallSupport" `
        -Name "lowDataChannelPort"  -Value 50000
    Set-WebConfigurationProperty `
        -Filter "system.ftpServer/firewallSupport" `
        -Name "highDataChannelPort" -Value 50100

    Write-Host "  [OK] Sitio FTP configurado." -ForegroundColor Green

    Set-FtpAuthRules

    Write-Host ""
    Write-Host "  [OK] Servidor FTP listo." -ForegroundColor Green
    # Ejecuta esto en tu consola de PowerShell (cargando el modulo primero)
    Repair-FtpUser -Username "pedro"
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
        $gInfo = $groups[$gName]
        $gPath = $gInfo.Path

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
        $adminGroup    = Get-AdminGroupName
        icacls $gPath /inheritance:r                            | Out-Null
        icacls $gPath /grant "SYSTEM:(OI)(CI)F"                | Out-Null
        icacls $gPath /grant "${adminGroup}:(OI)(CI)F"         | Out-Null
        icacls $gPath /grant "IIS_IUSRS:(OI)(CI)RX"            | Out-Null
        icacls $gPath /grant "${resolvedGroup}:(OI)(CI)M"       | Out-Null
        Write-Host "  [OK] Permisos en: $gPath" -ForegroundColor DarkGray
    }

    $rep = Get-LocalGroupName "Reprobados"
    $rec = Get-LocalGroupName "Recursadores"
    icacls $script:GeneralPath /grant "${rep}:(OI)(CI)M" | Out-Null
    icacls $script:GeneralPath /grant "${rec}:(OI)(CI)M" | Out-Null
    icacls $script:GeneralPath /grant "IUSR:(OI)(CI)RX"  | Out-Null
}


# ─────────────────────────────────────────────
#  VERIFICACION
# ─────────────────────────────────────────────

Function Get-FtpInstallation {
    Write-Host "Verificando instalacion de FTP Server..."
    $feature = Get-WindowsFeature -Name "Web-FTP-Service"
    if ($feature.Installed) {
        Write-Host "  [OK] $script:ServiceName instalado." -ForegroundColor Green
    } else {
        Write-Host "  [Error] $script:ServiceName NO instalado." -ForegroundColor Red
    }
    Get-FtpConfiguration
}

Function Get-FtpConfiguration {
    Write-Host ""
    Write-Host "Verificando configuracion..."

    $site = Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue
    if ($site) {
        Write-Host "  [OK] Sitio FTP existe. Estado: $($site.State)" -ForegroundColor Green
    } else {
        Write-Host "  [Error] Sitio FTP NO existe." -ForegroundColor Red
    }

    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "  [OK] ftpsvc corriendo." -ForegroundColor Green
    } else {
        Write-Host "  [!] ftpsvc detenido." -ForegroundColor Yellow
    }

    foreach ($path in @($script:GeneralPath, $script:ReprobadosPath, $script:RecursadoresPath)) {
        if (Test-Path $path) {
            Write-Host "  [OK] $path" -ForegroundColor Green
        } else {
            Write-Host "  [Error] Falta: $path" -ForegroundColor Red
        }
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback" } |
        Select-Object -First 1).IPAddress
    Write-Host "  IP  : $ip" -ForegroundColor Cyan
    Write-Host "  Puerto: 21" -ForegroundColor Cyan
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

    # Crear usuario Windows
    try {
        $user = $global:ADSI.Create("User", $Username)
        $user.SetInfo()
        $user.SetPassword($Password)
        # NORMAL_ACCOUNT | DONT_EXPIRE_PASSWD
        $user.psbase.InvokeSet("UserFlags", 0x10200)
        $user.SetInfo()
        Write-Host "  [OK] Usuario '$Username' creado." -ForegroundColor Green
    } catch {
        Write-Host "  [Error] No se pudo crear '$Username': $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    try { Set-LocalUser -Name $Username -PasswordNeverExpires $true -ErrorAction Stop } catch {}

    # Agregar al grupo FTP
    Add-LocalGroupMember -Group $Group -Member $Username -ErrorAction SilentlyContinue

    # Estructura de directorios del usuario:
    #   C:\FTP\LocalUser\<user>\         <- chroot IIS (IsolateAllDirectories)
    #   C:\FTP\LocalUser\<user>\<user>\  <- home visible (Modify para el usuario)
    #   C:\FTP\LocalUser\<user>\General  <- symlink -> GeneralPath
    #   C:\FTP\LocalUser\<user>\<Grupo>  <- symlink -> carpeta del grupo
    $userRoot    = "$script:LocalUserPath\$Username"
    $personalDir = "$userRoot\$Username"

    New-Item -Path $userRoot    -ItemType Directory -Force | Out-Null
    New-Item -Path $personalDir -ItemType Directory -Force | Out-Null

    # Aplicar permisos SOLO en las carpetas del usuario (no toca LocalUserPath)
    Set-UserRootPermissions -Username $Username -UserRoot $userRoot -PersonalDir $personalDir

    # Symlinks
    New-SymbolicLink -Path "$userRoot\General" -Target $script:GeneralPath          -Directory
    New-SymbolicLink -Path "$userRoot\$Group"  -Target "$script:FtpRootPath\$Group" -Directory

    # Registrar en lista
    if (-not (Select-String -Path $script:UserListPath -Pattern "^$Username$" -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -Path $script:UserListPath -Value $Username
    }

    Write-Host "  [OK] '$Username' registrado en grupo '$Group'." -ForegroundColor Green
}


# ─────────────────────────────────────────────
#  AGREGAR USUARIOS (interactivo)
# ─────────────────────────────────────────────

Function Add-FtpUsers {
    Write-Host "Agregar usuarios FTP"

    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        Write-Host "  [Error] Sitio FTP no existe. Ejecuta primero --install." -ForegroundColor Red
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

        do {
            $username = Read-Host "  Nombre de usuario"
            if (-not $username) {
                Write-Host "  [!] No puede estar vacio." -ForegroundColor Yellow
            } elseif ($username -notmatch '^[a-zA-Z][a-zA-Z0-9]{0,14}$') {
                Write-Host "  [!] Solo letras/numeros, empieza con letra, max 15 chars." -ForegroundColor Yellow
                $username = ""
            } elseif (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
                Write-Host "  [!] Usuario '$username' ya existe." -ForegroundColor Yellow
                $username = ""
            }
        } while (-not $username)

        do {
            $pwd = Read-Host "  Contrasena (8-15, May, min, num, especial)"
            if ($pwd -notmatch $regex) {
                Write-Host "  [!] Debe tener mayuscula, minuscula, numero, caracter especial, 8-15 chars." -ForegroundColor Yellow
                $pwd = ""
            } elseif ($pwd -match [regex]::Escape($username)) {
                Write-Host "  [!] No puede contener el nombre de usuario." -ForegroundColor Yellow
                $pwd = ""
            }
        } while (-not $pwd)

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
        $currentGroup = "Reprobados"
        $newGroup     = "Recursadores"
    } elseif (Get-LocalGroupMember -Group "Recursadores" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$username" }) {
        $currentGroup = "Recursadores"
        $newGroup     = "Reprobados"
    } else {
        Write-Host "  [Error] '$username' no pertenece a ningun grupo FTP." -ForegroundColor Red
        return
    }

    Write-Host "  Grupo actual: $currentGroup -> nuevo: $newGroup" -ForegroundColor Cyan
    $confirm = Read-Host "  Confirmar? [s/N]"
    if ($confirm -ne "s" -and $confirm -ne "S") {
        Write-Host "  Cancelado." -ForegroundColor DarkGray
        return
    }

    Update-FtpUserGroup -Username $username -CurrentGroup $currentGroup -NewGroup $newGroup
    Restart-WebItem "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Cambio completado." -ForegroundColor Green
}

Function Update-FtpUserGroup {
    param([string]$Username, [string]$CurrentGroup, [string]$NewGroup)

    $userRoot = "$script:LocalUserPath\$Username"

    Remove-LocalGroupMember -Group $CurrentGroup -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $NewGroup     -Member $Username -ErrorAction SilentlyContinue

    # Eliminar symlink del grupo anterior
    $oldLink = "$userRoot\$CurrentGroup"
    if (Test-Path $oldLink) {
        $item = Get-Item $oldLink -Force -ErrorAction SilentlyContinue
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$oldLink`"" 2>$null | Out-Null
        } else {
            Remove-Item $oldLink -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  [OK] Symlink '$CurrentGroup' eliminado." -ForegroundColor DarkGray
    }

    # Crear symlink del nuevo grupo
    New-SymbolicLink -Path "$userRoot\$NewGroup" `
                     -Target "$script:FtpRootPath\$NewGroup" -Directory

    # Re-aplicar permisos del userRoot (por si algo cambio)
    $personalDir = "$userRoot\$Username"
    Set-UserRootPermissions -Username $Username -UserRoot $userRoot -PersonalDir $personalDir

    Write-Host "  [OK] '$Username' -> '$NewGroup'." -ForegroundColor Green
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
                Where-Object { $_.Name -like "*$u" }) { $group = "Reprobados" }
            elseif (Get-LocalGroupMember -Group "Recursadores" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$u" }) { $group = "Recursadores" }
        } catch {}
        Write-Host ("  {0,-20} -> {1}" -f $u, $group)
    }

    Write-Host "**********************"
}


# ─────────────────────────────────────────────
#  REPARAR USUARIO EXISTENTE
# ─────────────────────────────────────────────

# Ejecutar manualmente si un usuario ya creado sigue con 530
Function Repair-FtpUser {
    param([string]$Username)

    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Host "  [Error] Usuario '$Username' no existe en Windows." -ForegroundColor Red
        return
    }

    $grupo = Get-GrupoActualFTP -FTPUserName $Username
    if (-not $grupo) {
        Write-Host "  [Error] '$Username' no pertenece a ningun grupo FTP." -ForegroundColor Red
        return
    }

    $userRoot    = "$script:LocalUserPath\$Username"
    $personalDir = "$userRoot\$Username"

    Write-Host "  Reparando '$Username' (grupo: $grupo)..." -ForegroundColor Cyan

    # Crear directorios si faltan
    foreach ($dir in @($userRoot, $personalDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "  [OK] Creado: $dir" -ForegroundColor Green
        }
    }

    Set-UserRootPermissions -Username $Username -UserRoot $userRoot -PersonalDir $personalDir

    # Recrear symlinks
    New-SymbolicLink -Path "$userRoot\General" -Target $script:GeneralPath           -Directory
    New-SymbolicLink -Path "$userRoot\$grupo"  -Target "$script:FtpRootPath\$grupo"  -Directory

    # Reiniciar FTP
    Stop-Service  ftpsvc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service ftpsvc -ErrorAction SilentlyContinue

    Write-Host "  [OK] '$Username' reparado." -ForegroundColor Green
}


# ─────────────────────────────────────────────
#  ALIAS — compatibilidad con menu_ftp.ps1
# ─────────────────────────────────────────────

function Initialize-ServidorFTP {
    Install-FtpDaemon
    Initialize-FtpGroups
}

function New-UsuarioFTP {
    param([string]$FTPUserName, [string]$FTPPassword, [string]$FTPUserGroupName)
    New-FtpUser -Username $FTPUserName -Password $FTPPassword -Group $FTPUserGroupName
}

function Set-GrupoFTP {
    param([string]$FTPUserName, [string]$NuevoGrupo)
    $actual = Get-GrupoActualFTP -FTPUserName $FTPUserName
    Update-FtpUserGroup -Username $FTPUserName -CurrentGroup $actual -NewGroup $NuevoGrupo
}

function Remove-UsuarioFTP {
    param([string]$FTPUserName)
    foreach ($g in @("Reprobados","Recursadores")) {
        Remove-LocalGroupMember -Group $g -Member $FTPUserName -ErrorAction SilentlyContinue
    }
    Remove-LocalUser -Name $FTPUserName -ErrorAction SilentlyContinue
    $userRoot = "$script:LocalUserPath\$FTPUserName"
    if (Test-Path $userRoot) {
        Get-ChildItem $userRoot -Force |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
            ForEach-Object { cmd /c "rmdir `"$($_.FullName)`"" 2>$null | Out-Null }
        Remove-Item $userRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $script:UserListPath) {
        $lines = Get-Content $script:UserListPath | Where-Object { $_ -ne $FTPUserName }
        Set-Content $script:UserListPath $lines
    }
    Write-Host "  [OK] '$FTPUserName' eliminado." -ForegroundColor Green
}

function Invoke-UsuarioExiste {
    param([string]$nombre)
    return ($null -ne (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue))
}

function Get-GrupoActualFTP {
    param([string]$FTPUserName)
    try {
        if (Get-LocalGroupMember -Group "Reprobados"   -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$FTPUserName" }) { return "Reprobados" }
        if (Get-LocalGroupMember -Group "Recursadores" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$FTPUserName" }) { return "Recursadores" }
    } catch {}
    return ""
}

function Invoke-CapturarUsuarioFTPValido {
    param([string]$mensaje)
    do {
        $c = Read-Host "  $mensaje"
        if (-not $c)                            { Write-Host "  [!] No puede estar vacio."        -ForegroundColor Yellow }
        elseif ($c -notmatch '^[a-zA-Z0-9]+$')  { Write-Host "  [!] Solo letras y numeros."       -ForegroundColor Yellow }
        elseif ($c -match    '^[0-9]')           { Write-Host "  [!] No puede empezar con numero." -ForegroundColor Yellow }
        elseif ($c.Length -gt 15)                { Write-Host "  [!] Maximo 15 caracteres."        -ForegroundColor Yellow }
        elseif (Invoke-UsuarioExiste $c)         { Write-Host "  [!] Usuario '$c' ya existe."     -ForegroundColor Yellow }
        else { return $c }
    } while ($true)
}

function Invoke-CapturarContra {
    $regex = "^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[^a-zA-Z0-9]).{8,15}$"
    do {
        $c = Read-Host "  Contrasena (8-15, May, min, num, especial)"
        if ($c -notmatch $regex) {
            Write-Host "  [!] No cumple requisitos." -ForegroundColor Yellow
            $c = ""
        }
    } while (-not $c)
    return $c
}

function Invoke-CapturarGrupoFTP {
    do {
        Write-Host "  Seleccione grupo:"
        Write-Host "    1) Reprobados"
        Write-Host "    2) Recursadores"
        $g = Read-Host "  Opcion"
        if ($g -eq "1") { return "Reprobados"   }
        if ($g -eq "2") { return "Recursadores" }
        Write-Host "  [!] Ingrese 1 o 2." -ForegroundColor Yellow
    } while ($true)
}