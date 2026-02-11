#!/bin/bash

CONFIG_FILE="/etc/dhcp/dhcpd.conf"
LEASE_FILE="/var/lib/dhcpd/dhcpd.leases"

# ==============================
# UTILIDADES IP
# ==============================
configurar_ip_servidor() {
    local ip=$1
    local iface=$2
    local cidr=$3

    echo "Asignando IP $ip/$cidr a la interfaz $iface"

    ip addr flush dev $iface
    ip addr add $ip/$cidr dev $iface
    ip link set $iface up
}

mascara_a_cidr() {
    local mask=$1
    local cidr=0
    IFS=. read -r o1 o2 o3 o4 <<< "$mask"
    for o in $o1 $o2 $o3 $o4; do
        case $o in
            255) ((cidr+=8));;
            254) ((cidr+=7));;
            252) ((cidr+=6));;
            248) ((cidr+=5));;
            240) ((cidr+=4));;
            224) ((cidr+=3));;
            192) ((cidr+=2));;
            128) ((cidr+=1));;
            0) ;;
        esac
    done
    echo $cidr
}


ip_a_entero() {
    IFS=. read -r o1 o2 o3 o4 <<< "$1"
    echo $((o1*256**3 + o2*256**2 + o3*256 + o4))
}

entero_a_ip() {
    local ip=$1
    echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"
}

validar_ip() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    for oct in ${ip//./ }; do
        ((oct>=0 && oct<=255)) || return 1
    done

    [[ "$ip" == "0.0.0.0" ]] && return 1
    [[ "$ip" == "127.0.0.1" ]] && return 1
    [[ "$ip" == "255.255.255.255" ]] && return 1

    return 0
}

validar_rango() {
    local start=$1
    local end=$2

    validar_ip "$start" || return 1
    validar_ip "$end" || return 1

    local s=$(ip_a_entero "$start")
    local e=$(ip_a_entero "$end")

    (( s < e )) || return 1
    return 0
}

# ==============================
# CALCULO AUTOMATICO DE RED
# ==============================

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

detectar_interfaz() {
    local ip=$1
    INTERFAZ=$(ip -o -4 addr show | grep "$ip" | awk '{print $2}' | head -n1)

    if [[ -z "$INTERFAZ" ]]; then
        INTERFAZ=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
    fi
}

# ==============================
# INSTALACION
# ==============================

instalar_dhcp() {
    if rpm -q dhcp-server &>/dev/null; then
        while true; do
            read -p "El servicio ya esta instalado. ¿Quieres volver a instalarlo? (y/n): " op
            [[ "$op" == "y" ]] && {
                dnf reinstall -y dhcp-server &>/dev/null
                echo "Servicio reinstalado."
                return
            }
            [[ "$op" == "n" ]] && {
                echo "Instalacion cancelada."
                return
            }
            echo "Solo se permite y o n"
        done
    else
        echo "Instalando DHCP..."
        dnf install -y dhcp-server &>/dev/null
        echo "Instalacion completada."
    fi
}

# ==============================
# CONFIGURACION
# ==============================

configurar_dhcp() {
    echo "=== CONFIGURACION DHCP ==="

    read -p "Nombre del ambito: " SCOPE

    while true; do
        read -p "IP inicial: " START
        validar_ip "$START" && break || echo "IP invalida"
    done

    while true; do
        read -p "IP final: " END
        validar_ip "$END" && break || echo "IP invalida"
    done

    validar_rango "$START" "$END" || {
        echo "La IP inicial debe ser menor que la final"
        return
    }

    calcular_red_y_mascara "$START" "$END"

    SERVER_IP=$START

    detectar_interfaz "$SERVER_IP"
    CIDR=$(mascara_a_cidr "$MASCARA")
    configurar_ip_servidor "$SERVER_IP" "$INTERFAZ" "$CIDR"


    while true; do
        read -p "Tiempo de concesion (segundos): " LEASE
        [[ "$LEASE" =~ ^[0-9]+$ ]] && ((LEASE>0)) && break
        echo "Solo numeros enteros positivos"
    done

    read -p "Gateway (opcional): " ROUTER
    [[ -n "$ROUTER" ]] && ! validar_ip "$ROUTER" && ROUTER=""

    read -p "DNS (opcional): " DNS
    [[ -n "$DNS" ]] && ! validar_ip "$DNS" && DNS=""

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

    dhcpd -t || { echo "Error en configuracion"; return; }

    systemctl enable dhcpd &>/dev/null
    systemctl restart dhcpd

    echo ""
    echo "Servidor configurado correctamente"
    echo "Red: $RED"
    echo "Mascara: $MASCARA"
    echo "Interfaz: $INTERFAZ"
}

# ==============================
# MONITOREO
# ==============================

monitoreo() {
    echo "CTRL + C para salir"
    while true; do
        clear
        echo "Estado del servicio:"
        systemctl is-active dhcpd
        echo ""
        echo "Concesiones activas:"
        grep -E "lease|hardware" $LEASE_FILE 2>/dev/null
        sleep 5
    done
}

verificar_instalacion() {
    echo "=== VERIFICACION DEL SERVICIO DHCP ==="
    echo ""

    if rpm -q dhcp-server &>/dev/null; then
        echo "Paquete dhcp-server instalado"
    else
        echo "Paquete dhcp-server NO instalado"
        return
    fi

    if systemctl list-unit-files | grep -q "^dhcpd.service"; then
        echo "Servicio dhcpd registrado en systemd"
    else
        echo "Servicio dhcpd no registrado"
        return
    fi

    estado=$(systemctl is-active dhcpd 2>/dev/null)

    case "$estado" in
        active)
            echo "Servicio en ejecucion"
            ;;
        inactive)
            echo "Servicio instalado pero detenido"
            ;;
        failed)
            echo "Servicio instalado pero en estado FAILED"
            ;;
        *)
            echo "Estado desconocido: $estado"
            ;;
    esac
}


# ==============================
# MENU
# ==============================

menu() {
    while true; do
        echo ""
        echo "===== MENU DHCP FEDORA SERVER ====="
        echo "1. Instalar servicio DHCP"
        echo "2. Configurar servicio DHCP"
        echo "3. Monitorear servicio"
        echo "4. Verificar instalacion"
        echo "5. Salir"
        read -p "Seleccione opcion: " op

        case $op in
            1) instalar_dhcp ;;
            2) configurar_dhcp ;;
            3) monitoreo ;;
            4) verificar_instalacion ;;
            5) exit ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}


menu
