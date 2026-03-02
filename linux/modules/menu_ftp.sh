#!/bin/bash
source ftp_functions.sh

# Inicializar configuración base al arrancar
clear
inicializar_sistema

while true; do
    echo -e "\n--- ADMINISTRADOR DE SERVIDOR FTP (Fedora) ---"
    echo "1. Alta masiva de usuarios"
    echo "2. Modificar grupo de un usuario existente"
    echo "3. Salir"
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
        3)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción no válida."
            ;;
    esac
done