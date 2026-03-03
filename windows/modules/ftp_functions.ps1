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
    
    # --- SOLUCION DEFINITIVA AL ERROR DE BLOQUEO ---
    Write-Host "[*] Desbloqueando secciones de IIS mediante APPCMD..." -ForegroundColor Yellow
    # Desbloqueamos las secciones a nivel global para permitir cambios locales
    & $appcmd unlock config -section:system.ftpServer/security/authorization
    & $appcmd unlock config -section:system.ftpServer/security/authentication

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

    # 4. Autorizacion Anonima
    # Usamos -Location para asegurar que la regla se escriba donde IIS la acepte
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="anonymous";permissions="Read"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
    
    Write-Host "[+] Entorno FTP configurado y desbloqueado." -ForegroundColor Green
}

function Add-MassiveUsers {
    $n_input = Read-Host "Ingrese el numero de usuarios a crear"
    
    # --- SOLUCION AL ERROR [ref] ---
    # Inicializamos explicitamente para que TryParse encuentre la referencia
    $n = 0 
    if (!([int]::TryParse($n_input, [ref]$n))) {
        Write-Host "[!] Error: '$n_input' no es un numero. Ingresa un valor numerico (ej: 3)." -ForegroundColor Red
        return
    }

    $basePath = "C:\inetpub\ftproot"

    foreach ($grp in @("reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $grp }
    }

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Datos Usuario $i ---" -ForegroundColor Yellow
        $userName = Read-Host "Nombre de usuario"
        Write-Host "[!] RECUERDA: La clave debe tener Mayus, Minus, Numero y Simbolo (ej: Alumno.2026*)" -ForegroundColor Gray
        $password = Read-Host "Password" -AsSecureString
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        # Crear Usuario con Try/Catch para detectar fallos de complejidad
        try {
            if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName" -Description "Usuario FTP Practica 5"
                Add-LocalGroupMember -Group $grupo -Member $userName
                Write-Host "[+] Usuario $userName creado y asignado a $grupo." -ForegroundColor Green
            }
        } catch {
            Write-Host "[!] ERROR: No se pudo crear el usuario. Probablemente la contraseña es muy debil." -ForegroundColor Red
            continue 
        }

        # Carpetas y permisos NTFS
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory | Out-Null }
        icacls $userPath /grant "${userName}:(OI)(CI)F" /inheritance:e
        
        # Regla de Autorizacion en IIS
        Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users=$userName;permissions="Read,Write"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location "FTPServer_Practica"
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