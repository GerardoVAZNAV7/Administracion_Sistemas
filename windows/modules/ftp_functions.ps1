# =========================================================
# MÓDULO DE FUNCIONES FTP - WINDOWS SERVER 2022
# =========================================================

# 1. Instalación del Rol de Servidor
function Instalar-ServicioFTP {
    Write-Host "[+] Instalando IIS y Servicio FTP (Silencioso)..." -ForegroundColor Cyan
    # Habilitación de características de IIS-FTPServer mediante PowerShell
    Install-WindowsFeature Web-Server, Web-Ftp-Server, Web-Mgmt-Console -IncludeManagementTools -NoRestart | Out-Null
    
    if (Get-Service ftpsvc -ErrorAction SilentlyContinue) {
        Write-Host "[✓] Instalación completada exitosamente." -ForegroundColor Green
    } else {
        Write-Host "[X] Error: No se pudo instalar el servicio. Ejecuta como Admin." -ForegroundColor Red
    }
}

# 2. Configuración de Estructura e Idempotencia
function Configurar-EntornoFTP {
    Write-Host "[+] Configurando directorios, grupos y permisos..." -ForegroundColor Cyan
    
    $ftpRoot = "C:\inetpub\ftproot"
    $basePath = "$ftpRoot\LocalUser"

    # Crear estructura de directorios base
    $dirs = @("$basePath", "$ftpRoot\general", "$basePath\reprobados", "$basePath\recursadores", "$ftpRoot\Public")
    foreach ($dir in $dirs) {
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    # Gestión Automatizada de Grupos: reprobados y recursadores
    foreach ($group in @("ftp-users", "reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) { 
            New-LocalGroup -Name $group | Out-Null
        }
    }

    # Configuración de IIS mediante WebAdministration
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\Default FTP Site")) {
        New-WebFtpSite -Name "Default FTP Site" -Port 21 -PhysicalPath $ftpRoot -Force | Out-Null
    }
    
    # Configurar Aislamiento de Usuarios (Requerimiento Técnico)
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/userIsolation" -Name "mode" -Value "IsolateUsers"

    # Acceso Anónimo: Solo lectura a la carpeta pública
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value "true"
    
    # Permisos NTFS: Escritura en 'general' para usuarios autenticados
    $acl = Get-Acl "$ftpRoot\general"
    $regRule = New-Object System.Security.AccessControl.FileSystemAccessRule("ftp-users","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $anonRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone","ReadAndExecute", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($regRule)
    $acl.SetAccessRule($anonRule)
    Set-Acl "$ftpRoot\general" $acl

    # Abrir Firewall (Puertos 21 y rango pasivo 40000-40010)
    Configurar-FirewallFTP
    
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "[✓] Entorno listo para conexiones FileZilla." -ForegroundColor Green
}

# 3. Alta de Usuarios y Mapeo de Carpetas
function Crear-UsuarioFTP {
    param($user, $pass, $group)

    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Write-Host "[!] El usuario $user ya existe." -ForegroundColor Yellow
        return
    }

    # Crear cuenta de sistema
    $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
    New-LocalUser -Name $user -Password $securePass -Description "Usuario FTP" | Out-Null
    Add-LocalGroupMember -Group "ftp-users" -Member $user
    Add-LocalGroupMember -Group $group -Member $user

    # Estructura de login requerida: general, grupo y personal
    $userHome = "C:\inetpub\ftproot\LocalUser\$user"
    if (!(Test-Path $userHome)) { New-Item -ItemType Directory -Path $userHome -Force | Out-Null }
    
    # Carpeta Personal (Escritura segmentada)
    $personalDir = "$userHome\$user"
    New-Item -ItemType Directory -Path $personalDir -Force | Out-Null

    # Enlaces Simbólicos (Mismo comportamiento que mount --bind en Linux)
    cmd /c mklink /D "$userHome\general" "C:\inetpub\ftproot\general"
    cmd /c mklink /D "$userHome\$group" "C:\inetpub\ftproot\LocalUser\$group"

    # Permisos NTFS en carpeta personal: Solo el propietario
    $acl = Get-Acl $personalDir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user,"FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $personalDir $acl

    Write-Host "[✓] Usuario $user creado y carpetas vinculadas." -ForegroundColor Green
}

# 4. Configuración de Seguridad de Red
function Configurar-FirewallFTP {
    Enable-NetFirewallRule -DisplayGroup "Servidor FTP" -ErrorAction SilentlyContinue
    if (!(Get-NetFirewallRule -Name "FTP-Passive" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Pasivo" -Name "FTP-Passive" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 40000-40010 | Out-Null
    }
}