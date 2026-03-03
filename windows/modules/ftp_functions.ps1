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
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
    
    Write-Host "[*] Desbloqueando secciones y configurando seguridad..." -ForegroundColor Yellow
    & $appcmd unlock config -section:system.ftpServer/security/authorization
    & $appcmd unlock config -section:system.ftpServer/security/authentication

    # 1. Crear directorios base y limpiar permisos heredados
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory | Out-Null }
    }

    # --- CONFIGURACIÓN DE PERMISOS NTFS RAÍZ ---
    # Permitir que los usuarios vean la raíz, pero no hereden permisos a subcarpetas ajenas
    icacls $basePath /inheritance:r # Quitar herencia
    icacls $basePath /grant "Administrators:(OI)(CI)F"
    icacls $basePath /grant "SYSTEM:(OI)(CI)F"
    icacls $basePath /grant "Users:(R)" # Solo lectura en la raíz para ver la lista

    # Carpeta General: Lectura para anónimos, Escritura para logeados
    icacls "$basePath\general" /grant "IUSR:(R)"
    icacls "$basePath\general" /grant "Users:(OI)(CI)M"

    # Carpetas de Grupo: Solo sus respectivos grupos tienen acceso
    icacls "$basePath\reprobados" /grant "reprobados:(OI)(CI)M"
    icacls "$basePath\recursadores" /grant "recursadores:(OI)(CI)M"

    # 2. Configurar Sitio en IIS
    Import-Module WebAdministration
    if (Test-Path "IIS:\Sites\$ftpSiteName") { Remove-WebFtpSite -Name $ftpSiteName }
    
    # IMPORTANTE: Forzamos la ruta física correcta
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # 3. Reglas de Autorización IIS
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="anonymous";permissions="Read"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="Users";permissions="Read,Write"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
    
    Write-Host "[+] Entorno FTP y Permisos NTFS configurados." -ForegroundColor Green
}

function Add-MassiveUsers {
    $n_input = Read-Host "Ingrese el numero de usuarios a crear"
    $n = 0 
    if (!([int]::TryParse($n_input, [ref]$n))) { return }

    $basePath = "C:\inetpub\ftproot"

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Datos Usuario $i ---" -ForegroundColor Yellow
        $userName = Read-Host "Nombre de usuario"
        $password = Read-Host "Password" -AsSecureString
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        # Crear Usuario y Asignar Grupo
        try {
            if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName"
                Add-LocalGroupMember -Group $grupo -Member $userName
            }
        } catch { continue }

        # --- CARPETA PERSONAL Y PRIVACIDAD ---
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory | Out-Null }
        
        # Solo el dueño tiene acceso a su carpeta (quitamos Users, dejamos al dueño)
        icacls $userPath /inheritance:r
        icacls $userPath /grant "Administrators:(OI)(CI)F"
        icacls $userPath /grant "${userName}:(OI)(CI)M"
        
        Write-Host "[+] Usuario $userName configurado con carpeta privada." -ForegroundColor Green
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