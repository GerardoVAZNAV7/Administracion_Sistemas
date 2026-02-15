#!/bin/bash

DOMINIO_BASE="reprobados.com"
NAMED_CONF="/etc/named.conf"
ZONA_DIR="/var/named"
ZONA_FILE="$ZONA_DIR/db.$DOMINIO_BASE"

# ==============================
# DETECTAR RED INTERNA
# ==============================

detectar_red_interna() {
    IFACE_NAT=$(ip route | grep default | awk '{print $5}')
    for i in $(ls /sys/class/net | grep -v lo); do
        [[ "$i" != "$IFACE_NAT" ]] && echo $i && return
    done
}

# ==============================
# OBTENER IP DEL SERVIDOR
# ==============================

obtener_ip_servidor() {
    IFACE_INTERNA=$(detectar_red_interna)
    IP_SERVIDOR=$(ip -4 addr show $IFACE_INTERNA | grep inet | awk '{print $2}' | cut -d/ -f1)
}

# ==============================
# INSTALAR DNS (IDEMPOTENTE)
# ==============================

instalar_dns() {

    echo "Instalando DNS automaticamente..."

    if ! rpm -q bind &>/dev/null; then
        dnf install -y bind bind-utils
    fi

    obtener_ip_servidor

    sed -i 's/listen-on port 53 {[^}]*};/listen-on port 53 { any; };/' $NAMED_CONF
    sed -i 's/allow-query[^;]*;/allow-query { any; };/' $NAMED_CONF

    firewall-cmd --permanent --add-service=dns >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1

    systemctl enable named
    systemctl restart named

    echo "DNS instalado correctamente"
    echo "IP servidor DNS: $IP_SERVIDOR"
}
crear_zona() {

    obtener_ip_servidor

    read -p "IP del cliente a resolver: " IP_CLIENTE

    SERIAL=$(date +%Y%m%d01)

cat > $ZONA_FILE <<EOF
\$TTL 86400
@   IN  SOA ns.$DOMINIO_BASE. root.$DOMINIO_BASE. (
        $SERIAL
        3600
        1800
        604800
        86400 )

@       IN  NS  ns.$DOMINIO_BASE.
ns      IN  A   $IP_SERVIDOR

@       IN  A   $IP_CLIENTE
www     IN  A   $IP_CLIENTE
EOF

    chown named:named $ZONA_FILE
    chmod 640 $ZONA_FILE
    restorecon $ZONA_FILE 2>/dev/null

    if ! grep -q "zone \"$DOMINIO_BASE\"" $NAMED_CONF; then
cat >> $NAMED_CONF <<EOF

zone "$DOMINIO_BASE" IN {
    type master;
    file "db.$DOMINIO_BASE";
};
EOF
    fi

    named-checkconf || { echo "Error en configuracion"; return; }
    named-checkzone $DOMINIO_BASE $ZONA_FILE || return

    systemctl restart named

    echo "Zona creada correctamente"
}
eliminar_zona() {

    rm -f $ZONA_FILE
    sed -i "/zone \"$DOMINIO_BASE\"/,/};/d" $NAMED_CONF
    systemctl restart named
    echo "Zona eliminada"
}
consultar_dominios() {

    echo ""
    printf "%-20s %-15s\n" "DOMINIO" "IP"
    printf "%-20s %-15s\n" "--------" "---------------"

    if [ ! -f "$ZONA_FILE" ]; then
        echo "No existe zona configurada"
        return
    fi

    IP=$(awk '$1=="@" && $3=="A" {print $4}' $ZONA_FILE)

    printf "%-20s %-15s\n" "$DOMINIO_BASE" "$IP"
    printf "%-20s %-15s\n" "www.$DOMINIO_BASE" "$IP"
}
probar_dns() {

    obtener_ip_servidor

    echo "Probando resolucion local..."
    nslookup $DOMINIO_BASE $IP_SERVIDOR
    ping -c 2 www.$DOMINIO_BASE
}
menu() {
    while true; do
        echo ""
        echo "===== SERVIDOR DNS AUTOMATIZADO ====="
        echo "1. Instalar DNS"
        echo "2. Crear/Actualizar zona"
        echo "3. Eliminar zona"
        echo "4. Consultar dominios"
        echo "5. Probar resolucion"
        echo "6. Salir"
        read -p "Seleccione: " op

        case $op in
            1) instalar_dns ;;
            2) crear_zona ;;
            3) eliminar_zona ;;
            4) consultar_dominios ;;
            5) probar_dns ;;
            6) exit ;;
        esac
    done
}

menu
