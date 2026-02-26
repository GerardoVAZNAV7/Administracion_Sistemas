# =========================================
# IMPORTAR MODULOS DE LA PRACTICA
# =========================================

. "$PSScriptRoot\core_utils.ps1"
. "$PSScriptRoot\dhcp_functions.ps1"

# =========================================
# MENU PRINCIPAL
# =========================================

function Menu-DHCP {

    do {
        Write-Host ""
        Write-Host "===== PRACTICA DHCP WINDOWS SERVER 2022 ====="
        Write-Host "1. Instalar servicio DHCP"
        Write-Host "2. Configurar DHCP"
        Write-Host "3. Monitorear DHCP"
        Write-Host "4. Ver estado del servicio"
        Write-Host "5. Salir"

        $op = Read-Host "Seleccione opcion"

        switch ($op) {
            "1" { Instalar-DHCP }
            "2" { Configurar-DHCP }
            "3" { Monitoreo-DHCP }
            "4" { Verificar-EstadoServicio }
        }

    } while ($op -ne "5")
}
