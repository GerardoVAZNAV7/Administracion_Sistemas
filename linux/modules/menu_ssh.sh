# =====================================================
# MENU SSH - FEDORA SERVER
# =====================================================

menu_ssh() {
    while true; do
        clear
        echo "================================="
        echo " PRACTICA 4 - SERVICIO SSH"
        echo "================================="
        echo "1) Instalar OpenSSH Server"
        echo "2) Configuracion automatica completa"
        echo "3) Verificar servicio"
        echo "4) Mostrar datos de conexion"
        echo "0) Volver al menu principal"
        echo ""

        read -p "Seleccione opcion: " op

        case $op in
            1) ssh_instalar ;;
            2) ssh_configurar ;;
            3) ssh_verificar ;;
            4) ssh_mostrar_conexion ;;
            0) break ;;
            *) echo "Opcion invalida" ;;
        esac

        read -p "Enter para continuar..."
    done
}