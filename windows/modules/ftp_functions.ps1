# =============================================================================
# ftp_functions.ps1 - Funciones del Servidor FTP para Windows Server 2022
# Equivalente a ftp_functions.sh (Fedora/vsftpd) => Windows Server / IIS FTP
# =============================================================================
# NOTA: Este archivo debe ser dot-sourced por menu_ftp.ps1.
# Las variables $FTP_* son globales para que todas las funciones las compartan
# incluso al ser llamadas desde otro script (main.ps1 -> menu_ftp.ps1 -> aquí).
# =============================================================================

# Rutas globales del servicio FTP
$global:FTP_ROOT       = "C:\inetpub\ftproot"
$global:FTP_GENERAL    = "$global:FTP_ROOT\general"
$global:FTP_GROUPS     = "$global:FTP_ROOT\groups"
$global:FTP_USERS_DIR  = "$global:FTP_ROOT\users"
$global:FTP_ANON_DIR   = "$global:FTP_ROOT\anonymous"
$global:FTP_SITE_NAME  = "ServicioFTP"
$global:FTP_PORT       = 21

# ============================================================
# FUNCIÓN: Inicializar-SistemaFTP
# Equivalente a: inicializar_sistema()
# ============================================================
function global:Inicializar-SistemaFTP {
    Write-Host "`n[+] Inicializando sistema FTP en Windows Server 2022..." -ForegroundColor Cyan

    # 1. Verificar que IIS FTP esté instalado
    $ftpFeature = Get-WindowsFeature -Name "Web-Ftp-Server" -ErrorAction SilentlyContinue
    if (!$ftpFeature -or $ftpFeature.InstallState -ne "Installed") {
        Write-Host "[!] El rol IIS-FTP no está instalado. Usa la opción 1 del menú para instalarlo primero." -ForegroundColor Red
        return
    }

    # 2. Importar módulo WebAdministration
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (!(Get-Module -Name WebAdministration)) {
        Write-Host "[!] No se pudo cargar WebAdministration. Verifica que IIS esté instalado." -ForegroundColor Red
        return
    }

    # 3. Crear estructura de directorios
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

    # 4. Crear grupos locales
    foreach ($grp in @("reprobados","recursadores","ftp-users")) {
        if (!(Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grp -Description "Grupo FTP: $grp" | Out-Null
            Write-Host "    Grupo creado: $grp" -ForegroundColor DarkGray
        }
    }

    # 5. Permisos sobre \general (ftp-users -> Modificar/RW)
    Set-PermisosDirectorio -Path $global:FTP_GENERAL -Group "ftp-users" -Rights "Modify" -Inherit $true

    # 6. Junction: \anonymous\general -> \general (solo lectura anónimo)
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

    # 7. Crear / reconfigurar sitio FTP en IIS
    Configurar-SitioIISFTP

    # 8. Reglas de Firewall
    Configurar-FirewallFTP

    # 9. Arrancar servicio
    Start-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    Set-Service   -Name "ftpsvc" -StartupType Automatic

    Write-Host "[✓] Sistema FTP inicializado correctamente." -ForegroundColor Green
}

# ============================================================
# FUNCIÓN: Configurar-SitioIISFTP  (interna)
# ============================================================
function global:Configurar-SitioIISFTP {
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar sitio previo para reconfigurar limpiamente
    if (Get-WebSite -Name $global:FTP_SITE_NAME -ErrorAction SilentlyContinue) {
        Remove-WebSite -Name $global:FTP_SITE_NAME
    }

    # Crear nuevo sitio FTP apuntando a la raíz
    New-WebFtpSite -Name $global:FTP_SITE_NAME -Port $global:FTP_PORT `
                   -PhysicalPath $global:FTP_ROOT -Force | Out-Null

    # Autenticación: básica (usuarios locales) + anónima
    Set-ItemProperty "IIS:\Sites\$global:FTP_SITE_NAME" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$global:FTP_SITE_NAME" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

    # Puertos pasivos 40000-40010
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" -PSPath "IIS:\" `
        -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" -PSPath "IIS:\" `
        -Name "highDataChannelPort" -Value 40010

    # SSL desactivado (modo Allow = opcional, no requerido)
    Set-ItemProperty "IIS:\Sites\$global:FTP_SITE_NAME" `
        -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$global:FTP_SITE_NAME" `
        -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"

    # Aislamiento de usuarios: cada usuario autenticado cae en
    # \users\<usuario>\LocalUser\<usuario>\  (IIS FTP User Isolation)
    # El anónimo cae en \anonymous\
    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/sites/site[@name='$global:FTP_SITE_NAME']/ftpServer/userIsolation" `
        -PSPath "IIS:\" -Name "mode" -Value "IsolateAllDirectories"

    # Regla de autorización: anónimo solo lectura
    Add-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$global:FTP_SITE_NAME" -Name "." `
        -Value @{accessType="Allow"; users="?"; permissions="Read"} `
        -ErrorAction SilentlyContinue

    # Regla de autorización: ftp-users lectura + escritura
    Add-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$global:FTP_SITE_NAME" -Name "." `
        -Value @{accessType="Allow"; roles="ftp-users"; permissions="Read,Write"} `
        -ErrorAction SilentlyContinue

    Write-Host "    Sitio IIS-FTP '$global:FTP_SITE_NAME' configurado en puerto $global:FTP_PORT." -ForegroundColor DarkGray
}

# ============================================================
# FUNCIÓN: Configurar-FirewallFTP
# Equivalente a: configurar_seguridad_ftp()
# ============================================================
function global:Configurar-FirewallFTP {
    Write-Host "[+] Configurando reglas de Firewall..." -ForegroundColor Cyan
    $rules = @(
        @{Name="FTP-Control"; Protocol="TCP"; Port="21"},
        @{Name="FTP-Pasivo";  Protocol="TCP"; Port="40000-40010"}
    )
    foreach ($r in $rules) {
        if (!(Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.Name -Direction Inbound `
                -Protocol $r.Protocol -LocalPort $r.Port -Action Allow | Out-Null
            Write-Host "    Regla creada: $($r.Name) (puerto $($r.Port))" -ForegroundColor DarkGray
        } else {
            Write-Host "    Regla ya existe: $($r.Name)" -ForegroundColor DarkGray
        }
    }
    Write-Host "[✓] Firewall configurado." -ForegroundColor Green
}

# ============================================================
# FUNCIÓN: Crear-UsuarioFTP
# Equivalente a: crear_usuario()
# ============================================================
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

    # Denegar inicio de sesión interactivo (equivalente a nologin)
    Deny-InteractiveLogon -Usuario $Usuario

    # Crear estructura de carpetas FTP del usuario
    Configurar-EstructuraUsuario -Usuario $Usuario -Grupo $Grupo

    Write-Host "[✓] Usuario '$Usuario' creado en grupo '$Grupo'." -ForegroundColor Green
}

# ============================================================
# FUNCIÓN: Configurar-EstructuraUsuario  (interna)
# Estructura bajo \users\<usuario>\LocalUser\<usuario>\:
#   general\    -> Junction a \general\         (RW, compartida todos)
#   <grupo>\    -> Junction a \groups\<grupo>\  (RW, compartida grupo)
#   <usuario>\  -> Carpeta personal exclusiva
# ============================================================
function global:Configurar-EstructuraUsuario {
    param(
        [string]$Usuario,
        [string]$Grupo
    )

    # IIS FTP User Isolation requiere la ruta: <raiz>\LocalUser\<nombre>\
    $userLocal   = "$global:FTP_USERS_DIR\$Usuario\LocalUser\$Usuario"
    $genLink     = "$userLocal\general"
    $groupLink   = "$userLocal\$Grupo"
    $personalDir = "$userLocal\$Usuario"

    New-Item -ItemType Directory -Path $userLocal -Force | Out-Null

    # Junction: general (compartida con todos)
    if (!(Test-Path $genLink)) {
        cmd /c "mklink /J `"$genLink`" `"$global:FTP_GENERAL`"" | Out-Null
    }

    # Junction: carpeta de grupo
    $groupSrc = "$global:FTP_GROUPS\$Grupo"
    if (!(Test-Path $groupSrc)) { New-Item -ItemType Directory -Path $groupSrc -Force | Out-Null }
    if (!(Test-Path $groupLink)) {
        cmd /c "mklink /J `"$groupLink`" `"$groupSrc`"" | Out-Null
    }

    # Carpeta personal: solo el dueño tiene control total
    if (!(Test-Path $personalDir)) {
        New-Item -ItemType Directory -Path $personalDir -Force | Out-Null
    }
    $acl = Get-Acl $personalDir
    $acl.SetAccessRuleProtection($true, $false)  # deshabilitar herencia
    $ownerAccount = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $Usuario)
    $ruleOwner = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $ownerAccount, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($ruleOwner)
    # Admins también necesitan acceso para administrar
    $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($ruleAdmin)
    Set-Acl -Path $personalDir -AclObject $acl

    # Permisos de grupo sobre la carpeta de grupo
    Set-PermisosDirectorio -Path $groupSrc -Group $Grupo -Rights "Modify" -Inherit $true

    Write-Host "    Estructura creada para '$Usuario': general/, $Grupo/, $Usuario/" -ForegroundColor DarkGray
}

# ============================================================
# FUNCIÓN: Modificar-GrupoUsuarioFTP
# Equivalente a: modificar_grupo_usuario()
# ============================================================
function global:Modificar-GrupoUsuarioFTP {
    param(
        [Parameter(Mandatory)][string]$Usuario,
        [Parameter(Mandatory)][ValidateSet("reprobados","recursadores")][string]$NuevoGrupo
    )

    if (!(Get-LocalUser -Name $Usuario -ErrorAction SilentlyContinue)) {
        Write-Host "[!] El usuario '$Usuario' no existe." -ForegroundColor Red
        return
    }

    # Quitar de grupos académicos anteriores
    foreach ($g in @("reprobados","recursadores")) {
        Remove-LocalGroupMember -Group $g -Member $Usuario -ErrorAction SilentlyContinue
    }

    Add-LocalGroupMember -Group $NuevoGrupo -Member $Usuario -ErrorAction SilentlyContinue

    # Eliminar junction de grupo anterior (sin borrar contenido real)
    $userLocal = "$global:FTP_USERS_DIR\$Usuario\LocalUser\$Usuario"
    foreach ($g in @("reprobados","recursadores")) {
        $linkPath = "$userLocal\$g"
        if (Test-Path $linkPath) {
            cmd /c "rmdir `"$linkPath`"" 2>$null
        }
    }

    # Reconfigurar con el nuevo grupo
    Configurar-EstructuraUsuario -Usuario $Usuario -Grupo $NuevoGrupo

    Write-Host "[✓] Usuario '$Usuario' movido a grupo '$NuevoGrupo'." -ForegroundColor Green
}

# ============================================================
# FUNCIÓN: Verificar-ServicioFTP
# Equivalente a: verificar_servicio_ftp()
# ============================================================
function global:Verificar-ServicioFTP {
    Write-Host "`n--- [ DIAGNOSTICO DEL SERVICIO FTP ] ---" -ForegroundColor Cyan

    # Estado del servicio
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    Write-Host "Estado servicio: " -NoNewline
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "[ EN EJECUCION ]" -ForegroundColor Green
    } elseif ($svc) {
        Write-Host "[ DETENIDO ]" -ForegroundColor Red
    } else {
        Write-Host "[ NO INSTALADO ]" -ForegroundColor Red
    }

    # Puertos escuchando
    Write-Host "Puertos FTP:     " -NoNewline
    $listening = netstat -ano 2>$null | Select-String "(:21\s|:400[0-9]{2}\s)"
    if ($listening) {
        Write-Host "Puerto 21 y/o pasivos activos" -ForegroundColor Green
    } else {
        Write-Host "Ninguno detectado" -ForegroundColor Yellow
    }

    # Junction anónima
    Write-Host "Junction anon:   " -NoNewline
    $anonJ = "$global:FTP_ANON_DIR\general"
    if ((Test-Path $anonJ) -and ((Get-Item $anonJ -Force).Attributes -match "ReparsePoint")) {
        Write-Host "[ OK - Junction activa ]" -ForegroundColor Green
    } else {
        Write-Host "[ FALLO o no existe ]" -ForegroundColor Red
    }

    # IP del servidor
    Write-Host "IP del servidor: " -NoNewline
    $ips = Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\." } |
           Select-Object -ExpandProperty IPAddress
    Write-Host ($ips -join ", ") -ForegroundColor Blue

    # Sitio IIS FTP
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $site = Get-WebSite -Name $global:FTP_SITE_NAME -ErrorAction SilentlyContinue
    Write-Host "Sitio IIS-FTP:   " -NoNewline
    if ($site) {
        $color = if ($site.State -eq "Started") { "Green" } else { "Red" }
        Write-Host "[ $($site.State.ToUpper()) ] - Puerto $global:FTP_PORT" -ForegroundColor $color
    } else {
        Write-Host "[ NO CONFIGURADO - Use opcion 6 ]" -ForegroundColor Red
    }

    # Carpetas
    Write-Host "Carpeta general: " -NoNewline
    if (Test-Path $global:FTP_GENERAL) { Write-Host "[ OK ] $global:FTP_GENERAL" -ForegroundColor Green }
    else { Write-Host "[ NO EXISTE ]" -ForegroundColor Red }

    Write-Host "---------------------------------------"
}

# ============================================================
# FUNCIÓN: Listar-UsuariosFTP
# Equivalente a: listar_usuarios_ftp()
# ============================================================
function global:Listar-UsuariosFTP {
    Write-Host "`n--- [ USUARIOS REGISTRADOS EN FTP ] ---" -ForegroundColor Cyan
    Write-Host ("{0,-20} | {1,-20}" -f "USUARIO", "GRUPO ACADEMICO")
    Write-Host ("-" * 48)

    $miembros = Get-LocalGroupMember -Group "ftp-users" -ErrorAction SilentlyContinue
    if (!$miembros) {
        Write-Host "No hay usuarios registrados aun."
    } else {
        foreach ($m in $miembros) {
            $nombre = $m.Name -replace ".*\\", ""
            $grupo  = "General / Sin Grupo"
            foreach ($g in @("reprobados","recursadores")) {
                $enGrupo = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue |
                           Where-Object { ($_.Name -replace ".*\\","") -eq $nombre }
                if ($enGrupo) { $grupo = $g; break }
            }
            Write-Host ("{0,-20} | {1,-20}" -f $nombre, $grupo)
        }
    }
    Write-Host ("-" * 48)
}

# ============================================================
# HELPER: Set-PermisosDirectorio
# ============================================================
function global:Set-PermisosDirectorio {
    param(
        [string]$Path,
        [string]$Group,
        [string]$Rights  = "Modify",
        [bool]  $Inherit = $true
    )
    $acl         = Get-Acl -Path $Path
    $inheritFlag = if ($Inherit) { "ContainerInherit,ObjectInherit" } else { "None" }

    # Intentar primero con prefijo de equipo local
    $ok = $false
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
        Write-Host "    [!] No se pudo aplicar ACL sobre '$Path' para '$Group'" -ForegroundColor Yellow
    }
}

# ============================================================
# HELPER: Deny-InteractiveLogon
# Equivalente a: shell=/sbin/nologin
# ============================================================
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
