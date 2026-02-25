#!/bin/bash
# =====================================================
# MENU DHCP
# =====================================================

Menu-DHCP() {
    while true; do
        clear
        print_section "PRACTICA 2 - SERVIDOR DHCP"

        echo "1) Instalar servicio DHCP"
        echo "2) Configurar servidor DHCP"
        echo "3) Monitorear servicio"
        echo "4) Verificar instalacion"
        echo "0) Volver al menu principal"
        echo ""

        read -p "Seleccione opcion: " op

        case $op in
            1) instalar_dhcp; pausa ;;
            2) configurar_dhcp; pausa ;;
            3) monitorear_dhcp ;;
            4) verificar_dhcp; pausa ;;
            0) break ;;
            *) print_error "Opcion invalida"; pausa ;;
        esac
    done
}