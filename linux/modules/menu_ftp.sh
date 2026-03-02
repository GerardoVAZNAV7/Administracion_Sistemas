#!/bin/bash

# ===== CARGAR FUNCIONES DE FTP =====
# Usamos la ruta relativa al orquestador
source "$BASE_DIR/modules/ftp_functions.sh"

menu_ftp() {
    # Inicializar configuración base al entrar al módulo por primera vez
    clear
    inicializar_sistema

    while true; do
        echo -e "\n======================================="
        echo "   ADMINISTRADOR DE SERVIDOR FTP"
        echo "======================================="
        echo "1) Alta masiva de usuarios"
        echo "2) Modificar grupo de un usuario existente"
        echo "0) Regresar al Menú Principal"
        echo "---------------------------------------"
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                read -p "Número de usuarios a crear: " n
                for (( i=1; i<=$n; i++ )); do
                    echo -e "\nConfigurando usuario $i de $n:"
                    read -p "Username: " uname
                    read -s -p "Password: " upass; echo
                    echo "Grupo (1: reprobados, 2: recursadores): "
                    read g_op
                    [[ "$g_op" == "1" ]] && ugroup="reprobados" || ugroup="recursadores"
                    crear_usuario "$uname" "$upass" "$ugroup"
                done
                ;;
            2)
                read -p "Nombre del usuario a modificar: " uname
                echo "Nuevo Grupo (1: reprobados, 2: recursadores): "
                read g_op
                [[ "$g_op" == "1" ]] && ugroup="reprobados" || ugroup="recursadores"
                modificar_grupo_usuario "$uname" "$ugroup"
                ;;
            0)
                echo "Regresando al menú principal..."
                break # Rompe el ciclo del submenú para volver al orquestador
                ;;
            *)
                echo "Opción no válida."
                ;;
        esac
        read -p "Presione Enter para continuar..."
    done
}