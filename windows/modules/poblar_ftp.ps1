# =============================================================================
# poblar_repositorio.ps1
# Descarga los instaladores ZIP y los coloca en el repositorio FTP de Windows
#
# EXPLICACIÓN SIMPLE:
#   Este script va a las páginas oficiales de Apache y Nginx,
#   descarga los ZIPs y los pone en la carpeta del FTP.
#   También genera el archivo .sha256 de cada uno.
#
# USO:
#   1. PowerShell como Administrador
#   2. Set-ExecutionPolicy Bypass -Scope Process
#   3. .\poblar_repositorio.ps1
# =============================================================================

#Requires -RunAsAdministrator

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Ok   { param($m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Info { param($m) Write-Host "  [*]   $m" -ForegroundColor Cyan   }
function Write-Warn { param($m) Write-Host "  [!]   $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [ERR] $m" -ForegroundColor Red    }

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |   POBLANDO REPOSITORIO FTP — WINDOWS SERVER 2022           |" -ForegroundColor Cyan
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host ""

# Carpeta base del repositorio (creada por setup_repositorio_ftp.ps1)
$REPO_BASE = "C:\FTP_Repositorio\repositorio"

# Crear carpetas si no existen
@("$REPO_BASE\Apache", "$REPO_BASE\Nginx") | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# =============================================================================
# FUNCIÓN PRINCIPAL DE DESCARGA
# =============================================================================
function Descargar-Instalador {
    param(
        [string]$Url,            # URL de descarga
        [string]$NombreArchivo,  # cómo se va a llamar el archivo en el FTP
        [string]$CarpetaDestino, # dónde guardarlo
        [string]$Etiqueta        # nombre para mostrar en pantalla
    )

    Write-Info "Procesando: $Etiqueta"
    Write-Host "    URL: $Url" -ForegroundColor DarkGray
    Write-Host "    Destino: $CarpetaDestino\$NombreArchivo" -ForegroundColor DarkGray

    $rutaCompleta = Join-Path $CarpetaDestino $NombreArchivo

    # ─────────────────────────────────────────────────────────────────────────
    # Si el archivo ya está en C:\ (de la Práctica 6), solo lo copiamos
    # No tiene sentido descargarlo de nuevo
    # ─────────────────────────────────────────────────────────────────────────
    $rutaEnC = "C:\$NombreArchivo"
    if (Test-Path $rutaEnC) {
        Write-Warn "  El archivo ya existe en C:\. Copiando al repositorio..."
        Copy-Item -Path $rutaEnC -Destination $rutaCompleta -Force
        Write-Ok  "  Copiado desde C:\ → $CarpetaDestino\"
    }
    elseif (Test-Path $rutaCompleta) {
        Write-Warn "  Ya existe en el repositorio. Omitiendo descarga."
    }
    else {
        # ─────────────────────────────────────────────────────────────────────
        # Descargar desde internet
        # Invoke-WebRequest es el equivalente de curl en PowerShell
        # -UseBasicParsing: no necesita Internet Explorer (más compatible)
        # ─────────────────────────────────────────────────────────────────────
        Write-Info "  Descargando desde internet..."
        try {
            $ProgressPreference = 'SilentlyContinue'  # Ocultar barra de progreso lenta
            Invoke-WebRequest -Uri $Url `
                              -OutFile $rutaCompleta `
                              -UseBasicParsing `
                              -TimeoutSec 180
            $ProgressPreference = 'Continue'
            Write-Ok "  Descargado: $NombreArchivo"

            # Copiar también a C:\ para que funciones_SSL.ps1 lo encuentre
            if (-not (Test-Path $rutaEnC)) {
                Copy-Item -Path $rutaCompleta -Destination $rutaEnC
                Write-Ok "  Copiado también a C:\ (necesario para mainSSL.ps1)"
            }
        }
        catch {
            $ProgressPreference = 'Continue'
            Write-Err "No se pudo descargar $Etiqueta"
            Write-Host ""
            Write-Host "  ┌─ DESCARGA MANUAL ────────────────────────────────────────┐" -ForegroundColor Yellow
            Write-Host "  │ Ve a esta URL en tu navegador y descarga el archivo:     │" -ForegroundColor Yellow
            Write-Host "  │                                                          │" -ForegroundColor Yellow
            Write-Host "  │   $Url" -ForegroundColor Yellow
            Write-Host "  │                                                          │" -ForegroundColor Yellow
            Write-Host "  │ Guarda el archivo con este nombre exacto:                │" -ForegroundColor Yellow
            Write-Host "  │   $NombreArchivo                                         " -ForegroundColor Yellow
            Write-Host "  │                                                          │" -ForegroundColor Yellow
            Write-Host "  │ Y colócalo en AMBAS rutas:                               │" -ForegroundColor Yellow
            Write-Host "  │   C:\$NombreArchivo                                      " -ForegroundColor Yellow
            Write-Host "  │   $CarpetaDestino\$NombreArchivo                         " -ForegroundColor Yellow
            Write-Host "  └──────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
            Write-Host ""
            return
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Generar el archivo .sha256
    # Get-FileHash calcula el hash criptográfico del archivo
    # Lo guardamos en un archivo de texto con solo el hash (en minúsculas)
    # mainSSL.ps1 lee este archivo y compara el hash para verificar integridad
    # ─────────────────────────────────────────────────────────────────────────
    $sha256Path = "$rutaCompleta.sha256"

    if (-not (Test-Path $sha256Path)) {
        Write-Info "  Calculando hash SHA256..."
        $hash = (Get-FileHash -Path $rutaCompleta -Algorithm SHA256).Hash.ToLower()

        # Guardamos el hash en un archivo de texto plano
        # -NoNewline: sin salto de línea al final (más fácil de leer en scripts)
        $hash | Out-File -FilePath $sha256Path -Encoding ascii -NoNewline

        Write-Ok  "  Hash SHA256: $hash"
        Write-Ok  "  Guardado en: $sha256Path"
    } else {
        Write-Warn "  El .sha256 ya existe. Omitiendo."
        $hash = Get-Content $sha256Path
        Write-Host "    Hash actual: $hash" -ForegroundColor DarkGray
    }
}

# =============================================================================
# LISTA DE DESCARGAS
# ─────────────────────────────────────────────────────────────────────────────
# ¿POR QUÉ ESTAS URLs?
#
# Apache para Windows:
#   ApacheLounge (https://www.apachelounge.com) es el proveedor OFICIAL
#   de binarios de Apache HTTP Server para Windows. El proyecto Apache
#   en sí no distribuye binarios para Windows, así que ApacheLounge es
#   la fuente recomendada en la documentación oficial.
#
# Nginx para Windows:
#   nginx.org es el sitio oficial del proyecto Nginx.
#   Los ZIPs de Windows están en https://nginx.org/download/
#
# VERSIONES:
#   Usamos versiones estables conocidas. Si el archivo no existe en esa URL,
#   el script te dice exactamente a dónde ir a buscar la versión actual.
# =============================================================================

Write-Host ""
Write-Info "Descargando Apache para Windows..."
Write-Host ""

# Apache 2.4.62 — rama estable, compilado con VS17 para Windows 64-bit
# Si esta versión ya no existe en ApacheLounge, ve a:
# https://www.apachelounge.com/download/  y busca la versión actual
Descargar-Instalador `
    -Url            "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.62-240904-win64-VS17.zip" `
    -NombreArchivo  "apache_2.4.62.zip" `
    -CarpetaDestino "$REPO_BASE\Apache" `
    -Etiqueta       "Apache 2.4.62 (Windows 64-bit)"

Write-Host ""
Write-Info "Descargando Nginx para Windows..."
Write-Host ""

# Nginx 1.26.2 — rama stable de Nginx para Windows
# Si esta versión ya no existe, ve a:
# https://nginx.org/en/download.html  y busca la versión Stable
Descargar-Instalador `
    -Url            "https://nginx.org/download/nginx-1.26.2.zip" `
    -NombreArchivo  "nginx_1.26.2.zip" `
    -CarpetaDestino "$REPO_BASE\Nginx" `
    -Etiqueta       "Nginx 1.26.2 (Windows)"

# =============================================================================
# RESULTADO FINAL
# =============================================================================
Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Green
Write-Host "  |           REPOSITORIO FTP LISTO — CONTENIDO ACTUAL         |" -ForegroundColor Green
Write-Host "  +============================================================+" -ForegroundColor Green
Write-Host ""

Get-ChildItem $REPO_BASE -Recurse -File | ForEach-Object {
    $tamanio = [math]::Round($_.Length / 1MB, 1)
    $rutaCorta = $_.FullName.Replace($REPO_BASE, "")
    Write-Host ("    {0,-55} {1} MB" -f $rutaCorta, $tamanio) -ForegroundColor Gray
}

$ipServidor = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  Para verificar que el FTP funciona:" -ForegroundColor Cyan
Write-Host "    curl -l -u danger:Gerardo1234!! ftp://$ipServidor/repositorio/Apache/" -ForegroundColor White
Write-Host "  Deberías ver apache_2.4.62.zip listado." -ForegroundColor DarkGray
Write-Host ""