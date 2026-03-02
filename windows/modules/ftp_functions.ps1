# --- Configuración Inicial e Idempotencia ---
function Inicializar-SistemaFTP {
    Write-Host "[+] Instalando Servidor Web (IIS) y Servicio FTP..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Ftp-Server, Web-Mgmt-Console -IncludeManagementTools

    $ftpRoot = "C:\inetpub\ftproot"
    $basePath = "$ftpRoot\LocalUser"

    # Crear estructura base
    # En Windows IIS, 'LocalUser\Public' se mapea comúnmente como carpeta compartida
    New-Item -ItemType Directory -Force -Path "$basePath\Public", "$ftpRoot\general", "$basePath\reprobados", "$basePath\recursadores"

    # Crear grupos locales si no existen
    if (!(Get-LocalGroup -Name "ftp-users" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "ftp-users" }
    if (!(Get-LocalGroup -Name "reprobados" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "reprobados" }
    if (!(Get-LocalGroup -Name "recursadores" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "recursadores" }

    # Configurar Sitio FTP en IIS
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\Default FTP Site")) {
        New-WebFtpSite -Name "Default FTP Site" -Port 21 -PhysicalPath $ftpRoot -Force
    }

    # Configurar Aislamiento de Usuarios
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/userIsolation" -Name "mode" -Value "IsolateUsers"

    # Permisos NTFS en la carpeta General (Lectura para todos, Escritura para registrados)
    $acl = Get-Acl "$ftpRoot\general"
    $regRule = New-Object System.Security.AccessControl.FileSystemAccessRule("ftp-users","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $anonRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone","ReadAndExecute", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($regRule)
    $acl.SetAccessRule($anonRule)
    Set-Acl "$ftpRoot\general" $acl

    Configurar-SeguridadFirewall
    Write-Host "[✓] Servidor FTP configurado y listo." -ForegroundColor Green
}

# --- Crear Usuario y Estructura Segmentada ---
function Crear-UsuarioFTP {
    param($user, $pass, $group)

    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Write-Host "[!] El usuario $user ya existe." -ForegroundColor Yellow
        return
    }

    # Crear cuenta de Windows
    $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
    New-LocalUser -Name $user -Password $securePass -Description "Usuario FTP"
    Add-LocalGroupMember -Group "ftp-users" -Member $user
    Add-LocalGroupMember -Group $group -Member $user

    # Estructura de Directorios (Aislamiento IIS)
    $userHome = "C:\inetpub\ftproot\LocalUser\$user"
    New-Item -ItemType Directory -Force -Path "$userHome\general", "$userHome\$group", "$userHome\$user"

    # --- SIMULACIÓN DE MONTAJES (Mapeo de directorios en Windows) ---
    # Usamos enlaces simbólicos de directorio (mklink /D) para replicar el comportamiento de Fedora
    cmd /c mklink /D "$userHome\general" "C:\inetpub\ftproot\general"
    cmd /c mklink /D "$userHome\$group" "C:\inetpub\ftproot\LocalUser\$group"

    # Permisos Personales (Solo el usuario entra a su carpeta privada)
    $acl = Get-Acl "$userHome\$user"
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user,"FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl "$userHome\$user" $acl

    Write-Host "[✓] Usuario $user configurado correctamente." -ForegroundColor Green
}

function Configurar-SeguridadFirewall {
    Write-Host "[+] Abriendo puertos en Firewall de Windows..." -ForegroundColor Cyan
    Enable-NetFirewallRule -DisplayGroup "Servidor FTP"
    # Puertos pasivos (rango similar a tu config de Linux)
    New-NetFirewallRule -DisplayName "FTP Pasivo" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 40000-40010
}