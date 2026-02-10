
#*** PRACTICA 2 CONFIGURACION DEL SERVICIO DHCP

CONFIG_FILE="/etc/dhcp/dhcpd.conf"
LEASE_FILE="/var/lib/dhcpd/dhcpd.leases"
INTERFAZ=$(ip -o -4 addr show | grep 192.168.100 | awk '{print $2}')

validar_ip() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    for oct in ${ip//./ }; do
        ((oct >= 0 && oct <= 255)) || return 1
    done
    return 0
}

instalar_si_no_existe() {
    if ! rpm -q dhcp-server &>/dev/null; then
        echo "No se encontro servicio DHCP. Procederemos con la descarga..."
        dnf install -y dhcp-server &>/dev/null
        echo "Descarga completada."
    else
        echo "Servicio DHCP detectado."
    fi
}

configurar_dhcp() {
    echo "=== CONFIGURACION DHCP ==="

    read -p "Nombre del ambito: " SCOPE

    while true; do
        read -p "IP inicial: " START_IP
        validar_ip $START_IP && break || echo "IP invalida"
    done

    while true; do
        read -p "IP final: " END_IP
        validar_ip $END_IP && break || echo "IP invalida"
    done

    read -p "Tiempo de concesion (segundos): " LEASE

    while true; do
        read -p "Gateway: " ROUTER
        validar_ip $ROUTER && break || echo "IP invalida"
    done

    while true; do
        read -p "DNS: " DNS
        validar_ip $DNS && break || echo "IP invalida"
    done

    cat > $CONFIG_FILE <<EOF
option domain-name "red.local";
option domain-name-servers $DNS;
default-lease-time $LEASE;
max-lease-time $LEASE;

subnet 192.168.100.0 netmask 255.255.255.0 {
    range $START_IP $END_IP;
    option routers $ROUTER;
}
EOF

    echo "Configuracion aplicada."

    echo "DHCPDARGS=$INTERFAZ" > /etc/sysconfig/dhcpd

    dhcpd -t || { echo "Error de sintaxis en configuracion"; exit 1; }

    systemctl enable dhcpd &>/dev/null
    systemctl restart dhcpd

    echo "Servidor DHCP activo en interfaz $INTERFAZ"
}

monitoreo() {
    echo "=== MONITOREO EN TIEMPO REAL ==="
    echo "Presiona CTRL + C para salir"
    echo ""

    while true; do
        clear
        echo "Estado del servicio:"
        systemctl is-active dhcpd
        echo ""
        echo "Concesiones activas:"
        cat $LEASE_FILE 2>/dev/null | grep -E "lease|hardware"
        sleep 5
    done
}

instalar_si_no_existe
configurar_dhcp
monitoreo
