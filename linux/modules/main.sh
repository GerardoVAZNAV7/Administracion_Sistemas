#!/bin/bash

source "$(dirname "$0")/http_functions.sh"

if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta como root: sudo bash $0"
    exit 1
fi

instalar_dependencias_base

while true; do
    echo ""
    echo "========================================="
    echo "   Aprovisionamiento HTTP Multi-Version  "
    echo "          Fedora Server 42               "
    echo "========================================="
    echo "1) Apache (httpd)"
    echo "2) Nginx"
    echo "3) Tomcat"
    echo "4) Limpiar entorno"
    echo "5) Salir"
    read -p "Selecciona una opcion (1-5): " opcion

    case $opcion in
        5) echo "Saliendo..."; break ;;
        4) liberar_entorno; continue ;;
        1) servicio="apache2"  ;;
        2) servicio="nginx"    ;;
        3) servicio="tomcat10" ;;
        *) echo "Opcion invalida."; continue ;;
    esac

    # FIX: llamar directamente (sin $()) para que el prompt sea visible
    # El puerto queda en la variable global PUERTO_ELEGIDO
    solicitarPuerto

    echo "Consultando versiones disponibles..."
    # FIX: llamar directamente (sin $()) — resultado en VERSION_ELEGIDA
    seleccionar_version "$servicio"

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        echo "No se selecciono version valida. Cancelando..."
        continue
    fi

    case $servicio in
        "apache2")  instalar_apache  "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
        "nginx")    instalar_nginx   "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
        "tomcat10") instalar_tomcat  "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" ;;
    esac

    read -p "Realizar otra accion? (s/n): " continuar
    [[ "$continuar" != "s" && "$continuar" != "S" ]] && break
done