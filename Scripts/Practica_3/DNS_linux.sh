

CONFIG_LOCAL="/etc/named.conf"
ZONA_DIR="/var/named"

# =========================================
# VALIDACIONES IP
# =========================================

validar_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    for o in ${1//./ }; do
        ((o>=0 && o<=255)) || return 1
    done
    return 0
}

# =========================================
# DETECTAR IP FIJA
# =========================================

tiene_ip_fija() {
    ip -4 addr show | grep -v dynamic | grep inet >/dev/null
}

configurar_ip_fija() {

    echo "=== CONFIGURAR IP FIJA ==="

    while true; do
        read -p "IP del servidor Fedora: " IP_SERVER
        validar_ip "$IP_SERVER" && break || echo "IP invalida"
    done

    read -p "Interfaz de red (ej: enp0s3): " IFACE

    nmcli con mod "$IFACE" ipv4.addresses "$IP_SERVER/24"
    nmcli con mod "$IFACE" ipv4.method manual
    nmcli con up "$IFACE"

    echo "IP fija configurada"
}

# =========================================
# INSTALAR BIND
# =========================================

instalar_dns() {

    if rpm -q bind &>/dev/null; then
        echo "BIND ya instalado"
        return
    fi

    echo "Instalando BIND..."
    dnf install -y bind bind-utils bind-doc
    systemctl enable named
    systemctl start named
    echo "Instalacion completada"
}

# =========================================
# ALTA DE DOMINIO
# =========================================

alta_dominio() {

    echo "=== ALTA DE DOMINIO ==="

    read -p "Nombre del dominio (ej: reprobados.com): " DOMINIO

    # VALIDAR QUE NO EXISTA
    if grep -q "zone \"$DOMINIO\"" $CONFIG_LOCAL; then
        echo "El dominio ya existe"
        return
    fi

    # VALIDAR IP DEL CLIENTE
    while true; do
        read -p "IP del cliente Ubuntu (asignada por DHCP): " IP_CLIENTE
        validar_ip "$IP_CLIENTE" && break || echo "IP invalida"
    done

    ARCHIVO_ZONA="db.$DOMINIO"
    RUTA_ZONA="$ZONA_DIR/$ARCHIVO_ZONA"
    SERIAL=$(date +%Y%m%d01)

    echo "Creando zona DNS automatica..."

cat > $RUTA_ZONA <<EOF
\$TTL 86400
@   IN  SOA ns.$DOMINIO. root.$DOMINIO. (
        $SERIAL
        3600
        1800
        604800
        86400 )

@       IN  NS  ns.$DOMINIO.
ns      IN  A   $IP_CLIENTE

; REGISTROS OBLIGATORIOS AUTOMATICOS
@       IN  A   $IP_CLIENTE
www     IN  A   $IP_CLIENTE
EOF

    echo "Registrando zona en named.conf..."

cat >> $CONFIG_LOCAL <<EOF

zone "$DOMINIO" IN {
    type master;
    file "$ARCHIVO_ZONA";
};
EOF

    echo "Validando configuracion..."

    named-checkconf || { echo "Error en named.conf"; return; }
    named-checkzone $DOMINIO $RUTA_ZONA || { echo "Error en archivo de zona"; return; }

    systemctl restart named

    echo "Dominio $DOMINIO creado correctamente"
    echo "Registros creados automaticamente:"
    echo " - $DOMINIO"
    echo " - www.$DOMINIO"
}
# =========================================
# BAJA DE DOMINIO
# =========================================

baja_dominio() {

    echo "=== BAJA DE DOMINIO ==="
    read -p "Dominio a eliminar: " DOMINIO
      if ! grep -q "zone \"$DOMINIO\"" $CONFIG_LOCAL; then
        echo "El dominio no existe"
      return
      fi


    ARCHIVO_ZONA="db.$DOMINIO"
    RUTA_ZONA="$ZONA_DIR/$ARCHIVO_ZONA"

    sed -i "/zone \"$DOMINIO\"/,/};/d" $CONFIG_LOCAL
    rm -f $RUTA_ZONA

    systemctl restart named

    echo "Dominio eliminado"
}

# =========================================
# CONSULTAR DOMINIOS
# =========================================

consultar_dominios() {

    echo ""
    echo "==============================="
    echo "   DOMINIOS CONFIGURADOS DNS"
    echo "==============================="
    printf "%-25s %-15s\n" "DOMINIO" "IP"
    printf "%-25s %-15s\n" "-------------------------" "---------------"

    DOMS=$(grep 'zone "' $CONFIG_LOCAL | cut -d '"' -f2)

    if [ -z "$DOMS" ]; then
        echo "No hay dominios configurados"
        return
    fi

    for d in $DOMS; do
        ZONA_FILE="$ZONA_DIR/db.$d"

        if [ -f "$ZONA_FILE" ]; then
            # Obtiene la IP del registro A principal (@)
            IP=$(grep -E "^[[:space:]]*@.*IN[[:space:]]+A" "$ZONA_FILE" | awk '{print $NF}')

            # Si no encuentra IP exacta, intenta con ns
            if [ -z "$IP" ]; then
                IP=$(grep -E "^[[:space:]]*ns.*IN[[:space:]]+A" "$ZONA_FILE" | awk '{print $NF}')
            fi

            printf "%-25s %-15s\n" "$d" "$IP"
        else
            printf "%-25s %-15s\n" "$d" "Archivo no encontrado"
        fi
    done

    echo ""
}


# =========================================
# PROBAR DNS
# =========================================

probar_dns() {

    read -p "Dominio a probar (ingresa sin wwww): " DOMINIO
    nslookup $DOMINIO
    nslookup www.$DOMINIO
}

# =========================================
# VERIFICAR SERVICIO
# =========================================

verificar_servicio() {

    echo "=== ESTADO DNS ==="

    if systemctl list-unit-files | grep -q named; then
        echo "Servicio instalado"
    else
        echo "Servicio NO instalado"
        return
    fi

    systemctl status named --no-pager
}

# =========================================
# MENU PRINCIPAL
# =========================================

menu() {

    while true; do
        echo ""
        echo "===== DNS FEDORA SERVER ====="
        echo "1. Instalar DNS"
        echo "2. Alta de dominio"
        echo "3. Baja de dominio"
        echo "4. Consultar dominios"
        echo "5. Probar resolucion"
        echo "6. Verificar servicio"
        echo "7. Salir"

        read -p "Seleccione: " op

        case $op in
            1)
                instalar_dns
                tiene_ip_fija || configurar_ip_fija
                ;;
            2) alta_dominio ;;
            3) baja_dominio ;;
            4) consultar_dominios ;;
            5) probar_dns ;;
            6) verificar_servicio ;;
            7) exit ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

menu
