#!/bin/bash
# =====================================================
# DNS FUNCTIONS - FEDORA SERVER
# Requiere: core_utils.sh
# =====================================================

CONF="/etc/named.conf"
ZONE_DIR="/var/named"


# =====================================================
# ASEGURAR PERMISOS CORRECTOS PARA ZONAS
# =====================================================

# =====================================================
# ASEGURAR PERMISOS CORRECTOS PARA DNS (BIND)
# =====================================================

asegurar_permisos_dns() {
    verificar_root
    print_section "CONFIGURANDO PERMISOS Y SELINUX"

    # 1. Asegurar que el directorio de zonas existe
    mkdir -p "$ZONE_DIR"

    # 2. Permisos de Directorio: 770 permite que el grupo 'named' escriba (necesario para archivos .jnl y temporales)
    # Cambiamos recursivamente la propiedad al grupo 'named'
    chown -R root:named "$ZONE_DIR"
    chmod -R 770 "$ZONE_DIR"

    # 3. Permisos del archivo de configuración principal
    if [[ -f "$CONF" ]]; then
        chown root:named "$CONF"
        chmod 664 "$CONF"
    fi

    # 4. SELinux: Esto es vital en Fedora. 
    # 'named_conf_t' para el archivo de configuración
    # 'named_zone_t' para la carpeta de zonas y sus archivos
    print_info "Aplicando contextos de seguridad SELinux..."
    
    # Aseguramos que los archivos tengan el tipo correcto en la base de datos de SELinux
    semanage fcontext -a -t named_conf_t "$CONF" 2>/dev/null
    semanage fcontext -a -t named_zone_t "$ZONE_DIR(/.*)?" 2>/dev/null
    
    # Aplicamos los cambios al sistema de archivos
    restorecon -Rv "$CONF" &>/dev/null
    restorecon -Rv "$ZONE_DIR" &>/dev/null

    print_ok "Permisos y contextos SELinux actualizados"
}


# =====================================================
# INSTALAR BIND
# =====================================================

instalar_dns() {
    verificar_root
    print_section "INSTALACION DNS (BIND)"

    if paquete_instalado "bind"; then
        print_warn "BIND ya esta instalado"
    else
        instalar_paquete "bind bind-utils"
        print_ok "BIND instalado"
    fi

    # Permitir consultas externas
    sed -i 's/listen-on port 53 { 127.0.0.1; };/listen-on port 53 { any; };/' "$CONF"
    sed -i 's/allow-query.*;/allow-query { any; };/' "$CONF"

    # Firewall
    if systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-service=dns &>/dev/null
        firewall-cmd --reload &>/dev/null
    fi

    asegurar_permisos_dns
    habilitar_servicio "named"
    reiniciar_servicio "named"

    servicio_activo "named" && print_ok "Servidor DNS listo" || print_error "named no pudo iniciar"
}


# =====================================================
# VERIFICAR INSTALACION
# =====================================================

verificar_dns() {
    print_section "VERIFICACION DNS"

    paquete_instalado "bind" && print_ok "Paquete bind instalado" || {
        print_error "bind no instalado"
        return
    }

    servicio_activo "named" && print_ok "Servicio en ejecucion" || print_warn "Servicio detenido"
}


# =====================================================
# AGREGAR DOMINIO
# =====================================================

agregar_dominio_dns() {
    verificar_root
    asegurar_permisos_dns

    print_section "AGREGAR DOMINIO DNS"

    read -p "Dominio (ej: empresa.local): " ZONA
    [[ -z "$ZONA" ]] && return

    while true; do
        read -p "IP del servidor: " IP_CLIENTE
        validar_ip "$IP_CLIENTE" && break || print_error "IP invalida"
    done

    ARCHIVO_ZONA="$ZONE_DIR/${ZONA}.zone"
    SERIAL=$(date +%Y%m%d01)

    if grep -q "zone \"$ZONA\"" "$CONF"; then
        print_warn "El dominio ya existe"
        return
    fi

    cat >> "$CONF" <<EOF

zone "$ZONA" IN {
    type master;
    file "${ZONA}.zone";
    allow-update { none; };
};
EOF

    cat > "$ARCHIVO_ZONA" <<EOF
\$TTL 86400
@   IN  SOA ns1.$ZONA. admin.$ZONA. (
            $SERIAL
            3600
            1800
            604800
            86400 )
@       IN  NS      ns1.$ZONA.
ns1     IN  A       $IP_CLIENTE
@       IN  A       $IP_CLIENTE
www     IN  A       $IP_CLIENTE
EOF

    # Permisos automáticos
    chown root:named "$ARCHIVO_ZONA"
    chmod 640 "$ARCHIVO_ZONA"
    restorecon -v "$ARCHIVO_ZONA" &>/dev/null

    named-checkconf || { print_error "Error en named.conf"; return; }
    named-checkzone "$ZONA" "$ARCHIVO_ZONA" || { print_error "Error en zona"; return; }

    reiniciar_servicio "named"
    print_ok "Dominio agregado correctamente"
}


# =====================================================
# ELIMINAR DOMINIO
# =====================================================

eliminar_dominio_dns() {
    verificar_root
    print_section "ELIMINAR DOMINIO DNS"

    mapfile -t DOMINIOS < <(grep 'zone "' "$CONF" | awk '{print $2}' | tr -d '"' | grep -v '^\.$\|^0\.\|^1\.\|^2\.')

    [[ ${#DOMINIOS[@]} -eq 0 ]] && {
        print_warn "No hay dominios configurados"
        return
    }

    for i in "${!DOMINIOS[@]}"; do
        echo "$((i+1))) ${DOMINIOS[$i]}"
    done
    echo "0) Cancelar"

    read -p "Seleccione dominio: " SEL
    [[ "$SEL" == "0" ]] && return

    ZONA="${DOMINIOS[$((SEL-1))]}"
    ARCHIVO_ZONA="$ZONE_DIR/${ZONA}.zone"

    cp "$CONF" "${CONF}.bak"

    awk '
        /zone "'"$ZONA"'"/ { dentro=1; prof=0 }
        dentro {
            prof += gsub(/{/, "{")
            prof -= gsub(/}/, "}")
            if (prof <= 0) { dentro=0 }
            next
        }
        { print }
    ' "$CONF" > /tmp/named_tmp.conf && mv /tmp/named_tmp.conf "$CONF"

    rm -f "$ARCHIVO_ZONA"

    if named-checkconf &>/dev/null; then
        reiniciar_servicio "named"
        print_ok "Dominio eliminado correctamente"
    else
        cp "${CONF}.bak" "$CONF"
        reiniciar_servicio "named"
        print_error "Error en configuracion → restaurado respaldo"
    fi
}


# =====================================================
# LISTAR DOMINIOS
# =====================================================

listar_dominios_dns() {
    print_section "DOMINIOS CONFIGURADOS"
    grep 'zone "' "$CONF" | awk '{print $2}' | tr -d '"' | grep -v '^\.$\|^0\.\|^1\.\|^2\.'
}