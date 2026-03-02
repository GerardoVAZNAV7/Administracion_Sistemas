#!/bin/bash
# =====================================================
# ORQUESTADOR PRINCIPAL - SERVIDOR FEDORA
# =====================================================

# ===== OBTENER RUTA REAL DEL SCRIPT =====
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== CARGAR LIBRERIAS BASE =====
source "$BASE_DIR/modules/core_utils.sh"

# ===== CARGAR MODULOS =====
source "$BASE_DIR/modules/diagnostico_functions.sh"
source "$BASE_DIR/modules/menu_diagnostico.sh"

source "$BASE_DIR/modules/dhcp_functions.sh"
source "$BASE_DIR/modules/menu_dhcp.sh"

source "$BASE_DIR/modules/dns_functions.sh"
source "$BASE_DIR/modules/menu_dns.sh"

source "$BASE_DIR/modules/ssh_functions.sh"
source "$BASE_DIR/modules/menu_ssh.sh"

source "$BASE_DIR/modules/ftp_functions.sh"
source "$BASE_DIR/modules/menu_ftp.sh"
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
        echo "5) Servicio FTP"
        echo "0) Salir"
        echo ""

        read -p "Seleccione una opcion: " op

        case $op in
            1) menu_diagnostico ;;
            2) Menu-DHCP ;;
            3) Menu-DNS ;;
            4) menu_ssh ;;
            5) menu_ftp ;;
            0) exit 0 ;;
            *) echo "Opcion invalida" ;;
        esac

        read -p "Enter para continuar..."
    done
}

menu_principal