#!/bin/bash

source "$BASE_DIR/modules/ftp_functions.sh"

menu_ftp() {
    clear
    if ! systemctl is-active --quiet vsftpd; then
        inicializar_sistema
    fi

    while true; do
        echo -e "\n======================================="
        echo "   ADMINISTRADOR DE SERVIDOR FTP"
        echo "======================================="
        echo "1) Alta masiva de usuarios"
        echo "2) Modificar grupo de usuario"
        echo "3) LISTAR USUARIOS REGISTRADOS"      # <-- Nueva opción
        echo "4) Verificar estado/IP del servicio"
        echo "5) RECONFIGURAR SERVICIO (Reset)"
        echo "0) Regresar al Menú Principal"
        echo "---------------------------------------"
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                read -p "Número de usuarios: " n
                for (( i=1; i<=$n; i++ )); do
                    read -p "Username: " uname
                    read -s -p "Password: " upass; echo
                    read -p "Grupo (1:reprobados, 2:recursadores): " g_op
                    [[ "$g_op" == "1" ]] && ugroup="reprobados" || ugroup="recursadores"
                    crear_usuario "$uname" "$upass" "$ugroup"
                done
                ;;
            2)
                read -p "Usuario: " uname
                read -p "Nuevo Grupo (1:reprobados, 2:recursadores): " g_op
                [[ "$g_op" == "1" ]] && ugroup="reprobados" || ugroup="recursadores"
                modificar_grupo_usuario "$uname" "$ugroup"
                ;;
            3)
                listar_usuarios_ftp
                ;;
            4)
                verificar_servicio_ftp
                ;;
            5)
                echo "Reaplicando configuración de archivos, firewall y SELinux..."
                inicializar_sistema
                ;;
            0) break ;;
            *) echo "Opción inválida." ;;
        esac
        read -p "Presione Enter para continuar..."
        clear
    done
}