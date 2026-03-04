# =============================================================================
# ftp_functions.ps1 - TODAS las funciones del Servidor FTP
# Windows Server 2022 / IIS FTP
# Todas las funciones son global: para que estén disponibles desde cualquier
# script que haga dot-source de este archivo (main.ps1 -> menu_ftp.ps1 -> aquí)
# =============================================================================

$global:FTP_ROOT      = "C:\inetpub\ftproot"
$global:FTP_GENERAL   = "$global:FTP_ROOT\general"
$global:FTP_GROUPS    = "$global:FTP_ROOT\groups"
$global:FTP_USERS_DIR = "$global:FTP_ROOT\users"
$global:FTP_ANON_DIR  = "$global:FTP_ROOT\anonymous"
$global:FTP_SITE_NAME = "ServicioFTP"
$global:FTP_PORT      = 21

# ─────────────────────────────────────────────────────────────
# Instalar-ServicioFTP
# Instala los roles IIS + FTP en Windows Server 2022
# ─────────────────────────────────────────────────────────────
function global:Instalar-ServicioFTP {
    Write-Host "`n[+] Instalando rol de Servidor FTP en Windows Server 2022..." -ForegroundColor Cyan

    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                 [Security.Principal.WindowsBuiltInRole]"Administrator")
    if (!$esAdmin) {
        Write-Host "[ERROR] Ejecuta PowerShell como Administrador." -ForegroundColor Red
        return
    }

    $features = @(
        @{Name="Web-Server";       Desc="IIS (Servidor Web base)"},
        @{Name="Web-Ftp-Server";   Desc="Servidor FTP"},
        @{Name="Web-Ftp-Service";  Desc="Servicio FTP"},
        @{Name="Web-Mgmt-Console"; Desc="Consola de administracion IIS"}
    )

    $reinicioRequerido = $false
    foreach ($f in $features) {
        $feat = Get-WindowsFeature -Name $f.Name -ErrorAction SilentlyContinue
        if ($feat -and $feat.InstallState -eq "Installed") {
            Write-Host "  [✓] Ya instalado:  $($f.Desc)" -ForegroundColor DarkGray
        } else {
            Write-Host "  [~] Instalando:    $($f.Desc)..." -ForegroundColor Yellow
            $result = Install-WindowsFeature -Name $f.Name -IncludeManagementTools
            if ($result.Success) {
                Write-Host "  [✓] Instalado:     $($f.Desc)" -ForegroundColor Green
                if ($result.RestartNeeded -eq "Yes") { $reinicioRequerido = $true }
            } else {
                Write-Host "  [!] FALLO:         $($f.Desc)" -ForegroundColor Red
            }
        }
    }

    # Arrancar servicio
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name "ftpsvc" -StartupType Automatic
        if ($svc.Status -ne "Running") {
            Start-Service -Name "ftpsvc"
            Write-Host "  [✓] Servicio ftpsvc iniciado." -ForegroundColor Green
        } else {
            Write-Host "  [✓] Servicio ftpsvc ya en ejecucion." -ForegroundColor Green
        }
    } else {
        Write-Host "  [!] ftpsvc no encontrado aun (puede requerir reinicio)." -ForegroundColor Yellow
    }

    # Cargar módulo WebAdministration
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (Get-Module -Name WebAdministration) {
        Write-Host "  [✓] Modulo WebAdministration cargado." -ForegroundColor Green
    } else {
        Write-Host "  [!] WebAdministration no disponible aun." -ForegroundColor Yellow
    }

    if ($reinicioRequerido) {
        Write-Host "`n[!] Se requiere REINICIAR para completar la instalacion." -ForegroundColor Yellow
        $resp = Read-Host "Reiniciar ahora? (s/n)"
        if ($resp -eq "s") { Restart-Computer -Force }
    } else {
        Write-Host "`n[✓] Instalacion completada. Usa la opcion 6 del menu FTP para inicializar." -ForegroundColor Green
    }
}

# ─────────────────────────────────────────────────────────────
# Inicializar-SistemaFTP
# Crea carpetas, grupos, junctions, sitio IIS y firewall
# ─────────────────────────────────────────────────────────────
function global:Inicializar-SistemaFTP {
    Write-Host "`n[+] Inicializando sistema FTP..." -ForegroundColor Cyan

    # Verificar rol instalado
    $ftpFeature = Get-WindowsFeature -Name "Web-Ftp-Server" -ErrorAction SilentlyContinue
    if (!$ftpFeature -or $ftpFeature.InstallState -ne "Installed") {
        Write-Host "[!] Rol IIS-FTP no instalado. Usa la opcion 1 del menu primero." -ForegroundColor Red
        return
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (!(Get-Module -Name WebAdministration)) {
        Write-Host "[!] No se pudo cargar WebAdministration." -ForegroundColor Red
        return
    }

    # Crear estructura de directorios
    $dirs = @(
        $global:FTP_ROOT,
        $global:FTP_GENERAL,
        $global:FTP_GROUPS,
        "$global:FTP_GROUPS\reprobados",
        "$global:FTP_GROUPS\recursadores",
        $global:FTP_USERS_DIR,
        $global:FTP_ANON_DIR
    )
    foreach ($d in $dirs) {
        if (!(Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Write-Host "    Creado: $d" -ForegroundColor DarkGray
        }
    }

    # Crear grupos locales
    foreach ($grp in @("reprobados","recursadores","ftp-users")) {
        if (!(Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grp -Description "Grupo FTP: $grp" | Out-Null
            Write-Host "    Grupo creado: $grp" -ForegroundColor DarkGray
        }
    }

    # Permisos carpeta general (ftp-users RW)
    Set-PermisosDirectorio -Path $global:FTP_GENERAL -Group "ftp-users" -Rights "Modify" -Inherit $true

    # Junction anónima: \anonymous\general -> \general (solo lectura)
    $junctionTarget = "$global:FTP_ANON_DIR\general"
    if (Test-Path $junctionTarget) {
        $item = Get-Item $junctionTarget -Force
        if ($item.Attributes -notmatch "ReparsePoint") {
            Remove-Item $junctionTarget -Recurse -Force
            cmd /c "mklink /J `"$junctionTarget`" `"$global:FTP_GENERAL`"" | Out-Null
        }
    } else {
        cmd /c "mklink /J `"$junctionTarget`" `"$global:FTP_GENERAL`"" | Out-Null
    }
    Write-Host "    Junction anon: $junctionTarget => $global:FTP_GENERAL" -ForegroundColor DarkGray

    Configurar-SitioIISFTP
    Configurar-FirewallFTP

    Start-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    Set-Service   -Name "ftpsvc" -StartupType Automatic

    Write-Host "[✓] Sistema FTP inicializado correctamente." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# Configurar-SitioIISFTP  (llamada desde Inicializar-SistemaFTP)
# ─────────────────────────────────────────────────────────────
function global:Configurar-SitioIISFTP {
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    if (Get-WebSite -Name $global:FTP_SITE_NAME -ErrorAction SilentlyContinue) {
        Remove-WebSite -Name $global:FTP_SITE_NAME
    }

    New-WebFtpSite -Name $global:FTP_SITE_NAME -Port $global:FTP_PORT `
                   -PhysicalPath $global:FTP_ROOT -Force | Out-Null

    # Autenticación básica + anónima
    Set-ItemProperty "IIS:\Sites\$global:FTP_SITE_NAME" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$global:FTP_SITE_NAME" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

    # Puertos pasivos
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" -PSPath "IIS:\" `
        -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" -PSPath "IIS:\" `
        -Name "highDataChannelPort" -Value 40010

    # SSL opcional
    Set-ItemProperty "IIS:\Sites\$global:FTP_SITE_NAME" `
        -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$global:FTP_SITE_NAME" `
        -Name ftpServer.security.ssl.dataChannelPolicy    -Value "SslAllow"

    # Aislamiento de usuarios por directorio
    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/sites/site[@name='$global:FTP_SITE_NAME']/ftpServer/userIsolation" `
        -PSPath "IIS:\" -Name "mode" -Value "IsolateAllDirectories"

    # Autorización: anónimo = solo lectura
    Add-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$global:FTP_SITE_NAME" -Name "." `
        -Value @{accessType="Allow"; users="?"; permissions="Read"} `
        -ErrorAction SilentlyContinue

    # Autorización: ftp-users = lectura + escritura
    Add-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$global:FTP_SITE_NAME" -Name "." `
        -Value @{accessType="Allow"; roles="ftp-users"; permissions="Read,Write"} `
        -ErrorAction SilentlyContinue

    Write-Host "    Sitio IIS-FTP '$global:FTP_SITE_NAME' configurado (puerto $global:FTP_PORT)." -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────────────────────
# Configurar-FirewallFTP
# ─────────────────────────────────────────────────────────────
function global:Configurar-FirewallFTP {
    Write-Host "[+] Configurando Firewall..." -ForegroundColor Cyan
    $rules = @(
        @{Name="FTP-Control"; Protocol="TCP"; Port="21"},
        @{Name="FTP-Pasivo";  Protocol="TCP"; Port="40000-40010"}
    )
    foreach ($r in $rules) {
        if (!(Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.Name -Direction Inbound `
                -Protocol $r.Protocol -LocalPort $r.Port -Action Allow | Out-Null
            Write-Host "    Regla creada: $($r.Name) ($($r.Port))" -ForegroundColor DarkGray
        } else {
            Write-Host "    Regla ya existe: $($r.Name)" -ForegroundColor DarkGray
        }
    }
    Write-Host "[✓] Firewall configurado." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# Crear-UsuarioFTP
# ─────────────────────────────────────────────────────────────
function global:Crear-UsuarioFTP {
    param(
        [Parameter(Mandatory)][string]$Usuario,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][ValidateSet("reprobados","recursadores")][string]$Grupo
    )

    if (Get-LocalUser -Name $Usuario -ErrorAction SilentlyContinue) {
        Write-Host "[!] El usuario '$Usuario' ya existe." -ForegroundColor Yellow
        return
    }

    $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Usuario -Password $secPass `
        -PasswordNeverExpires:$true -UserMayNotChangePassword:$false `
        -Description "Usuario FTP - Grupo: $Grupo" | Out-Null

    Add-LocalGroupMember -Group "ftp-users" -Member $Usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $Grupo      -Member $Usuario -ErrorAction SilentlyContinue

    Deny-InteractiveLogon -Usuario $Usuario
    Configurar-EstructuraUsuario -Usuario $Usuario -Grupo $Grupo

    Write-Host "[✓] Usuario '$Usuario' creado en grupo '$Grupo'." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# Configurar-EstructuraUsuario  (llamada desde Crear y Modificar)
# Estructura IIS User Isolation: \users\<u>\LocalUser\<u>\
#   general\   -> Junction a \general\        (RW todos)
#   <grupo>\   -> Junction a \groups\<grupo>\ (RW grupo)
#   <usuario>\ -> Carpeta personal exclusiva
# ─────────────────────────────────────────────────────────────
function global:Configurar-EstructuraUsuario {
    param(
        [string]$Usuario,
        [string]$Grupo
    )

    $userLocal   = "$global:FTP_USERS_DIR\$Usuario\LocalUser\$Usuario"
    $genLink     = "$userLocal\general"
    $groupLink   = "$userLocal\$Grupo"
    $personalDir = "$userLocal\$Usuario"

    New-Item -ItemType Directory -Path $userLocal -Force | Out-Null

    # Junction: carpeta general compartida
    if (!(Test-Path $genLink)) {
        cmd /c "mklink /J `"$genLink`" `"$global:FTP_GENERAL`"" | Out-Null
    }

    # Junction: carpeta de grupo
    $groupSrc = "$global:FTP_GROUPS\$Grupo"
    if (!(Test-Path $groupSrc)) { New-Item -ItemType Directory -Path $groupSrc -Force | Out-Null }
    if (!(Test-Path $groupLink)) {
        cmd /c "mklink /J `"$groupLink`" `"$groupSrc`"" | Out-Null
    }

    # Carpeta personal: solo el dueño + Administradores
    if (!(Test-Path $personalDir)) {
        New-Item -ItemType Directory -Path $personalDir -Force | Out-Null
    }
    $acl = Get-Acl $personalDir
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($entry in @(
        @{Account="$env:COMPUTERNAME\$Usuario"; Rights="FullControl"},
        @{Account="BUILTIN\Administrators";     Rights="FullControl"}
    )) {
        try {
            $acctObj = New-Object System.Security.Principal.NTAccount($entry.Account)
            $rule    = New-Object System.Security.AccessControl.FileSystemAccessRule(
                           $acctObj, $entry.Rights, "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.AddAccessRule($rule)
        } catch { }
    }
    Set-Acl -Path $personalDir -AclObject $acl

    # Permisos de escritura en carpeta de grupo
    Set-PermisosDirectorio -Path $groupSrc -Group $Grupo -Rights "Modify" -Inherit $true

    Write-Host "    Estructura lista para '$Usuario': general\ | $Grupo\ | $Usuario\" -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────────────────────
# Modificar-GrupoUsuarioFTP
# ─────────────────────────────────────────────────────────────
function global:Modificar-GrupoUsuarioFTP {
    param(
        [Parameter(Mandatory)][string]$Usuario,
        [Parameter(Mandatory)][ValidateSet("reprobados","recursadores")][string]$NuevoGrupo
    )

    if (!(Get-LocalUser -Name $Usuario -ErrorAction SilentlyContinue)) {
        Write-Host "[!] El usuario '$Usuario' no existe." -ForegroundColor Red
        return
    }

    foreach ($g in @("reprobados","recursadores")) {
        Remove-LocalGroupMember -Group $g -Member $Usuario -ErrorAction SilentlyContinue
    }
    Add-LocalGroupMember -Group $NuevoGrupo -Member $Usuario -ErrorAction SilentlyContinue

    # Eliminar junction del grupo anterior sin borrar contenido real
    $userLocal = "$global:FTP_USERS_DIR\$Usuario\LocalUser\$Usuario"
    foreach ($g in @("reprobados","recursadores")) {
        $linkPath = "$userLocal\$g"
        if (Test-Path $linkPath) {
            cmd /c "rmdir `"$linkPath`"" 2>$null
        }
    }

    Configurar-EstructuraUsuario -Usuario $Usuario -Grupo $NuevoGrupo
    Write-Host "[✓] Usuario '$Usuario' movido al grupo '$NuevoGrupo'." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# Verificar-ServicioFTP
# ─────────────────────────────────────────────────────────────
function global:Verificar-ServicioFTP {
    Write-Host "`n--- [ DIAGNOSTICO DEL SERVICIO FTP ] ---" -ForegroundColor Cyan

    # Servicio
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    Write-Host "Servicio ftpsvc: " -NoNewline
    if      ($svc -and $svc.Status -eq "Running") { Write-Host "[ EN EJECUCION ]" -ForegroundColor Green  }
    elseif  ($svc)                                { Write-Host "[ DETENIDO ]"     -ForegroundColor Red    }
    else                                          { Write-Host "[ NO INSTALADO ]" -ForegroundColor Red    }

    # Puertos
    Write-Host "Puertos FTP:     " -NoNewline
    $listening = netstat -ano 2>$null | Select-String "(:21\s|:400[0-9]{2}\s)"
    if ($listening) { Write-Host "Puerto 21 y/o pasivos activos" -ForegroundColor Green }
    else            { Write-Host "Ninguno detectado"             -ForegroundColor Yellow }

    # Junction anónima
    Write-Host "Junction anon:   " -NoNewline
    $anonJ = "$global:FTP_ANON_DIR\general"
    if ((Test-Path $anonJ) -and ((Get-Item $anonJ -Force).Attributes -match "ReparsePoint")) {
        Write-Host "[ OK ]" -ForegroundColor Green
    } else {
        Write-Host "[ FALLO o no existe ]" -ForegroundColor Red
    }

    # IP
    Write-Host "IP del servidor: " -NoNewline
    $ips = Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\." } |
           Select-Object -ExpandProperty IPAddress
    Write-Host ($ips -join ", ") -ForegroundColor Blue

    # Sitio IIS
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $site = Get-WebSite -Name $global:FTP_SITE_NAME -ErrorAction SilentlyContinue
    Write-Host "Sitio IIS-FTP:   " -NoNewline
    if ($site) {
        $color = if ($site.State -eq "Started") { "Green" } else { "Red" }
        Write-Host "[ $($site.State.ToUpper()) ] puerto $global:FTP_PORT" -ForegroundColor $color
    } else {
        Write-Host "[ NO CONFIGURADO ]" -ForegroundColor Red
    }

    # Carpeta general
    Write-Host "Carpeta general: " -NoNewline
    if (Test-Path $global:FTP_GENERAL) { Write-Host "[ OK ] $global:FTP_GENERAL" -ForegroundColor Green }
    else                               { Write-Host "[ NO EXISTE ]"               -ForegroundColor Red   }

    Write-Host "----------------------------------------"
}

# ─────────────────────────────────────────────────────────────
# Listar-UsuariosFTP
# ─────────────────────────────────────────────────────────────
function global:Listar-UsuariosFTP {
    Write-Host "`n--- [ USUARIOS REGISTRADOS EN FTP ] ---" -ForegroundColor Cyan
    Write-Host ("{0,-20} | {1,-20}" -f "USUARIO", "GRUPO ACADEMICO")
    Write-Host ("-" * 45)

    $miembros = Get-LocalGroupMember -Group "ftp-users" -ErrorAction SilentlyContinue
    if (!$miembros) {
        Write-Host "No hay usuarios registrados aun."
    } else {
        foreach ($m in $miembros) {
            $nombre = $m.Name -replace ".*\\", ""
            $grupo  = "Sin Grupo"
            foreach ($g in @("reprobados","recursadores")) {
                $found = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue |
                         Where-Object { ($_.Name -replace ".*\\","") -eq $nombre }
                if ($found) { $grupo = $g; break }
            }
            Write-Host ("{0,-20} | {1,-20}" -f $nombre, $grupo)
        }
    }
    Write-Host ("-" * 45)
}

# ─────────────────────────────────────────────────────────────
# Set-PermisosDirectorio  (helper)
# ─────────────────────────────────────────────────────────────
function global:Set-PermisosDirectorio {
    param(
        [string]$Path,
        [string]$Group,
        [string]$Rights  = "Modify",
        [bool]  $Inherit = $true
    )
    $acl         = Get-Acl -Path $Path
    $inheritFlag = if ($Inherit) { "ContainerInherit,ObjectInherit" } else { "None" }
    $ok          = $false

    foreach ($accountName in @("$env:COMPUTERNAME\$Group", $Group)) {
        try {
            $account = New-Object System.Security.Principal.NTAccount($accountName)
            $rule    = New-Object System.Security.AccessControl.FileSystemAccessRule(
                           $account, $Rights, $inheritFlag, "None", "Allow")
            $acl.AddAccessRule($rule)
            Set-Acl -Path $Path -AclObject $acl
            $ok = $true
            break
        } catch { }
    }
    if (!$ok) {
        Write-Host "    [!] No se pudo aplicar ACL en '$Path' para '$Group'" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────
# Deny-InteractiveLogon  (helper - equivalente a nologin)
# ─────────────────────────────────────────────────────────────
function global:Deny-InteractiveLogon {
    param([string]$Usuario)
    try {
        $sid    = (Get-LocalUser -Name $Usuario).SID.Value
        $tmpInf = [System.IO.Path]::GetTempFileName() + ".inf"
        $tmpDb  = [System.IO.Path]::GetTempFileName() + ".sdb"
        @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
[Privilege Rights]
SeDenyInteractiveLogonRight = *$sid
"@ | Set-Content -Path $tmpInf -Encoding Unicode
        secedit /configure /db $tmpDb /cfg $tmpInf /quiet 2>$null
        Remove-Item $tmpInf, $tmpDb -ErrorAction SilentlyContinue
    } catch {
        Write-Host "    [!] No se pudo denegar logon para '$Usuario'" -ForegroundColor Yellow
    }
}
