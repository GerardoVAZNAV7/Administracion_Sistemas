# =============================================================================
# ftp_functions.ps1
# Ubicacion: windows/modules/ftp_functions.ps1
# =============================================================================

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

function Get-AdminGroupName {
    return (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate(
        [System.Security.Principal.NTAccount]).Value
}

function New-SymbolicLink {
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
        if ($Directory) { cmd /c "mklink /D `"$Path`" `"$Target`"" | Out-Null }
        else            { cmd /c "mklink `"$Path`" `"$Target`"" | Out-Null }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [Error] mklink fallo: $Path -> $Target" -ForegroundColor Red
        } else {
            Write-Host "  [OK] Symlink (mklink): $Path -> $Target" -ForegroundColor DarkGray
        }
    }
}

# userRoot  = C:\FTP\LocalUser\<user>       -> IIS necesita RX (fix error 530)
# personalDir = C:\FTP\LocalUser\<user>\<user> -> usuario tiene Modify
function Set-UserRootPermissions {
    param([string]$Username, [string]$UserRoot, [string]$PersonalDir)

    $adminGroup = Get-AdminGroupName

    takeown /F $UserRoot    /D Y 2>$null | Out-Null
    takeown /F $PersonalDir /D Y 2>$null | Out-Null

    icacls $UserRoot /inheritance:r                        | Out-Null
    icacls $UserRoot /grant "SYSTEM:(OI)(CI)F"             | Out-Null
    icacls $UserRoot /grant "${adminGroup}:(OI)(CI)F"      | Out-Null
    icacls $UserRoot /grant "IUSR:(OI)(CI)RX"              | Out-Null
    icacls $UserRoot /grant "IIS_IUSRS:(OI)(CI)RX"         | Out-Null
    icacls $UserRoot /grant "${Username}:(OI)(CI)RX"       | Out-Null

    icacls $PersonalDir /inheritance:r                     | Out-Null
    icacls $PersonalDir /grant "SYSTEM:(OI)(CI)F"          | Out-Null
    icacls $PersonalDir /grant "${adminGroup}:(OI)(CI)F"   | Out-Null
    icacls $PersonalDir /grant "IUSR:(OI)(CI)RX"           | Out-Null
    icacls $PersonalDir /grant "IIS_IUSRS:(OI)(CI)RX"      | Out-Null
    icacls $PersonalDir /grant "${Username}:(OI)(CI)M"     | Out-Null
}

# ─────────────────────────────────────────────
#  REGLAS DE AUTORIZACION FTP
#
#  El error "configuration section cannot be used at this path"
#  ocurre porque en applicationHost.config la seccion
#  system.ftpServer/security/authorization tiene:
#      overrideModeDefault="Deny"
#  lo que impide escribirla a nivel de sitio con Add-WebConfiguration.
#
#  SOLUCION: editar applicationHost.config directamente para cambiar
#  ese atributo a "Allow", luego usar appcmd para las reglas.
# ─────────────────────────────────────────────

function Set-FtpAuthRules {
    Write-Host "  Configurando reglas de autorizacion FTP..." -ForegroundColor Cyan

    $appcmd   = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    $ahConfig = "$env:SystemRoot\system32\inetsrv\config\applicationHost.config"

    if (-not (Test-Path $appcmd)) {
        Write-Host "  [Error] appcmd.exe no encontrado. IIS no esta instalado correctamente." -ForegroundColor Red
        return
    }

    # ── Paso 1: Cambiar overrideModeDefault a "Allow" en applicationHost.config ──
    # Esto es necesario para poder definir reglas de autorizacion a nivel de sitio.
    if (Test-Path $ahConfig) {
        $content = Get-Content $ahConfig -Raw -Encoding UTF8

        # Buscar el patron exacto de la seccion de autorizacion FTP y cambiar Deny->Allow
        $oldLine = '<section name="authorization" overrideModeDefault="Deny" />'
        $newLine = '<section name="authorization" overrideModeDefault="Allow" />'

        # Solo hay UNA seccion authorization dentro de system.ftpServer/security
        # Usamos reemplazo contextual para no tocar la seccion de HTTP
        if ($content -match [regex]::Escape($oldLine)) {
            # Reemplazar solo la primera ocurrencia despues de "system.ftpServer"
            $idx = $content.IndexOf('<sectionGroup name="system.ftpServer"')
            if ($idx -ge 0) {
                $before  = $content.Substring(0, $idx)
                $after   = $content.Substring($idx)
                $after   = $after.Replace($oldLine, $newLine)
                $content = $before + $after
                [System.IO.File]::WriteAllText($ahConfig, $content, [System.Text.Encoding]::UTF8)
                Write-Host "  [OK] applicationHost.config actualizado (overrideModeDefault=Allow)." -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  [~] applicationHost.config ya tiene Allow o el formato difiere, continuando..." -ForegroundColor DarkGray
        }
    }

    # ── Paso 2: Reiniciar IIS para que lea el config actualizado ──
    & iisreset /noforce 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    # ── Paso 3: Limpiar reglas previas e insertar las nuevas con appcmd ──
    & $appcmd clear config "FTP" /section:system.ftpServer/security/authorization 2>&1 | Out-Null

    # Regla 1: usuario anonimo - solo lectura
    & $appcmd set config "FTP" /section:system.ftpServer/security/authorization `
        "/+[accessType='Allow',users='anonimo',roles='',permissions='Read']" 2>&1 | Out-Null

    # Regla 2: grupos autenticados - lectura y escritura
    & $appcmd set config "FTP" /section:system.ftpServer/security/authorization `
        "/+[accessType='Allow',users='',roles='Reprobados,Recursadores',permissions='Read, Write']" 2>&1 | Out-Null

    # Regla 3: denegar todo lo demas
    & $appcmd set config "FTP" /section:system.ftpServer/security/authorization `
        "/+[accessType='Deny',users='*',roles='',permissions='Read, Write']" 2>&1 | Out-Null

    Write-Host "  [OK] Reglas de autorizacion aplicadas." -ForegroundColor Green
}

# ─────────────────────────────────────────────
#  INSTALACION
# ─────────────────────────────────────────────

function Install-FtpDaemon {
    Write-Host "Instalando dependencias de FTP..." -ForegroundColor Cyan

    foreach ($f in @("Web-Server","Web-FTP-Service","Web-FTP-Server","Web-Basic-Auth")) {
        $feat = Get-WindowsFeature -Name $f
        if (-not $feat.Installed) {
            Install-WindowsFeature $f -IncludeAllSubFeature | Out-Null
            Write-Host "  [OK] $f instalado." -ForegroundColor Green
        } else {
            Write-Host "  [~] $f ya instalado." -ForegroundColor DarkGray
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
            Write-Host "  [OK] Firewall '$($rule.Name)' creado." -ForegroundColor Green
        } else {
            Write-Host "  [~] Firewall '$($rule.Name)' ya existe." -ForegroundColor DarkGray
        }
    }

    # Estructura de directorios
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

    icacls $script:FtpRootPath /grant "SYSTEM:(OI)(CI)F"          | Out-Null
    icacls $script:FtpRootPath /grant "${adminGroup}:(OI)(CI)F"   | Out-Null
    icacls $script:FtpRootPath /grant "IUSR:(OI)(CI)RX"           | Out-Null
    icacls $script:FtpRootPath /grant "IIS_IUSRS:(OI)(CI)RX"      | Out-Null

    icacls $script:LocalUserPath /grant "SYSTEM:(OI)(CI)F"         | Out-Null
    icacls $script:LocalUserPath /grant "${adminGroup}:(OI)(CI)F"  | Out-Null
    icacls $script:LocalUserPath /grant "IUSR:(OI)(CI)RX"          | Out-Null
    icacls $script:LocalUserPath /grant "IIS_IUSRS:(OI)(CI)RX"     | Out-Null
    icacls $script:LocalUserPath /grant "Users:(RX)"               | Out-Null

    icacls $script:PublicPath /inheritance:r                       | Out-Null
    icacls $script:PublicPath /grant "SYSTEM:(OI)(CI)F"            | Out-Null
    icacls $script:PublicPath /grant "${adminGroup}:(OI)(CI)F"     | Out-Null
    icacls $script:PublicPath /grant "IUSR:(OI)(CI)RX"             | Out-Null
    icacls $script:PublicPath /grant "IIS_IUSRS:(OI)(CI)RX"        | Out-Null

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
        Write-Host "  [~] Sitio FTP actualizado." -ForegroundColor DarkGray
    }

    # IsolateAllDirectories: home = C:\FTP\LocalUser\<usuario>\
    Set-WebConfigurationProperty `
        -Filter "/system.applicationHost/sites/site[@name='FTP']/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateAllDirectories"

    # Basic Auth activado, anonimo desactivado
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
}

# ─────────────────────────────────────────────
#  GRUPOS
# ─────────────────────────────────────────────

function Initialize-FtpGroups {
    Write-Host "Configurando grupos FTP..." -ForegroundColor Cyan

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
            Write-Host "  [~] Grupo '$gName' ya existe." -ForegroundColor DarkGray
        }

        if (-not (Test-Path $gPath)) {
            New-Item -ItemType Directory -Path $gPath -Force | Out-Null
        }

        $adminGroup = Get-AdminGroupName
        icacls $gPath /inheritance:r                        | Out-Null
        icacls $gPath /grant "SYSTEM:(OI)(CI)F"            | Out-Null
        icacls $gPath /grant "${adminGroup}:(OI)(CI)F"     | Out-Null
        icacls $gPath /grant "IIS_IUSRS:(OI)(CI)RX"        | Out-Null
        icacls $gPath /grant "${gName}:(OI)(CI)M"          | Out-Null
        Write-Host "  [OK] Permisos en: $gPath" -ForegroundColor DarkGray
    }

    icacls $script:GeneralPath /grant "Reprobados:(OI)(CI)M"   | Out-Null
    icacls $script:GeneralPath /grant "Recursadores:(OI)(CI)M" | Out-Null
}

# ─────────────────────────────────────────────
#  VERIFICACION
# ─────────────────────────────────────────────

function Get-FtpInstallation {
    Write-Host "Verificando instalacion de FTP Server..."
    $feature = Get-WindowsFeature -Name "Web-FTP-Service"
    if ($feature.Installed) {
        Write-Host "  [OK] Web-FTP-Service instalado." -ForegroundColor Green
    } else {
        Write-Host "  [Error] Web-FTP-Service NO instalado." -ForegroundColor Red
    }
    Get-FtpConfiguration
}

function Get-FtpConfiguration {
    Write-Host ""
    Write-Host "Verificando configuracion..." -ForegroundColor Cyan

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
        Write-Host "  [!] ftpsvc detenido o no instalado." -ForegroundColor Yellow
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
    Write-Host "  IP    : $ip" -ForegroundColor Cyan
    Write-Host "  Puerto: 21"  -ForegroundColor Cyan
}

# ─────────────────────────────────────────────
#  CREAR USUARIO (interno)
# ─────────────────────────────────────────────

function New-FtpUser {
    param(
        [string]$Username,
        [string]$Password,
        [string]$Group
    )

    if ($null -eq $global:ADSI) {
        $global:ADSI = [ADSI]"WinNT://$env:ComputerName"
    }

    try {
        $user = $global:ADSI.Create("User", $Username)
        $user.SetInfo()
        $user.SetPassword($Password)
        $user.psbase.InvokeSet("UserFlags", 0x10200)  # NORMAL_ACCOUNT | DONT_EXPIRE_PASSWD
        $user.SetInfo()
        Write-Host "  [OK] Usuario '$Username' creado." -ForegroundColor Green
    } catch {
        Write-Host "  [Error] No se pudo crear '$Username': $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    try { Set-LocalUser -Name $Username -PasswordNeverExpires $true -ErrorAction Stop } catch {}

    Add-LocalGroupMember -Group $Group -Member $Username -ErrorAction SilentlyContinue

    # Estructura IsolateAllDirectories:
    #   C:\FTP\LocalUser\<user>\         <- chroot raiz (IIS aterriza aqui)
    #   C:\FTP\LocalUser\<user>\<user>\  <- carpeta personal (Modify)
    #   C:\FTP\LocalUser\<user>\General  <- symlink -> GeneralPath
    #   C:\FTP\LocalUser\<user>\<Grupo>  <- symlink -> carpeta del grupo
    $userRoot    = "$script:LocalUserPath\$Username"
    $personalDir = "$userRoot\$Username"

    New-Item -Path $userRoot    -ItemType Directory -Force | Out-Null
    New-Item -Path $personalDir -ItemType Directory -Force | Out-Null

    Set-UserRootPermissions -Username $Username -UserRoot $userRoot -PersonalDir $personalDir

    New-SymbolicLink -Path "$userRoot\General" -Target $script:GeneralPath          -Directory
    New-SymbolicLink -Path "$userRoot\$Group"  -Target "$script:FtpRootPath\$Group" -Directory

    if (-not (Select-String -Path $script:UserListPath -Pattern "^$Username$" -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -Path $script:UserListPath -Value $Username
    }

    Write-Host "  [OK] '$Username' registrado en grupo '$Group'." -ForegroundColor Green
}

# ─────────────────────────────────────────────
#  LISTAR USUARIOS
# ─────────────────────────────────────────────

function Get-FtpUsers {
    Write-Host ""
    Write-Host "Usuarios FTP registrados:" -ForegroundColor Cyan
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
            if (Get-LocalGroupMember -Group "Reprobados" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$u" }) { $group = "Reprobados" }
            elseif (Get-LocalGroupMember -Group "Recursadores" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$u" }) { $group = "Recursadores" }
        } catch {}
        Write-Host ("  {0,-20} -> {1}" -f $u, $group)
    }
    Write-Host "**********************"
}

# ─────────────────────────────────────────────
#  REPARAR USUARIO EXISTENTE (fix 530)
# ─────────────────────────────────────────────

function Repair-FtpUser {
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

    foreach ($dir in @($userRoot, $personalDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "  [OK] Creado: $dir" -ForegroundColor Green
        }
    }

    Set-UserRootPermissions -Username $Username -UserRoot $userRoot -PersonalDir $personalDir
    New-SymbolicLink -Path "$userRoot\General" -Target $script:GeneralPath          -Directory
    New-SymbolicLink -Path "$userRoot\$grupo"  -Target "$script:FtpRootPath\$grupo" -Directory

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
    if (-not $actual) {
        Write-Host "  [Error] '$FTPUserName' no pertenece a ningun grupo FTP." -ForegroundColor Red
        return
    }
    if ($actual -eq $NuevoGrupo) {
        Write-Host "  [~] '$FTPUserName' ya pertenece a '$NuevoGrupo'." -ForegroundColor DarkGray
        return
    }

    $userRoot = "$script:LocalUserPath\$FTPUserName"

    Remove-LocalGroupMember -Group $actual     -Member $FTPUserName -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $NuevoGrupo -Member $FTPUserName -ErrorAction SilentlyContinue

    $oldLink = "$userRoot\$actual"
    if (Test-Path $oldLink) {
        $item = Get-Item $oldLink -Force -ErrorAction SilentlyContinue
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$oldLink`"" 2>$null | Out-Null
        } else {
            Remove-Item $oldLink -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    New-SymbolicLink -Path "$userRoot\$NuevoGrupo" `
                     -Target "$script:FtpRootPath\$NuevoGrupo" -Directory

    $personalDir = "$userRoot\$FTPUserName"
    Set-UserRootPermissions -Username $FTPUserName -UserRoot $userRoot -PersonalDir $personalDir

    Restart-WebItem "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
    Write-Host "  [OK] '$FTPUserName' cambiado a '$NuevoGrupo'." -ForegroundColor Green
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
        if (Get-LocalGroupMember -Group "Reprobados" -ErrorAction SilentlyContinue |
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
        elseif (Invoke-UsuarioExiste $c)         { Write-Host "  [!] Usuario '$c' ya existe."      -ForegroundColor Yellow }
        else { return $c }
    } while ($true)
}

function Invoke-CapturarContra {
    $regex = "^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[^a-zA-Z0-9]).{8,15}$"
    do {
        $c = Read-Host "  Contrasena (8-15 chars, May, min, num, especial)"
        if ($c -notmatch $regex) {
            Write-Host "  [!] Debe tener mayuscula, minuscula, numero y caracter especial (8-15 chars)." -ForegroundColor Yellow
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
        $g = Read-Host "  Opcion [1/2]"
        if ($g -eq "1") { return "Reprobados"   }
        if ($g -eq "2") { return "Recursadores" }
        Write-Host "  [!] Ingrese 1 o 2." -ForegroundColor Yellow
    } while ($true)
}