#!/bin/bash
# =====================================================
# MENU SSH - FEDORA SERVER
# =====================================================

menu_ssh() {
    while true; do
        clear
        print_section "PRACTICA 4 - SERVICIO SSH"

        echo "1) Instalar OpenSSH Server"
        echo "2) Configuracion automatica completa"
        echo "3) Verificar servicio"
        echo "4) Mostrar datos de conexion"
        echo "0) Volver al menu principal"
        echo ""

        read -p "Seleccione opcion: " op

        case $op in
            1) instalar_ssh; pausa ;;
            2) configurar_ssh; pausa ;;
            3) verificar_ssh; pausa ;;
            4) mostrar_datos_conexion; pausa ;;
            0) break ;;
            *) print_error "Opcion invalida"; pausa ;;
        esac
    done
}