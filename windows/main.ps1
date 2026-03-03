# =====================================================
# SISTEMA DE ADMINISTRACION DE SERVIDORES (WINDOWS)
# MENU ORQUESTADOR GENERAL - PRACTICAS 1 → 5
# =====================================================

# Referencia absoluta a la carpeta de módulos
$ModulePath = Join-Path $PSScriptRoot "modules"

# ===== CARGA DE MODULOS DE FORMA SEGURA =====
$modulos = @("core_utils.ps1", "menu_dhcp.ps1", "menu_dns.ps1", "menu_ssh.ps1", "menu_ftp.ps1")

foreach ($mod in $modulos) {
    $fullPath = Join-Path $ModulePath $mod
    if (Test-Path $fullPath) {
        . $fullPath
    } else {
        Write-Host "[!] Error crítico: No se encontró $fullPath" -ForegroundColor Red
    }
}

# =====================================================
# PRACTICA 1 - DIAGNOSTICO DEL SISTEMA
# =====================================================
function Menu-Diagnostico {
    Clear-Host
    if (Get-Command Write-Section -ErrorAction SilentlyContinue) {
        Write-Section "PRACTICA 1 - DIAGNOSTICO DEL SISTEMA"
        Write-Section "NOMBRE DEL EQUIPO"; Get-SystemHostname
        Write-Section "DIRECCION IPv4"; Get-SystemIPv4
        Write-Section "USO DE DISCO C:"; Get-DiskUsageC
    } else {
        Write-Host "--- PRACTICA 1: DIAGNOSTICO ---"
        hostname; ipconfig | findstr "IPv4"
    }
    Write-Host "`nDiagnostico completado" -ForegroundColor Green
    Pause
}

# =====================================================
# MENU PRINCIPAL ORQUESTADOR
# =====================================================
do {
    Clear-Host
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "  ADMINISTRACION CENTRAL DE SERVIDORES" -ForegroundColor White
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "1) Practica 1 - Diagnostico del sistema"
    Write-Host "2) Practica 2 - DHCP"
    Write-Host "3) Practica 3 - DNS"
    Write-Host "4) Practica 4 - SSH"
    Write-Host "5) Practica 5 - FTP (Gestión de Usuarios)"
    Write-Host "0) Salir"
    Write-Host ""

    $opcion = Read-Host "Seleccione una practica"

    switch ($opcion) {
        "1" { Menu-Diagnostico }
        "2" { if (Get-Command Menu-DHCP -ErrorAction SilentlyContinue) { Menu-DHCP } else { Write-Host "Modulo no cargado"; Pause } }
        "3" { if (Get-Command Menu-DNS -ErrorAction SilentlyContinue) { Menu-DNS } else { Write-Host "Modulo no cargado"; Pause } }
        "4" { if (Get-Command Menu-SSH -ErrorAction SilentlyContinue) { Menu-SSH } else { Write-Host "Modulo no cargado"; Pause } }
        "5" { 
            if (Get-Command menu-ftp -ErrorAction SilentlyContinue) {
                menu-ftp 
            } else {
                Write-Host "[!] Error: La función menu-ftp no está cargada." -ForegroundColor Red
                Pause
            }
        }
        "0" { Write-Host "Saliendo..." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        default { Write-Host "Opcion invalida" -ForegroundColor Red; Pause }
    }
} while ($opcion -ne "0")