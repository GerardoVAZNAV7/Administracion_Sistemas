#!/bin/bash
# =====================================================
# CORE UTILS - ADMINISTRACION DE SISTEMAS (FEDORA)
# Funciones reutilizables para TODAS las practicas
# =====================================================


# =====================================================
# FORMATO Y MENSAJES
# =====================================================

print_section() {
    echo ""
    echo "====================================="
    echo "$1"
    echo "====================================="
}

print_ok() {
    echo -e "\033[0;32m$1\033[0m"
}

print_error() {
    echo -e "\033[0;31m$1\033[0m"
}

print_warn() {
    echo -e "\033[1;33m$1\033[0m"
}


# =====================================================
# VALIDACIONES GENERALES
# =====================================================

verificar_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script requiere privilegios root"
        exit 1
    fi
}

pausa() {
    read -p "Presiona Enter para continuar..."
}


# =====================================================
# VALIDACION IPv4
# =====================================================

validar_ip() {
    local ip=$1

    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"

    for o in $o1 $o2 $o3 $o4; do
        ((o>=0 && o<=255)) || return 1
    done

    [[ "$ip" == "0.0.0.0" ]] && return 1
    [[ "$ip" == "127.0.0.1" ]] && return 1
    [[ "$ip" == "255.255.255.255" ]] && return 1

    return 0
}


# =====================================================
# CONVERSIONES IP
# =====================================================

ip_a_entero() {
    IFS=. read -r o1 o2 o3 o4 <<< "$1"
    echo $((o1*256**3 + o2*256**2 + o3*256 + o4))
}

entero_a_ip() {
    local ip=$1
    echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"
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


# =====================================================
# RED Y RANGOS
# =====================================================

validar_rango_ip() {
    local start=$1
    local end=$2

    validar_ip "$start" || return 1
    validar_ip "$end" || return 1

    local s=$(ip_a_entero "$start")
    local e=$(ip_a_entero "$end")

    (( s < e )) || return 1
    return 0
}

detectar_interfaz_por_ip() {
    local ip=$1
    ip -o -4 addr show | grep "$ip" | awk '{print $2}' | head -n1
}

obtener_primera_interfaz() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1
}


# =====================================================
# SERVICIOS SYSTEMD
# =====================================================

servicio_activo() {
    systemctl is-active "$1" &>/dev/null
}

iniciar_servicio() {
    systemctl start "$1"
}

reiniciar_servicio() {
    systemctl restart "$1"
}

habilitar_servicio() {
    systemctl enable "$1" &>/dev/null
}


# =====================================================
# PAQUETES FEDORA (DNF)
# =====================================================

paquete_instalado() {
    rpm -q "$1" &>/dev/null
}

instalar_paquete() {
    dnf install -y "$1" &>/dev/null
}

reinstalar_paquete() {
    dnf reinstall -y "$1" &>/dev/null
}


# =====================================================
# FIREWALLD
# =====================================================

firewall_activo() {
    systemctl is-active firewalld &>/dev/null
}

abrir_puerto_firewall() {
    local puerto=$1
    firewall-cmd --permanent --add-port=${puerto}/tcp &>/dev/null
    firewall-cmd --reload &>/dev/null
}

abrir_servicio_firewall() {
    local servicio=$1
    firewall-cmd --permanent --add-service=$servicio &>/dev/null
    firewall-cmd --reload &>/dev/null
}


# =====================================================
# DIAGNOSTICO DEL SISTEMA (PRACTICA 1)
# =====================================================

get_hostname() {
    hostname
}

get_ipv4() {
    ip -4 addr show | awk '/inet / {print $2}' | cut -d/ -f1 | grep -v 127.0.0.1
}

get_disk_root() {
    df -h /
}