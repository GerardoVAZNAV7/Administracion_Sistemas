# =============================================================================
# ftp_functions.ps1 - Funciones del Servidor FTP para Windows Server 2022
# Equivalente a ftp_functions.sh (Fedora/vsftpd) => Windows Server / IIS FTP
# =============================================================================

# Rutas globales del servicio FTP
$FTP_ROOT       = "C:\inetpub\ftproot"
$FTP_GENERAL    = "$FTP_ROOT\general"
$FTP_GROUPS     = "$FTP_ROOT\groups"
$FTP_USERS_DIR  = "$FTP_ROOT\users"
$FTP_ANON_DIR   = "$FTP_ROOT\anonymous"
$FTP_SITE_NAME  = "ServicioFTP"
$FTP_PORT       = 21

# ============================================================
# FUNCIÓN: Inicializar-SistemaFTP
# Equivalente a: inicializar_sistema()
# ============================================================
function Inicializar-SistemaFTP {
    Write-Host "`n[+] Inicializando sistema FTP en Windows Server 2022..." -ForegroundColor Cyan

    # 1. Instalar IIS y el rol de FTP si no están presentes
    $features = @("Web-Ftp-Server", "Web-Ftp-Service", "Web-Server")
    foreach ($f in $features) {
        $state = (Get-WindowsFeature -Name $f).InstallState
        if ($state -ne "Installed") {
            Write-Host "    Instalando feature: $f ..."
            Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
        }
    }

    # 2. Importar módulos WebAdministration
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # 3. Crear estructura de directorios
    $dirs = @($FTP_ROOT, $FTP_GENERAL, $FTP_GROUPS,
              "$FTP_GROUPS\reprobados", "$FTP_GROUPS\recursadores",
              $FTP_USERS_DIR, $FTP_ANON_DIR, "$FTP_ANON_DIR\general")
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

    # 5. Configurar permisos sobre \general  (ftp-users -> Modificar/RW)
    Set-PermisosDirectorio -Path $FTP_GENERAL -Group "ftp-users" -Rights "Modify" -Inherit $true

    # 6. Configurar permisos sobre \anonymous\general (solo lectura para todos)
    #    Se usa una Junction Point para que apunte al mismo contenido que \general
    $junctionTarget = "$FTP_ANON_DIR\general"
    if (Test-Path $junctionTarget) {
        # Si ya es junction, nada; si es carpeta normal, convertirla
        $item = Get-Item $junctionTarget -Force
        if ($item.Attributes -notmatch "ReparsePoint") {
            Remove-Item $junctionTarget -Recurse -Force
            cmd /c "mklink /J `"$junctionTarget`" `"$FTP_GENERAL`"" | Out-Null
        }
    } else {
        cmd /c "mklink /J `"$junctionTarget`" `"$FTP_GENERAL`"" | Out-Null
    }
    Write-Host "    Junction: $junctionTarget => $FTP_GENERAL" -ForegroundColor DarkGray

    # 7. Crear / reconfigurar sitio FTP en IIS
    Configurar-SitioIISFTP

    # 8. Reglas de Firewall
    Configurar-FirewallFTP

    # 9. Iniciar servicio FTP
    Start-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    Set-Service  -Name "ftpsvc" -StartupType Automatic

    Write-Host "[✓] Sistema FTP inicializado correctamente." -ForegroundColor Green
}

# ============================================================
# FUNCIÓN: Configurar-SitioIISFTP  (privada, llamada desde Inicializar)
# ============================================================
function Configurar-SitioIISFTP {
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar sitio previo si existe para reconfigurar limpiamente
    if (Get-WebSite -Name $FTP_SITE_NAME -ErrorAction SilentlyContinue) {
        Remove-WebSite -Name $FTP_SITE_NAME
    }

    # Crear nuevo sitio FTP
    New-WebFtpSite -Name $FTP_SITE_NAME -Port $FTP_PORT -PhysicalPath $FTP_ROOT -Force | Out-Null

    # Habilitar autenticación básica (usuarios locales) y anónima
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name ftpServer.security.authentication.basicAuthentication.enabled  -Value $true
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

    # Modo pasivo: puertos 40000-40010
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" -PSPath "IIS:\" `
        -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" -PSPath "IIS:\" `
        -Name "highDataChannelPort" -Value 40010

    # SSL: desactivado (equivalente a vsftpd sin SSL)
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" -Name ftpServer.security.ssl.dataChannelPolicy    -Value "SslAllow"

    # Aislamiento de usuarios: cada usuario cae en su carpeta bajo \users\<usuario>
    # El usuario anónimo cae en \anonymous
    Set-WebConfigurationProperty -Filter "system.applicationHost/sites/site[@name='$FTP_SITE_NAME']/ftpServer/userIsolation" `
        -PSPath "IIS:\" -Name "mode" -Value "IsolateAllDirectories"

    # Autorización: anónimo solo lectura sobre \anonymous
    Add-WebConfigurationProperty -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$FTP_SITE_NAME" -Name "." `
        -Value @{accessType="Allow"; users="?"; permissions="Read"} -ErrorAction SilentlyContinue

    # Autorización: usuarios autenticados lectura+escritura en sus carpetas
    Add-WebConfigurationProperty -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$FTP_SITE_NAME" -Name "." `
        -Value @{accessType="Allow"; roles="ftp-users"; permissions="Read,Write"} -ErrorAction SilentlyContinue

    Write-Host "    Sitio IIS-FTP '$FTP_SITE_NAME' configurado." -ForegroundColor DarkGray
}

# ============================================================
# FUNCIÓN: Configurar-FirewallFTP
# Equivalente a: configurar_seguridad_ftp()
# ============================================================
function Configurar-FirewallFTP {
    Write-Host "[+] Configurando reglas de Firewall..." -ForegroundColor Cyan

    $rules = @(
        @{Name="FTP-Control";  Protocol="TCP"; Port="21"},
        @{Name="FTP-Pasivo";   Protocol="TCP"; Port="40000-40010"}
    )
    foreach ($r in $rules) {
        if (!(Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.Name -Direction Inbound `
                -Protocol $r.Protocol -LocalPort $r.Port -Action Allow | Out-Null
            Write-Host "    Regla creada: $($r.Name) ($($r.Port))" -ForegroundColor DarkGray
        }
    }
    Write-Host "[✓] Firewall configurado." -ForegroundColor Green
}

# ============================================================
# FUNCIÓN: Crear-UsuarioFTP
# Equivalente a: crear_usuario()
# ============================================================
function Crear-UsuarioFTP {
    param(
        [Parameter(Mandatory)][string]$Usuario,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][ValidateSet("reprobados","recursadores")][string]$Grupo
    )

    # Verificar si ya existe
    if (Get-LocalUser -Name $Usuario -ErrorAction SilentlyContinue) {
        Write-Host "[!] El usuario '$Usuario' ya existe." -ForegroundColor Yellow
        return
    }

    # Crear usuario local (sin logon interactivo: equivalente a nologin)
    $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Usuario -Password $secPass `
        -PasswordNeverExpires:$true -UserMayNotChangePassword:$false `
        -Description "Usuario FTP - Grupo: $Grupo" | Out-Null

    # Agregar a ftp-users (grupo primario funcional) y al grupo académico
    Add-LocalGroupMember -Group "ftp-users"  -Member $Usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $Grupo       -Member $Usuario -ErrorAction SilentlyContinue

    # Denegar inicio de sesión interactivo (equivalente a /sbin/nologin)
    Deny-InteractiveLogon -Usuario $Usuario

    # Crear estructura de carpetas del usuario dentro de \users\<usuario>
    Configurar-EstructuraUsuario -Usuario $Usuario -Grupo $Grupo

    Write-Host "[✓] Usuario '$Usuario' creado y configurado en grupo '$Grupo'." -ForegroundColor Green
}

# ============================================================
# FUNCIÓN: Configurar-EstructuraUsuario  (privada)
# Crea y vincula las carpetas del usuario bajo \users\<usuario>
#   \users\<usuario>\               <- raíz FTP del usuario (IIS isolation)
#   \users\<usuario>\general\       <- Junction => \general  (RW compartido)
#   \users\<usuario>\<grupo>\       <- Junction => \groups\<grupo>  (RW por grupo)
#   \users\<usuario>\<usuario>\     <- Carpeta personal exclusiva
# ============================================================
function Configurar-EstructuraUsuario {
    param(
        [string]$Usuario,
        [string]$Grupo
    )

    $userRoot   = "$FTP_USERS_DIR\$Usuario"
    $userLocal  = "$userRoot\LocalUser\$Usuario"  # IIS FTP isolation path
    $genLink    = "$userLocal\general"
    $groupLink  = "$userLocal\$Grupo"
    $personalDir= "$userLocal\$Usuario"

    # Crear raíz del usuario (IIS FTP isolation requiere LocalUser\<nombre>)
    New-Item -ItemType Directory -Path $userLocal -Force | Out-Null

    # --- Junction: general (compartida con todos) ---
    if (!(Test-Path $genLink)) {
        cmd /c "mklink /J `"$genLink`" `"$FTP_GENERAL`"" | Out-Null
    }

    # --- Junction: carpeta de grupo ---
    $groupSrc = "$FTP_GROUPS\$Grupo"
    if (!(Test-Path $groupSrc)) { New-Item -ItemType Directory -Path $groupSrc -Force | Out-Null }
    if (!(Test-Path $groupLink)) {
        cmd /c "mklink /J `"$groupLink`" `"$groupSrc`"" | Out-Null
    }

    # --- Carpeta personal del usuario ---
    if (!(Test-Path $personalDir)) {
        New-Item -ItemType Directory -Path $personalDir -Force | Out-Null
    }

    # Permisos sobre carpeta personal: solo el dueño puede escribir
    Set-PermisosDirectorio -Path $personalDir -Group $Usuario -Rights "Modify" -Inherit $true
    # Revocar escritura para ftp-users en carpeta personal
    $acl = Get-Acl $personalDir
    $acl.SetAccessRuleProtection($true, $false)
    $ownerSid = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $Usuario)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $ownerSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)
    Set-Acl -Path $personalDir -AclObject $acl

    # Asegurar permisos de escritura sobre la carpeta de grupo
    Set-PermisosDirectorio -Path $groupSrc -Group $Grupo -Rights "Modify" -Inherit $true
}

# ============================================================
# FUNCIÓN: Modificar-GrupoUsuarioFTP
# Equivalente a: modificar_grupo_usuario()
# ============================================================
function Modificar-GrupoUsuarioFTP {
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

    # Asignar nuevo grupo académico
    Add-LocalGroupMember -Group $NuevoGrupo -Member $Usuario -ErrorAction SilentlyContinue

    # Limpiar junctions de grupo en el home FTP del usuario
    $userLocal = "$FTP_USERS_DIR\$Usuario\LocalUser\$Usuario"
    foreach ($g in @("reprobados","recursadores")) {
        $linkPath = "$userLocal\$g"
        if (Test-Path $linkPath) {
            # Eliminar junction (rmdir sin /s para no borrar contenido real)
            cmd /c "rmdir `"$linkPath`"" 2>$null
        }
    }

    # Reconfigurar con el nuevo grupo
    Configurar-EstructuraUsuario -Usuario $Usuario -Grupo $NuevoGrupo

    Write-Host "[✓] Usuario '$Usuario' movido al grupo '$NuevoGrupo' con éxito." -ForegroundColor Green
}

# ============================================================
# FUNCIÓN: Verificar-ServicioFTP
# Equivalente a: verificar_servicio_ftp()
# ============================================================
function Verificar-ServicioFTP {
    Write-Host "`n--- [ DIAGNÓSTICO DEL SERVICIO FTP ] ---" -ForegroundColor Cyan

    # 1. Estado del servicio
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "Estado:          " -NoNewline; Write-Host "[ EN EJECUCION ]" -ForegroundColor Green
    } else {
        Write-Host "Estado:          " -NoNewline; Write-Host "[ DETENIDO ]" -ForegroundColor Red
    }

    # 2. Puertos escuchando
    Write-Host "Puertos activos: " -NoNewline
    $ports = netstat -ano | Select-String ":21 |:400[0-9]{2} " | ForEach-Object { $_.ToString().Trim() }
    if ($ports) { $ports | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
    else { Write-Host "Ninguno detectado" -ForegroundColor Yellow }

    # 3. Junction anónima
    Write-Host "Carpeta anon:    " -NoNewline
    $anonJunction = "$FTP_ANON_DIR\general"
    if ((Test-Path $anonJunction) -and ((Get-Item $anonJunction -Force).Attributes -match "ReparsePoint")) {
        Write-Host "[ OK - Junction activa ]" -ForegroundColor Green
    } else {
        Write-Host "[ FALLO - no es Junction ]" -ForegroundColor Red
    }

    # 4. IP del servidor
    Write-Host "IP del servidor: " -NoNewline
    $ips = Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\." } |
           Select-Object -ExpandProperty IPAddress
    Write-Host ($ips -join ", ") -ForegroundColor Blue

    # 5. Sitio IIS FTP
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $site = Get-WebSite -Name $FTP_SITE_NAME -ErrorAction SilentlyContinue
    Write-Host "Sitio IIS-FTP:   " -NoNewline
    if ($site) {
        Write-Host "[ $($site.State.ToUpper()) ] - Puerto $FTP_PORT" -ForegroundColor $(if ($site.State -eq "Started") { "Green" } else { "Red" })
    } else {
        Write-Host "[ NO ENCONTRADO ]" -ForegroundColor Red
    }

    Write-Host "---------------------------------------"
}

# ============================================================
# FUNCIÓN: Listar-UsuariosFTP
# Equivalente a: listar_usuarios_ftp()
# ============================================================
function Listar-UsuariosFTP {
    Write-Host "`n--- [ USUARIOS REGISTRADOS EN FTP ] ---" -ForegroundColor Cyan
    Write-Host ("{0,-20} | {1,-20}" -f "USUARIO", "GRUPO ACADEMICO")
    Write-Host ("─" * 48)

    $miembros = Get-LocalGroupMember -Group "ftp-users" -ErrorAction SilentlyContinue
    if (!$miembros) {
        Write-Host "No hay usuarios registrados aún."
    } else {
        foreach ($m in $miembros) {
            $nombre = $m.Name -replace ".*\\", ""  # quitar dominio/equipo
            $grupo = "General / Sin Grupo"
            foreach ($g in @("reprobados","recursadores")) {
                $enGrupo = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue |
                           Where-Object { ($_.Name -replace ".*\\","") -eq $nombre }
                if ($enGrupo) { $grupo = $g; break }
            }
            Write-Host ("{0,-20} | {1,-20}" -f $nombre, $grupo)
        }
    }
    Write-Host ("─" * 48)
}

# ============================================================
# FUNCIÓN: Set-PermisosDirectorio  (helper interno)
# Aplica ACL de grupo a un directorio con herencia opcional
# ============================================================
function Set-PermisosDirectorio {
    param(
        [string]$Path,
        [string]$Group,
        [string]$Rights = "Modify",
        [bool]$Inherit = $true
    )
    $acl = Get-Acl -Path $Path
    $inherit = if ($Inherit) { "ContainerInherit,ObjectInherit" } else { "None" }
    try {
        $account = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $Group)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $account, $Rights, $inherit, "None", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl
    } catch {
        # Puede que sea un usuario de dominio o cuenta built-in; intentar sin prefijo de equipo
        try {
            $account = New-Object System.Security.Principal.NTAccount($Group)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $account, $Rights, $inherit, "None", "Allow")
            $acl.AddAccessRule($rule)
            Set-Acl -Path $Path -AclObject $acl
        } catch {
            Write-Host "    [!] No se pudo aplicar ACL a $Path para $Group" -ForegroundColor Yellow
        }
    }
}

# ============================================================
# FUNCIÓN: Deny-InteractiveLogon  (helper interno)
# Deniega inicio de sesión interactivo al usuario (equiv. nologin)
# ============================================================
function Deny-InteractiveLogon {
    param([string]$Usuario)
    try {
        $policy = "Deny log on locally"
        $sid = (Get-LocalUser -Name $Usuario).SID.Value
        # Usar secedit para denegar logon local
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
        Write-Host "    [!] No se pudo denegar logon interactivo para $Usuario" -ForegroundColor Yellow
    }
}
