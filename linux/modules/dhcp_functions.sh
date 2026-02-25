#!/bin/bash
# =====================================================
# DHCP FUNCTIONS - FEDORA SERVER
# Usa utilidades de core_utils.sh
# =====================================================

CONFIG_FILE="/etc/dhcp/dhcpd.conf"
LEASE_FILE="/var/lib/dhcpd/dhcpd.leases"


# =====================================================
# CONFIGURAR IP DEL SERVIDOR
# =====================================================

configurar_ip_servidor() {
    local ip=$1
    local iface=$2
    local cidr=$3

    print_section "CONFIGURANDO IP DEL SERVIDOR"
    ip addr flush dev "$iface"
    ip addr add "$ip/$cidr" dev "$iface"
    ip link set "$iface" up
    print_ok "IP asignada correctamente"
}


# =====================================================
# CALCULO AUTOMATICO RED Y MASCARA
# =====================================================

calcular_red_y_mascara() {
    local ip1=$1
    local ip2=$2

    local n1=$(ip_a_entero "$ip1")
    local n2=$(ip_a_entero "$ip2")

    local diff=$(( n1 ^ n2 ))

    local bits=32
    while (( diff > 0 )); do
        diff=$(( diff >> 1 ))
        ((bits--))
    done

    local mask=$(( 0xFFFFFFFF << (32-bits) & 0xFFFFFFFF ))
    local net=$(( n1 & mask ))

    RED=$(entero_a_ip $net)
    MASCARA=$(entero_a_ip $mask)
}


# =====================================================
# INSTALACION DHCP
# =====================================================

instalar_dhcp() {
    verificar_root

    print_section "INSTALACION DHCP SERVER"

    if paquete_instalado "dhcp-server"; then
        read -p "El servicio ya esta instalado ¿Reinstalar? (y/n): " op
        [[ "$op" == "y" ]] && {
            reinstalar_paquete "dhcp-server"
            print_ok "Servicio reinstalado"
        }
        return
    fi

    instalar_paquete "dhcp-server"
    print_ok "DHCP instalado correctamente"
}


# =====================================================
# CONFIGURACION DHCP
# =====================================================

configurar_dhcp() {
    verificar_root
    print_section "CONFIGURACION DEL SERVIDOR DHCP"

    read -p "Nombre del ambito: " SCOPE

    while true; do
        read -p "IP inicial: " START
        validar_ip "$START" && break || print_error "IP invalida"
    done

    while true; do
        read -p "IP final: " END
        validar_ip "$END" && break || print_error "IP invalida"
    done

    validar_rango_ip "$START" "$END" || {
        print_error "La IP inicial debe ser menor que la final"
        return
    }

    calcular_red_y_mascara "$START" "$END"

    SERVER_IP=$START
    INTERFAZ=$(detectar_interfaz_por_ip "$SERVER_IP")
    [[ -z "$INTERFAZ" ]] && INTERFAZ=$(obtener_primera_interfaz)

    CIDR=$(mascara_a_cidr "$MASCARA")
    configurar_ip_servidor "$SERVER_IP" "$INTERFAZ" "$CIDR"

    while true; do
        read -p "Tiempo de concesion (segundos): " LEASE
        [[ "$LEASE" =~ ^[0-9]+$ ]] && ((LEASE>0)) && break
        print_error "Solo numeros positivos"
    done

    read -p "Gateway (opcional): " ROUTER
    [[ -n "$ROUTER" ]] && ! validar_ip "$ROUTER" && ROUTER=""

    DNS=""
    read -p "DNS principal,secundario (opcional): " DNS_INPUT

    if [[ -n "$DNS_INPUT" ]]; then
        IFS=',' read -r DNS1 DNS2 <<< "$DNS_INPUT"
        validar_ip "$DNS1" && DNS="$DNS1"
        validar_ip "$DNS2" && DNS="$DNS1, $DNS2"
    fi

    cat > $CONFIG_FILE <<EOF
default-lease-time $LEASE;
max-lease-time $LEASE;

subnet $RED netmask $MASCARA {
    range $START $END;
EOF

    [[ -n "$ROUTER" ]] && echo "    option routers $ROUTER;" >> $CONFIG_FILE
    [[ -n "$DNS" ]] && echo "    option domain-name-servers $DNS;" >> $CONFIG_FILE

    echo "}" >> $CONFIG_FILE

    echo "DHCPDARGS=$INTERFAZ" > /etc/sysconfig/dhcpd

    dhcpd -t || { print_error "Error en configuracion"; return; }

    habilitar_servicio "dhcpd"
    reiniciar_servicio "dhcpd"

    print_ok "Servidor DHCP configurado correctamente"
    echo "Red: $RED"
    echo "Mascara: $MASCARA"
    echo "Interfaz: $INTERFAZ"
}


# =====================================================
# MONITOREO DHCP
# =====================================================

monitorear_dhcp() {
    print_warn "CTRL + C para salir"

    while true; do
        clear
        print_section "ESTADO DEL SERVICIO DHCP"
        systemctl is-active dhcpd
        echo ""
        print_section "CONCESIONES ACTIVAS"
        grep -E "lease|hardware" $LEASE_FILE 2>/dev/null
        sleep 5
    done
}


# =====================================================
# VERIFICACION
# =====================================================

verificar_dhcp() {
    print_section "VERIFICACION DEL SERVICIO DHCP"

    paquete_instalado "dhcp-server" && print_ok "Paquete instalado" || {
        print_error "Paquete NO instalado"
        return
    }

    servicio_activo "dhcpd" && print_ok "Servicio en ejecucion" || print_warn "Servicio detenido"
}