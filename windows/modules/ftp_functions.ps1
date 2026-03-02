# --- Configuración Inicial e Idempotencia ---
# --- Configuración Inicial e Idempotencia (Instalación Silenciosa) ---
function Inicializar-SistemaFTP {
    Write-Host "[+] Verificando componentes de Windows Server..." -ForegroundColor Cyan
    
    # Instalación silenciosa de IIS y el servicio FTP
    # -NoRestart: Evita que el servidor se reinicie solo
    # &>/dev/null: (Equivalente en PS) Out-Null para silenciar la barra de progreso
    Write-Host "[+] Instalando IIS-FTPServer de forma silenciosa. Por favor, espere..." -ForegroundColor Gray
    Install-WindowsFeature Web-Server, Web-Ftp-Server, Web-Mgmt-Console -IncludeManagementTools -NoRestart | Out-Null

    $ftpRoot = "C:\inetpub\ftproot"
    $basePath = "$ftpRoot\LocalUser"

    # Crear estructura base de directorios de forma forzada e idempotente
    $directorios = @(
        "$basePath\Public", 
        "$ftpRoot\general", 
        "$basePath\reprobados", 
        "$basePath\recursadores"
    )
    foreach ($dir in $directorios) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }

    # Crear grupos locales (Idempotente)
    foreach ($group in @("ftp-users", "reprobados", "recursadores")) {
        if (!(Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) { 
            New-LocalGroup -Name $group | Out-Null
            Write-Host "[✓] Grupo $group creado." -ForegroundColor Gray
        }
    }

    # Configurar Sitio FTP en IIS mediante el módulo WebAdministration
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\Default FTP Site")) {
        New-WebFtpSite -Name "Default FTP Site" -Port 21 -PhysicalPath $ftpRoot -Force | Out-Null
    }

    # Configurar Aislamiento de Usuarios (Requerimiento Técnico)
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='Default FTP Site']/ftpServer/userIsolation" -Name "mode" -Value "IsolateUsers"

    # Permisos NTFS Recursivos en General: g:ftp-users (Escritura), Todos (Lectura)
    $acl = Get-Acl "$ftpRoot\general"
    # ContainerInherit, ObjectInherit asegura que carpetas y archivos nuevos hereden el permiso
    $regRule = New-Object System.Security.AccessControl.FileSystemAccessRule("ftp-users","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $anonRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone","ReadAndExecute", "ContainerInherit, ObjectInherit", "None", "Allow")
    
    $acl.SetAccessRule($regRule)
    $acl.SetAccessRule($anonRule)
    Set-Acl "$ftpRoot\general" $acl

    # Abrir Firewall y asegurar que el servicio esté corriendo
    Configurar-SeguridadFirewall
    
    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Restart-Service ftpsvc
    
    Write-Host "[✓] Servidor FTP Windows instalado y configurado correctamente." -ForegroundColor Green
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