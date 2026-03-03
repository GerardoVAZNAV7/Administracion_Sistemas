# =========================================================
# MÓDULO DE FUNCIONES FTP - WINDOWS SERVER 2022
# =========================================================

function Instalar-ServicioFTP {
    Write-Host "[+] Instalando IIS y Servicio FTP (Silencioso)..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Ftp-Server, Web-Mgmt-Console -IncludeManagementTools -NoRestart | Out-Null
    
    if (Get-Service ftpsvc -ErrorAction SilentlyContinue) {
        Write-Host "[✓] Instalación completada exitosamente." -ForegroundColor Green
    } else {
        Write-Host "[X] Error: No se pudo instalar el servicio. Ejecuta como Administrador." -ForegroundColor Red
    }
}

function Configurar-EntornoFTP {
    Write-Host "[+] Configurando directorios, grupos y permisos..." -ForegroundColor Cyan
    $ftpRoot = "C:\inetpub\ftproot"
    $basePath = "$ftpRoot\LocalUser"

    $dirs = @("$basePath", "$ftpRoot\general", "$basePath\reprobados", "$basePath\recursadores", "$ftpRoot\Public")
    foreach ($dir in $dirs) {
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    foreach ($group in @("ftp-users", "reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) { 
            New-LocalGroup -Name $group | Out-Null
        }
    }

    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\Default FTP Site")) {
        New-WebFtpSite -Name "Default FTP Site" -Port 21 -PhysicalPath $ftpRoot -Force | Out-Null
    }
    
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/userIsolation" -Name "mode" -Value "IsolateUsers"
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value "true"
    
    $acl = Get-Acl "$ftpRoot\general"
    $regRule = New-Object System.Security.AccessControl.FileSystemAccessRule("ftp-users","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($regRule)
    Set-Acl "$ftpRoot\general" $acl

    Configurar-FirewallFTP
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "[✓] Entorno configurado correctamente." -ForegroundColor Green
}

function Crear-UsuarioFTP {
    param($user, $pass, $group)
    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Write-Host "[!] El usuario $user ya existe." -ForegroundColor Yellow
        return
    }

    $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
    New-LocalUser -Name $user -Password $securePass -Description "Usuario FTP" | Out-Null
    Add-LocalGroupMember -Group "ftp-users" -Member $user
    Add-LocalGroupMember -Group $group -Member $user

    $userHome = "C:\inetpub\ftproot\LocalUser\$user"
    if (!(Test-Path $userHome)) { New-Item -ItemType Directory -Path $userHome -Force | Out-Null }
    
    $personalDir = "$userHome\$user"
    New-Item -ItemType Directory -Path $personalDir -Force | Out-Null

    cmd /c mklink /D "$userHome\general" "C:\inetpub\ftproot\general"
    cmd /c mklink /D "$userHome\$group" "C:\inetpub\ftproot\LocalUser\$group"

    $acl = Get-Acl $personalDir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user,"FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $personalDir $acl
    Write-Host "[✓] Usuario $user configurado con acceso a $group." -ForegroundColor Green
}

function Configurar-FirewallFTP {
    Enable-NetFirewallRule -DisplayGroup "Servidor FTP" -ErrorAction SilentlyContinue
    if (!(Get-NetFirewallRule -Name "FTP-Passive" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Pasivo" -Name "FTP-Passive" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 40000-40010 | Out-Null
    }
}