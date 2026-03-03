# =====================================================
# SISTEMA DE ADMINISTRACION DE SERVIDORES
# MENU ORQUESTADOR GENERAL - PRACTICAS 1 → 5
# =====================================================

# Determinar la ruta base del proyecto de forma dinámica
$P1Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModulePath = Join-Path $P1Root "modules"

# ===== CARGA DE MODULOS DE FORMA SEGURA =====
try {
    . (Join-Path $ModulePath "core_utils.ps1")
    . (Join-Path $ModulePath "menu_dhcp.ps1")
    . (Join-Path $ModulePath "menu_dns.ps1")
    . (Join-Path $ModulePath "menu_ssh.ps1")
    . (Join-Path $ModulePath "menu_ftp.ps1") # Carga el menú corregido anteriormente
} catch {
    Write-Host "[!] Error crítico al cargar los módulos: $($_.Exception.Message)" -ForegroundColor Red
    Pause
    exit
}

# =====================================================
# PRACTICA 1 - DIAGNOSTICO DEL SISTEMA
# =====================================================
function Menu-Diagnostico {
    Clear-Host
    Write-Section "PRACTICA 1 - DIAGNOSTICO DEL SISTEMA"

    Write-Section "NOMBRE DEL EQUIPO"
    Get-SystemHostname

    Write-Section "DIRECCION IPv4"
    Get-SystemIPv4

    Write-Section "USO DE DISCO C:"
    Get-DiskUsageC

    Write-Host ""
    Write-Color "Diagnostico completado" Green
    Pause
}

# =====================================================
# MENU PRINCIPAL ORQUESTADOR
# =====================================================
do {
    Clear-Host # He reactivado el Clear-Host para que el menú se vea limpio

    Write-Section "ADMINISTRACION CENTRAL DE SERVIDORES"

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
        "2" { Menu-DHCP }
        "3" { Menu-DNS }
        "4" { Menu-SSH }
        "5" { 
            # Llamada a la función definida en modules\menu_ftp.ps1
            if (Get-Command menu-ftp -ErrorAction SilentlyContinue) {
                menu-ftp 
            } else {
                Write-Host "[!] Error: La función menu-ftp no está cargada." -ForegroundColor Red
                Pause
            }
        }
        "0" {
            Write-Color "Saliendo del sistema..." Yellow
            Start-Sleep -Seconds 1
        }
        default {
            Write-Color "Opcion invalida" Red
            Pause
        }
    }

} while ($opcion -ne "0")