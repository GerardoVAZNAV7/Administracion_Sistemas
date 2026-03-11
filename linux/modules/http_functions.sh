#!/bin/bash

# ==========================================
# 1. UTILIDADES Y VALIDACIONES
# ==========================================
instalar_dependencias_base() {
    echo "Automatizando configuración de repositorios y dependencias..."
    
    # Inyectar repositorio de Bookworm (Debian 12 Estable) para garantizar que haya historial de versiones
    if ! grep -q "bookworm" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "Añadiendo repositorio 'bookworm' (Estable) para obtener el historial de versiones..."
        echo "deb http://deb.debian.org/debian bookworm main" >> /etc/apt/sources.list
    fi

    echo "Actualizando índices e instalando dependencias base (ufw, curl, net-tools, gawk)..."
    apt-get update -qq
    apt-get install -y -q ufw curl net-tools gawk
    apt-get install -y -qq iproute2 awk > /dev/null 2>&1
}

liberar_entorno() {
    echo "Iniciando limpieza profunda del entorno..."

    # 1. Asegurar que tenemos las herramientas necesarias (psmisc contiene fuser)
    if ! command -v fuser &> /dev/null; then
        echo "Instalando dependencias de limpieza (psmisc)..."
        apt-get install -y -qq psmisc > /dev/null 2>&1
    fi

    # 2. Detener servicios de forma estándar primero
    echo "Deteniendo servicios conocidos..."
    systemctl stop apache2 nginx tomcat10 tomcat9 2>/dev/null

    # 3. Limpieza DINÁMICA de puertos
    # Buscamos procesos que se llamen como nuestros servidores y los matamos con fuser
    echo "Liberando puertos ocupados por servidores web..."
    local procesos=("apache2" "nginx" "java" "httpd")
    for proc in "${procesos[@]}"; do
        # Buscamos los puertos que esos procesos tienen abiertos y los matamos
        # 'lsof -t -i' nos da los PIDs de cualquier cosa escuchando en red
        pids=$(pgrep -f $proc)
        if [ -n "$pids" ]; then
            kill -9 $pids 2>/dev/null
        fi
    done

    # 4. Desinstalar y limpiar rastros
    export DEBIAN_FRONTEND=noninteractive
    echo "Purgando paquetes y archivos de configuración..."
    apt-get purge -y apache2* nginx* tomcat* > /dev/null 2>&1
    apt-get autoremove -y -qq > /dev/null 2>&1
    
    # Limpiar directorios de raíz para evitar duplicados en el index
    rm -rf /var/www/html/*
    rm -rf /var/lib/tomcat10/webapps/ROOT/*

    echo "¡Entorno 100% liberado y limpio!"
}
# Función para validar puertos y mostrar por qué están reservados
solicitarPuerto() {
    local puerto
    # Diccionario para informar qué servicio vive en cada puerto bloqueado
    declare -A servicios=(
        [20]="FTP" [21]="FTP" [22]="SSH" [25]="SMTP" [53]="DNS" 
        [110]="POP3" [143]="IMAP" [445]="SMB/Samba" [2222]="Tu SSH actual"
        [3306]="MySQL/MariaDB" [5432]="PostgreSQL" [3389]="RDP"
    )

    # Lista de puertos RESERVADOS (Cosas que NO son servidores web y son críticos)
    # He quitado el 80, 81, 8080, 8888, etc. para que los puedas usar.
    local reservedPorts=(1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 43 53 69 77 79 110 111 113 115 117 118 119 123 135 137 139 143 161 177 179 389 427 445 465 512 513 514 515 526 530 531 532 540 548 554 556 563 587 601 636 989 990 993 995 1723 2049 2222 3306 3389 5432)

    while true; do
        read -p "Ingrese el puerto para el servicio (ej. 80, 8080, 81): " puerto
        
        # 1. Validar que sea un número
        if [[ ! "$puerto" =~ ^[0-9]+$ ]] || [ "$puerto" -le 0 ] || [ "$puerto" -gt 65535 ]; then
            echo "Error: Ingresa un número de puerto válido (1-65535)." >&2
            continue
        fi

        # 2. Validar contra puertos críticos de sistema (No Web)
        if [[ " ${reservedPorts[*]} " =~ " ${puerto} " ]]; then
            local desc=${servicios[$puerto]:-"Sistema Crítico"}
            echo "Error: El puerto $puerto está reservado para $desc. ¡No lo uses para HTTP!" >&2
            continue
        fi

        # 3. Verificar si el puerto ya está ocupado físicamente
        if ss -tuln | grep -q ":$puerto "; then
            echo "Error: El puerto $puerto ya está ocupado por un servicio en ejecución." >&2
            continue
        fi

        # Si llega aquí, el puerto es apto para un servidor web
        break
    done

    echo "$puerto"
}


seleccionar_version() {
    local paquete=$1
    # Obtenemos versiones, limpiamos duplicados y tomamos las 5 mejores
    mapfile -t versiones_crudas < <(apt-cache madison "$paquete" | awk '{print $3}' | sort -Vu | tail -n 5)
    
    if [ ${#versiones_crudas[@]} -eq 0 ]; then
        echo "No se encontraron versiones para $paquete." >&2
        return
    fi

    echo "Versiones encontradas para $paquete:" >&2
    
    local i=1
    for ver in "${versiones_crudas[@]}"; do
        if [[ "$ver" == *"deb12"* ]]; then
            echo "  $i) $ver  --> [LTS / Estable]" >&2
        elif [[ "$ver" == *"deb13"* ]]; then
            echo "  $i) $ver  --> [Latest / Desarrollo]" >&2
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
    echo "Configurando UFW para permitir el puerto $puerto..."
    ufw allow "$puerto"/tcp > /dev/null
    ufw --force enable > /dev/null
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
    
    echo "Instalando Apache2 ($version) en puerto $puerto..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq --allow-downgrades \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        apache2="$version" apache2-bin="$version" apache2-data="$version" apache2-utils="$version" > /dev/null 2>&1
    
    # 1. Crear directorio raíz exclusivo para este puerto
    local vhost_dir="/var/www/apache_$puerto"
    mkdir -p "$vhost_dir"

    # 2. Configurar el puerto en ports.conf
    echo "Listen $puerto" > /etc/apache2/ports.conf

    # 3. Configurar el Site para que use la nueva carpeta y el nuevo puerto
    cat <<EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:$puerto>
    ServerAdmin webmaster@localhost
    DocumentRoot $vhost_dir
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

    echo "Aplicando Hardening a Apache..."
    sed -i 's/ServerTokens OS/ServerTokens Prod/g' /etc/apache2/conf-available/security.conf
    sed -i 's/ServerSignature On/ServerSignature Off/g' /etc/apache2/conf-available/security.conf
    
    # 4. Crear el index personalizado en SU carpeta
    crear_index "$vhost_dir" "Apache2" "$version" "$puerto"
    
    chown -R www-data:www-data "$vhost_dir"
    chmod -R 755 "$vhost_dir"
    
    a2enmod headers > /dev/null 2>&1
    configurar_firewall "$puerto"
    systemctl restart apache2
    echo "Apache configurado en puerto $puerto (Ruta: $vhost_dir)"
}


instalar_nginx() {
    local version=$1
    local puerto=$2
    
    echo "Instalando Nginx de forma forzada y desatendida..."
    export DEBIAN_FRONTEND=noninteractive

    # Matamos cualquier proceso de nginx que haya quedado vivo para evitar bloqueos
    pkill -9 nginx 2>/dev/null

    # Instalamos sin preguntar nada y aceptando todo por defecto
    apt-get install -y -qq -f nginx > /dev/null 2>&1

    # Si por alguna razón el servicio no se creó, lo forzamos
    if [ ! -f "/lib/systemd/system/nginx.service" ]; then
        apt-get install -y --reinstall nginx-common nginx-full > /dev/null 2>&1
    fi

    # Configuración de carpetas
    local vhost_dir="/var/www/nginx_$puerto"
    mkdir -p "$vhost_dir"
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled

    # Escribir configuración mínima funcional
    cat <<EOF > /etc/nginx/sites-available/default
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

    # Enlace simbólico forzado
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

    # Crear el index
    crear_index "$vhost_dir" "Nginx" "$version" "$puerto"
    
    # Recarga total de servicios
    systemctl daemon-reload
    systemctl unmask nginx 2>/dev/null
    systemctl enable nginx 2>/dev/null
    systemctl restart nginx
    
    echo "Nginx configurado en puerto $puerto."
}
instalar_tomcat() {
    local version=$1
    local puerto=$2
    
    # Detectar si debemos usar tomcat10 (Debian moderno) o tomcat9 (viejo)
    local pkg="tomcat10"
    if ! apt-cache show tomcat10 > /dev/null 2>&1; then
        pkg="tomcat9"
    fi

    echo "Instalando $pkg ($version) de forma silenciosa y desatendida..."
    export DEBIAN_FRONTEND=noninteractive
    
    # Instalación forzada del paquete disponible
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $pkg > /dev/null 2>&1

    if [ ! -d "/etc/$pkg" ]; then
        echo "Error crítico: No se pudo instalar Tomcat. Verificando disponibilidad..." >&2
        return
    fi
    
    echo "Cambiando puerto a $puerto..."
    sed -i "s/port=\"8080\"/port=\"$puerto\"/g" /etc/$pkg/server.xml
    
    echo "Aplicando Hardening a Tomcat..."
    sed -i "s/port=\"$puerto\"/port=\"$puerto\" server=\"Apache Tomcat\"/g" /etc/$pkg/server.xml
    
    # Crear carpeta ROOT si no existe
    mkdir -p /var/lib/$pkg/webapps/ROOT
    crear_index "/var/lib/$pkg/webapps/ROOT" "Tomcat" "$version" "$puerto"
    
    # Ajuste de permisos con el usuario correcto según la versión
    chown -R $pkg:$pkg /var/lib/$pkg/webapps
    chmod -R 750 /var/lib/$pkg/webapps
    
    configurar_firewall "$puerto"
    systemctl restart $pkg
    echo "Tomcat configurado y asegurado exitosamente."
}