# =====================================================
# SISTEMA DE ADMINISTRACION DE SERVIDORES
# MENU ORQUESTADOR GENERAL
# PRACTICAS 1 → 4
# =====================================================

# ===== CARGA DE MODULOS =====
. .\modules\core_utils.ps1
. .\modules\menu_dhcp.ps1
. .\modules\menu_dns.ps1
. .\modules\menu_ssh.ps1
. .\modules\menu_ftp.ps1


# =====================================================
# PRACTICA 1 - DIAGNOSTICO DEL SISTEMA
# Muestra toda la informacion automaticamente
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
    #Clear-Host

    Write-Section "ADMINISTRACION CENTRAL DE SERVIDORES"

    Write-Host "1) Practica 1 - Diagnostico del sistema"
    Write-Host "2) Practica 2 - DHCP"
    Write-Host "3) Practica 3 - DNS"
    Write-Host "4) Practica 4 - SSH"
    Write-Host "5) Practica 5 - FTP"
    Write-Host "0) Salir"
    Write-Host ""

    $opcion = Read-Host "Seleccione una practica"

    switch ($opcion) {

        "1" { Menu-Diagnostico }

        "2" { Menu-DHCP }

        "3" { Menu-DNS }

        "4" { Menu-SSH }

        "5" { menu-ftp }

        "0" {
            Write-Color "Saliendo del sistema..." Yellow
        }

        default {
            Write-Color "Opcion invalida" Red
            Pause
        }
    }

} while ($opcion -ne "0")