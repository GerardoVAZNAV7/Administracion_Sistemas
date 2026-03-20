# =============================================================================
# fix_ftp_530.ps1
# Arregla el error "530 User cannot log in, home directory inaccessible"
# y verifica que todo el repositorio FTP este en orden
#
# Ejecutar cuando FileZilla o curl dan error 530.
# USO: PowerShell como Admin -> .\fix_ftp_530.ps1
# =============================================================================

#Requires -RunAsAdministrator

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Import-Module WebAdministration -ErrorAction SilentlyContinue

function Write-Ok   { param($m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Info { param($m) Write-Host "  [*]   $m" -ForegroundColor Cyan   }
function Write-Warn { param($m) Write-Host "  [!]   $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [ERR] $m" -ForegroundColor Red    }

$USUARIO     = "danger"
$FTP_ROOT    = "C:\FTP_Repositorio"
$LOCAL_USER  = "$FTP_ROOT\LocalUser"
$DANGER_HOME = "$LOCAL_USER\$USUARIO"
$REPO_BASE   = "$DANGER_HOME\repositorio"
$SITE_NAME   = "Repositorio_P7"

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |        FIX ERROR 530 - FTP REPOSITORIO P7                  |" -ForegroundColor Cyan
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# FIX 1: Crear carpetas que falten
# =============================================================================
Write-Info "Verificando carpetas..."

foreach ($carpeta in @($FTP_ROOT, $LOCAL_USER, $DANGER_HOME, $REPO_BASE,
                        "$REPO_BASE\Apache", "$REPO_BASE\Nginx")) {
    if (-not (Test-Path $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
        Write-Ok "Creada: $carpeta"
    } else {
        Write-Ok "Existe: $carpeta"
    }
}

# =============================================================================
# FIX 2: Permisos NTFS correctos
# -----------------------------------------------------------------------------
# CAUSA RAIZ DEL ERROR 530:
# IIS-FTP verifica que el usuario NO sea dueno de la raiz del chroot.
# Si "danger" tiene FullControl en C:\FTP_Repositorio -> error 530.
# La raiz debe ser propiedad de Administrators/SYSTEM.
# El usuario solo necesita RX en su propia subcarpeta.
# =============================================================================
Write-Info "Corrigiendo permisos NTFS (causa raiz del error 530)..."

$adminGrp = (New-Object Security.Principal.SecurityIdentifier "S-1-5-32-544").Translate(
    [Security.Principal.NTAccount]).Value

# Tomar propiedad de las carpetas
takeown /F $FTP_ROOT /D Y 2>$null | Out-Null
takeown /F $LOCAL_USER /D Y 2>$null | Out-Null

# Raiz y LocalUser: Admins tienen todo, danger NO tiene control aqui
icacls $FTP_ROOT   /inheritance:r /grant "SYSTEM:(OI)(CI)F" /grant "${adminGrp}:(OI)(CI)F" /grant "IIS_IUSRS:(OI)(CI)RX" /grant "IUSR:(OI)(CI)RX" /Q | Out-Null
icacls $LOCAL_USER /inheritance:r /grant "SYSTEM:(OI)(CI)F" /grant "${adminGrp}:(OI)(CI)F" /grant "IIS_IUSRS:(OI)(CI)RX" /grant "IUSR:(OI)(CI)RX" /Q | Out-Null

# Home del usuario: danger puede leer y ejecutar (RX), no escribir en la raiz del home
icacls $DANGER_HOME /inheritance:r /grant "SYSTEM:(OI)(CI)F" /grant "${adminGrp}:(OI)(CI)F" /grant "IIS_IUSRS:(OI)(CI)RX" /grant "IUSR:(OI)(CI)RX" /grant "${USUARIO}:(OI)(CI)RX" /Q | Out-Null

# Repo: danger puede leer
icacls $REPO_BASE /inheritance:r /grant "SYSTEM:(OI)(CI)F" /grant "${adminGrp}:(OI)(CI)F" /grant "IIS_IUSRS:(OI)(CI)RX" /grant "IUSR:(OI)(CI)RX" /grant "${USUARIO}:(OI)(CI)RX" /Q | Out-Null

Write-Ok "Permisos corregidos."

# =============================================================================
# FIX 3: Verificar que el sitio FTP usa IsolateAllDirectories (modo 3)
# =============================================================================
Write-Info "Verificando configuracion del sitio FTP..."

$sitio = Get-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue
if (-not $sitio) {
    Write-Err "Sitio '$SITE_NAME' no existe. Ejecuta setup_repositorio_ftp.ps1 primero."
} else {
    # Verificar y corregir la raiz fisica
    if ($sitio.PhysicalPath -ne $FTP_ROOT) {
        Set-ItemProperty "IIS:\Sites\$SITE_NAME" -Name physicalPath -Value $FTP_ROOT
        Write-Ok "Raiz del sitio corregida a $FTP_ROOT"
    } else {
        Write-Ok "Raiz del sitio: $FTP_ROOT"
    }

    # Verificar modo de aislamiento
    $modo = (Get-ItemProperty "IIS:\Sites\$SITE_NAME").ftpServer.userIsolation.mode
    if ($modo -ne 3) {
        Set-ItemProperty "IIS:\Sites\$SITE_NAME" -Name ftpServer.userIsolation.mode -Value 3
        Write-Ok "Modo IsolateAllDirectories activado."
    } else {
        Write-Ok "Modo IsolateAllDirectories ya activo."
    }
}

# =============================================================================
# FIX 4: Verificar que el usuario "danger" existe y tiene contrasena correcta
# =============================================================================
Write-Info "Verificando usuario 'danger'..."

$usr = Get-LocalUser -Name $USUARIO -ErrorAction SilentlyContinue
if (-not $usr) {
    Write-Err "Usuario 'danger' no existe. Creandolo..."
    $pwd = ConvertTo-SecureString "Gerardo1234!!" -AsPlainText -Force
    New-LocalUser -Name $USUARIO -Password $pwd -PasswordNeverExpires `
        -UserMayNotChangePassword | Out-Null
    Write-Ok "Usuario 'danger' creado."
} else {
    Write-Ok "Usuario 'danger' existe. Estado: $($usr.Enabled)"
    if (-not $usr.Enabled) {
        Enable-LocalUser -Name $USUARIO
        Write-Ok "Usuario habilitado."
    }
}

# =============================================================================
# FIX 5: Verificar .sha256 de los ZIPs
# =============================================================================
Write-Info "Verificando archivos SHA256..."

Get-ChildItem "$REPO_BASE" -Recurse -Filter "*.zip" | ForEach-Object {
    $sha256 = "$($_.FullName).sha256"
    if (-not (Test-Path $sha256)) {
        Write-Warn "Falta .sha256 para: $($_.Name). Generando..."
        $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLower()
        $hash | Out-File -FilePath $sha256 -Encoding ascii -NoNewline
        Write-Ok "SHA256 generado: $([System.IO.Path]::GetFileName($sha256))"
    } else {
        Write-Ok "SHA256 ok: $([System.IO.Path]::GetFileName($sha256))"
    }
}

# =============================================================================
# FIX 6: Reiniciar FTP para aplicar todos los cambios
# =============================================================================
Write-Info "Reiniciando servicio FTP..."

Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service ftpsvc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

if ((Get-Service ftpsvc).Status -eq "Running") {
    Write-Ok "ftpsvc reiniciado correctamente."
} else {
    Write-Err "ftpsvc no pudo iniciar. Revisa el Visor de Eventos."
}

Start-WebSite -Name $SITE_NAME -ErrorAction SilentlyContinue

# =============================================================================
# DIAGNOSTICO FINAL
# =============================================================================
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Green
Write-Host "  |                    DIAGNOSTICO FINAL                       |" -ForegroundColor Green
Write-Host "  +============================================================+" -ForegroundColor Green

# Verificar estructura de carpetas
Write-Host "  Carpetas:" -ForegroundColor White
foreach ($carpeta in @($FTP_ROOT, $LOCAL_USER, $DANGER_HOME, "$REPO_BASE\Apache", "$REPO_BASE\Nginx")) {
    $existe = Test-Path $carpeta
    $estado = if ($existe) { "[OK]" } else { "[FALTA]" }
    $color  = if ($existe) { "Green" } else { "Red" }
    Write-Host ("    " + $estado.PadRight(8) + $carpeta) -ForegroundColor $color
}

# Verificar archivos
Write-Host ""
Write-Host "  Archivos en el repositorio:" -ForegroundColor White
Get-ChildItem $REPO_BASE -Recurse -File | ForEach-Object {
    $mb = [math]::Round($_.Length / 1MB, 1)
    Write-Host ("    [OK]     " + $_.Name + "  ($mb MB)") -ForegroundColor Green
}

# Prueba de conexion
Write-Host ""
Write-Host "  Prueba de conexion FTP:" -ForegroundColor White
Write-Host ("    curl -l -u danger:Gerardo1234!! ftp://" + $ip + "/repositorio/Apache/") -ForegroundColor Cyan
Write-Host "    Debes ver: apache_2.4.62.zip y apache_2.4.62.zip.sha256" -ForegroundColor DarkGray

Write-Host ""
Write-Host "  En FileZilla usa estos ajustes:" -ForegroundColor Yellow
Write-Host "    Protocolo  : FTP (NO SFTP, NO FTPS)" -ForegroundColor Yellow
Write-Host "    Host       : $ip" -ForegroundColor Yellow
Write-Host "    Puerto     : 21" -ForegroundColor Yellow
Write-Host "    Cifrado    : Usar FTP plano (SIN TLS)" -ForegroundColor Yellow
Write-Host "    Usuario    : danger" -ForegroundColor Yellow
Write-Host "    Contrasena : Gerardo1234!!" -ForegroundColor Yellow
Write-Host "  +============================================================+" -ForegroundColor Green
Write-Host ""