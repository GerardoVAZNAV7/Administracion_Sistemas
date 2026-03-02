# --- 1. Inicialización e Idempotencia ---
function Initialize-FTPServer {
    Write-Host "[+] Instalando Rol Web-Server e IIS-FTPServer..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Ftp-Server, Web-Mgmt-Console -IncludeManagementTools | Out-Null

    # Crear rutas físicas de datos
    $basePath = "C:\ftp_data"
    $paths = @("$basePath\general", "$basePath\groups\reprobados", "$basePath\groups\recursadores", "$basePath\users")
    foreach ($p in $paths) { if (!(Test-Path $p)) { New-Item -Path $p -ItemType Directory } }

    # Crear carpetas para el aislamiento de IIS (Requerido por Windows)
    $iisRoot = "C:\inetpub\ftproot\LocalUser"
    if (!(Test-Path "$iisRoot\Public")) { New-Item -Path "$iisRoot\Public" -ItemType Directory }

    # Crear Grupos Locales
    if (!(Get-LocalGroup -Name "reprobados" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "reprobados" }
    if (!(Get-LocalGroup -Name "recursadores" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "recursadores" }
    if (!(Get-LocalGroup -Name "ftp_users" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "ftp_users" }

    # Configurar Sitio FTP en IIS
    Import-Module WebAdministration
    if (!(Get-WebSite -Name "FTPServer" -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name "FTPServer" -Port 21 -PhysicalPath "C:\inetpub\ftproot" -Force
    }

    # Habilitar Aislamiento de Usuario
    Set-ItemProperty "IIS:\Sites\FTPServer" -Name ftpServer.userIsolation.mode -Value "IsolateUsers"

    # Permisos NTFS base para la carpeta General (Lectura para todos, Escritura para logueados)
    $acl = Get-Acl "$basePath\general"
    $ar = New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "ReadAndExecute", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($ar)
    Set-Acl "$basePath\general" $acl

    Set-FTPFirewall
    Write-Host "[✓] Servidor base configurado." -ForegroundColor Green
}

# --- 2. Alta de Usuarios y Directorios Virtuales ---
function Add-FTPUser {
    param($Username, $Password, $GroupName)

    # Crear Usuario Local
    $securePass = ConvertTo-SecureString $Password -AsPlainText -Force
    if (!(Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $Username -Password $securePass -FullName "Usuario FTP $Username" -Description "SysAdmin Practice"
        Add-LocalGroupMember -Group "ftp_users" -Member $Username
        Add-LocalGroupMember -Group $GroupName -Member $Username
    }

    # Carpeta de aislamiento y subcarpeta personal
    $userPath = "C:\inetpub\ftproot\LocalUser\$Username"
    if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory }
    
    $personalDataPath = "C:\ftp_data\users\$Username"
    if (!(Test-Path $personalDataPath)) { New-Item -Path $personalDataPath -ItemType Directory }

    # Permisos NTFS en carpeta personal
    $acl = Get-Acl $personalDataPath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($Username, "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $personalDataPath $acl

    # Crear Directorios Virtuales para la estructura visual solicitada
    # Estos aparecerán como carpetas dentro de la raíz del usuario al loguearse
    New-WebVirtualDirectory -Site "FTPServer" -Name "general" -PhysicalPath "C:\ftp_data\general" -Name "$Username/general"
    New-WebVirtualDirectory -Site "FTPServer" -Name "$GroupName" -PhysicalPath "C:\ftp_data\groups\$GroupName" -Name "$Username/$GroupName"
    New-WebVirtualDirectory -Site "FTPServer" -Name "$Username" -PhysicalPath "$personalDataPath" -Name "$Username/$Username"

    # Reglas de Autorización de FTP (Permitir lectura/escritura)
    Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";roles="";permissions="Read,Write";users=$Username} -PSPath "IIS:\" -location "FTPServer/$Username"

    Write-Host "[✓] Usuario $Username configurado en grupo $GroupName." -ForegroundColor Green
}

# --- 3. Modificación de Grupo ---
function Edit-FTPUserGroup {
    param($Username, $NewGroup)

    $oldGroup = if ($NewGroup -eq "reprobados") { "recursadores" } else { "reprobados" }

    # Cambiar grupo local
    Remove-LocalGroupMember -Group $oldGroup -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $NewGroup -Member $Username

    # Actualizar Directorio Virtual (Eliminar el anterior y crear el nuevo)
    Remove-WebVirtualDirectory -Site "FTPServer" -Name "$Username/$oldGroup" -ErrorAction SilentlyContinue
    New-WebVirtualDirectory -Site "FTPServer" -Name "$NewGroup" -PhysicalPath "C:\ftp_data\groups\$NewGroup" -Name "$Username/$NewGroup"

    Write-Host "[✓] Usuario $Username movido a $NewGroup." -ForegroundColor Green
}
function Set-FTPFirewall {
    Write-Host "[+] Configurando Firewall de Windows y Puertos Pasivos..." -ForegroundColor Cyan

    # 1. Crear reglas de entrada para el puerto 21 y el rango pasivo
    # Usamos -ErrorAction SilentlyContinue por si la regla ya existe (idempotencia)
    New-NetFirewallRule -Name "FTP_Control" -DisplayName "FTP Control (21)" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -Name "FTP_Passive" -DisplayName "FTP Passive Data (40000-40010)" -Direction Inbound -Protocol TCP -LocalPort 40000-40010 -Action Allow -ErrorAction SilentlyContinue | Out-Null

    # 2. Configurar el rango de puertos pasivos en la configuración de IIS
    Set-WebConfigurationProperty -Filter "/system.ftpServer/firewallSupport" -Name "lowDataPort" -Value 40000 -PSPath "IIS:\"
    Set-WebConfigurationProperty -Filter "/system.ftpServer/firewallSupport" -Name "highDataPort" -Value 40010 -PSPath "IIS:\"

    # 3. Reiniciar el servicio de FTP para que reconozca el rango pasivo
    Restart-Service ftpsvc
    Write-Host "[✓] Firewall e IIS configurados para conexiones desde la máquina física." -ForegroundColor Green
}