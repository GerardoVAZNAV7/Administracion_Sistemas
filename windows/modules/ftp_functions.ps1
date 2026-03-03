# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP (CORREGIDO)
# =====================================================

function Install-FTPService {
    Write-Host "[*] Verificando e instalando Rol Web-Server e IIS-FTPServer..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Mgmt-Console, Web-Ftp-Server, Web-Ftp-Service -IncludeManagementTools
    Write-Host "[+] Instalacion completada." -ForegroundColor Green
}

function Configure-FTPEnvironment {
    $ftpSiteName = "FTPServer_Practica"
    $basePath = "C:\inetpub\ftproot"
    
    # --- SOLUCION AL ERROR DE BLOQUEO ---
    Write-Host "[*] Desbloqueando secciones de configuracion de IIS..." -ForegroundColor Yellow
    # Esta linea permite que el script modifique la autorizacion de FTP
    Set-WebConfigurationProperty -Filter /configSections/sectionGroup[@name='system.ftpServer']/section[@name='security'] -Name overrideModeDefault -Value Allow -PSPath MACHINE/WEBROOT/APPHOST
    
    # 1. Crear directorios base
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory | Out-Null }
    }

    # 2. Firewall
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

    # 4. Regla de Acceso Anonimo (Lectura)
    Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";roles="";permissions="Read";users="anonymous"} -PSPath "IIS:\Sites\$ftpSiteName"
    
    Write-Host "[+] Entorno FTP configurado y desbloqueado." -ForegroundColor Green
}

function Add-MassiveUsers {
    # --- SOLUCION AL ERROR DE CONVERSION ---
    $n_input = Read-Host "Ingrese el numero de usuarios a crear"
    if (!([int]::TryParse($n_input, [ref]$n))) {
        Write-Host "[!] Error: Debes ingresar un numero valido, no un nombre." -ForegroundColor Red
        return
    }

    $basePath = "C:\inetpub\ftproot"

    foreach ($grp in @("reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $grp }
    }

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Datos Usuario $i ---" -ForegroundColor Yellow
        $userName = Read-Host "Nombre de usuario"
        $password = Read-Host "Password" -AsSecureString
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName"
            Add-LocalGroupMember -Group $grupo -Member $userName
        }

        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory | Out-Null }

        # ACLs robustas para FileZilla
        icacls $userPath /grant "${userName}:(OI)(CI)F" /inheritance:e
        $groupPath = Join-Path $basePath $grupo
        icacls $groupPath /grant "${grupo}:(OI)(CI)M"
        icacls "$basePath\general" /grant "Users:(OI)(CI)M"

        Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";roles="";permissions="Read,Write";users=$userName} -PSPath "IIS:\Sites\FTPServer_Practica"
        
        Write-Host "[+] Usuario $userName listo." -ForegroundColor Green
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