# =====================================================
# ftp_functions.ps1 - FUNCIONES TECNICAS SERVICIO FTP
# Windows Server 2022 / IIS FTP
# =====================================================

$basePath    = "C:\inetpub\ftproot"
$ftpSiteName = "FTPServer_Practica"
$appcmd      = "$env:windir\system32\inetsrv\appcmd.exe"

# ─────────────────────────────────────────────────────
# Install-FTPService
# Instala los roles IIS + FTP si no están presentes
# ─────────────────────────────────────────────────────
function Install-FTPService {
    Write-Host "`n[+] Instalando rol IIS + FTP..." -ForegroundColor Cyan

    $features = @(
        @{Name="Web-Server";       Desc="IIS (base)"},
        @{Name="Web-Ftp-Server";   Desc="Servidor FTP"},
        @{Name="Web-Ftp-Service";  Desc="Servicio FTP"},
        @{Name="Web-Mgmt-Console"; Desc="Consola IIS"}
    )

    $needRestart = $false
    foreach ($f in $features) {
        $feat = Get-WindowsFeature -Name $f.Name -ErrorAction SilentlyContinue
        if ($feat -and $feat.InstallState -eq "Installed") {
            Write-Host "  [✓] Ya instalado: $($f.Desc)" -ForegroundColor DarkGray
        } else {
            Write-Host "  [~] Instalando:   $($f.Desc)..." -ForegroundColor Yellow
            $r = Install-WindowsFeature -Name $f.Name -IncludeManagementTools
            if ($r.Success) {
                Write-Host "  [✓] Listo:        $($f.Desc)" -ForegroundColor Green
                if ($r.RestartNeeded -eq "Yes") { $needRestart = $true }
            } else {
                Write-Host "  [!] FALLO:        $($f.Desc)" -ForegroundColor Red
            }
        }
    }

    # Arrancar servicio
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name "ftpsvc" -StartupType Automatic
        if ($svc.Status -ne "Running") {
            Start-Service "ftpsvc"
            Write-Host "  [✓] Servicio ftpsvc iniciado." -ForegroundColor Green
        } else {
            Write-Host "  [✓] Servicio ftpsvc ya en ejecucion." -ForegroundColor Green
        }
    } else {
        Write-Host "  [!] ftpsvc no encontrado aun (reinicio puede ser necesario)." -ForegroundColor Yellow
    }

    if ($needRestart) {
        Write-Host "`n[!] Se requiere REINICIAR para completar la instalacion." -ForegroundColor Yellow
        $resp = Read-Host "Reiniciar ahora? (s/n)"
        if ($resp -eq "s") { Restart-Computer -Force }
    } else {
        Write-Host "`n[✓] Instalacion completada. Ejecuta 'Configurar Servicio' (opcion 2)." -ForegroundColor Green
    }
}

# ─────────────────────────────────────────────────────
# Configure-FTPEnvironment
# Crea estructura de carpetas, sitio IIS-FTP y permisos.
#
# Estructura visible por cada usuario autenticado:
#   [raiz del usuario en FTP]
#   ├── general\      ← carpeta física compartida (todos RW)
#   ├── reprobados\   ← carpeta física compartida (solo grupo)
#   ├── recursadores\ ← carpeta física compartida (solo grupo)
#   └── <usuario>\    ← carpeta personal exclusiva
#
# El usuario anónimo ve SOLO general\ en modo lectura.
# NO se usa User Isolation de IIS: todos aterrizan en ftproot
# y los permisos NTFS controlan qué pueden ver/hacer.
# ─────────────────────────────────────────────────────
function Configure-FTPEnvironment {
    Write-Host "`n[*] Configurando entorno FTP..." -ForegroundColor Yellow

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (!(Get-Module -Name WebAdministration)) {
        Write-Host "[!] No se pudo cargar WebAdministration. Instala IIS primero (opcion 1)." -ForegroundColor Red
        return
    }

    # Detener servicio para evitar bloqueos
    Stop-Service ftpsvc -ErrorAction SilentlyContinue

    # Eliminar sitio previo si existe
    if (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue) {
        Remove-WebSite -Name $ftpSiteName
    }

    # ── Crear carpetas base ──────────────────────────
    $dirs = @($basePath,
              "$basePath\general",
              "$basePath\reprobados",
              "$basePath\recursadores")
    foreach ($d in $dirs) {
        if (!(Test-Path $d)) {
            New-Item -Path $d -ItemType Directory -Force | Out-Null
            Write-Host "    Creado: $d" -ForegroundColor DarkGray
        }
    }

    # ── Crear grupos locales ─────────────────────────
    foreach ($grp in @("reprobados","recursadores")) {
        if (!(Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grp -Description "Grupo FTP $grp" | Out-Null
            Write-Host "    Grupo creado: $grp" -ForegroundColor DarkGray
        }
    }

    # ── Crear sitio FTP en IIS ───────────────────────
    # SIN User Isolation: todos aterrizan en ftproot, NTFS filtra el acceso
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath -Force | Out-Null
    Start-Sleep -Seconds 2

    # Autenticación anónima + básica
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # SSL opcional
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.ssl.dataChannelPolicy    -Value "SslAllow"

    # Puertos pasivos
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" -PSPath "IIS:\" `
        -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" -PSPath "IIS:\" `
        -Name "highDataChannelPort" -Value 40010

    # Reglas de autorización IIS (NTFS es la barrera real, esto es capa extra)
    & $appcmd set config "$ftpSiteName" -section:system.ftpServer/security/authorization `
        /+"[accessType='Allow',users='anonymous',permissions='Read']" /commit:apphost 2>$null
    & $appcmd set config "$ftpSiteName" -section:system.ftpServer/security/authorization `
        /+"[accessType='Allow',roles='Users',permissions='Read,Write']" /commit:apphost 2>$null

    # ── Permisos NTFS ────────────────────────────────

    # Raíz: solo listar (no RW) — usuarios ven las carpetas al entrar
    takeown /f $basePath /r /d y 2>$null | Out-Null
    icacls $basePath /inheritance:r                       | Out-Null
    icacls $basePath /grant "Administrators:(OI)(CI)F"    | Out-Null
    icacls $basePath /grant "SYSTEM:(OI)(CI)F"            | Out-Null
    # Users puede listar la raíz pero NO heredar permisos a subcarpetas
    # (las subcarpetas tienen sus propias ACLs)
    icacls $basePath /grant "Users:(RX)"                  | Out-Null
    # IUSR es la cuenta del usuario anónimo de IIS
    icacls $basePath /grant "IUSR:(RX)"                   | Out-Null

    # General: todos los usuarios autenticados + anónimo pueden leer y escribir
    # El anónimo (IUSR) solo lee — se restringe a nivel IIS con la regla de arriba
    icacls "$basePath\general" /inheritance:r                     | Out-Null
    icacls "$basePath\general" /grant "Administrators:(OI)(CI)F"  | Out-Null
    icacls "$basePath\general" /grant "SYSTEM:(OI)(CI)F"          | Out-Null
    icacls "$basePath\general" /grant "Users:(OI)(CI)M"           | Out-Null
    # IUSR = anónimo: solo listar y leer, SIN escribir
    icacls "$basePath\general" /grant "IUSR:(OI)(CI)RX"           | Out-Null

    # Reprobados / Recursadores: por defecto nadie entra (se activa al crear usuarios)
    foreach ($grp in @("reprobados","recursadores")) {
        icacls "$basePath\$grp" /inheritance:r                    | Out-Null
        icacls "$basePath\$grp" /grant "Administrators:(OI)(CI)F" | Out-Null
        icacls "$basePath\$grp" /grant "SYSTEM:(OI)(CI)F"         | Out-Null
        # Los miembros del grupo pueden leer y modificar
        icacls "$basePath\$grp" /grant "${grp}:(OI)(CI)M"         | Out-Null
    }

    # ── Firewall ─────────────────────────────────────
    foreach ($rule in @(
        @{Name="FTP-Control"; Port="21"},
        @{Name="FTP-Pasivo";  Port="40000-40010"}
    )) {
        if (!(Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound `
                -Protocol TCP -LocalPort $rule.Port -Action Allow | Out-Null
            Write-Host "    Regla firewall creada: $($rule.Name)" -ForegroundColor DarkGray
        }
    }

    Start-Service ftpsvc
    Write-Host "`n[✓] Entorno FTP configurado correctamente en $basePath" -ForegroundColor Green
    Write-Host "    Anonimo: acceso de SOLO LECTURA a \general" -ForegroundColor DarkGray
    Write-Host "    Usuarios: ven \general (RW), \<grupo> (RW), \<usuario> (personal)" -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────────────
# Add-MassiveUsers
# Crea N usuarios con carpeta personal + permisos
# ─────────────────────────────────────────────────────
function Add-MassiveUsers {
    $n_input = Read-Host "Numero de usuarios a crear"
    $n = 0
    if (!([int]::TryParse($n_input, [ref]$n)) -or $n -lt 1) {
        Write-Host "[!] Numero invalido." -ForegroundColor Red
        return
    }

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Usuario $i de $n ---" -ForegroundColor DarkCyan
        $userName    = Read-Host "  Nombre de usuario"
        $passwordRaw = Read-Host "  Password"
        $password    = $passwordRaw | ConvertTo-SecureString -AsPlainText -Force
        $grupo       = ""
        while ($grupo -notin @("reprobados","recursadores")) {
            $grupo = Read-Host "  Grupo (reprobados / recursadores)"
        }

        # Crear grupo local si no existe
        if (!(Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grupo | Out-Null
        }

        # Crear usuario local si no existe
        if (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue) {
            Write-Host "  [!] Usuario '$userName' ya existe, se omite creacion." -ForegroundColor Yellow
        } else {
            New-LocalUser -Name $userName -Password $password `
                -PasswordNeverExpires:$true -Description "FTP - $grupo" | Out-Null
            Add-LocalGroupMember -Group "Users"  -Member $userName -ErrorAction SilentlyContinue
            Add-LocalGroupMember -Group $grupo   -Member $userName -ErrorAction SilentlyContinue
            Write-Host "  [✓] Usuario '$userName' creado." -ForegroundColor Green
        }

        # ── Carpeta personal del usuario ──────────────
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) {
            New-Item -Path $userPath -ItemType Directory -Force | Out-Null
        }
        # Solo el dueño y Admins tienen acceso
        icacls $userPath /inheritance:r                        | Out-Null
        icacls $userPath /grant "Administrators:(OI)(CI)F"     | Out-Null
        icacls $userPath /grant "SYSTEM:(OI)(CI)F"             | Out-Null
        icacls $userPath /grant "${userName}:(OI)(CI)M"        | Out-Null

        # ── Asegurar permisos en carpeta de grupo ─────
        # (ya creada en Configure-FTPEnvironment, pero por si acaso)
        $grupoPath = Join-Path $basePath $grupo
        if (!(Test-Path $grupoPath)) {
            New-Item -Path $grupoPath -ItemType Directory -Force | Out-Null
        }
        icacls $grupoPath /grant "${grupo}:(OI)(CI)M" | Out-Null

        Write-Host "  [✓] '$userName' listo. Ve: \general, \$grupo, \$userName" -ForegroundColor Green
    }
}

# ─────────────────────────────────────────────────────
# Update-UserGroup
# Cambia el grupo académico de un usuario
# ─────────────────────────────────────────────────────
function Update-UserGroup {
    $user       = Read-Host "Usuario a mover"
    $nuevoGrupo = ""
    while ($nuevoGrupo -notin @("reprobados","recursadores")) {
        $nuevoGrupo = Read-Host "Nuevo grupo (reprobados / recursadores)"
    }

    if (!(Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
        Write-Host "[!] El usuario '$user' no existe." -ForegroundColor Red
        return
    }

    # Quitar de grupos anteriores
    foreach ($g in @("reprobados","recursadores")) {
        Remove-LocalGroupMember -Group $g -Member $user -ErrorAction SilentlyContinue
    }

    # Asignar nuevo grupo
    if (!(Get-LocalGroup -Name $nuevoGrupo -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $nuevoGrupo | Out-Null
    }
    Add-LocalGroupMember -Group $nuevoGrupo -Member $user -ErrorAction SilentlyContinue

    # Refrescar permisos de la carpeta del nuevo grupo
    $grupoPath = Join-Path $basePath $nuevoGrupo
    if (!(Test-Path $grupoPath)) {
        New-Item -Path $grupoPath -ItemType Directory -Force | Out-Null
    }
    icacls $grupoPath /grant "${nuevoGrupo}:(OI)(CI)M" | Out-Null

    Write-Host "[✓] '$user' movido a '$nuevoGrupo'. FileZilla actualizara al reconectar." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────
# Show-FTPUsers
# Lista usuarios locales con su grupo FTP
# ─────────────────────────────────────────────────────
function Show-FTPUsers {
    Write-Host "`n--- [ USUARIOS FTP ] ---" -ForegroundColor Cyan
    Write-Host ("{0,-20} | {1,-15} | {2}" -f "USUARIO", "GRUPO", "HABILITADO")
    Write-Host ("-" * 52)

    $todos = Get-LocalUser | Where-Object { $_.Name -notin @("Administrator","DefaultAccount","Guest","WDAGUtilityAccount") }

    if (!$todos) {
        Write-Host "No hay usuarios registrados."
    } else {
        foreach ($u in $todos) {
            $grupo = "Sin grupo"
            foreach ($g in @("reprobados","recursadores")) {
                $found = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue |
                         Where-Object { ($_.Name -replace ".*\\","") -eq $u.Name }
                if ($found) { $grupo = $g; break }
            }
            Write-Host ("{0,-20} | {1,-15} | {2}" -f $u.Name, $grupo, $u.Enabled)
        }
    }
    Write-Host ("-" * 52)
}
