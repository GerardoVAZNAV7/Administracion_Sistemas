# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP (PRACTICA 5)
# =====================================================

function Install-FTPService {
    Write-Host "[*] Verificando e instalando Rol Web-Server e IIS-FTPServer..." -ForegroundColor Cyan
    # Idempotencia: Solo instala si no está presente
    Install-WindowsFeature Web-Server, Web-Mgmt-Console, Web-Ftp-Server, Web-Ftp-Service -IncludeManagementTools
    Write-Host "[+] Instalacion completada con exito." -ForegroundColor Green
}

function Configure-FTPEnvironment {
    $ftpSiteName = "FTPServer_Practica"
    $basePath = "C:\inetpub\ftproot"
    
    # 1. Crear directorios base si no existen
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory | Out-Null }
    }

    # 2. Configurar Firewall de Windows
    Write-Host "[*] Abriendo puertos en Firewall para FTP..." -ForegroundColor Cyan
    Set-NetFirewallRule -DisplayGroup "FTP Server" -Enabled True

    # 3. Configuracion de IIS para FTP
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\$ftpSiteName")) {
        New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath
        # Permitir SSL pero no requerirlo para facilitar pruebas iniciales
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
        # Habilitar Autenticacion
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    }

    # 4. Regla de Acceso Anonimo: Solo lectura a la raiz (que incluye /general)
    Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";roles="";permissions="Read";users="anonymous"} -PSPath "IIS:\Sites\$ftpSiteName"
    
    Write-Host "[+] Entorno FTP listo en $basePath" -ForegroundColor Green
}

function Add-MassiveUsers {
    $n = Read-Host "Ingrese el numero de usuarios a crear"
    $basePath = "C:\inetpub\ftproot"

    # Asegurar existencia de grupos locales
    foreach ($grp in @("reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $grp }
    }

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Datos Usuario $i ---" -ForegroundColor Yellow
        $userName = Read-Host "Nombre de usuario"
        $password = Read-Host "Password" -AsSecureString
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        # Crear Usuario
        if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName"
            Add-LocalGroupMember -Group $grupo -Member $userName
        }

        # Crear carpeta personal
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory | Out-Null }

        # --- GESTION DE PERMISOS NTFS (ACLs) ---
        # 1. Permisos en carpeta personal (Full Control para el dueño)
        icacls $userPath /grant "${userName}:(OI)(CI)F" /inheritance:e

        # 2. Permisos en carpeta de grupo (Escritura para el grupo correspondiente)
        $groupPath = Join-Path $basePath $grupo
        icacls $groupPath /grant "${grupo}:(OI)(CI)M"

        # 3. Permisos en carpeta 'general' (Escritura para todos los usuarios logeados)
        icacls "$basePath\general" /grant "Users:(OI)(CI)M"

        # Autorizacion en IIS para el usuario especifico
        Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";roles="";permissions="Read,Write";users=$userName} -PSPath "IIS:\Sites\FTPServer_Practica"
        
        Write-Host "[+] Usuario $userName configurado correctamente." -ForegroundColor Green
    }
}

function Update-UserGroup {
    $user = Read-Host "Usuario a mover"
    $nuevoGrupo = Read-Host "Nuevo grupo destino (reprobados/recursadores)"
    
    # Remover de grupos anteriores para evitar conflictos
    $gruposBusqueda = @("reprobados", "recursadores")
    foreach ($g in $gruposBusqueda) {
        Remove-LocalGroupMember -Group $g -Member $user -ErrorAction SilentlyContinue
    }
    
    Add-LocalGroupMember -Group $nuevoGrupo -Member $user
    Write-Host "[+] Cambio de grupo exitoso para $user" -ForegroundColor Green
}