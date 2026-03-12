Import-Module WebAdministration

$Global:BASE_DATA  = "C:\inetpub\ftproot"
$Global:FTP_ROOT   = "C:\FTP_Users"
$Global:LOCAL_USER = "$Global:FTP_ROOT\LocalUser"
$Global:SITE_NAME  = "ServidorPracticas"

function Instalar_Requisitos {
    Write-Host "[+] Verificando roles de Windows..." -ForegroundColor Cyan
    $features = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service")
    foreach ($f in $features) {
        $state = (Get-WindowsFeature -Name $f).InstallState
        if ($state -ne "Installed") {
            Write-Host "[+] Instalando $f..."
            Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
            Write-Host "[OK] $f instalado." -ForegroundColor Green
        } else {
            Write-Host "[OK] $f ya instalado." -ForegroundColor Green
        }
    }
    Import-Module WebAdministration -ErrorAction Stop
}

function Configurar_Servicio_FTP {
    Instalar_Requisitos

    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

    Write-Host "[+] Configurando estructura de directorios..."
    foreach ($dir in @("general", "reprobados", "recursadores")) {
        $path = Join-Path $Global:BASE_DATA $dir
        if (!(Test-Path $path)) { New-Item $path -ItemType Directory -Force | Out-Null }
    }

    if (!(Test-Path $Global:LOCAL_USER)) {
        New-Item $Global:LOCAL_USER -ItemType Directory -Force | Out-Null
    }

    $AnonPath = Join-Path $Global:LOCAL_USER "Public"
    if (!(Test-Path $AnonPath)) {
        New-Item $AnonPath -ItemType Directory -Force | Out-Null
    }
    if (!(Test-Path "$AnonPath\general")) {
        cmd /c "mklink /D `"$AnonPath\general`" `"$Global:BASE_DATA\general`"" | Out-Null
    }

    Write-Host "[+] Archivo de bienvenida..."
    $welcome = Join-Path $Global:BASE_DATA "general\LEEME.txt"
    if (!(Test-Path $welcome)) {
        "Bienvenido al servidor FTP Publico" | Out-File $welcome -Encoding UTF8
    }

    Write-Host "[+] Creando grupos locales..."
    foreach ($g in @("reprobados", "recursadores")) {
        if (!(Get-LocalGroup $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $g | Out-Null
            Write-Host "[+] Grupo $g creado." -ForegroundColor Green
        } else {
            Write-Host "[OK] Grupo $g ya existe." -ForegroundColor Green
        }
    }

    Write-Host "[+] Configurando sitio FTP en IIS..."
    if (!(Get-Website -Name $Global:SITE_NAME -ErrorAction SilentlyContinue)) {
        & $appcmd add site /name:"$Global:SITE_NAME" /bindings:"ftp://*:21" /physicalPath:"$Global:FTP_ROOT"
        Write-Host "[+] Sitio $Global:SITE_NAME creado." -ForegroundColor Green
    } else {
        Write-Host "[OK] Sitio $Global:SITE_NAME ya existe." -ForegroundColor Green
    }

    & $appcmd set site "$Global:SITE_NAME" "-ftpServer.userIsolation.mode:IsolateAllDirectories"
    & $appcmd set site "$Global:SITE_NAME" "-ftpServer.security.ssl.controlChannelPolicy:SslAllow"
    & $appcmd set site "$Global:SITE_NAME" "-ftpServer.security.ssl.dataChannelPolicy:SslAllow"
    & $appcmd set site "$Global:SITE_NAME" "-ftpServer.security.authentication.basicAuthentication.enabled:true"
    & $appcmd set site "$Global:SITE_NAME" "-ftpServer.security.authentication.anonymousAuthentication.enabled:true"

    & $appcmd clear config "$Global:SITE_NAME" -section:system.ftpServer/security/authorization 2>$null

    & $appcmd set config "$Global:SITE_NAME" -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='?',permissions='Read']" /commit:apphost
    & $appcmd set config "$Global:SITE_NAME" -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='*',permissions='Read,Write']" /commit:apphost

    foreach ($g in @("reprobados", "recursadores")) {
        icacls "$Global:BASE_DATA\general" /grant "${g}:(OI)(CI)M" /T /Q | Out-Null
        icacls "$Global:BASE_DATA\$g"      /grant "${g}:(OI)(CI)M" /T /Q | Out-Null
    }

    icacls "$Global:BASE_DATA\general" /grant "IUSR:(OI)(CI)R" /T /Q | Out-Null

    Restart-Service ftpsvc
    Write-Host "[OK] Servicio FTP configurado correctamente." -ForegroundColor Green
}

function _Aplicar_Permisos_Usuario {
    param($User, $Grupo, $UserHome)
    icacls "$UserHome\$User"   /inheritance:r /grant "${User}:(OI)(CI)F"  /Q | Out-Null
    icacls "$UserHome\general" /grant "${User}:(OI)(CI)M" /T /Q | Out-Null
    icacls "$UserHome\$Grupo"  /grant "${User}:(OI)(CI)M" /T /Q | Out-Null
}

function _Eliminar_Junction {
    param([string]$Path)
    # Verifica que existe y es un ReparsePoint (junction/symlink) antes de borrar
    if (Test-Path $Path) {
        $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            # Usar cmd /c rmdir SIN /S para no borrar el contenido destino
            $result = cmd /c "rmdir `"$Path`"" 2>&1
            if (Test-Path $Path) {
                # Si rmdir fallo, forzar con [System.IO.Directory]
                [System.IO.Directory]::Delete($Path, $false) 2>$null
            }
        } elseif ($item) {
            # Es carpeta real (no junction), borrar normalmente
            Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Crear_Usuarios {
    $input_N = Read-Host "Cantidad de usuarios a crear"
    if (!($input_N -as [int])) { Write-Host "Numero invalido."; return }
    $Cant = [int]$input_N

    for ($i = 1; $i -le $Cant; $i++) {
        Write-Host "`n--- Usuario $i de $Cant ---"
        $User = Read-Host "Nombre de usuario"

        if (Get-LocalUser $User -ErrorAction SilentlyContinue) {
            Write-Host "[!] $User ya existe. Saltando..." -ForegroundColor Yellow
            continue
        }

        $Pass  = Read-Host "Contrasena" -AsSecureString
        $G_Opt = Read-Host "Grupo: 1) reprobados | 2) recursadores"
        $Grupo = if ($G_Opt -eq "1") { "reprobados" } else { "recursadores" }

        New-LocalUser -Name $User -Password $Pass -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
        Add-LocalGroupMember -Group $Grupo -Member $User

        $UserHome = Join-Path $Global:LOCAL_USER $User
        New-Item $UserHome -ItemType Directory -Force | Out-Null

        if (!(Test-Path "$UserHome\general")) {
            cmd /c "mklink /D `"$UserHome\general`" `"$Global:BASE_DATA\general`"" | Out-Null
        }
        if (!(Test-Path "$UserHome\$Grupo")) {
            cmd /c "mklink /D `"$UserHome\$Grupo`" `"$Global:BASE_DATA\$Grupo`"" | Out-Null
        }

        New-Item (Join-Path $UserHome $User) -ItemType Directory -Force | Out-Null

        _Aplicar_Permisos_Usuario -User $User -Grupo $Grupo -UserHome $UserHome

        Write-Host "[OK] $User configurado en grupo $Grupo." -ForegroundColor Green
    }
}

function Cambiar_Grupo {
    $User = Read-Host "Nombre del usuario"
    if (!(Get-LocalUser $User -ErrorAction SilentlyContinue)) {
        Write-Host "[!] El usuario no existe." -ForegroundColor Red
        return
    }

    $G_Opt  = Read-Host "Nuevo Grupo: 1) reprobados | 2) recursadores"
    $NuevoG = if ($G_Opt -eq "1") { "reprobados" } else { "recursadores" }
    $ViejoG = if ($G_Opt -eq "1") { "recursadores" } else { "reprobados" }

    # Verificar que el usuario no este ya en el grupo destino
    $yaEnGrupo = Get-LocalGroupMember $NuevoG -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match "\\$User$" }
    if ($yaEnGrupo) {
        Write-Host "[!] $User ya pertenece a $NuevoG." -ForegroundColor Yellow
        return
    }

    # Cambiar membresia de grupo
    Remove-LocalGroupMember -Group $ViejoG -Member $User -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $NuevoG -Member $User -ErrorAction SilentlyContinue

    $UserHome = Join-Path $Global:LOCAL_USER $User

    # ── Detener ftpsvc para liberar handles sobre los junctions ──
    Write-Host "[+] Deteniendo ftpsvc para liberar handles..." -ForegroundColor Cyan
    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    #TENGO QUE BORRAR ESTO DESPUES
    # ── DIAGNOSTICO TEMPORAL - borrar despues ──
Write-Host "`n=== ESTADO DEL DIRECTORIO DEL USUARIO ===" -ForegroundColor Yellow
Write-Host "UserHome: $UserHome"
Write-Host "Existe UserHome: $(Test-Path $UserHome)"
Get-ChildItem $UserHome -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $esJunction = ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    Write-Host "  $($_.Name)  [Junction=$esJunction]  Atributos=$($_.Attributes)"
    if ($esJunction) {
        $target = cmd /c "fsutil reparsepoint query `"$($_.FullName)`"" 2>&1 | Select-String "Print Name"
        Write-Host "    -> Target: $target"
    }
}
Write-Host "==========================================`n" -ForegroundColor Yellow
    Start-Sleep -Seconds 2

    # ── Eliminar TODOS los junctions de grupo (reprobados y recursadores) por si hay residuos ──
    foreach ($g in @("reprobados", "recursadores")) {
        $jPath = Join-Path $UserHome $g
        if (Test-Path $jPath) {
            Write-Host "[+] Eliminando junction '$g'..." -ForegroundColor Cyan
            _Eliminar_Junction -Path $jPath
            if (Test-Path $jPath) {
                Write-Host "    [!] No se pudo eliminar $jPath" -ForegroundColor Red
            } else {
                Write-Host "    [OK] Junction '$g' eliminada." -ForegroundColor Green
            }
        }
    }

    # ── Crear SOLO el junction del grupo nuevo ──
    $junctionNuevo = Join-Path $UserHome $NuevoG
    if (!(Test-Path $junctionNuevo)) {
        $mkResult = cmd /c "mklink /D `"$junctionNuevo`" `"$Global:BASE_DATA\$NuevoG`"" 2>&1
        if (Test-Path $junctionNuevo) {
            Write-Host "    [OK] Junction '$NuevoG' creada -> $Global:BASE_DATA\$NuevoG" -ForegroundColor Green
        } else {
            Write-Host "    [!] ERROR creando junction '$NuevoG': $mkResult" -ForegroundColor Red
        }
    } else {
        Write-Host "    [OK] Junction '$NuevoG' ya existe." -ForegroundColor Green
    }

    # ── Revocar permisos NTFS del grupo viejo, aplicar los del nuevo ──
    icacls "$Global:BASE_DATA\$ViejoG" /remove "${User}" /T /Q | Out-Null
    _Aplicar_Permisos_Usuario -User $User -Grupo $NuevoG -UserHome $UserHome

    # ── Reiniciar ftpsvc para que IIS refresque los junctions ──
    Write-Host "[+] Reiniciando ftpsvc..." -ForegroundColor Cyan
    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    Write-Host "[OK] $User movido de $ViejoG a $NuevoG." -ForegroundColor Green
}

function Listar_Usuarios {
    Write-Host "`n--- [ USUARIOS FTP REGISTRADOS ] ---" -ForegroundColor Cyan
    Write-Host ("{0,-20} | {1,-15} | {2}" -f "USUARIO", "GRUPO", "HABILITADO")
    Write-Host ("-" * 55)

    $excluir = @("Administrator","Guest","DefaultAccount","WDAGUtilityAccount")
    $users = Get-LocalUser | Where-Object { $_.Name -notin $excluir }

    foreach ($u in $users) {
        $grupo = "Sin grupo"
        foreach ($g in @("reprobados","recursadores")) {
            $members = Get-LocalGroupMember $g -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            if ($members -match "\\$($u.Name)$") { $grupo = $g; break }
        }
        $habilitado = if ($u.Enabled) { "Si" } else { "No" }
        Write-Host ("{0,-20} | {1,-15} | {2}" -f $u.Name, $grupo, $habilitado)
    }
    Write-Host ("-" * 55)
}

function Verificar_Servicio {
    Write-Host "`n--- [ DIAGNOSTICO FTP ] ---" -ForegroundColor Cyan

    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc.Status -eq "Running") {
        Write-Host "Estado ftpsvc : " -NoNewline; Write-Host "[ EN EJECUCION ]" -ForegroundColor Green
    } else {
        Write-Host "Estado ftpsvc : " -NoNewline; Write-Host "[ DETENIDO ]" -ForegroundColor Red
    }

    $sitio = Get-Website -Name $Global:SITE_NAME -ErrorAction SilentlyContinue
    if ($sitio) {
        $color = if ($sitio.State -eq "Started") { "Green" } else { "Red" }
        Write-Host "Sitio IIS     : " -NoNewline; Write-Host "[ $($sitio.State.ToUpper()) ]" -ForegroundColor $color
    } else {
        Write-Host "Sitio IIS     : " -NoNewline; Write-Host "[ NO EXISTE ]" -ForegroundColor Red
    }

    $puerto = netstat -an | Select-String ":21 "
    Write-Host "Puerto 21     : " -NoNewline
    if ($puerto) { Write-Host "[ ESCUCHANDO ]" -ForegroundColor Green } else { Write-Host "[ CERRADO ]" -ForegroundColor Red }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Select-Object -First 1).IPAddress
    Write-Host "IP servidor   : " -NoNewline; Write-Host "$ip" -ForegroundColor Blue
    Write-Host ("-" * 40)
}

function Gestion_UG {
    while ($true) {
        Write-Host "`n[*] GESTION DE USUARIOS Y GRUPOS"
        Write-Host "1) Crear Usuarios (Masivo)"
        Write-Host "2) Cambiar Usuario de Grupo"
        Write-Host "3) Listar Usuarios"
        Write-Host "7) Volver"
        $op = Read-Host "Opcion"
        switch ($op) {
            "1" { Crear_Usuarios }
            "2" { Cambiar_Grupo }
            "3" { Listar_Usuarios }
            "7" { return }
            default { Write-Host "Opcion no valida." }
        }
    }
}

function Menu_Principal {
    $cfg = "C:\Windows\Temp\sec.cfg"
    secedit /export /cfg $cfg 2>$null | Out-Null
    (Get-Content $cfg) -replace "PasswordComplexity = 1", "PasswordComplexity = 0" | Set-Content $cfg
    secedit /configure /db "$env:windir\security\local.sdb" /cfg $cfg /areas SECURITYPOLICY 2>$null | Out-Null

    Configurar_Servicio_FTP

    while ($true) {
        Write-Host "`n========================================"
        Write-Host "   SERVIDOR FTP AUTOMATIZADO (IIS)      "
        Write-Host "========================================"
        Write-Host "1) Gestion de Usuarios y Grupos"
        Write-Host "2) Diagnostico del servicio"
        Write-Host "3) Reiniciar servicio (ftpsvc)"
        Write-Host "4) Salir"
        $op = Read-Host "Opcion"
        switch ($op) {
            "1" { Gestion_UG }
            "2" { Verificar_Servicio }
            "3" { Restart-Service ftpsvc; Write-Host "[OK] ftpsvc reiniciado." -ForegroundColor Green }
            "4" { Write-Host "Saliendo..."; return }
            default { Write-Host "Opcion no valida." }
        }
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "[ERROR] Ejecutar como Administrador (PowerShell como Admin)."
    exit 1
}

Menu_Principal