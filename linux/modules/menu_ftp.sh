#!/bin/bash
# =============================================================================
# menu_ftp.sh — Menu interactivo de gestion FTP
# Ubicacion: linux/modules/menu_ftp.sh
# Llamado desde: linux/main.sh
# Depende de:    linux/modules/ftp_functions.sh
# =============================================================================

source "$BASE_DIR/modules/ftp_functions.sh"

menu_ftp() {
    clear

    # Inicializar si vsftpd no esta corriendo (idempotente)
    if ! systemctl is-active --quiet vsftpd; then
        inicializar_sistema
    fi

    while true; do
        echo ""
        echo "======================================="
        echo "   ADMINISTRADOR DE SERVIDOR FTP"
        echo "======================================="
        echo "  1) Alta de usuarios"
        echo "  2) Modificar grupo de usuario"
        echo "  3) Eliminar usuario"
        echo "  4) Listar usuarios registrados"
        echo "  5) Verificar estado / IP del servicio"
        echo "  6) Reconfigurar servicio (Reset)"
        echo "  0) Regresar al Menu Principal"
        echo "---------------------------------------"
        read -p "  Seleccione una opcion: " opcion

        case "$opcion" in

            # ------------------------------------------------------------------
            1)
                echo ""
                echo "--- Alta de Usuarios ---"
                local n=0
                while true; do
                    read -p "  Numero de usuarios a agregar: " n
                    [[ "$n" =~ ^[1-9][0-9]*$ ]] && break
                    echo "  [!] Ingrese un numero valido mayor a 0."
                done

                for (( i=1; i<=n; i++ )); do
                    echo ""
                    echo "  -- Usuario $i de $n --"
                    local uname
                    uname=$(capturar_usuario_valido "Nombre de usuario")
                    local upass
                    upass=$(capturar_contrasena)
                    local ugroup
                    ugroup=$(capturar_grupo_ftp)
                    crear_usuario "$uname" "$upass" "$ugroup"
                done
                ;;

            # ------------------------------------------------------------------
            2)
                echo ""
                echo "--- Modificar Grupo ---"
                read -p "  Nombre del usuario: " uname

                if ! id "$uname" &>/dev/null; then
                    echo "  [!] El usuario '$uname' no existe."
                else
                    local cur_group="Sin grupo"
                    id "$uname" | grep -q "reprobados"   && cur_group="reprobados"
                    id "$uname" | grep -q "recursadores" && cur_group="recursadores"
                    echo "  Grupo actual: $cur_group"

                    local new_group
                    new_group=$(capturar_grupo_ftp)
                    modificar_grupo_usuario "$uname" "$new_group"
                fi
                ;;

            # ------------------------------------------------------------------
            3)
                echo ""
                echo "--- Eliminar Usuario ---"
                read -p "  Nombre del usuario: " uname

                if ! id "$uname" &>/dev/null; then
                    echo "  [!] El usuario '$uname' no existe."
                else
                    read -p "  Confirmar eliminacion de '$uname' (s/n): " confirm
                    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                        eliminar_usuario "$uname"
                    else
                        echo "  Operacion cancelada."
                    fi
                fi
                ;;

            # ------------------------------------------------------------------
            4)
                listar_usuarios_ftp
                ;;

            # ------------------------------------------------------------------
            5)
                verificar_servicio_ftp
                ;;

            # ------------------------------------------------------------------
            6)
                echo "  Reaplicando configuracion completa..."
                inicializar_sistema
                ;;

            # ------------------------------------------------------------------
            0)
                echo "  Volviendo al menu principal..."
                break
                ;;

            # ------------------------------------------------------------------
            *)
                echo "  [!] Opcion invalida. Intente de nuevo."
                ;;
        esac

        echo ""
        read -p "  Presione Enter para continuar..."
        clear
    done
}