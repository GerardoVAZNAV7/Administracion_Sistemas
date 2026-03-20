# =============================================================================
# setup_repositorio_ftp.ps1  v3
# Practica 7 - Windows Server 2022
#
# CORRECCIONES v3:
#   - Fix error 530 "home directory inaccessible":
#       IIS-FTP con IsolateAllDirectories requiere una estructura EXACTA:
#       C:\FTP_Repositorio\LocalUser\danger\   <- home del usuario (chroot)
#       El usuario VE el contenido de esa carpeta al conectarse.
#       Los ZIPs van dentro de esa carpeta estructura:
#       C:\FTP_Repositorio\LocalUser\danger\repositorio\Apache\
#       C:\FTP_Repositorio\LocalUser\danger\repositorio\Nginx\
#   - Se elimino Tomcat (Windows solo tiene IIS, Apache, Nginx)
#   - Se agrega generacion de .sha256 para todos los archivos
#   - Sin caracteres especiales (ASCII puro)
#
# USO:
#   PowerShell como Administrador
#   Set-ExecutionPolicy Bypass -Scope Process
#   .\setup_repositorio_ftp.ps1
# =============================================================================

#Requires -RunAsAdministrator

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue

function Write-Ok   { param($m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Info { param($m) Write-Host "  [*]   $m" -ForegroundColor Cyan   }
function Write-Warn { param($m) Write-Host "  [!]   $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [ERR] $m" -ForegroundColor Red    }

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |   SETUP REPOSITORIO FTP - PRACTICA 7 - WINDOWS SERVER     |" -ForegroundColor Cyan
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# PASO 1: IIS + FTP
# =============================================================================
Write-Info "PASO 1: Verificando IIS y Web-FTP-Server..."

foreach ($f in @("Web-Server","Web-Ftp-Server","Web-Ftp-Service")) {
    if ((Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue).InstallState -ne "Installed") {
        Write-Info "Instalando $f..."
        Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
        Write-Ok "$f instalado."
    } else {
        Write-Ok "$f ya instalado."
    }
}
Import-Module WebAdministration -ErrorAction Stop

# =============================================================================
# PASO 2: USUARIO "danger"
# =============================================================================
Write-Info "PASO 2: Creando usuario 'danger'..."

$USUARIO    = "danger"
$CONTRASENA = ConvertTo-SecureString "Gerardo1234!!" -AsPlainText -Force

if (Get-LocalUser -Name $USUARIO -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $USUARIO -Password $CONTRASENA
    Write-Warn "Usuario ya existia. Contrasena actualizada."
} else {
    New-LocalUser -Name $USUARIO -Password $CONTRASENA `
        -FullName "Repositorio FTP P7" `
        -Description "Cuenta repositorio Practica 7" `
        -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    Write-Ok "Usuario 'danger' creado."
}

# =============================================================================
# PASO 3: ESTRUCTURA DE CARPETAS
# -----------------------------------------------------------------------------
# EXPLICACION del error 530 "home directory inaccessible":
#
# IIS-FTP en modo IsolateAllDirectories busca el home del usuario en:
#   <raiz_sitio>\LocalUser\<nombre_usuario>\
#
# Si esa carpeta no existe o no tiene permisos correctos -> error 530.
#
# La raiz del sitio apunta a: C:\FTP_Repositorio
# Por lo tanto el home de "danger" DEBE estar en:
#   C:\FTP_Repositorio\LocalUser\danger\
#
# Lo que "danger" ve al conectarse es el contenido de esa carpeta.
# Entonces los ZIPs van DENTRO:
#   C:\FTP_Repositorio\LocalUser\danger\repositorio\Apache\apache_2.4.62.zip
#   C:\FTP_Repositorio\LocalUser\danger\repositorio\Nginx\nginx_1.26.2.zip
#
# Cuando mainSSL.ps1 conecta por FTP y navega a /repositorio/Apache/
# en realidad esta accediendo a:
#   C:\FTP_Repositorio\LocalUser\danger\repositorio\Apache\
# =============================================================================
Write-Info "PASO 3: Creando estructura de carpetas (fix error 530)..."

$FTP_ROOT    = "C:\FTP_Repositorio"
$LOCAL_USER  = "$FTP_ROOT\LocalUser"
$DANGER_HOME = "$LOCAL_USER\$USUARIO"         # <- home chroot del usuario
$REPO_BASE   = "$DANGER_HOME\repositorio"     # <- lo que ve "danger" al conectarse

$carpetas = @(
    $FTP_ROOT,
    $LOCAL_USER,
    $DANGER_HOME,
    $REPO_BASE,
    "$REPO_BASE\Apache",
    "$REPO_BASE\Nginx"
)

foreach ($carpeta in $carpetas) {
    if (-not (Test-Path $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
        Write-Ok "Creada: $carpeta"
    } else {
        Write-Warn "Ya existe: $carpeta"
    }
}

# =============================================================================
# PASO 4: PERMISOS NTFS
# -----------------------------------------------------------------------------
# La raiz del sitio (FTP_ROOT) debe ser de Administrators, NO del usuario.
# Si el usuario es dueno de la raiz, IIS-FTP rechaza la conexion.
# El usuario solo necesita RX en su home y en las subcarpetas de repo.
# =============================================================================
Write-Info "PASO 4: Aplicando permisos NTFS correctos..."

$adminGrp = (New-Object Security.Principal.SecurityIdentifier "S-1-5-32-544").Translate(
    [Security.Principal.NTAccount]).Value

# Raiz del sitio: solo Admins y SYSTEM tienen control total
# danger NO debe tener control total aqui — eso causa el error 530
icacls $FTP_ROOT    /inheritance:r                      /Q | Out-Null
icacls $FTP_ROOT    /grant "SYSTEM:(OI)(CI)F"           /Q | Out-Null
icacls $FTP_ROOT    /grant "${adminGrp}:(OI)(CI)F"      /Q | Out-Null
icacls $FTP_ROOT    /grant "IIS_IUSRS:(OI)(CI)RX"       /Q | Out-Null
icacls $FTP_ROOT    /grant "IUSR:(OI)(CI)RX"            /Q | Out-Null

# LocalUser: mismo esquema
icacls $LOCAL_USER  /inheritance:r                      /Q | Out-Null
icacls $LOCAL_USER  /grant "SYSTEM:(OI)(CI)F"           /Q | Out-Null
icacls $LOCAL_USER  /grant "${adminGrp}:(OI)(CI)F"      /Q | Out-Null
icacls $LOCAL_USER  /grant "IIS_IUSRS:(OI)(CI)RX"       /Q | Out-Null
icacls $LOCAL_USER  /grant "IUSR:(OI)(CI)RX"            /Q | Out-Null

# Home del usuario: danger tiene lectura/ejecucion (no escritura en la raiz)
icacls $DANGER_HOME /inheritance:r                      /Q | Out-Null
icacls $DANGER_HOME /grant "SYSTEM:(OI)(CI)F"           /Q | Out-Null
icacls $DANGER_HOME /grant "${adminGrp}:(OI)(CI)F"      /Q | Out-Null
icacls $DANGER_HOME /grant "IIS_IUSRS:(OI)(CI)RX"       /Q | Out-Null
icacls $DANGER_HOME /grant "IUSR:(OI)(CI)RX"            /Q | Out-Null
icacls $DANGER_HOME /grant "${USUARIO}:(OI)(CI)RX"      /Q | Out-Null

# Repositorio y subcarpetas: danger puede leer
icacls $REPO_BASE   /inheritance:r                      /Q | Out-Null
icacls $REPO_BASE   /grant "SYSTEM:(OI)(CI)F"           /Q | Out-Null
icacls $REPO_BASE   /grant "${adminGrp}:(OI)(CI)F"      /Q | Out-Null
icacls $REPO_BASE   /grant "IIS_IUSRS:(OI)(CI)RX"       /Q | Out-Null
icacls $REPO_BASE   /grant "IUSR:(OI)(CI)RX"            /Q | Out-Null
icacls $REPO_BASE   /grant "${USUARIO}:(OI)(CI)RX"      /Q | Out-Null

Write-Ok "Permisos NTFS aplicados correctamente."

# =============================================================================
# PASO 5: DESCARGAR INSTALADORES Y GENERAR .sha256
# =============================================================================
Write-Info "PASO 5: Descargando instaladores y generando hashes SHA256..."

function Obtener-ZIP {
    param(
        [string]$Url,
        [string]$NombreArchivo,
        [string]$Destino,
        [string]$Etiqueta
    )
    $ruta    = Join-Path $Destino $NombreArchivo
    $rutaEnC = "C:\$NombreArchivo"

    # Prioridad: ya en repo > ya en C:\ > descargar
    if (Test-Path $ruta) {
        Write-Warn "$Etiqueta ya en repositorio. Omitiendo descarga."
    } elseif (Test-Path $rutaEnC) {
        Write-Info "Encontrado en C:\. Copiando al repositorio..."
        Copy-Item $rutaEnC $ruta -Force
        Write-Ok "Copiado a $Destino\"
    } else {
        Write-Info "Descargando $Etiqueta desde internet..."
        Write-Host "    $Url" -ForegroundColor DarkGray
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $ruta -UseBasicParsing -TimeoutSec 180
            $ProgressPreference = 'Continue'
            Write-Ok "$Etiqueta descargado."
            # Copiar tambien a C:\ para que funciones_SSL.ps1 lo encuentre
            if (-not (Test-Path $rutaEnC)) {
                Copy-Item $ruta $rutaEnC
                Write-Ok "Copia en C:\$NombreArchivo"
            }
        } catch {
            $ProgressPreference = 'Continue'
            Write-Err "Descarga fallida: $Etiqueta"
            Write-Host ""
            Write-Host "  Descarga manual:" -ForegroundColor Yellow
            Write-Host "    URL  : $Url" -ForegroundColor Yellow
            Write-Host "    Guarda como: C:\$NombreArchivo" -ForegroundColor Yellow
            Write-Host "    Y tambien en: $Destino\$NombreArchivo" -ForegroundColor Yellow
            Write-Host ""
            return
        }
    }

    # Generar .sha256 siempre que el archivo exista
    if (Test-Path $ruta) {
        $sha256Path = "$ruta.sha256"
        $hash = (Get-FileHash -Path $ruta -Algorithm SHA256).Hash.ToLower()
        $hash | Out-File -FilePath $sha256Path -Encoding ascii -NoNewline
        Write-Ok "SHA256 generado: $([System.IO.Path]::GetFileName($sha256Path))"
        Write-Host "    Hash: $hash" -ForegroundColor DarkGray
    }
}

# Apache 2.4.62 — fuente: apachelounge.com (proveedor oficial para Windows)
Obtener-ZIP `
    -Url           "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.62-240904-win64-VS17.zip" `
    -NombreArchivo "apache_2.4.62.zip" `
    -Destino       "$REPO_BASE\Apache" `
    -Etiqueta      "Apache 2.4.62"

Write-Host ""

# Nginx 1.26.2 — fuente: nginx.org (sitio oficial)
Obtener-ZIP `
    -Url           "https://nginx.org/download/nginx-1.26.2.zip" `
    -NombreArchivo "nginx_1.26.2.zip" `
    -Destino       "$REPO_BASE\Nginx" `
    -Etiqueta      "Nginx 1.26.2"

# =============================================================================
# PASO 6: CONFIGURAR SITIO FTP EN IIS
# =============================================================================
Write-Host ""
Write-Info "PASO 6: Configurando sitio FTP en IIS..."

$SITE_NAME = "Repositorio_P7"

# Eliminar sitio anterior si existe
if (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue) {
    Write-Warn "Eliminando sitio anterior '$SITE_NAME'..."
    Stop-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
    Remove-WebSite -Name $SITE_NAME
}

# Crear sitio FTP apuntando a la RAIZ (no al home del usuario)
# IIS-FTP construye la ruta del home automaticamente:
#   <FTP_ROOT>\LocalUser\<usuario>\ 
New-WebFtpSite -Name $SITE_NAME -Port 21 -PhysicalPath $FTP_ROOT -Force | Out-Null
Write-Ok "Sitio FTP '$SITE_NAME' creado. Raiz: $FTP_ROOT"

# IsolateAllDirectories: cada usuario va a su propia carpeta
# Modo 3 = IsolateAllDirectories
Set-ItemProperty "IIS:\Sites\$SITE_NAME" -Name ftpServer.userIsolation.mode -Value 3
Write-Ok "Modo IsolateAllDirectories activado."

# Autenticacion basica activada, anonimo desactivado
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $false

# Sin SSL en el FTP del repositorio (mainSSL.ps1 usa curl sin cifrado)
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

Write-Ok "Autenticacion basica configurada."

# Puertos pasivos
Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" `
    -Name "lowDataChannelPort"  -Value 50000
Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" `
    -Name "highDataChannelPort" -Value 50100
Write-Ok "Puertos pasivos: 50000-50100."

# Regla de autorizacion FTP para "danger"
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    & $appcmd clear config $SITE_NAME /section:system.ftpServer/security/authorization 2>&1 | Out-Null
    & $appcmd set config $SITE_NAME /section:system.ftpServer/security/authorization `
        "/+[accessType='Allow',users='$USUARIO',permissions='Read']" 2>&1 | Out-Null
    Write-Ok "Regla FTP: 'danger' puede leer."
}

# =============================================================================
# PASO 7: FIREWALL
# =============================================================================
Write-Host ""
Write-Info "PASO 7: Configurando firewall..."

foreach ($regla in @(
    @{ Name = "FTP Control Port P7";  Port = "21"          },
    @{ Name = "FTP Passive Ports P7"; Port = "50000-50100" }
)) {
    if (-not (Get-NetFirewallRule -DisplayName $regla.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $regla.Name -Direction Inbound `
            -Protocol TCP -LocalPort $regla.Port -Action Allow | Out-Null
        Write-Ok "Regla creada: $($regla.Name)"
    } else {
        Write-Warn "Regla ya existe: $($regla.Name)"
    }
}

# =============================================================================
# PASO 8: INICIAR SERVICIOS
# =============================================================================
Write-Host ""
Write-Info "PASO 8: Iniciando servicios..."

Start-Service W3SVC  -ErrorAction SilentlyContinue
Start-Service ftpsvc -ErrorAction SilentlyContinue
Start-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$ftpOk   = (Get-Service ftpsvc -ErrorAction SilentlyContinue).Status -eq "Running"
$sitioOk = (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue).State -eq "Started"

if ($ftpOk -and $sitioOk) {
    Write-Ok "ftpsvc corriendo y sitio '$SITE_NAME' iniciado."
} else {
    Write-Warn "Verifica manualmente: Get-Service ftpsvc"
}

# =============================================================================
# RESUMEN
# =============================================================================
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  +================================================================+" -ForegroundColor Green
Write-Host "  |                SETUP COMPLETADO                                |" -ForegroundColor Green
Write-Host "  +================================================================+" -ForegroundColor Green
Write-Host ("  |  Usuario      : danger                                         |") -ForegroundColor White
Write-Host ("  |  Contrasena   : Gerardo1234!!                                  |") -ForegroundColor White
Write-Host ("  |  IP Servidor  : " + $ip.PadRight(45) + "|") -ForegroundColor White
Write-Host ("  |  Puerto FTP   : 21                                             |") -ForegroundColor White
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  Estructura de carpetas:                                       |" -ForegroundColor White
Write-Host "  |    C:\FTP_Repositorio\                  <- raiz del sitio FTP  |" -ForegroundColor White
Write-Host "  |    C:\FTP_Repositorio\LocalUser\danger\ <- home de danger      |" -ForegroundColor White
Write-Host "  |    ...\danger\repositorio\Apache\       <- ZIPs Apache         |" -ForegroundColor White
Write-Host "  |    ...\danger\repositorio\Nginx\        <- ZIPs Nginx          |" -ForegroundColor White
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  Prueba de conexion FTP:                                       |" -ForegroundColor Cyan
Write-Host ("  |    curl -l -u danger:Gerardo1234!! ftp://" + $ip + "/repositorio/Apache/") -ForegroundColor Cyan
Write-Host "  |  Debes ver: apache_2.4.62.zip  apache_2.4.62.zip.sha256        |" -ForegroundColor Cyan
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  En FileZilla:                                                  |" -ForegroundColor Yellow
Write-Host "  |    Host    : $ip                                                |" -ForegroundColor Yellow
Write-Host "  |    Usuario : danger                                             |" -ForegroundColor Yellow
Write-Host "  |    Contrasena: Gerardo1234!!                                    |" -ForegroundColor Yellow
Write-Host "  |    Puerto  : 21                                                 |" -ForegroundColor Yellow
Write-Host "  |    Cifrado : FTP plano (sin TLS)                                |" -ForegroundColor Yellow
Write-Host "  +================================================================+" -ForegroundColor Green
Write-Host ""

Write-Info "Contenido del repositorio:"
Get-ChildItem $REPO_BASE -Recurse -File | ForEach-Object {
    $mb = [math]::Round($_.Length / 1MB, 1)
    Write-Host ("    " + $_.FullName.Replace($DANGER_HOME,"") + "  ($mb MB)") -ForegroundColor Gray
}
Write-Host ""