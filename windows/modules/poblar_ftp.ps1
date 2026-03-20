# =============================================================================
# poblar_repositorio.ps1
# Descarga los instaladores ZIP y los coloca en el repositorio FTP de Windows
#
# USO:
#   1. PowerShell como Administrador
#   2. Set-ExecutionPolicy Bypass -Scope Process
#   3. .\poblar_repositorio.ps1
# =============================================================================

#Requires -RunAsAdministrator

# Forzar UTF-8 en consola para evitar caracteres corruptos
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Ok   { param($m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Info { param($m) Write-Host "  [*]   $m" -ForegroundColor Cyan   }
function Write-Warn { param($m) Write-Host "  [!]   $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [ERR] $m" -ForegroundColor Red    }

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |   POBLANDO REPOSITORIO FTP - WINDOWS SERVER 2022           |" -ForegroundColor Cyan
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host ""

$REPO_BASE = "C:\FTP_Repositorio\repositorio"

# Crear carpetas si no existen
@("$REPO_BASE\Apache", "$REPO_BASE\Nginx") | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# =============================================================================
# FUNCION PRINCIPAL DE DESCARGA
# =============================================================================
function Descargar-Instalador {
    param(
        [string]$Url,
        [string]$NombreArchivo,
        [string]$CarpetaDestino,
        [string]$Etiqueta
    )

    Write-Info "Procesando: $Etiqueta"
    Write-Host "    URL: $Url" -ForegroundColor DarkGray
    Write-Host "    Destino: $CarpetaDestino\$NombreArchivo" -ForegroundColor DarkGray

    $rutaCompleta = Join-Path $CarpetaDestino $NombreArchivo
    $rutaEnC      = "C:\$NombreArchivo"

    # Si ya existe en C:\ (de la Practica 6), solo copiamos - no descargamos de nuevo
    if (Test-Path $rutaEnC) {
        Write-Warn "  Encontrado en C:\$NombreArchivo. Copiando al repositorio..."
        Copy-Item -Path $rutaEnC -Destination $rutaCompleta -Force
        Write-Ok  "  Copiado a $CarpetaDestino\"
    }
    elseif (Test-Path $rutaCompleta) {
        Write-Warn "  Ya existe en el repositorio. Omitiendo descarga."
    }
    else {
        Write-Info "  Descargando desde internet..."
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url `
                              -OutFile $rutaCompleta `
                              -UseBasicParsing `
                              -TimeoutSec 180
            $ProgressPreference = 'Continue'
            Write-Ok "  Descargado: $NombreArchivo"

            # Copiar tambien a C:\ para que funciones_SSL.ps1 lo encuentre
            if (-not (Test-Path $rutaEnC)) {
                Copy-Item -Path $rutaCompleta -Destination $rutaEnC
                Write-Ok "  Copiado tambien a C:\$NombreArchivo"
            }
        }
        catch {
            $ProgressPreference = 'Continue'
            Write-Err "No se pudo descargar $Etiqueta"
            Write-Host ""
            Write-Host "  +--- DESCARGA MANUAL -------------------------------------------+" -ForegroundColor Yellow
            Write-Host "  | Ve a esta URL en tu navegador y descarga el archivo:          |" -ForegroundColor Yellow
            Write-Host ("  |   " + $Url) -ForegroundColor Yellow
            Write-Host "  |                                                                |" -ForegroundColor Yellow
            Write-Host "  | Guarda el archivo con este nombre exacto:                     |" -ForegroundColor Yellow
            Write-Host ("  |   " + $NombreArchivo) -ForegroundColor Yellow
            Write-Host "  |                                                                |" -ForegroundColor Yellow
            Write-Host "  | Coloca el archivo en AMBAS rutas:                             |" -ForegroundColor Yellow
            Write-Host ("  |   C:\" + $NombreArchivo) -ForegroundColor Yellow
            Write-Host ("  |   " + $CarpetaDestino + "\" + $NombreArchivo) -ForegroundColor Yellow
            Write-Host "  +---------------------------------------------------------------+" -ForegroundColor Yellow
            Write-Host ""
            return
        }
    }

    # Generar el .sha256
    # Get-FileHash calcula el hash criptografico del archivo
    # Se guarda en minusculas sin salto de linea para que mainSSL.ps1 lo compare bien
    $sha256Path = "$rutaCompleta.sha256"
    if (-not (Test-Path $sha256Path)) {
        Write-Info "  Calculando hash SHA256..."
        $hash = (Get-FileHash -Path $rutaCompleta -Algorithm SHA256).Hash.ToLower()
        $hash | Out-File -FilePath $sha256Path -Encoding ascii -NoNewline
        Write-Ok  "  SHA256: $hash"
        Write-Ok  "  Guardado en: $sha256Path"
    } else {
        Write-Warn "  El .sha256 ya existe. Omitiendo calculo."
        $hash = Get-Content $sha256Path
        Write-Host "    Hash actual: $hash" -ForegroundColor DarkGray
    }
}

# =============================================================================
# DESCARGAS
# -----------------------------------------------------------------------------
# Apache para Windows:
#   ApacheLounge es el proveedor OFICIAL de binarios Apache para Windows.
#   El proyecto Apache no distribuye binarios Windows por su cuenta.
#   URL: https://www.apachelounge.com/download/
#
# Nginx para Windows:
#   nginx.org es el sitio oficial. Los ZIPs estan en /download/
#   URL: https://nginx.org/en/download.html
# =============================================================================

Write-Host ""
Write-Info "Descargando Apache para Windows..."
Write-Host ""

Descargar-Instalador `
    -Url            "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.62-240904-win64-VS17.zip" `
    -NombreArchivo  "apache_2.4.62.zip" `
    -CarpetaDestino "$REPO_BASE\Apache" `
    -Etiqueta       "Apache 2.4.62 (Windows 64-bit)"

Write-Host ""
Write-Info "Descargando Nginx para Windows..."
Write-Host ""

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
Write-Host "  |           REPOSITORIO FTP LISTO - CONTENIDO ACTUAL         |" -ForegroundColor Green
Write-Host "  +============================================================+" -ForegroundColor Green
Write-Host ""

Get-ChildItem $REPO_BASE -Recurse -File | ForEach-Object {
    $tamanio   = [math]::Round($_.Length / 1MB, 1)
    $rutaCorta = $_.FullName.Replace($REPO_BASE, "")
    Write-Host ("    {0,-55} {1} MB" -f $rutaCorta, $tamanio) -ForegroundColor Gray
}

$ipServidor = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  Para verificar que el FTP funciona:" -ForegroundColor Cyan
Write-Host ("    curl -l -u danger:Gerardo1234!! ftp://" + $ipServidor + "/repositorio/Apache/") -ForegroundColor White
Write-Host "  Deberias ver: apache_2.4.62.zip listado." -ForegroundColor DarkGray
Write-Host ""