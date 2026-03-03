# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP
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
    
    Import-Module WebAdministration

    # Crear Grupos Locales si no existen (necesario para permisos NTFS)
    foreach ($g in @("reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $g
            Write-Host "[+] Grupo local '$g' creado." -ForegroundColor Gray
        }
    }

    Write-Host "[*] Desbloqueando secciones de configuracion..." -ForegroundColor Yellow
    & $appcmd unlock config -section:system.ftpServer/security/authorization
    & $appcmd unlock config -section:system.ftpServer/security/authentication

    # 1. Crear directorios base
    if (!(Test-Path $basePath)) { New-Item -Path $basePath -ItemType Directory -Force | Out-Null }
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
    }

    # --- CONFIGURACIÓN DE PERMISOS NTFS RAÍZ ---
    # Esto permite que el usuario "vea" la lista en la raíz, pero solo entre a lo permitido
    Write-Host "[*] Aplicando permisos NTFS en $basePath..." -ForegroundColor Yellow
    icacls $basePath /inheritance:r
    icacls $basePath /grant "Administrators:(OI)(CI)F"
    icacls $basePath /grant "SYSTEM:(OI)(CI)F"
    icacls $basePath /grant "Users:(R)" 

    # Permisos carpetas compartidas
    icacls "$basePath\general" /grant "IUSR:(R)"
    icacls "$basePath\general" /grant "Users:(OI)(CI)M"
    icacls "$basePath\reprobados" /grant "reprobados:(OI)(CI)M"
    icacls "$basePath\recursadores" /grant "recursadores:(OI)(CI)M"

    # 2. Configurar Sitio en IIS
    if (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue) { 
        Remove-WebSite -Name $ftpSiteName 
    }
    
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath -Force
    
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # 3. Reglas de Autorización IIS (Permitir el acceso al servicio)
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="anonymous";permissions="Read"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="Users";permissions="Read,Write"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
    
    Write-Host "[+] Entorno FTP configurado correctamente." -ForegroundColor Green
}

function Add-MassiveUsers {
    $n_input = Read-Host "Ingrese el numero de usuarios a crear"
    $n = 0 
    if (!([int]::TryParse($n_input, [ref]$n))) { return }

    $basePath = "C:\inetpub\ftproot"

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Datos Usuario $i ---" -ForegroundColor Yellow
        $userName = Read-Host "Nombre de usuario"
        $passwordRaw = Read-Host "Password"
        $password = $passwordRaw | ConvertTo-SecureString -AsPlainText -Force
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        try {
            if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName"
                Add-LocalGroupMember -Group "Users" -Member $userName
                Add-LocalGroupMember -Group $grupo -Member $userName
            }

            # --- CARPETA PERSONAL ---
            $userPath = Join-Path $basePath $userName
            if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory -Force | Out-Null }
            
            icacls $userPath /inheritance:r
            icacls $userPath /grant "Administrators:(OI)(CI)F"
            icacls $userPath /grant "${userName}:(OI)(CI)M"
            
            Write-Host "[+] Usuario $userName creado y carpeta configurada." -ForegroundColor Green
        } catch { 
            Write-Host "[!] Error: Verifique que el grupo '$grupo' exista." -ForegroundColor Red
        }
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
    Write-Host "[+] El usuario $user ahora pertenece a $nuevoGrupo (se actualizo su acceso FTP)." -ForegroundColor Green
}