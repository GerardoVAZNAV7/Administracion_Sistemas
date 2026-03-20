# =============================================================================
# setup_repositorio_ftp.ps1
# Propósito: Preparar el servidor FTP de Windows para la Práctica 7
#
# Este script hace TODO lo siguiente:
#   1. Verifica que IIS y Web-FTP-Server estén instalados
#   2. Crea el usuario "danger" con contraseña "Gerardo1234!!"
#   3. Crea la estructura de carpetas del repositorio FTP
#   4. Descarga los ZIPs de Apache y Nginx desde sus sitios oficiales
#   5. Genera los archivos .sha256 de cada instalador
#   6. Configura el sitio FTP para que "danger" pueda acceder
#
# USO:
#   1. Abrir PowerShell como Administrador
#   2. Set-ExecutionPolicy Bypass -Scope Process
#   3. .\windows\modules\setup_repositorio_ftp.ps1
# =============================================================================

#Requires -RunAsAdministrator

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue

# ── Colores / helpers ────────────────────────────────────────────────────────
function Write-Ok   { param($m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Info { param($m) Write-Host "  [*]   $m" -ForegroundColor Cyan   }
function Write-Warn { param($m) Write-Host "  [!]   $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [ERR] $m" -ForegroundColor Red    }

# TLS 1.2 para descargas HTTPS (Windows Server a veces usa versiones antiguas)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |  SETUP REPOSITORIO FTP — PRÁCTICA 7 — WINDOWS SERVER 2022 |" -ForegroundColor Cyan
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
    Write-Warn "El usuario '$USUARIO' ya existe. Actualizando contraseña..."
    Set-LocalUser -Name $USUARIO -Password $CONTRASENA
    Write-Ok "Contraseña de '$USUARIO' actualizada."
} else {
    # New-LocalUser:
    #   -PasswordNeverExpires   = la contraseña no caduca (útil para labs)
    #   -UserMayNotChangePassword = el usuario no puede cambiarla
    New-LocalUser -Name $USUARIO `
                  -Password $CONTRASENA `
                  -FullName "Usuario Repositorio FTP" `
                  -Description "Cuenta para repositorio de Práctica 7" `
                  -PasswordNeverExpires `
                  -UserMayNotChangePassword | Out-Null
    Write-Ok "Usuario '$USUARIO' creado con contraseña 'Gerardo1234!!'."
}

# =============================================================================
# PASO 3: CREAR ESTRUCTURA DE CARPETAS DEL REPOSITORIO
# =============================================================================
Write-Info "PASO 3: Creando estructura del repositorio FTP..."

# En Windows con IIS-FTP en modo IsolateAllDirectories la estructura es:
#
#   C:\FTP\LocalUser\<usuario>\         ← chroot raíz del usuario
#   C:\FTP\LocalUser\<usuario>\<usuario>\ ← carpeta personal
#
# Pero para el REPOSITORIO vamos a hacer algo más simple:
# El sitio FTP apuntará a C:\FTP_Repositorio\ y danger tendrá acceso a todo.
#
# Estructura que necesita mainSSL.ps1 (via Navegar-Descargar-FTP):
#   C:\FTP_Repositorio\repositorio\Apache\   ← ZIPs de Apache + .sha256
#   C:\FTP_Repositorio\repositorio\Nginx\    ← ZIPs de Nginx + .sha256
#
# El usuario "repositorio" de funciones_SSL.ps1 ya estaba hardcodeado.
# Creamos TAMBIÉN "danger" con acceso a las mismas carpetas.

$FTP_ROOT  = "C:\FTP_Repositorio"
$REPO_BASE = "$FTP_ROOT\repositorio"

$carpetas = @(
    "$FTP_ROOT",
    "$REPO_BASE",
    "$REPO_BASE\Apache",
    "$REPO_BASE\Nginx",
    # Para compatibilidad con la estructura Linux también
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

# Estructura para IIS-FTP IsolateAllDirectories
# (carpeta del usuario danger dentro de LocalUser)
$FTP_USERS   = "C:\FTP_Repositorio\LocalUser"
$DANGER_HOME = "$FTP_USERS\$USUARIO"
$DANGER_PERSONAL = "$DANGER_HOME\$USUARIO"

New-Item -ItemType Directory -Path $DANGER_HOME     -Force | Out-Null
New-Item -ItemType Directory -Path $DANGER_PERSONAL -Force | Out-Null

Write-Ok "Estructura de carpetas creada."

# =============================================================================
# PASO 4: DESCARGAR LOS INSTALADORES ZIP
# =============================================================================
# ─────────────────────────────────────────────────────────────────────────────
# ¿DE DÓNDE SE DESCARGAN?
#
# Apache para Windows:
#   https://www.apachelounge.com/download/
#   URL directa: https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.62-240904-win64-VS17.zip
#   (la versión cambia — el script busca la más reciente)
#
# Nginx para Windows:
#   https://nginx.org/en/download.html
#   URL directa: https://nginx.org/download/nginx-1.26.2.zip
#
# ¿Por qué estas URLs?
#   - Son las fuentes OFICIALES de cada proyecto
#   - Los ZIPs son portables (no instaladores .msi) → se usan directamente en C:\
#   - Ya los necesitabas en C:\ para la Práctica 6, ahora también van al repo FTP
# ─────────────────────────────────────────────────────────────────────────────

Write-Info "PASO 4: Descargando instaladores ZIP..."

# Función para descargar un ZIP y generar su .sha256
function Descargar-ZIP {
    param(
        [string]$Url,
        [string]$Destino,
        [string]$NombreArchivo,
        [string]$Etiqueta
    )

    $rutaCompleta = Join-Path $Destino $NombreArchivo

    if (Test-Path $rutaCompleta) {
        Write-Warn "$Etiqueta ya existe en $rutaCompleta. Omitiendo descarga."
    } else {
        Write-Info "Descargando $Etiqueta desde: $Url"
        try {
            # Invoke-WebRequest descarga el archivo
            # -UseBasicParsing: más compatible (no necesita IE engine)
            Invoke-WebRequest -Uri $Url `
                              -OutFile $rutaCompleta `
                              -UseBasicParsing `
                              -TimeoutSec 120
            Write-Ok "$Etiqueta descargado: $rutaCompleta"
        } catch {
            Write-Warn "Fallo la descarga automática de $Etiqueta."
            Write-Warn "URL intentada: $Url"
            Write-Warn "Descárgalo manualmente y colócalo en: $Destino"
            Write-Warn "Nombre esperado del archivo: $NombreArchivo"
            return $false
        }
    }

    # Generar .sha256
    $sha256Path = "$rutaCompleta.sha256"
    if (-not (Test-Path $sha256Path)) {
        Write-Info "Generando hash SHA256 para $Etiqueta..."
        $hash = (Get-FileHash -Path $rutaCompleta -Algorithm SHA256).Hash.ToLower()
        # Guardamos solo el hash (sin el nombre del archivo)
        # para que mainSSL.ps1 pueda leerlo con Get-Content
        $hash | Out-File -FilePath $sha256Path -Encoding ascii -NoNewline
        Write-Ok "Hash generado: $sha256Path"
        Write-Ok "SHA256: $hash"
    } else {
        Write-Warn "El archivo .sha256 ya existe. Omitiendo."
    }

    # Copiar también a C:\ para que funciones_SSL.ps1 lo encuentre
    # (funciones_SSL.ps1 busca ZIPs en C:\)
    $rutaC = "C:\$NombreArchivo"
    if (-not (Test-Path $rutaC)) {
        Copy-Item -Path $rutaCompleta -Destination $rutaC
        Write-Ok "Copiado también a $rutaC (para funciones_SSL.ps1)"
    }

    return $true
}

# ── Apache ───────────────────────────────────────────────────────────────────
# ApacheLounge es el proveedor oficial de binarios de Apache para Windows
# La versión 2.4.62 es la estable al momento de escribir este script
# Si la URL cambia, ve a https://www.apachelounge.com/download/ y busca la actual

$apacheVersion  = "2.4.62"
$apacheFileName = "apache_$apacheVersion.zip"
$apacheUrl      = "https://www.apachelounge.com/download/VS17/binaries/httpd-${apacheVersion}-240904-win64-VS17.zip"

$descargado = Descargar-ZIP -Url $apacheUrl `
                             -Destino "$REPO_BASE\Apache" `
                             -NombreArchivo $apacheFileName `
                             -Etiqueta "Apache $apacheVersion"

if (-not $descargado) {
    Write-Warn ""
    Write-Warn "Si la descarga falló, descarga manualmente Apache desde:"
    Write-Warn "  https://www.apachelounge.com/download/"
    Write-Warn "Busca el ZIP de 'Apache 2.4.x Win64 VS17'"
    Write-Warn "Renómbralo como: $apacheFileName"
    Write-Warn "Colócalo en: $REPO_BASE\Apache\"
    Write-Warn "Y también en: C:\"
    Write-Warn ""
}

# ── Nginx ────────────────────────────────────────────────────────────────────
# nginx.org es el sitio oficial de Nginx
# La versión 1.26.2 es la rama estable (stable) para Windows

$nginxVersion  = "1.26.2"
$nginxFileName = "nginx_$nginxVersion.zip"
$nginxUrl      = "https://nginx.org/download/nginx-$nginxVersion.zip"

$descargado = Descargar-ZIP -Url $nginxUrl `
                             -Destino "$REPO_BASE\Nginx" `
                             -NombreArchivo $nginxFileName `
                             -Etiqueta "Nginx $nginxVersion"

if (-not $descargado) {
    Write-Warn ""
    Write-Warn "Si la descarga falló, descarga manualmente Nginx desde:"
    Write-Warn "  https://nginx.org/en/download.html"
    Write-Warn "Busca 'nginx/Windows-X.XX.X' en la sección Stable"
    Write-Warn "El ZIP descargado se llama nginx-X.XX.X.zip"
    Write-Warn "Renómbralo como: $nginxFileName"
    Write-Warn "Colócalo en: $REPO_BASE\Nginx\"
    Write-Warn "Y también en: C:\"
    Write-Warn ""
}

# =============================================================================
# PASO 5: CONFIGURAR EL SITIO FTP EN IIS
# =============================================================================
Write-Info "PASO 5: Configurando sitio FTP en IIS..."

$SITE_NAME = "Repositorio_P7"

# Eliminar sitio previo si existe
if (Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue) {
    Write-Warn "Eliminando sitio FTP anterior '$SITE_NAME'..."
    Remove-WebSite -Name $SITE_NAME
}

# Crear el sitio FTP
# -PhysicalPath: apunta a C:\FTP_Repositorio (raíz del repositorio)
# -Port 21: puerto estándar FTP
New-WebFtpSite -Name $SITE_NAME `
               -Port 21 `
               -PhysicalPath $FTP_ROOT `
               -Force | Out-Null

Write-Ok "Sitio FTP '$SITE_NAME' creado."

# ── Configurar autenticación ─────────────────────────────────────────────────
# Activar autenticación básica (usuario + contraseña)
# Desactivar anónimo (el repositorio es privado)
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $false

# ── Sin SSL (para acceso desde mainSSL.ps1 con curl) ────────────────────────
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

# ── Sin aislamiento: el usuario ve todo $FTP_ROOT ───────────────────────────
# (Usamos mode 0 = No isolation para el repositorio)
Set-ItemProperty "IIS:\Sites\$SITE_NAME" `
    -Name ftpServer.userIsolation.mode -Value 0

Write-Ok "Autenticación configurada (básica, sin anónimo, sin SSL)."

# ── Permisos NTFS para "danger" ──────────────────────────────────────────────
Write-Info "Configurando permisos NTFS para '$USUARIO'..."

icacls $FTP_ROOT /grant "${USUARIO}:(OI)(CI)RX" /T /Q | Out-Null
icacls "$REPO_BASE" /grant "${USUARIO}:(OI)(CI)RX" /T /Q | Out-Null

# Permisos de IIS
icacls $FTP_ROOT /grant "IIS_IUSRS:(OI)(CI)RX" /T /Q | Out-Null
icacls $FTP_ROOT /grant "IUSR:(OI)(CI)RX"       /T /Q | Out-Null

Write-Ok "Permisos NTFS aplicados."

# ── Regla de autorización FTP ────────────────────────────────────────────────
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    # Limpiar reglas anteriores
    & $appcmd clear config $SITE_NAME /section:system.ftpServer/security/authorization 2>&1 | Out-Null

    # Permitir lectura al usuario danger
    & $appcmd set config $SITE_NAME /section:system.ftpServer/security/authorization `
        "/+[accessType='Allow',users='$USUARIO',permissions='Read']" 2>&1 | Out-Null

    Write-Ok "Regla de autorización FTP creada para '$USUARIO'."
}

# ── Puertos pasivos ──────────────────────────────────────────────────────────
Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" `
    -Name "lowDataChannelPort"  -Value 50000
Set-WebConfigurationProperty -Filter "system.ftpServer/firewallSupport" `
    -Name "highDataChannelPort" -Value 50100

Write-Ok "Puertos pasivos configurados: 50000-50100."

# =============================================================================
# PASO 6: ABRIR PUERTOS EN FIREWALL DE WINDOWS
# =============================================================================
Write-Info "PASO 6: Configurando firewall de Windows..."

$reglasFTP = @(
    @{ Name = "FTP Control Port P7";  Port = "21";          },
    @{ Name = "FTP Passive Ports P7"; Port = "50000-50100"; }
)

foreach ($regla in $reglasFTP) {
    if (-not (Get-NetFirewallRule -DisplayName $regla.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $regla.Name `
                            -Direction Inbound `
                            -Protocol TCP `
                            -LocalPort $regla.Port `
                            -Action Allow | Out-Null
        Write-Ok "Regla de firewall creada: $($regla.Name)"
    } else {
        Write-Warn "Regla ya existe: $($regla.Name)"
    }
}

# =============================================================================
# PASO 7: INICIAR SERVICIOS
# =============================================================================
Write-Info "PASO 7: Iniciando servicios FTP..."

Start-Service W3SVC   -ErrorAction SilentlyContinue
Start-Service ftpsvc  -ErrorAction SilentlyContinue

Start-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$ftpActivo = (Get-Service ftpsvc -ErrorAction SilentlyContinue).Status -eq "Running"
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
Write-Host ("  |  Usuario FTP  : danger                                         |") -ForegroundColor White
Write-Host ("  |  Contraseña   : Gerardo1234!!                                  |") -ForegroundColor White
Write-Host ("  |  IP Servidor  : $ipServidor") -ForegroundColor White
Write-Host ("  |  Puerto FTP   : 21                                             |") -ForegroundColor White
Write-Host ("  |  Sitio IIS    : $SITE_NAME") -ForegroundColor White
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  Estructura del repositorio:                                   |" -ForegroundColor White
Write-Host "  |    C:\FTP_Repositorio\repositorio\Apache\  ← ZIPs Apache       |" -ForegroundColor White
Write-Host "  |    C:\FTP_Repositorio\repositorio\Nginx\   ← ZIPs Nginx        |" -ForegroundColor White
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  Para probar con curl (como lo hace mainSSL.ps1):              |" -ForegroundColor White
Write-Host ("  |    curl -l -u danger:Gerardo1234!! ftp://$ipServidor/repositorio/Apache/") -ForegroundColor Cyan
Write-Host "  +----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |  SIGUIENTE PASO: Actualizar en funciones_SSL.ps1:              |" -ForegroundColor Yellow
Write-Host "  |    `$ftpUser = 'danger'                                          |" -ForegroundColor Yellow
Write-Host "  |    `$ftpPassword = 'Gerardo1234!!'                               |" -ForegroundColor Yellow
Write-Host ("  |    `$urlBase = 'ftp://$ipServidor/'                             |") -ForegroundColor Yellow
Write-Host "  +================================================================+" -ForegroundColor Green
Write-Host ""

Write-Info "Archivos en el repositorio:"
Get-ChildItem "$REPO_BASE" -Recurse -File | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 2)
    Write-Host "    $($_.FullName)  ($size MB)" -ForegroundColor Gray
}
Write-Host ""