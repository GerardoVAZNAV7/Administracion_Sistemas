# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP (VERSION FINAL)
# =====================================================

function Install-FTPService {
    Write-Host "[*] Verificando e instalando Rol Web-Server e IIS-FTPServer..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Mgmt-Console, Web-Ftp-Server, Web-Ftp-Service -IncludeManagementTools
    Write-Host "[+] Instalacion completada." -ForegroundColor Green
}

function Configure-FTPEnvironment {
    $ftpSiteName = "FTPServer_Practica"
    $basePath = "C:\inetpub\ftproot"
    
    # 1. Crear directorios base
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory | Out-Null }
    }

    # 2. Configurar Firewall
    Set-NetFirewallRule -DisplayGroup "FTP Server" -Enabled True

    # 3. Configuracion de IIS (Sitio)
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\$ftpSiteName")) {
        New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
        Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    }

    # 4. Autorizacion Anonima (bypass del error de bloqueo usando -Location)
    # Esto escribe en el config central en lugar de un web.config local
    Write-Host "[*] Aplicando reglas de autorizacion global..." -ForegroundColor Yellow
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="anonymous";permissions="Read"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
    
    Write-Host "[+] Entorno FTP configurado correctamente." -ForegroundColor Green
}

function Add-MassiveUsers {
    $n_input = Read-Host "Ingrese el numero de usuarios a crear"
    
    # Inicializacion para evitar el error de [ref]
    $n = 0
    if (!([int]::TryParse($n_input, [ref]$n))) {
        Write-Host "[!] Error: Debes ingresar un numero valido." -ForegroundColor Red
        return
    }

    $basePath = "C:\inetpub\ftproot"

    foreach ($grp in @("reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $grp }
    }

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Datos Usuario $i ---" -ForegroundColor Yellow
        $userName = Read-Host "Nombre de usuario"
        Write-Host "[!] Nota: La clave debe tener Mayus, Minus, Numero y Simbolo (ej: P@ssword123)" -ForegroundColor Gray
        $password = Read-Host "Password" -AsSecureString
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        # Crear Usuario
        try {
            if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName"
                Add-LocalGroupMember -Group $grupo -Member $userName
                Write-Host "[+] Usuario $userName creado." -ForegroundColor Green
            }
        } catch {
            Write-Host "[!] Error al crear $userName: Verifica que la contraseña sea compleja." -ForegroundColor Red
            continue
        }

        # Carpeta y Permisos NTFS
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory | Out-Null }
        
        icacls $userPath /grant "${userName}:(OI)(CI)F" /inheritance:e
        icacls "$basePath\$grupo" /grant "${grupo}:(OI)(CI)M"
        icacls "$basePath\general" /grant "Users:(OI)(CI)M"

        # Autorizacion IIS con -Location para evitar bloqueos
        Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users=$userName;permissions="Read,Write"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location "FTPServer_Practica"
    }
}