# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP (CORREGIDO)
# =====================================================

function Install-FTPService {
    Write-Host "[*] Verificando e instalando Rol Web-Server e IIS-FTPServer..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Mgmt-Console, Web-Ftp-Server, Web-Ftp-Service -IncludeManagementTools
    Write-Host "[+] Instalacion completada." -ForegroundColor Green
}

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
    
    # IMPORTANTE: Asegurar que el modulo está cargado
    Import-Module WebAdministration

    Write-Host "[*] Desbloqueando secciones de configuracion..." -ForegroundColor Yellow
    & $appcmd unlock config -section:system.ftpServer/security/authorization
    & $appcmd unlock config -section:system.ftpServer/security/authentication

    # 1. Crear directorios base
    if (!(Test-Path $basePath)) { New-Item -Path $basePath -ItemType Directory | Out-Null }
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory | Out-Null }
    }

    # --- CONFIGURACIÓN DE PERMISOS NTFS RAÍZ ---
    Write-Host "[*] Configurando permisos NTFS..." -ForegroundColor Yellow
    icacls $basePath /inheritance:r
    icacls $basePath /grant "Administrators:(OI)(CI)F"
    icacls $basePath /grant "SYSTEM:(OI)(CI)F"
    icacls $basePath /grant "Users:(R)" # Permite ver la lista de carpetas

    # Carpeta General: Lectura para anónimos (IUSR), Modificar para usuarios autenticados
    icacls "$basePath\general" /grant "IUSR:(R)"
    icacls "$basePath\general" /grant "Users:(OI)(CI)M"

    # Carpetas de Grupo
    icacls "$basePath\reprobados" /grant "reprobados:(OI)(CI)M"
    icacls "$basePath\recursadores" /grant "recursadores:(OI)(CI)M"

    # 2. Configurar Sitio en IIS
    # CORRECCIÓN: El cmdlet correcto es Remove-WebSite
    if (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue) { 
        Remove-WebSite -Name $ftpSiteName 
        Write-Host "[-] Sitio anterior eliminado para refrescar configuracion." -ForegroundColor Gray
    }
    
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath -Force
    
    # Configurar SSL (Permitir sin requerir para facilitar la practica)
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    
    # Habilitar Autenticación
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # 3. Reglas de Autorización IIS (Permitir que entren al sitio)
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
        $passwordRaw = Read-Host "Password"
        $password = $passwordRaw | ConvertTo-SecureString -AsPlainText -Force
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        # Crear Usuario y Asignar Grupo
        try {
            if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName" -Description "Usuario FTP"
                Add-LocalGroupMember -Group "Users" -Member $userName
                Add-LocalGroupMember -Group $grupo -Member $userName
            }
        } catch { 
            Write-Host "[!] Error al crear usuario $userName" -ForegroundColor Red
            continue 
        }

        # --- CARPETA PERSONAL ---
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory | Out-Null }
        
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