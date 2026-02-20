#!/bin/bash

CONF="/etc/named.conf"
ZONE_DIR="/var/named"

# ─── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

validar_ip() {
    local ip=$1
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    [[ ! $ip =~ $regex ]] && return 1
    IFS='.' read -r -a octs <<< "$ip"
    for o in "${octs[@]}"; do
        [[ $o -lt 0 || $o -gt 255 ]] && return 1
    done
    return 0
}

opcion_verificar() {
    echo "__________________________________________"
    echo "Verificando instalacion DNS..."
    if rpm -q bind &>/dev/null; then
        echo -e "${GREEN}El paquete BIND esta instalado.${NC}"
        systemctl is-active named
        echo ""
        systemctl status named --no-pager | head -20
    else
        echo -e "${RED}BIND NO esta instalado.${NC}"
    fi
    read -p "Presiona Enter para continuar..."
}

opcion_instalar() {
    echo "__________________________________________"
    if ! rpm -q bind &>/dev/null; then
        echo "Instalando BIND, espera..."
        sudo yum install -y bind bind-utils &>/dev/null
        sudo systemctl enable named &>/dev/null
    else
        echo -e "${YELLOW}BIND ya estaba instalado.${NC}"
    fi

    # ── Configurar named.conf para aceptar consultas de la red ────────────────
    # Por defecto CentOS solo escucha en 127.0.0.1 y solo responde a localhost
    # Hay que cambiarlo para que los clientes puedan resolver
    echo "Configurando servidor para aceptar consultas externas..."

    # listen-on: escuchar en todas las interfaces
    sudo sed -i 's/listen-on port 53 { 127.0.0.1; };/listen-on port 53 { any; };/' "$CONF"

    # allow-query: permitir consultas desde cualquier host
    sudo sed -i 's/allow-query     { localhost; };/allow-query     { any; };/' "$CONF"

    sudo systemctl restart named &>/dev/null

    if systemctl is-active named &>/dev/null; then
        echo -e "${GREEN}Instalacion y configuracion completadas.${NC}"
    else
        echo -e "${RED}[ERROR] named no pudo iniciarse. Revisa: journalctl -xe${NC}"
    fi

    read -p "Presiona Enter para continuar..."
}

opcion_agregar() {
    echo "++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "         AGREGAR DOMINIO DNS"
    echo "++++++++++++++++++++++++++++++++++++++++++++++++++"

    read -p "Dominio (ej: reprobados.com): " ZONA
    if [[ -z "$ZONA" ]]; then
        echo -e "${RED}Dominio no puede estar vacio.${NC}"
        read -p "Enter para continuar..."
        return
    fi

    while true; do
        read -p "IP del servidor/cliente: " IP_CLIENTE
        if validar_ip "$IP_CLIENTE"; then
            break
        else
            echo -e "${RED}IP invalida, intenta de nuevo.${NC}"
        fi
    done

    ARCHIVO_ZONA="$ZONE_DIR/${ZONA}.zone"

    # Verificar si ya existe
    if grep -q "zone \"$ZONA\"" "$CONF"; then
        echo -e "${YELLOW}El dominio '$ZONA' ya existe.${NC}"
        read -p "Enter para continuar..."
        return
    fi

    # Obtener numero de serie basado en fecha actual
    SERIAL=$(date +%Y%m%d01)

    # ── Agregar zona a named.conf ──────────────────────────────────────────────
    sudo tee -a "$CONF" > /dev/null <<EOF

zone "$ZONA" IN {
    type master;
    file "${ZONA}.zone";
    allow-update { none; };
};
EOF

    # ── Crear archivo de zona ──────────────────────────────────────────────────
    # IMPORTANTE: usamos 'sudo tee' para que named pueda escribir correctamente
    sudo tee "$ARCHIVO_ZONA" > /dev/null <<EOF
\$TTL 86400
@   IN  SOA ns1.$ZONA. admin.$ZONA. (
            $SERIAL ; Serial
            3600    ; Refresh
            1800    ; Retry
            604800  ; Expire
            86400 ) ; Minimum TTL
;
@       IN  NS      ns1.$ZONA.
ns1     IN  A       $IP_CLIENTE
@       IN  A       $IP_CLIENTE
www     IN  A       $IP_CLIENTE
EOF

    # ── Permisos correctos para CentOS 7 con SELinux ──────────────────────────
    sudo chown root:named "$ARCHIVO_ZONA"
    sudo chmod 640 "$ARCHIVO_ZONA"

    # Restaurar contexto SELinux (crítico en CentOS 7)
    if command -v restorecon &>/dev/null; then
        sudo restorecon -v "$ARCHIVO_ZONA" &>/dev/null
    fi

    # ── Validar configuración antes de reiniciar ───────────────────────────────
    if ! sudo named-checkconf "$CONF" &>/dev/null; then
        echo -e "${RED}[ERROR] named.conf tiene errores. Revisa la configuracion.${NC}"
        read -p "Enter para continuar..."
        return
    fi

    if ! sudo named-checkzone "$ZONA" "$ARCHIVO_ZONA" &>/dev/null; then
        echo -e "${RED}[ERROR] El archivo de zona tiene errores.${NC}"
        read -p "Enter para continuar..."
        return
    fi

    sudo systemctl restart named
    if systemctl is-active named &>/dev/null; then
        echo -e "${GREEN}Dominio '$ZONA' agregado correctamente.${NC}"
    else
        echo -e "${RED}[ERROR] named no pudo reiniciarse. Revisa: journalctl -xe${NC}"
    fi

    read -p "Presiona Enter para continuar..."
}

opcion_borrar() {
    echo "__________________________________________"

    # ── Obtener lista de dominios personalizados ───────────────────────────────
    mapfile -t DOMINIOS < <(grep 'zone "' "$CONF" | awk '{print $2}' | tr -d '"' | grep -v '^\.$\|^0\.\|^1\.\|^2\.')

    if [[ ${#DOMINIOS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No hay dominios configurados para eliminar.${NC}"
        read -p "Enter para continuar..."
        return
    fi

    echo "Dominios configurados:"
    echo ""
    for i in "${!DOMINIOS[@]}"; do
        echo "  $((i+1))) ${DOMINIOS[$i]}"
    done
    echo "  0) Cancelar"
    echo ""

    while true; do
        read -p "Selecciona el numero del dominio a borrar: " SEL
        if [[ "$SEL" == "0" ]]; then
            echo "Operacion cancelada."
            read -p "Enter para continuar..."
            return
        fi
        if [[ "$SEL" =~ ^[0-9]+$ ]] && [[ "$SEL" -ge 1 ]] && [[ "$SEL" -le ${#DOMINIOS[@]} ]]; then
            break
        else
            echo -e "${RED}Opcion invalida, elige un numero entre 1 y ${#DOMINIOS[@]}.${NC}"
        fi
    done

    ZONA="${DOMINIOS[$((SEL-1))]}"
    ARCHIVO_ZONA="$ZONE_DIR/${ZONA}.zone"

    echo ""
    echo -e "Vas a eliminar el dominio: ${YELLOW}$ZONA${NC}"
    read -p "Confirmas? (s/n): " CONFIRM
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo "Operacion cancelada."
        read -p "Enter para continuar..."
        return
    fi

    # ── Backup antes de modificar ──────────────────────────────────────────────
    sudo cp "$CONF" "${CONF}.bak"

    # ── Eliminar bloque de zona con awk (sin necesitar Python) ───────────────
    sudo awk '
        /zone "'"$ZONA"'"/ { dentro=1; prof=0 }
        dentro {
            prof += gsub(/{/, "{")
            prof -= gsub(/}/, "}")
            if (prof <= 0) { dentro=0 }
            next
        }
        { print }
    ' "$CONF" > /tmp/named_tmp.conf && sudo mv /tmp/named_tmp.conf "$CONF"

    # ── Eliminar archivo de zona ───────────────────────────────────────────────
    if [[ -f "$ARCHIVO_ZONA" ]]; then
        sudo rm -f "$ARCHIVO_ZONA"
        echo "Archivo de zona eliminado: $ARCHIVO_ZONA"
    fi

    # ── Verificar y reiniciar ──────────────────────────────────────────────────
    if sudo named-checkconf "$CONF" &>/dev/null; then
        sudo systemctl restart named
        if systemctl is-active named &>/dev/null; then
            echo -e "${GREEN}Dominio '$ZONA' eliminado correctamente.${NC}"
        else
            echo -e "${RED}[ERROR] named no reinicio. Revisa: journalctl -xe${NC}"
        fi
    else
        echo -e "${RED}[ERROR] named.conf tiene errores. Restaurando respaldo...${NC}"
        sudo cp "${CONF}.bak" "$CONF"
        sudo systemctl restart named
        sudo named-checkconf "$CONF"
    fi

    read -p "Presiona Enter para continuar..."
}

opcion_ver() {
    echo "__________________________________________"
    echo "DOMINIOS CONFIGURADOS EN named.conf:"
    echo ""
    # Mostrar solo zonas que NO son las internas de BIND
    grep 'zone "' "$CONF" | awk '{print $2}' | tr -d '"' | grep -v '^\.$\|^0\.\|^1\.\|^2\.'
    echo ""
    read -p "Presiona Enter para continuar..."
}

# ─── Menú principal ────────────────────────────────────────────────────────────
while true; do
    echo -e "\n++++++++++++++++++++++++++++++++++"
    echo "         SISTEMA DNS - CentOS 7"
    echo "++++++++++++++++++++++++++++++++++"
    echo "1) Verificar instalacion DNS"
    echo "2) Instalar DNS"
    echo "3) Agregar dominio"
    echo "4) Borrar dominio"
    echo "5) Ver dominios"
    echo "6) Salir"
    echo "__________________________________________"
    read -p "Selecciona una opcion: " OPT

    case $OPT in
        1) opcion_verificar ;;
        2) opcion_instalar ;;
        3) opcion_agregar ;;
        4) opcion_borrar ;;
        5) opcion_ver ;;
        6) exit 0 ;;
        *) echo -e "${RED}Opcion invalida.${NC}" ;;
    esac
done