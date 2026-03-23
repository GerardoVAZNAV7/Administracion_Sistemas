#Requires -RunAsAdministrator
# =============================================================================
# 01_setup_servidor.ps1
# PRACTICA 8 - Instalacion de roles necesarios en Windows Server 2022
#
# EJECUTAR PRIMERO en el servidor, antes de promover el DC
# =============================================================================

$ErrorActionPreference = "Stop"

function Write-Paso { param($n,$m) Write-Host "`n[$n] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m)    Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Info { param($m)    Write-Host "    [i]  $m" -ForegroundColor Yellow }

Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "   PRACTICA 8 - SETUP INICIAL SERVIDOR     " -ForegroundColor Magenta
Write-Host "============================================`n" -ForegroundColor Magenta

# ── Paso 1: Instalar AD DS y herramientas de administracion ──────────────────
Write-Paso "1" "Instalando Active Directory Domain Services..."
Install-WindowsFeature -Name AD-Domain-Services `
    -IncludeManagementTools -IncludeAllSubFeature | Out-Null
Write-Ok "AD-Domain-Services instalado."

# ── Paso 2: Instalar FSRM (File Server Resource Manager) ────────────────────
Write-Paso "2" "Instalando File Server Resource Manager (FSRM)..."
Install-WindowsFeature -Name FS-Resource-Manager `
    -IncludeManagementTools | Out-Null
Write-Ok "FSRM instalado."

# ── Paso 3: Instalar el servidor de archivos base ────────────────────────────
Write-Paso "3" "Instalando rol File Server..."
Install-WindowsFeature -Name FS-FileServer | Out-Null
Write-Ok "File Server instalado."

# ── Paso 4: Verificar que AppLocker este disponible (viene con el SO) ────────
Write-Paso "4" "Verificando AppLocker..."
$applockerFeature = Get-WindowsFeature -Name AppLocker -ErrorAction SilentlyContinue
if ($null -eq $applockerFeature) {
    # En Server 2022, AppLocker es parte del OS, se habilita via GPO
    Write-Info "AppLocker se configura via Group Policy, no como feature separado."
    Write-Info "Se habilitara en el script 04_fsrm_applocker.ps1"
} else {
    Write-Ok "AppLocker disponible en el sistema."
}

# ── Paso 5: Instalar RSAT-AD-PowerShell para administracion ─────────────────
Write-Paso "5" "Instalando RSAT-AD-PowerShell..."
Install-WindowsFeature -Name RSAT-AD-PowerShell | Out-Null
Write-Ok "RSAT-AD-PowerShell instalado."

# ── Paso 6: Instalar GPMC (Group Policy Management Console) ─────────────────
Write-Paso "6" "Instalando Group Policy Management Console..."
Install-WindowsFeature -Name GPMC | Out-Null
Write-Ok "GPMC instalado."

# ── Paso 7: Configurar IP estatica ───────────────────────────────────────────
Write-Paso "7" "Configurando IP estatica del servidor..."

$interfaz = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

# IMPORTANTE: Ajusta estos valores a tu red
$ipServidor  = "192.168.1.10"
$mascara     = 24
$gateway     = "192.168.1.1"
$dns         = "127.0.0.1"   # El propio servidor sera el DNS

$ipActual = Get-NetIPAddress -InterfaceAlias $interfaz.Name `
            -AddressFamily IPv4 -ErrorAction SilentlyContinue

if ($ipActual) {
    Remove-NetIPAddress -InterfaceAlias $interfaz.Name `
        -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias $interfaz.Name `
        -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
}

New-NetIPAddress -InterfaceAlias $interfaz.Name `
    -IPAddress $ipServidor `
    -PrefixLength $mascara `
    -DefaultGateway $gateway | Out-Null

Set-DnsClientServerAddress -InterfaceAlias $interfaz.Name `
    -ServerAddresses $dns | Out-Null

Write-Ok "IP configurada: $ipServidor / $mascara"
Write-Ok "Gateway: $gateway | DNS: $dns"

# ── Paso 8: Configurar el nombre del servidor ─────────────────────────────────
Write-Paso "8" "Verificando nombre del servidor..."
$nombreActual = $env:COMPUTERNAME
if ($nombreActual -ne "SERVIDOR-DC") {
    Write-Info "Renombrando el servidor a SERVIDOR-DC (requiere reinicio)..."
    Rename-Computer -NewName "SERVIDOR-DC" -Force
    Write-Info "El nombre se aplicara al reiniciar."
} else {
    Write-Ok "El servidor ya se llama SERVIDOR-DC."
}

# ── Resumen ───────────────────────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Green
Write-Host "   SETUP INICIAL COMPLETADO                 " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "SIGUIENTE PASO:" -ForegroundColor Yellow
Write-Host "  1. Reinicia el servidor si cambio el nombre"
Write-Host "  2. Ejecuta: .\02_crear_dominio.ps1"
Write-Host ""