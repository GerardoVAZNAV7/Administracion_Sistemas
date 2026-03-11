#!/bin/bash

# Se carga el archivo de funciones locales
source ./http_functions.sh

# Validar que somos root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit 1
fi

instalar_dependencias_base

while true; do
    echo "========================================="
    echo "   Aprovisionamiento HTTP Multi-Versión  "
    echo "========================================="
    echo "1. Apache2"
    echo "2. Nginx"
    echo "3. Tomcat"
    echo "4. Limpiar entorno (Liberar puertos)"
    echo "5. Salir"
    read -p "Selecciona una opción (1-5): " opcion

    if [[ "$opcion" == "5" ]]; then
        echo "Saliendo del instalador..."
        break
    elif [[ "$opcion" == "4" ]]; then
        liberar_entorno
        continue
    fi

    # Mapeo de la selección al nombre del servicio
    case $opcion in
        1) servicio="apache2" ;;
        2) servicio="nginx" ;;
        3) servicio="tomcat10" ;;
        *) echo "Opción inválida."; continue ;;
    esac

    # Llamada a la función de puerto validada
    puerto=$(solicitarPuerto)

    echo "Consultando versiones disponibles para $servicio..."
    
   echo "Consultando versiones disponibles en los repositorios de Debian..."
    version_elegida=$(seleccionar_version "$servicio")

    if [[ -z "$version_elegida" ]]; then
        echo "No se seleccionó una versión válida. Cancelando..."
        continue
    fi

    # Ejecutar la instalación silenciosa según el servicio
    case $servicio in
        "apache2") instalar_apache "$version_elegida" "$puerto" ;;
        "nginx")   instalar_nginx "$version_elegida" "$puerto" ;;
        "tomcat10") instalar_tomcat "$version_elegida" "$puerto" ;;
    esac

    read -p "¿Deseas realizar otra acción? (s/n): " continuar
    if [[ "$continuar" != "s" && "$continuar" != "S" ]]; then
        break
    fi
done