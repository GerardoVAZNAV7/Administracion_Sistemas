# MÓDULO: FTP_Functions.ps1
# =========================================================

# 1. Instalación del Servicio (Opción 5 del menú)
function Instalar-ServicioFTP {
    Write-Host "[+] Iniciando instalación silenciosa de IIS y FTP Service..." -ForegroundColor Cyan
    # Instalación de características necesarias sin reinicio
    Install-WindowsFeature Web-Server, Web-Ftp-Server, Web-Mgmt-Console -IncludeManagementTools -NoRestart | Out-Null
    
    if (Get-Service ftpsvc -ErrorAction SilentlyContinue) {
        Write-Host "[✓] Características instaladas correctamente." -ForegroundColor Green
    } else {
        Write-Host "[X] Error en la instalación." -ForegroundColor Red
    }
}

# 2. Configuración General e Idempotencia (Opción 6 del menú)
function Configurar-EntornoFTP {
    Write-Host "[+] Configurando estructuras, grupos y seguridad..." -ForegroundColor Cyan
    
    $ftpRoot = "C:\inetpub\ftproot"
    $basePath = "$ftpRoot\LocalUser"

    # Crear directorios base (Equivalente a /srv/ftp en Linux)
    $dirs = @("$basePath", "$ftpRoot\general", "$basePath\reprobados", "$basePath\recursadores", "$ftpRoot\Public")
    foreach ($dir in $dirs) {
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    # Crear Grupos Locales
    foreach ($group in @("ftp-users", "reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) { 
            New-LocalGroup -Name $group | Out-Null
            Write-Host "[✓] Grupo $group creado." -ForegroundColor Gray
        }
    }

    # Configurar IIS y Aislamiento (Requerido para la estructura de carpetas personalizada)
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\Default FTP Site")) {
        New-WebFtpSite -Name "Default FTP Site" -Port 21 -PhysicalPath $ftpRoot -Force | Out-Null
    }
    
    # Modo: IsolateUsers (Busca automáticamente en LocalUser\NombreUsuario)
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/userIsolation" -Name "mode" -Value "IsolateUsers"

    # Configurar Acceso Anónimo (Solo lectura a /Public)
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value "true"
    
    # Permisos NTFS en 'general': Escritura para registrados, Lectura para todos
    $acl = Get-Acl "$ftpRoot\general"
    $regRule = New-Object System.Security.AccessControl.FileSystemAccessRule("ftp-users","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $anonRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone","ReadAndExecute", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($regRule)
    $acl.SetAccessRule($anonRule)
    Set-Acl "$ftpRoot\general" $acl

    # Firewall
    Configurar-FirewallFTP
    
    Restart-Service ftpsvc
    Write-Host "[✓] Entorno configurado para FileZilla." -ForegroundColor Green
}

# 3. Gestión de Usuarios
function Crear-UsuarioFTP {
    param($user, $pass, $group)

    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Write-Host "[!] El usuario $user ya existe." -ForegroundColor Yellow
        return
    }

    # Crear cuenta de Windows
    $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
    New-LocalUser -Name $user -Password $securePass -Description "Usuario FTP Práctica" | Out-Null
    Add-LocalGroupMember -Group "ftp-users" -Member $user
    Add-LocalGroupMember -Group $group -Member $user

    # Estructura requerida por la práctica
    $userHome = "C:\inetpub\ftproot\LocalUser\$user"
    New-Item -ItemType Directory -Force -Path "$userHome\$user" | Out-Null # Carpeta Personal

    # Montajes Simbólicos (Igual que el mount --bind de Fedora)
    cmd /c mklink /D "$userHome\general" "C:\inetpub\ftproot\general"
    cmd /c mklink /D "$userHome\$group" "C:\inetpub\ftproot\LocalUser\$group"

    # Permisos en Carpeta Personal (Solo el dueño)
    $acl = Get-Acl "$userHome\$user"
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user,"FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl "$userHome\$user" $acl

    Write-Host "[✓] Usuario $user configurado con acceso a general, $group y personal." -ForegroundColor Green
}

function Configurar-FirewallFTP {
    Write-Host "[+] Abriendo puertos 21 y rango pasivo 40000-40010..." -ForegroundColor Cyan
    Enable-NetFirewallRule -DisplayGroup "Servidor FTP" -ErrorAction SilentlyContinue
    if (!(Get-NetFirewallRule -Name "FTP-Passive" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Pasivo" -Name "FTP-Passive" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 40000-40010 | Out-Null
    }
}