CONFIG_FILE="/etc/dhcp/dhcpd.conf"
LEASE_FILE="/var/lib/dhcpd/dhcpd.leases"
INTERFAZ=$(ip -o -4 addr show | grep 192.168.100 | awk '{print $2}')

validar_ip() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    for oct in ${ip//./ }; do
        ((oct>=0 && oct<=255)) || return 1
    done
    return 0
}

instalar_dhcp() {
    if ! rpm -q dhcp-server &>/dev/null; then
        echo "Iniciando descarga del servicio DHCP..."
        dnf install -y dhcp-server &>/dev/null
        echo "Descarga finalizada."
    else
        echo "El servicio DHCP ya esta instalado."
    fi
}

configurar_dhcp() {
    echo "=== CONFIGURACION DHCP ==="

    read -p "Nombre del ambito: " SCOPE

    while true; do read -p "IP inicial: " START; validar_ip $START && break || echo "IP invalida"; done
    while true; do read -p "IP final: " END; validar_ip $END && break || echo "IP invalida"; done

    read -p "Tiempo de concesion (segundos): " LEASE

    while true; do read -p "Gateway: " ROUTER; validar_ip $ROUTER && break || echo "IP invalida"; done
    while true; do read -p "DNS: " DNS; validar_ip $DNS && break || echo "IP invalida"; done

    cat > $CONFIG_FILE <<EOF
option domain-name "red.local";
option domain-name-servers $DNS;
default-lease-time $LEASE;
max-lease-time $LEASE;

subnet 192.168.100.0 netmask 255.255.255.0 {
    range $START $END;
    option routers $ROUTER;
}
EOF

    echo "DHCPDARGS=$INTERFAZ" > /etc/sysconfig/dhcpd

    dhcpd -t || { echo "Error de sintaxis"; exit 1; }

    systemctl enable dhcpd &>/dev/null
    systemctl restart dhcpd

    echo "Configuracion aplicada correctamente."
}

monitoreo() {
    echo "=== MONITOREO DHCP ==="
    echo "CTRL + C para salir"

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

menu() {
    while true; do
        echo ""
        echo "===== MENU DHCP LINUX ====="
        echo "1. Instalar servicio DHCP"
        echo "2. Configurar servicio DHCP"
        echo "3. Monitorear servicio"
        echo "4. Salir"
        read -p "Seleccione opcion: " op

        case $op in
            1) instalar_dhcp ;;
            2) configurar_dhcp ;;
            3) monitoreo ;;
            4) exit ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

menu
