#!/bin/bash
# =====================================================
# ORQUESTADOR PRINCIPAL - SERVIDOR FEDORA
# =====================================================

# ===== CARGAR LIBRERIAS BASE =====
source ./modules/core_utils.sh

# ===== CARGAR MODULOS =====
source ./modules/diagnostico_functions.sh
source ./modules/menu_diagnostico.sh

source ./modules/dhcp_functions.sh
source ./modules/menu_dhcp.sh

source ./modules/dns_functions.sh
source ./modules/menu_dns.sh

source ./modules/ssh_functions.sh
source ./modules/menu_ssh.sh


# =====================================================
# MENU PRINCIPAL
# =====================================================

menu_principal() {
    while true; do
        clear
        echo "======================================="
        echo " SERVIDOR FEDORA - ADMINISTRACION REMOTA"
        echo "======================================="
        echo "1) Diagnostico del sistema"
        echo "2) Servicio DHCP"
        echo "3) Servicio DNS"
        echo "4) Servicio SSH"
        echo "0) Salir"
        echo ""

        read -p "Seleccione una opcion: " op

        case $op in
            1) menu_diagnostico ;;
            2) menu_dhcp ;;
            3) menu_dns ;;
            4) menu_ssh ;;
            0) exit 0 ;;
            *) echo "Opcion invalida" ;;
        esac

        read -p "Enter para continuar..."
    done
}

menu_principal