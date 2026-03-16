# #!/bin/bash

# source "$(dirname "$0")/http_functions.sh"

# if [ "$EUID" -ne 0 ]; then
#     echo "Ejecuta como root: sudo bash $0"
#     exit 1
# fi

# instalar_dependencias_base

# while true; do
#     echo ""
#     echo "========================================="
#     echo "   Aprovisionamiento HTTP Multi-Version  "
#     echo "          Fedora Server 42               "
#     echo "========================================="
#     echo "1) Apache (httpd)"
#     echo "2) Nginx"
#     echo "3) Tomcat"
#     echo "4) Limpiar entorno"
#     echo "5) Salir"
#     read -p "Selecciona una opcion (1-5): " opcion

#     case $opcion in
#         5) echo "Saliendo..."; break ;;
#         4) liberar_entorno; continue ;;
#         1) servicio="apache2"  ;;
#         2) servicio="nginx"    ;;
#         3) servicio="tomcat10" ;;
#         *) echo "Opcion invalida."; continue ;;
#     esac

#     # FIX: llamar directamente (sin $()) para que el prompt sea visible
#     # El puerto queda en la variable global PUERTO_ELEGIDO
#     solicitarPuerto

#     echo "Consultando versiones disponibles..."
#     # FIX: llamar directamente (sin $()) — resultado en VERSION_ELEGIDA
#     seleccionar_version "$servicio"

#     if [[ -z "$VERSION_ELEGIDA" ]]; then
#         echo "No se selecciono version valida. Cancelando..."
#         continue
#     fi

#     case $servicio in
#         "apache2")  instalar_apache  "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
#         "nginx")    instalar_nginx   "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
#         "tomcat10") instalar_tomcat  "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
#     esac

#     read -p "Realizar otra accion? (s/n): " continuar
#     [[ "$continuar" != "s" && "$continuar" != "S" ]] && break
# done
#!/bin/bash
# =============================================================================
# main_linux.sh — Aprovisionamiento HTTP Multi-Servidor en Fedora Server 42
# Uso: sudo bash main_linux.sh
# Arquitectura: Solo llama funciones definidas en http_functions.sh
# =============================================================================

# Cargar funciones desde el mismo directorio que este script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/http_functions.sh"

# -----------------------------------------------------------------------------
# Verificar que se ejecuta como root
# -----------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo ""
    echo "  [ERROR] Este script requiere privilegios de superusuario."
    echo "  Uso correcto: sudo bash $0"
    echo ""
    exit 1
fi

# -----------------------------------------------------------------------------
# Inicialización: instalar dependencias base una sola vez
# -----------------------------------------------------------------------------
instalar_dependencias_base

# -----------------------------------------------------------------------------
# Bucle principal del menú
# -----------------------------------------------------------------------------
while true; do
    echo ""
    echo "  ╔═════════════════════════════════════════════╗"
    echo "  ║    Aprovisionamiento HTTP Multi-Versión     ║"
    echo "  ║           Fedora Server 42                  ║"
    echo "  ║           VM: $VM_IP                        ║"
    echo "  ╠═════════════════════════════════════════════╣"
    echo "  ║  1) Apache (httpd)                          ║"
    echo "  ║  2) Nginx                                   ║"
    echo "  ║  3) Tomcat                                  ║"
    echo "  ║  4) Limpiar entorno                         ║"
    echo "  ║  5) Salir                                   ║"
    echo "  ╚═════════════════════════════════════════════╝"
    echo ""
    read -p "  Selecciona una opción (1-5): " opcion

    # Validar que no esté vacía ni tenga caracteres especiales
    if [[ -z "$opcion" || ! "$opcion" =~ ^[1-5]$ ]]; then
        echo "  [!] Opción inválida. Elige entre 1 y 5."
        continue
    fi

    case "$opcion" in
        5)
            echo ""
            echo "  [*] Saliendo del aprovisionador. ¡Hasta luego!"
            echo ""
            exit 0
            ;;
        4)
            liberar_entorno
            continue
            ;;
        1) servicio="apache2"  ; nombre_display="Apache (httpd)" ;;
        2) servicio="nginx"    ; nombre_display="Nginx"          ;;
        3) servicio="tomcat10" ; nombre_display="Tomcat"         ;;
    esac

    echo ""
    echo "  [*] Configurando: $nombre_display"
    echo "  ─────────────────────────────────────────────"

    # Solicitar y validar puerto (resultado en $PUERTO_ELEGIDO)
    solicitarPuerto "$nombre_display"

    echo ""
    echo "  [*] Consultando versiones disponibles en el repositorio..."
    # Seleccionar versión dinámicamente (resultado en $VERSION_ELEGIDA)
    seleccionar_version "$servicio"

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        echo "  [!] No se pudo determinar la versión. Operación cancelada."
        continue
    fi

    echo ""
    echo "  [*] Iniciando instalación..."
    echo "      Servidor : $nombre_display"
    echo "      Versión  : $VERSION_ELEGIDA"
    echo "      Puerto   : $PUERTO_ELEGIDO"
    echo "      URL      : http://$VM_IP:$PUERTO_ELEGIDO"
    echo "  ─────────────────────────────────────────────"
    echo ""

    # Llamar a la función de instalación correspondiente
    case "$servicio" in
        "apache2")  instalar_apache  "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
        "nginx")    instalar_nginx   "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
        "tomcat10") instalar_tomcat  "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
    esac

    echo ""
    echo "  ─────────────────────────────────────────────"
    echo "  Verificación rápida con curl:"
    echo "    curl -I http://$VM_IP:$PUERTO_ELEGIDO"
    echo "  ─────────────────────────────────────────────"

    echo ""
    read -p "  ¿Instalar otro servidor? (s/n): " continuar

    # Validar respuesta
    if [[ -z "$continuar" || ! "$continuar" =~ ^[sSnN]$ ]]; then
        continuar="n"
    fi

    if [[ "$continuar" != "s" && "$continuar" != "S" ]]; then
        echo ""
        echo "  [*] ¡Aprovisionamiento completado!"
        echo ""
        break
    fi
done