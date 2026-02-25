#!/bin/bash
# =====================================================
# MENU DNS
# =====================================================

Menu-DNS() {
    while true; do
        clear
        print_section "PRACTICA 3 - SERVIDOR DNS"

        echo "1) Verificar instalacion"
        echo "2) Instalar servidor DNS"
        echo "3) Agregar dominio"
        echo "4) Eliminar dominio"
        echo "5) Ver dominios"
        echo "0) Volver al menu principal"
        echo ""

        read -p "Seleccione opcion: " op

        case $op in
            1) verificar_dns; pausa ;;
            2) instalar_dns; pausa ;;
            3) agregar_dominio_dns; pausa ;;
            4) eliminar_dominio_dns; pausa ;;
            5) listar_dominios_dns; pausa ;;
            0) break ;;
            *) print_error "Opcion invalida"; pausa ;;
        esac
    done
}