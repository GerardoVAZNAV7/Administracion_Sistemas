# *** PRACTICA 2 CONFIGURACION DEL SERVICIO DCHP

CONFIG_FILE="/etc/dhcp/dhcpd.conf"
LEASE_FILE="/var/lib/dhcpd/dhcpd.leases"

function validar_ip() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    for oct in ${ip//./ }; do
        ((oct >= 0 && oct <= 255)) || return 1
    done
    return 0
}

function instalar_dhcp() {
    if ! rpm -q dhcp-server &>/dev/null; then
        echo "Instalando isc-dhcp-server..."
        dnf install -y dhcp-server
    else
        echo "DHCP ya instalado."
    fi
}

function configurar_dhcp() {
    read -p "Nombre del ámbito: " SCOPE

    while true; do
        read -p "IP inicial: " START_IP
        validar_ip $START_IP && break || echo "IP inválida"
    done

    while true; do
        read -p "IP final: " END_IP
        validar_ip $END_IP && break || echo "IP inválida"
    done

    read -p "Tiempo de concesión en segundos: " LEASE

    while true; do
        read -p "Gateway: " ROUTER
        validar_ip $ROUTER && break || echo "IP inválida"
    done

    while true; do
        read -p "DNS: " DNS
        validar_ip $DNS && break || echo "IP inválida"
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

    dhcpd -t || { echo "Error de sintaxis"; exit 1; }

    systemctl enable dhcpd
    systemctl restart dhcpd
}

function monitoreo() {
    echo "Estado del servicio:"
    systemctl status dhcpd --no-pager

    echo "Concesiones activas:"
    cat $LEASE_FILE
}

case "$1" in
    instalar) instalar_dhcp ;;
    configurar) configurar_dhcp ;;
    monitoreo) monitoreo ;;
    *) echo "Uso: $0 {instalar|configurar|monitoreo}" ;;
esac
