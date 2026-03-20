#!/bin/bash

# Importar todas las funciones (incluyendo navegar_y_descargar_ftp)
source ./ssl_functions.sh

# Inicializar arreglo global para el resumen final
export RESUMEN_INSTALACIONES=()

mostrar_menu() {
    clear
    echo "=========================================================="
    echo "         ORQUESTADOR HIBRIDO DE SERVICIOS (LINUX)         "
    echo "=========================================================="
    echo "1) Apache"
    echo "2) Nginx"
    echo "3) Tomcat"
    echo "4) vsftpd"
    echo "5) Salir y mostrar resumen final"
    echo "=========================================================="
    read -p "Seleccione el servicio a instalar: " opcion
    echo ""
}

preguntar_fuente_y_ssl() {
    local servicio=$1
    echo "----------------------------------------------------------"
    echo "Configuracion para $servicio"
    echo "----------------------------------------------------------"
    echo "Seleccione la fuente de instalacion:"
    echo "1) WEB (Descarga directa oficial)"
    echo "2) FTP (Repositorio privado dinamico)"
    read -p "Opcion: " fuente_opcion

    if [[ "$fuente_opcion" == "2" ]]; then
        fuente="FTP"
        # Llamamos a la funcion de navegacion interactiva
        navegar_y_descargar_ftp
        
        # Si la funcion retorna 1 (error de descarga o validacion hash)
        if [[ $? -ne 0 ]]; then
            echo "Aviso: No se pudo obtener el instalador seguro desde el FTP."
            echo "Presione ENTER para volver al menu principal."
            read
            return 1
        fi
        
        # Si todo salio bien, tomamos el nombre del archivo validado
        archivo_a_instalar="$PAQUETE_DESCARGADO"
    else
        fuente="WEB"
        archivo_a_instalar="" # La funcion individual hara el wget/curl web
    fi

    echo ""
    read -p "Desea activar SSL en este servicio? [S/N]: " activar_ssl
    # Normalizamos la respuesta a mayuscula para evitar errores
    activar_ssl=$(echo "$activar_ssl" | tr '[:lower:]' '[:upper:]')
    
    return 0
}

# Bucle principal del Orquestador
while true; do
    mostrar_menu
    
    case $opcion in
        1)
            preguntar_fuente_y_ssl "Apache"
            if [[ $? -eq 0 ]]; then
                instalar_apache "$archivo_a_instalar" "$fuente" "$activar_ssl"
            fi
            ;;
        2)
            preguntar_fuente_y_ssl "Nginx"
            if [[ $? -eq 0 ]]; then
                instalar_nginx "$archivo_a_instalar" "$fuente" "$activar_ssl"
            fi
            ;;
        3)
            preguntar_fuente_y_ssl "Tomcat"
            if [[ $? -eq 0 ]]; then
                instalar_tomcat "$archivo_a_instalar" "$fuente" "$activar_ssl"
            fi
            ;;
        4)
            preguntar_fuente_y_ssl "vsftpd"
            if [[ $? -eq 0 ]]; then
                instalar_vsftpd "$archivo_a_instalar" "$fuente" "$activar_ssl"
            fi
            ;;
        5)
            mostrar_resumen_final
            break
            ;;
        *)
            echo "Opcion no valida."
            sleep 2
            ;;
    esac
    
    # Preguntar si desea continuar despues de cada instalacion
    if [[ "$opcion" != "5" ]]; then
        echo ""
        read -p "Deseas orquestar otra instalacion? (s/n): " continuar
        continuar=$(echo "$continuar" | tr '[:lower:]' '[:upper:]')
        if [[ "$continuar" == "N" ]]; then
            mostrar_resumen_final
            break
        fi
    fi
done