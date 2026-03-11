#!/bin/bash

# ==========================================
# 1. UTILIDADES Y VALIDACIONES
# ==========================================
instalar_dependencias_base() {
    echo "Automatizando configuración de repositorios y dependencias..."

    echo "Actualizando índices e instalando dependencias base (firewalld, curl, net-tools, gawk)..."
    dnf install -y -q firewalld curl net-tools gawk iproute 2>/dev/null

    # Activar firewalld si no está corriendo (equivalente a ufw en Debian)
    systemctl enable firewalld --now &>/dev/null
}

liberar_entorno() {
    echo "Iniciando limpieza profunda del entorno..."

    # 1. Detener servicios
    echo "Deteniendo servicios conocidos..."
    systemctl stop httpd nginx tomcat 2>/dev/null
    systemctl disable httpd nginx tomcat 2>/dev/null

    # 2. Matar procesos residuales
    echo "Liberando puertos ocupados por servidores web..."
    local procesos=("httpd" "nginx" "java")
    for proc in "${procesos[@]}"; do
        pids=$(pgrep -f $proc)
        if [ -n "$pids" ]; then
            kill -9 $pids 2>/dev/null
        fi
    done

    # 3. Desinstalar y limpiar rastros
    echo "Eliminando paquetes y archivos de configuración..."
    dnf remove -y httpd nginx tomcat 2>/dev/null
    dnf autoremove -y -q 2>/dev/null

    # Limpiar directorios de raíz
    rm -rf /var/www/apache_*
    rm -rf /var/www/nginx_*
    rm -rf /var/lib/tomcat/webapps/ROOT/*

    # Limpiar reglas de firewall agregadas por el script
    for port in $(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n'); do
        firewall-cmd --permanent --remove-port="$port" 2>/dev/null
    done
    firewall-cmd --reload 2>/dev/null

    echo "¡Entorno 100% liberado y limpio!"
}

solicitarPuerto() {
    local puerto
    declare -A servicios=(
        [20]="FTP" [21]="FTP" [22]="SSH" [25]="SMTP" [53]="DNS"
        [110]="POP3" [143]="IMAP" [445]="SMB/Samba" [2222]="Tu SSH actual"
        [3306]="MySQL/MariaDB" [5432]="PostgreSQL" [3389]="RDP"
    )

    local reservedPorts=(1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 43 53 69 77 79 110 111 113 115 117 118 119 123 135 137 139 143 161 177 179 389 427 445 465 512 513 514 515 526 530 531 532 540 548 554 556 563 587 601 636 989 990 993 995 1723 2049 2222 3306 3389 5432)

    while true; do
        read -p "Ingrese el puerto para el servicio (ej. 80, 8080, 81): " puerto

        if [[ ! "$puerto" =~ ^[0-9]+$ ]] || [ "$puerto" -le 0 ] || [ "$puerto" -gt 65535 ]; then
            echo "Error: Ingresa un número de puerto válido (1-65535)." >&2
            continue
        fi

        if [[ " ${reservedPorts[*]} " =~ " ${puerto} " ]]; then
            local desc=${servicios[$puerto]:-"Sistema Crítico"}
            echo "Error: El puerto $puerto está reservado para $desc. ¡No lo uses para HTTP!" >&2
            continue
        fi

        if ss -tuln | grep -q ":$puerto "; then
            echo "Error: El puerto $puerto ya está ocupado por un servicio en ejecución." >&2
            continue
        fi

        break
    done

    echo "$puerto"
}

seleccionar_version() {
    local paquete=$1

    # Mapear nombres Debian -> Fedora
    case "$paquete" in
        apache2)  paquete="httpd"  ;;
        nginx)    paquete="nginx"  ;;
        tomcat10) paquete="tomcat" ;;
    esac

    # dnf repoquery reemplaza a apt-cache madison en Fedora
    mapfile -t versiones_crudas < <(dnf repoquery --available --queryformat '%{version}-%{release}' "$paquete" 2>/dev/null | sort -Vu | tail -n 5)

    if [ ${#versiones_crudas[@]} -eq 0 ]; then
        echo "No se encontraron versiones para $paquete." >&2
        echo "latest"
        return
    fi

    echo "Versiones encontradas para $paquete:" >&2

    local i=1
    for ver in "${versiones_crudas[@]}"; do
        if [[ "$ver" == *"fc42"* ]]; then
            echo "  $i) $ver  --> [Fedora 42 / Estable]" >&2
        elif [[ "$ver" == *"fc41"* ]]; then
            echo "  $i) $ver  --> [Fedora 41 / Legado]" >&2
        else
            echo "  $i) $ver  --> [Versión Repositorio]" >&2
        fi
        ((i++))
    done

    while true; do
        read -p "Selecciona el número de versión (1-${#versiones_crudas[@]}): " seleccion
        if [[ "$seleccion" =~ ^[0-9]+$ ]] && [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "${#versiones_crudas[@]}" ]; then
            local index=$((seleccion - 1))
            echo "${versiones_crudas[$index]}"
            break
        else
            echo "Error: Selección inválida." >&2
        fi
    done
}

configurar_firewall() {
    local puerto=$1
    echo "Configurando firewalld para permitir el puerto $puerto..."
    # Fedora usa firewalld en lugar de ufw
    firewall-cmd --permanent --add-port="${puerto}/tcp" > /dev/null
    firewall-cmd --reload > /dev/null
}

crear_index() {
    local ruta=$1
    local servicio=$2
    local version=$3
    local puerto=$4
    echo "<h1>Servidor: $servicio - Version: $version - Puerto: $puerto</h1>" > "$ruta/index.html"
}

# ==========================================
# 2. FUNCIONES DE INSTALACIÓN Y HARDENING
# ==========================================

instalar_apache() {
    local version=$1
    local puerto=$2

    echo "Instalando Apache (httpd) ($version) en puerto $puerto..."

    # Fedora: paquete httpd, instalación con dnf
    dnf install -y -q httpd > /dev/null 2>&1

    # 1. Directorio raíz exclusivo por puerto
    local vhost_dir="/var/www/apache_$puerto"
    mkdir -p "$vhost_dir"

    # 2. En Fedora no existe sites-available — los vhosts van en /etc/httpd/conf.d/
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

    # 3. Hardening — en Fedora va en /etc/httpd/conf/httpd.conf (no existe security.conf)
    echo "Aplicando Hardening a Apache..."
    if grep -q "^ServerTokens" /etc/httpd/conf/httpd.conf; then
        sed -i 's/^ServerTokens .*/ServerTokens Prod/' /etc/httpd/conf/httpd.conf
    else
        echo "ServerTokens Prod" >> /etc/httpd/conf/httpd.conf
    fi
    if grep -q "^ServerSignature" /etc/httpd/conf/httpd.conf; then
        sed -i 's/^ServerSignature .*/ServerSignature Off/' /etc/httpd/conf/httpd.conf
    else
        echo "ServerSignature Off" >> /etc/httpd/conf/httpd.conf
    fi

    # 4. Index personalizado
    crear_index "$vhost_dir" "Apache/httpd" "$version" "$puerto"

    # Fedora usa 'apache' como usuario del proceso, no 'www-data'
    chown -R apache:apache "$vhost_dir"
    chmod -R 755 "$vhost_dir"

    # SELinux: etiquetar el directorio (Fedora trae SELinux en Enforcing por defecto)
    chcon -R -t httpd_sys_content_t "$vhost_dir" 2>/dev/null

    # Fedora no tiene a2enmod — headers ya viene cargado en httpd por defecto
    configurar_firewall "$puerto"
    systemctl enable httpd --now
    systemctl restart httpd
    echo "Apache configurado en puerto $puerto (Ruta: $vhost_dir)"
}

instalar_nginx() {
    local version=$1
    local puerto=$2

    echo "Instalando Nginx en puerto $puerto..."
    pkill -9 nginx 2>/dev/null

    dnf install -y -q nginx > /dev/null 2>&1

    # Fedora: el unit está en /usr/lib/systemd/system/, no /lib/systemd/system/
    if [ ! -f "/usr/lib/systemd/system/nginx.service" ]; then
        dnf reinstall -y -q nginx > /dev/null 2>&1
    fi

    local vhost_dir="/var/www/nginx_$puerto"
    mkdir -p "$vhost_dir"

    # Fedora usa /etc/nginx/conf.d/ — no existe sites-available/sites-enabled
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

    # SELinux
    chcon -R -t httpd_sys_content_t "$vhost_dir" 2>/dev/null
    # Registrar puerto no estándar en SELinux
    if [ "$puerto" != "80" ] && [ "$puerto" != "443" ]; then
        semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null \
            || semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
    fi

    configurar_firewall "$puerto"
    systemctl daemon-reload
    systemctl enable nginx --now
    systemctl restart nginx
    echo "Nginx configurado en puerto $puerto (Ruta: $vhost_dir)"
}

instalar_tomcat() {
    local version=$1
    local puerto=$2

    # Fedora 42: el paquete se llama 'tomcat', no tomcat10/tomcat9
    local pkg="tomcat"

    echo "Instalando $pkg ($version) en puerto $puerto..."
    dnf install -y -q java-17-openjdk "$pkg" > /dev/null 2>&1

    # En Fedora la config de tomcat está en /etc/tomcat/ igual que en Debian
    if [ ! -d "/etc/tomcat" ]; then
        echo "Error crítico: No se pudo instalar Tomcat." >&2
        return 1
    fi

    echo "Cambiando puerto a $puerto..."
    sed -i "s/port=\"8080\"/port=\"$puerto\"/g" /etc/tomcat/server.xml

    echo "Aplicando Hardening a Tomcat..."
    sed -i "s/port=\"$puerto\"/port=\"$puerto\" server=\"Apache Tomcat\"/g" /etc/tomcat/server.xml

    # En Fedora los webapps están en /var/lib/tomcat/webapps (sin número de versión)
    mkdir -p /var/lib/tomcat/webapps/ROOT
    crear_index "/var/lib/tomcat/webapps/ROOT" "Tomcat" "$version" "$puerto"

    chown -R tomcat:tomcat /var/lib/tomcat/webapps
    chmod -R 750 /var/lib/tomcat/webapps

    # SELinux
    chcon -R -t tomcat_var_lib_t /var/lib/tomcat/webapps 2>/dev/null

    configurar_firewall "$puerto"
    systemctl enable tomcat --now
    systemctl restart tomcat
    echo "Tomcat configurado y asegurado exitosamente en puerto $puerto."
}