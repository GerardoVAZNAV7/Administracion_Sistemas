#!/bin/bash

# ==========================================
# 1. UTILIDADES Y VALIDACIONES
# ==========================================

instalar_dependencias_base() {
    echo "Instalando dependencias base..."
    dnf install -y -q firewalld curl net-tools gawk iproute policycoreutils-python-utils 2>/dev/null
    systemctl enable firewalld --now &>/dev/null
}

liberar_entorno() {
    echo "Iniciando limpieza profunda del entorno..."

    systemctl stop httpd nginx tomcat 2>/dev/null
    systemctl disable httpd nginx tomcat 2>/dev/null

    for proc in httpd nginx java; do
        pids=$(pgrep -f "$proc")
        [ -n "$pids" ] && kill -9 $pids 2>/dev/null
    done

    dnf remove -y httpd nginx tomcat 2>/dev/null
    dnf autoremove -y -q 2>/dev/null

    # FIX: limpiar vhosts residuales
    rm -f /etc/httpd/conf.d/vhost_*.conf
    rm -f /etc/nginx/conf.d/vhost_*.conf
    rm -rf /var/www/apache_*
    rm -rf /var/www/nginx_*
    rm -rf /var/lib/tomcat/webapps/ROOT/*

    # FIX: limpiar puertos SELinux registrados para nginx (no-estandar)
    for port in $(semanage port -l 2>/dev/null | grep http_port_t | grep -oP '\b[0-9]{4,5}\b' | grep -v '^80$\|^443$\|^8080$\|^8443$'); do
        semanage port -d -t http_port_t -p tcp "$port" 2>/dev/null
    done

    # Limpiar reglas de firewall agregadas
    for port in $(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n'); do
        firewall-cmd --permanent --remove-port="$port" 2>/dev/null
    done
    firewall-cmd --reload 2>/dev/null

    echo "Entorno liberado y limpio."
}

# FIX: usar variable global en lugar de subshell $() para evitar
# que el prompt y los mensajes se mezclen con el valor retornado.
solicitarPuerto() {
    declare -A servicios=(
        [20]="FTP" [21]="FTP" [22]="SSH" [25]="SMTP" [53]="DNS"
        [110]="POP3" [143]="IMAP" [445]="SMB/Samba" [2222]="SSH alternativo"
        [3306]="MySQL/MariaDB" [5432]="PostgreSQL" [3389]="RDP"
    )
    local reservedPorts=(1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 43 53 69
        77 79 110 111 113 115 117 118 119 123 135 137 139 143 161 177 179 389
        427 445 465 512 513 514 515 526 530 531 532 540 548 554 556 563 587
        601 636 989 990 993 995 1723 2049 2222 3306 3389 5432)

    while true; do
        read -p "Ingrese el puerto para el servicio (ej. 8080, 8081): " PUERTO_ELEGIDO

        if [[ ! "$PUERTO_ELEGIDO" =~ ^[0-9]+$ ]] || \
           [ "$PUERTO_ELEGIDO" -le 0 ] || [ "$PUERTO_ELEGIDO" -gt 65535 ]; then
            echo "  [!] Puerto invalido. Rango permitido: 1-65535." >&2
            continue
        fi

        if [[ " ${reservedPorts[*]} " =~ " ${PUERTO_ELEGIDO} " ]]; then
            local desc=${servicios[$PUERTO_ELEGIDO]:-"Sistema Critico"}
            echo "  [!] Puerto $PUERTO_ELEGIDO reservado para $desc." >&2
            continue
        fi

        if ss -tuln 2>/dev/null | grep -q ":${PUERTO_ELEGIDO} "; then
            echo "  [!] Puerto $PUERTO_ELEGIDO ya esta en uso." >&2
            continue
        fi

        break
    done
    # PUERTO_ELEGIDO queda disponible en el scope del llamador (global en bash)
}

# FIX: usar variable global VERSION_ELEGIDA en lugar de subshell $()
seleccionar_version() {
    local paquete=$1
    case "$paquete" in
        apache2)  paquete="httpd"  ;;
        nginx)    paquete="nginx"  ;;
        tomcat10) paquete="tomcat" ;;
    esac

    mapfile -t versiones_crudas < <(
        dnf repoquery --available --queryformat '%{version}-%{release}' "$paquete" \
            2>/dev/null | sort -Vu | tail -n 5
    )

    if [ ${#versiones_crudas[@]} -eq 0 ]; then
        echo "  [!] No se encontraron versiones para $paquete. Usando 'latest'."
        VERSION_ELEGIDA="latest"
        return
    fi

    echo "Versiones disponibles para $paquete:"
    local i=1
    for ver in "${versiones_crudas[@]}"; do
        if   [[ "$ver" == *"fc42"* ]]; then echo "  $i) $ver  [Fedora 42 / Actual]"
        elif [[ "$ver" == *"fc41"* ]]; then echo "  $i) $ver  [Fedora 41 / Legado]"
        else                                echo "  $i) $ver  [Repositorio]"
        fi
        ((i++))
    done

    while true; do
        read -p "Selecciona el numero de version (1-${#versiones_crudas[@]}): " seleccion
        if [[ "$seleccion" =~ ^[0-9]+$ ]] && \
           [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "${#versiones_crudas[@]}" ]; then
            VERSION_ELEGIDA="${versiones_crudas[$((seleccion - 1))]}"
            break
        fi
        echo "  [!] Seleccion invalida."
    done
}

configurar_firewall() {
    local puerto=$1
    echo "  Abriendo puerto $puerto en firewalld..."
    firewall-cmd --permanent --add-port="${puerto}/tcp" &>/dev/null
    firewall-cmd --reload &>/dev/null
}

crear_index() {
    local ruta=$1 servicio=$2 version=$3 puerto=$4
    cat > "$ruta/index.html" << HTML
<!DOCTYPE html>
<html>
<head><title>$servicio</title></head>
<body>
<h1>Servidor: $servicio</h1>
<p>Version: $version</p>
<p>Puerto: $puerto</p>
<p>IP: $(ip -4 addr show enp0s9 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)</p>
</body>
</html>
HTML
}

# ==========================================
# 2. INSTALACION Y HARDENING
# ==========================================

instalar_apache() {
    local version=$1
    local puerto=$2

    echo "Instalando Apache (httpd) en puerto $puerto..."
    dnf install -y -q httpd &>/dev/null

    local vhost_dir="/var/www/apache_$puerto"
    mkdir -p "$vhost_dir"

    # FIX: deshabilitar el VirtualHost default que escucha en 80
    # para evitar conflictos con puertos personalizados
    if [ -f /etc/httpd/conf.d/welcome.conf ]; then
        mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf.disabled
    fi
    # Comentar el Listen 80 del conf principal si el puerto elegido no es 80
    if [ "$puerto" != "80" ]; then
        sed -i 's/^Listen 80$/#Listen 80 (disabled by script)/' /etc/httpd/conf/httpd.conf
    fi

    cat > /etc/httpd/conf.d/vhost_${puerto}.conf << EOF
Listen $puerto

<VirtualHost *:$puerto>
    ServerAdmin webmaster@localhost
    DocumentRoot $vhost_dir
    ErrorLog /var/log/httpd/error_${puerto}.log
    CustomLog /var/log/httpd/access_${puerto}.log combined
    <Directory "$vhost_dir">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF

    # Hardening
    grep -q "^ServerTokens" /etc/httpd/conf/httpd.conf \
        && sed -i 's/^ServerTokens .*/ServerTokens Prod/' /etc/httpd/conf/httpd.conf \
        || echo "ServerTokens Prod" >> /etc/httpd/conf/httpd.conf

    grep -q "^ServerSignature" /etc/httpd/conf/httpd.conf \
        && sed -i 's/^ServerSignature .*/ServerSignature Off/' /etc/httpd/conf/httpd.conf \
        || echo "ServerSignature Off" >> /etc/httpd/conf/httpd.conf

    crear_index "$vhost_dir" "Apache/httpd" "$version" "$puerto"
    chown -R apache:apache "$vhost_dir"
    chmod -R 755 "$vhost_dir"
    chcon -R -t httpd_sys_content_t "$vhost_dir" 2>/dev/null

    # SELinux: permitir el puerto si no es estandar
    if [ "$puerto" != "80" ] && [ "$puerto" != "443" ]; then
        semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null \
            || semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
    fi

    configurar_firewall "$puerto"
    systemctl enable httpd --now &>/dev/null
    systemctl restart httpd

    if systemctl is-active --quiet httpd; then
        echo "  [OK] Apache activo en http://192.168.56.101:$puerto"
    else
        echo "  [!] Apache no inicio. Revisa: journalctl -u httpd -n 20"
    fi
}

instalar_nginx() {
    local version=$1
    local puerto=$2

    echo "Instalando Nginx en puerto $puerto..."
    pkill -9 nginx 2>/dev/null
    dnf install -y -q nginx &>/dev/null

    local vhost_dir="/var/www/nginx_$puerto"
    mkdir -p "$vhost_dir"

    # FIX: renombrar default.conf para evitar conflicto con puerto 80
    if [ -f /etc/nginx/conf.d/default.conf ]; then
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
    fi

    cat > /etc/nginx/conf.d/vhost_${puerto}.conf << EOF
server {
    listen $puerto;
    root $vhost_dir;
    index index.html;
    server_name _;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    crear_index "$vhost_dir" "Nginx" "$version" "$puerto"
    chcon -R -t httpd_sys_content_t "$vhost_dir" 2>/dev/null

    if [ "$puerto" != "80" ] && [ "$puerto" != "443" ]; then
        semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null \
            || semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
    fi

    configurar_firewall "$puerto"
    systemctl daemon-reload
    systemctl enable nginx --now &>/dev/null
    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        echo "  [OK] Nginx activo en http://192.168.56.101:$puerto"
    else
        echo "  [!] Nginx no inicio. Revisa: journalctl -u nginx -n 20"
    fi
}

instalar_tomcat() {
    local version=$1
    local puerto=$2

    echo "Instalando Tomcat en puerto $puerto..."
    dnf install -y -q java-17-openjdk tomcat &>/dev/null

    if [ ! -d "/etc/tomcat" ]; then
        echo "  [!] Error: Tomcat no se instalo correctamente."
        return 1
    fi

    # FIX: hacer ambos sed en un solo paso para evitar que el patron cambie
    # entre el primer y segundo sed
    sed -i "s/port=\"8080\"/port=\"$puerto\" server=\"Apache Tomcat\"/" /etc/tomcat/server.xml

    mkdir -p /var/lib/tomcat/webapps/ROOT
    crear_index "/var/lib/tomcat/webapps/ROOT" "Tomcat" "$version" "$puerto"
    chown -R tomcat:tomcat /var/lib/tomcat/webapps
    chmod -R 750 /var/lib/tomcat/webapps
    chcon -R -t tomcat_var_lib_t /var/lib/tomcat/webapps 2>/dev/null

    configurar_firewall "$puerto"
    systemctl enable tomcat --now &>/dev/null
    systemctl restart tomcat

    if systemctl is-active --quiet tomcat; then
        echo "  [OK] Tomcat activo en http://192.168.56.101:$puerto"
    else
        echo "  [!] Tomcat no inicio. Revisa: journalctl -u tomcat -n 20"
    fi
}