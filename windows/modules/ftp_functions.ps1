# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP (PRACTICA 5)
# =====================================================

function Install-FTPService {
    Write-Host "[*] Verificando e instalando Rol Web-Server e IIS-FTPServer..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Mgmt-Console, Web-Ftp-Server, Web-Ftp-Service -IncludeManagementTools
    Write-Host "[+] Instalacion completada." -ForegroundColor Green
}

function Configure-FTPEnvironment {
    $ftpSiteName = "FTPServer_Practica"
    $basePath = "C:\inetpub\ftproot"
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
    
    # --- DESBLOQUEO GARANTIZADO DE IIS ---
    Write-Host "[*] Desbloqueando secciones de seguridad en IIS..." -ForegroundColor Yellow
    & $appcmd unlock config -section:system.ftpServer/security/authorization
    & $appcmd unlock config -section:system.ftpServer/security/authentication

    # 1. Crear directorios base
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory | Out-Null }
    }

    # 2. Configurar Firewall
    Set-NetFirewallRule -DisplayGroup "FTP Server" -Enabled True

    # 3. Configuracion de IIS
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\$ftpSiteName")) {
        New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    }

    # 4. Autorizacion Anonima (Solo Lectura)
    Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";roles="";permissions="Read";users="anonymous"} -PSPath "IIS:\Sites\$ftpSiteName"
    
    Write-Host "[+] Entorno FTP configurado y desbloqueado exitosamente." -ForegroundColor Green
}

function Add-MassiveUsers {
    $n_input = Read-Host "Ingrese el numero de usuarios a crear"
    
    # --- SOLUCION AL ERROR [ref] ---
    # Es necesario inicializar la variable antes de pasarla por referencia
    $n = 0
    if (!([int]::TryParse($n_input, [ref]$n))) {
        Write-Host "[!] Error: '$n_input' no es un numero. Operacion cancelada." -ForegroundColor Red
        return
    }

    $basePath = "C:\inetpub\ftproot"

    # Grupos
    foreach ($grp in @("reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $grp }
    }

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Datos Usuario $i ---" -ForegroundColor Yellow
        $userName = Read-Host "Nombre de usuario"
        $password = Read-Host "Password" -AsSecureString
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        # Crear Usuario si no existe
        if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName"
            Add-LocalGroupMember -Group $grupo -Member $userName
        }

        # Carpeta personal
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory | Out-Null }

        # Permisos NTFS (Críticos para FileZilla)
        icacls $userPath /grant "${userName}:(OI)(CI)F" /inheritance:e
        icacls "$basePath\$grupo" /grant "${grupo}:(OI)(CI)M"
        icacls "$basePath\general" /grant "Users:(OI)(CI)M"

        # Autorizacion IIS
        Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";roles="";permissions="Read,Write";users=$userName} -PSPath "IIS:\Sites\FTPServer_Practica"
        
        Write-Host "[+] Usuario $userName configurado." -ForegroundColor Green
    }
}

function Update-UserGroup {
    $user = Read-Host "Usuario a mover"
    $nuevoGrupo = Read-Host "Nuevo grupo destino (reprobados/recursadores)"
    
    $gruposBusqueda = @("reprobados", "recursadores")
    foreach ($g in $gruposBusqueda) {
        Remove-LocalGroupMember -Group $g -Member $user -ErrorAction SilentlyContinue
    }
    
    Add-LocalGroupMember -Group $nuevoGrupo -Member $user
    Write-Host "[+] Cambio de grupo exitoso para $user" -ForegroundColor Green
}