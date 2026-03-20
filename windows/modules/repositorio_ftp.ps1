# =============================================================================
# setup_repositorio_ftp.ps1
# Proposito: Preparar el servidor FTP de Windows para la Practica 7
#
# Este script hace TODO lo siguiente:
#   1. Verifica que IIS y Web-FTP-Server esten instalados
#   2. Crea el usuario "danger" con contrasena "Gerardo1234!!"
#   3. Crea la estructura de carpetas del repositorio FTP
#   4. Descarga los ZIPs de Apache y Nginx desde sus sitios oficiales
#   5. Genera los archivos .sha256 de cada instalador
#   6. Configura el sitio FTP para que "danger" pueda acceder
#
# NOTA SOBRE EL ENCODING:
#   Este script usa solo ASCII puro (sin tildes ni caracteres especiales)
#   para evitar que PowerShell muestre caracteres corruptos en Windows Server
#   que usa CP850 por defecto en lugar de UTF-8.
#
# USO:
#   1. Abrir PowerShell como Administrador
#   2. Set-ExecutionPolicy Bypass -Scope Process
#   3. .\windows\modules\setup_repositorio_ftp.ps1
# =============================================================================

#Requires -RunAsAdministrator

# Forzar UTF-8 en la consola para evitar caracteres corruptos
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue

# Helpers de color — sin tildes ni caracteres especiales
function Write-Ok   { param($m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Info { param($m) Write-Host "  [*]   $m" -ForegroundColor Cyan   }
function Write-Warn { param($m) Write-Host "  [!]   $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [ERR] $m" -ForegroundColor Red    }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |   SETUP REPOSITORIO FTP - PRACTICA 7 - WINDOWS SERVER     |" -ForegroundColor Cyan
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# PASO 1: VERIFICAR E INSTALAR IIS + FTP
# =============================================================================
Write-Info "PASO 1: Verificando IIS y Web-FTP-Server..."

$features = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service")
foreach ($f in $features) {
    $state = (Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue).InstallState
    if ($state -ne "Installed") {
        Write-Info "Instalando $f..."
        Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
        Write-Ok "$f instalado."
    } else {
        Write-Ok "$f ya instalado."
    }
}

Import-Module WebAdministration -ErrorAction Stop

# =============================================================================
# PASO 2: CREAR USUARIO "danger"
# =============================================================================
Write-Info "PASO 2: Creando usuario local 'danger'..."

$USUARIO    = "danger"
$CONTRASENA = ConvertTo-SecureString "Gerardo1234!!" -AsPlainText -Force

$usuarioExiste = Get-LocalUser -Name $USUARIO -ErrorAction SilentlyContinue

if ($usuarioExiste) {
    Write-Warn "El usuario '$USUARIO' ya existe. Actualizando contrasena..."
    Set-LocalUser -Name $USUARIO -Password $CONTRASENA
    Write-Ok "Contrasena de '$USUARIO' actualizada."
} else {
    New-LocalUser -Name $USUARIO `
                  -Password $CONTRASENA `
                  -FullName "Usuario Repositorio FTP" `
                  -Description "Cuenta repositorio Practica 7" `
                  -PasswordNeverExpires `
                  -UserMayNotChangePassword | Out-Null
    Write-Ok "Usuario '$USUARIO' creado con contrasena 'Gerardo1234!!'."
}

# =============================================================================
# PASO 3: CREAR ESTRUCTURA DE CARPETAS
# =============================================================================
Write-Info "PASO 3: Creando estructura del repositorio FTP..."

# Estructura de carpetas:
#   C:\FTP_Repositorio\                    <- raiz del sitio FTP
#   C:\FTP_Repositorio\repositorio\Apache\ <- ZIPs de Apache + .sha256
#   C:\FTP_Repositorio\repositorio\Nginx\  <- ZIPs de Nginx  + .sha256
#
# Cuando mainSSL.ps1 se conecta por FTP como "danger" ve:
#   /repositorio/Apache/apache_2.4.62.zip
#   /repositorio/Nginx/nginx_1.26.2.zip

$FTP_ROOT  = "C:\FTP_Repositorio"
$REPO_BASE = "$FTP_ROOT\repositorio"

$carpetas = @(
    $FTP_ROOT,
    $REPO_BASE,
    "$REPO_BASE\Apache",
    "$REPO_BASE\Nginx",
    "$REPO_BASE\Tomcat",
    "$REPO_BASE\vsftpd"
)

foreach ($carpeta in $carpetas) {
    if (-not (Test-Path $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
        Write-Ok "Creada: $carpeta"
    } else {
        Write-Warn "Ya existe: $carpeta"
    }
}

Write-Ok "Estructura de carpetas lista."

# =============================================================================
# PASO 4: DESCARGAR LOS INSTALADORES ZIP
# =============================================================================
# De donde se descargan:
#
#   Apache: https://www.apachelounge.com/download/
#     -> proveedor oficial de binarios Apache para Windows
#     -> los ZIPs son portables, no instaladores MSI
#
#   Nginx:  https://nginx.org/download/
#     -> sitio oficial del proyecto Nginx
#
# Por que estos y no otros:
#     Los ZIPs van en C:\ para que funciones_SSL.ps1 los encuentre
#     al momento de instalar (la practica 6 usaba el mismo enfoque).

Write-Info "PASO 4: Descargando instaladores ZIP..."

function Descargar-ZIP {
    param(
        [string]$Url,
        [string]$Destino,
        [string]$NombreArchivo,
        [string]$Etiqueta
    )

    $rutaCompleta = Join-Path $Destino $NombreArchivo

    # Si ya existe en el repositorio, no descargamos de nuevo
    if (Test-Path $rutaCompleta) {
        Write-Warn "$Etiqueta ya existe en $rutaCompleta. Omitiendo descarga."
    }
    # Si ya existe en C:\ (de la Practica 6), solo copiamos
    elseif (Test-Path "C:\$NombreArchivo") {
        Write-Warn "Encontrado en C:\$NombreArchivo. Copiando al repositorio..."
        Copy-Item -Path "C:\$NombreArchivo" -Destination $rutaCompleta -Force
        Write-Ok "Copiado desde C:\ -> $Destino\"
    }
    else {
        Write-Info "Descargando $Etiqueta desde internet..."
        Write-Info "  URL: $Url"
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url `
                              -OutFile $rutaCompleta `
                              -UseBasicParsing `
                              -TimeoutSec 180
            $ProgressPreference = 'Continue'
            Write-Ok "$Etiqueta descargado: $NombreArchivo"

            # Copiar tambien a C:\ para que funciones_SSL.ps1 lo encuentre
            if (-not (Test-Path "C:\$NombreArchivo")) {
                Copy-Item -Path $rutaCompleta -Destination "C:\$NombreArchivo"
                Write-Ok "Copiado tambien a C:\$NombreArchivo"
            }
        }
        catch {
            $ProgressPreference = 'Continue'
            Write-Err "No se pudo descargar $Etiqueta"
            Write-Host ""
            Write-Host "  +--- DESCARGA MANUAL -----------------------------------+" -ForegroundColor Yellow
            Write-Host "  | Ve a esta URL en tu navegador y descarga el archivo:  |" -ForegroundColor Yellow
            Write-Host "  |   $Url" -ForegroundColor Yellow
            Write-Host "  |                                                        |" -ForegroundColor Yellow
            Write-Host "  | Guarda el archivo con este nombre exacto:             |" -ForegroundColor Yellow
            Write-Host "  |   $NombreArchivo" -ForegroundColor Yellow
            Write-Host "  |                                                        |" -ForegroundColor Yellow
            Write-Host "  | Coloca el archivo en AMBAS rutas:                     |" -ForegroundColor Yellow
            Write-Host "  |   C:\$NombreArchivo" -ForegroundColor Yellow
            Write-Host "  |   $Destino\$NombreArchivo" -ForegroundColor Yellow
            Write-Host "  +-------------------------------------------------------+" -ForegroundColor Yellow
            Write-Host ""
            return
        }
    }

    # Generar el .sha256
    # Get-FileHash calcula el hash del archivo
    # Lo guardamos en minusculas sin salto de linea
    $sha256Path = "$rutaCompleta.sha256"
    if (-not (Test-Path $sha256Path)) {
        Write-Info "Calculando hash SHA256..."
        $hash = (Get-FileHash -Path $rutaCompleta -Algorithm SHA256).Hash.ToLower()
        $hash | Out-File -FilePath $sha256Path -Encoding ascii -NoNewline
        Write-Ok "SHA256: $hash"
        Write-Ok "Guardado en: $sha256Path"
    } else {
        Write-Warn "El .sha256 ya existe. Omitiendo calculo."
    }
}

# Apache 2.4.62 para Windows 64-bit (VS17 = Visual Studio 2022 runtime)
# Si esta URL ya no existe ve a: https://www.apachelounge.com/download/
# y busca la version "Apache X.X.X Win64 VS17"
$apacheVersion  = "2.4.62"
$apacheFileName = "apache_$apacheVersion.zip"
$apacheUrl      = "https://www.apachelounge.com/download/VS17/binaries/httpd-${apacheVersion}-240904-win64-VS17.zip"

Write-Host ""
Write-Info "Descargando Apache para Windows..."
Descargar-ZIP -Url $apacheUrl `
              -Destino "$REPO_BASE\Apache" `
              -NombreArchivo $apacheFileName `
              -Etiqueta "Apache $apacheVersion"

# Nginx 1.26.2 para Windows (rama stable)
# Si esta URL ya no existe ve a: https://nginx.org/en/download.html
# y busca la version "Stable version"
$nginxVersion  = "1.26.2"
$nginxFileName = "nginx_$nginxVersion.zip"
$nginxUrl      = "https://nginx.org/download/nginx-$nginxVersion.zip"

Write-Host ""
Write-Info "Descargando Nginx para Windows..."
Descargar-ZIP -Url $nginxUrl `
              -Destino "$REPO_BASE\Nginx" `
              -NombreArchivo $nginxFileName `
              -Etiqueta "Nginx $nginxVersion"

# =============================================================================
# PASO 5: CONFIGURAR EL SITIO FTP EN IIS
# =============================================================================
Write-Host ""
Write-Info "PASO 5: Configurando sitio FTP en IIS..."

$SITE_NAME = "Repositorio_P7"

if (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue) {
    Write-Warn "Eliminando sitio FTP anterior '$SITE_NAME'..."
    Stop-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
    Remove-WebSite -Name $SITE_NAME
}

# Crear el sitio FTP apuntando a C:\FTP_Repositorio
New-WebFtpSite -Name $SITE_NAME `
               -Port 21 `
               -PhysicalPath $FTP_ROOT `
               -Force | Out-Null

Write-Ok "Sitio FTP '$SITE_NAME' creado."

# Autenticacion basica activada, anonimo desactivado
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $false

# Sin SSL en el FTP del repositorio
# (mainSSL.ps1 usa curl sin cifrado para listar/descargar los ZIPs)
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

# Sin aislamiento de usuario — danger ve todo C:\FTP_Repositorio
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.userIsolation.mode -Value 0

Write-Ok "Autenticacion configurada (basica, sin anonimo, sin SSL)."

# Permisos NTFS
Write-Info "Configurando permisos NTFS para '$USUARIO'..."
icacls $FTP_ROOT /grant "${USUARIO}:(OI)(CI)RX" /T /Q | Out-Null
icacls $FTP_ROOT /grant "IIS_IUSRS:(OI)(CI)RX"  /T /Q | Out-Null
icacls $FTP_ROOT /grant "IUSR:(OI)(CI)RX"        /T /Q | Out-Null
Write-Ok "Permisos NTFS aplicados."

# Regla de autorizacion FTP
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    & $appcmd clear config $SITE_NAME /section:system.ftpServer/security/authorization 2>&1 | Out-Null
    & $appcmd set config $SITE_NAME /section:system.ftpServer/security/authorization `
        "/+[accessType='Allow',users='$USUARIO',permissions='Read']" 2>&1 | Out-Null
    Write-Ok "Regla de autorizacion FTP creada para '$USUARIO'."
}

# Puertos pasivos
Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" `
    -Name "lowDataChannelPort"  -Value 50000
Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" `
    -Name "highDataChannelPort" -Value 50100
Write-Ok "Puertos pasivos: 50000-50100."

# =============================================================================
# PASO 6: FIREWALL DE WINDOWS
# =============================================================================
Write-Host ""
Write-Info "PASO 6: Configurando firewall de Windows..."

$reglasFTP = @(
    @{ Name = "FTP Control Port P7";  Port = "21";          },
    @{ Name = "FTP Passive Ports P7"; Port = "50000-50100"; }
)

foreach ($regla in $reglasFTP) {
    if (-not (Get-NetFirewallRule -DisplayName $regla.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $regla.Name `
                            -Direction Inbound -Protocol TCP `
                            -LocalPort $regla.Port -Action Allow | Out-Null
        Write-Ok "Regla creada: $($regla.Name)"
    } else {
        Write-Warn "Regla ya existe: $($regla.Name)"
    }
}

# =============================================================================
# PASO 7: INICIAR SERVICIOS
# =============================================================================
Write-Host ""
Write-Info "PASO 7: Iniciando servicios FTP..."

Start-Service W3SVC   -ErrorAction SilentlyContinue
Start-Service ftpsvc  -ErrorAction SilentlyContinue
Start-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$ftpActivo   = (Get-Service ftpsvc -ErrorAction SilentlyContinue).Status -eq "Running"
$sitioActivo = (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue).State -eq "Started"

if ($ftpActivo -and $sitioActivo) {
    Write-Ok "FTP corriendo. Sitio '$SITE_NAME' iniciado."
} else {
    Write-Warn "Verifica el estado manualmente:"
    Write-Warn "  Get-Service ftpsvc"
    Write-Warn "  Get-WebSite -Name '$SITE_NAME'"
}

# =============================================================================
# RESUMEN FINAL
# =============================================================================
$ipServidor = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  +================================================================+" -ForegroundColor Green
Write-Host "  |              SETUP COMPLETADO EXITOSAMENTE                     |" -ForegroundColor Green
Write-Host "  +================================================================+" -ForegroundColor Green
Write-Host "  |  Usuario FTP : danger                                          |" -ForegroundColor White
Write-Host "  |  Contrasena  : Gerardo1234!!                                   |" -ForegroundColor White
Write-Host ("  |  IP Servidor : " + $ipServidor.PadRight(45) + "|") -ForegroundColor White
Write-Host "  |  Puerto FTP  : 21                                              |" -ForegroundColor White
Write-Host ("  |  Sitio IIS   : " + $SITE_NAME.PadRight(45) + "|") -ForegroundColor White
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  Estructura del repositorio:                                   |" -ForegroundColor White
Write-Host "  |    C:\FTP_Repositorio\repositorio\Apache\  (ZIPs Apache)       |" -ForegroundColor White
Write-Host "  |    C:\FTP_Repositorio\repositorio\Nginx\   (ZIPs Nginx)        |" -ForegroundColor White
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  Para probar la conexion FTP:                                  |" -ForegroundColor Cyan
Write-Host ("  |    curl -l -u danger:Gerardo1234!! ftp://" + $ipServidor + "/repositorio/Apache/") -ForegroundColor Cyan
Write-Host "  |  Deberias ver: apache_2.4.62.zip                               |" -ForegroundColor Cyan
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  SIGUIENTE PASO: Actualizar en funciones_SSL.ps1:              |" -ForegroundColor Yellow
Write-Host "  |    `$ftpUser     = 'danger'                                      |" -ForegroundColor Yellow
Write-Host "  |    `$ftpPassword = 'Gerardo1234!!'                               |" -ForegroundColor Yellow
Write-Host ("  |    `$urlBase     = 'ftp://" + $ipServidor + "/'") -ForegroundColor Yellow
Write-Host "  +================================================================+" -ForegroundColor Green
Write-Host ""

Write-Info "Archivos en el repositorio:"
Get-ChildItem $REPO_BASE -Recurse -File | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 2)
    Write-Host ("    " + $_.FullName + "  (" + $size + " MB)") -ForegroundColor Gray
}
Write-Host ""