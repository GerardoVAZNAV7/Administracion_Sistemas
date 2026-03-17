# #!/bin/bash

# # ==========================================
# # 1. UTILIDADES Y VALIDACIONES
# # ==========================================

# instalar_dependencias_base() {
#     echo "Instalando dependencias base..."
#     dnf install -y -q firewalld curl net-tools gawk iproute policycoreutils-python-utils 2>/dev/null
#     systemctl enable firewalld --now &>/dev/null
# }

# liberar_entorno() {
#     echo "Iniciando limpieza profunda del entorno..."

#     systemctl stop httpd nginx tomcat 2>/dev/null
#     systemctl disable httpd nginx tomcat 2>/dev/null

#     for proc in httpd nginx java; do
#         pids=$(pgrep -f "$proc")
#         [ -n "$pids" ] && kill -9 $pids 2>/dev/null
#     done

#     dnf remove -y httpd nginx tomcat 2>/dev/null
#     dnf autoremove -y -q 2>/dev/null

#     # FIX: limpiar vhosts residuales
#     rm -f /etc/httpd/conf.d/vhost_*.conf
#     rm -f /etc/nginx/conf.d/vhost_*.conf
#     rm -rf /var/www/apache_*
#     rm -rf /var/www/nginx_*
#     rm -rf /var/lib/tomcat/webapps/ROOT/*

#     # FIX: limpiar puertos SELinux registrados para nginx (no-estandar)
#     for port in $(semanage port -l 2>/dev/null | grep http_port_t | grep -oP '\b[0-9]{4,5}\b' | grep -v '^80$\|^443$\|^8080$\|^8443$'); do
#         semanage port -d -t http_port_t -p tcp "$port" 2>/dev/null
#     done

#     # Limpiar reglas de firewall agregadas
#     for port in $(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n'); do
#         firewall-cmd --permanent --remove-port="$port" 2>/dev/null
#     done
#     firewall-cmd --reload 2>/dev/null

#     echo "Entorno liberado y limpio."
# }

# # FIX: usar variable global en lugar de subshell $() para evitar
# # que el prompt y los mensajes se mezclen con el valor retornado.
# solicitarPuerto() {
#     declare -A servicios=(
#         [20]="FTP" [21]="FTP" [22]="SSH" [25]="SMTP" [53]="DNS"
#         [110]="POP3" [143]="IMAP" [445]="SMB/Samba" [2222]="SSH alternativo"
#         [3306]="MySQL/MariaDB" [5432]="PostgreSQL" [3389]="RDP"
#     )
#     local reservedPorts=(1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 43 53 69
#         77 79 110 111 113 115 117 118 119 123 135 137 139 143 161 177 179 389
#         427 445 465 512 513 514 515 526 530 531 532 540 548 554 556 563 587
#         601 636 989 990 993 995 1723 2049 2222 3306 3389 5432)

#     while true; do
#         read -p "Ingrese el puerto para el servicio (ej. 8080, 8081): " PUERTO_ELEGIDO

#         if [[ ! "$PUERTO_ELEGIDO" =~ ^[0-9]+$ ]] || \
#            [ "$PUERTO_ELEGIDO" -le 0 ] || [ "$PUERTO_ELEGIDO" -gt 65535 ]; then
#             echo "  [!] Puerto invalido. Rango permitido: 1-65535." >&2
#             continue
#         fi

#         if [[ " ${reservedPorts[*]} " =~ " ${PUERTO_ELEGIDO} " ]]; then
#             local desc=${servicios[$PUERTO_ELEGIDO]:-"Sistema Critico"}
#             echo "  [!] Puerto $PUERTO_ELEGIDO reservado para $desc." >&2
#             continue
#         fi

#         if ss -tuln 2>/dev/null | grep -q ":${PUERTO_ELEGIDO} "; then
#             echo "  [!] Puerto $PUERTO_ELEGIDO ya esta en uso." >&2
#             continue
#         fi

#         break
#     done
#     # PUERTO_ELEGIDO queda disponible en el scope del llamador (global en bash)
# }

# # FIX: usar variable global VERSION_ELEGIDA en lugar de subshell $()
# seleccionar_version() {
#     local paquete=$1
#     case "$paquete" in
#         apache2)  paquete="httpd"  ;;
#         nginx)    paquete="nginx"  ;;
#         tomcat10) paquete="tomcat" ;;
#     esac

#     mapfile -t versiones_crudas < <(
#         dnf repoquery --available --queryformat '%{version}-%{release}' "$paquete" \
#             2>/dev/null | sort -Vu | tail -n 5
#     )

#     if [ ${#versiones_crudas[@]} -eq 0 ]; then
#         echo "  [!] No se encontraron versiones para $paquete. Usando 'latest'."
#         VERSION_ELEGIDA="latest"
#         return
#     fi

#     echo "Versiones disponibles para $paquete:"
#     local i=1
#     for ver in "${versiones_crudas[@]}"; do
#         if   [[ "$ver" == *"fc42"* ]]; then echo "  $i) $ver  [Fedora 42 / Actual]"
#         elif [[ "$ver" == *"fc41"* ]]; then echo "  $i) $ver  [Fedora 41 / Legado]"
#         else                                echo "  $i) $ver  [Repositorio]"
#         fi
#         ((i++))
#     done

#     while true; do
#         read -p "Selecciona el numero de version (1-${#versiones_crudas[@]}): " seleccion
#         if [[ "$seleccion" =~ ^[0-9]+$ ]] && \
#            [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "${#versiones_crudas[@]}" ]; then
#             VERSION_ELEGIDA="${versiones_crudas[$((seleccion - 1))]}"
#             break
#         fi
#         echo "  [!] Seleccion invalida."
#     done
# }

# configurar_firewall() {
#     local puerto=$1
#     echo "  Abriendo puerto $puerto en firewalld..."
#     firewall-cmd --permanent --add-port="${puerto}/tcp" &>/dev/null
#     firewall-cmd --reload &>/dev/null
# }

# crear_index() {
#     local ruta=$1 servicio=$2 version=$3 puerto=$4
#     cat > "$ruta/index.html" << HTML
# <!DOCTYPE html>
# <html>
# <head><title>$servicio</title></head>
# <body>
# <h1>Servidor: $servicio</h1>
# <p>Version: $version</p>
# <p>Puerto: $puerto</p>
# <p>IP: $(ip -4 addr show enp0s9 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)</p>
# </body>
# </html>
# HTML
# }

# # ==========================================
# # 2. INSTALACION Y HARDENING
# # ==========================================

# instalar_apache() {
#     local version=$1
#     local puerto=$2

#     echo "Instalando Apache (httpd) en puerto $puerto..."
#     dnf install -y -q httpd &>/dev/null

#     local vhost_dir="/var/www/apache_$puerto"
#     mkdir -p "$vhost_dir"

#     # FIX: deshabilitar el VirtualHost default que escucha en 80
#     # para evitar conflictos con puertos personalizados
#     if [ -f /etc/httpd/conf.d/welcome.conf ]; then
#         mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf.disabled
#     fi
#     # Comentar el Listen 80 del conf principal si el puerto elegido no es 80
#     if [ "$puerto" != "80" ]; then
#         sed -i 's/^Listen 80$/#Listen 80 (disabled by script)/' /etc/httpd/conf/httpd.conf
#     fi

#     cat > /etc/httpd/conf.d/vhost_${puerto}.conf << EOF
# Listen $puerto

# <VirtualHost *:$puerto>
#     ServerAdmin webmaster@localhost
#     DocumentRoot $vhost_dir
#     ErrorLog /var/log/httpd/error_${puerto}.log
#     CustomLog /var/log/httpd/access_${puerto}.log combined
#     <Directory "$vhost_dir">
#         Options Indexes FollowSymLinks
#         AllowOverride None
#         Require all granted
#     </Directory>
# </VirtualHost>
# EOF

#     # Hardening
#     grep -q "^ServerTokens" /etc/httpd/conf/httpd.conf \
#         && sed -i 's/^ServerTokens .*/ServerTokens Prod/' /etc/httpd/conf/httpd.conf \
#         || echo "ServerTokens Prod" >> /etc/httpd/conf/httpd.conf

#     grep -q "^ServerSignature" /etc/httpd/conf/httpd.conf \
#         && sed -i 's/^ServerSignature .*/ServerSignature Off/' /etc/httpd/conf/httpd.conf \
#         || echo "ServerSignature Off" >> /etc/httpd/conf/httpd.conf

#     crear_index "$vhost_dir" "Apache/httpd" "$version" "$puerto"
#     chown -R apache:apache "$vhost_dir"
#     chmod -R 755 "$vhost_dir"
#     chcon -R -t httpd_sys_content_t "$vhost_dir" 2>/dev/null

#     # SELinux: permitir el puerto si no es estandar
#     if [ "$puerto" != "80" ] && [ "$puerto" != "443" ]; then
#         semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null \
#             || semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
#     fi

#     configurar_firewall "$puerto"
#     systemctl enable httpd --now &>/dev/null
#     systemctl restart httpd

#     if systemctl is-active --quiet httpd; then
#         echo "  [OK] Apache activo en http://192.168.56.101:$puerto"
#     else
#         echo "  [!] Apache no inicio. Revisa: journalctl -u httpd -n 20"
#     fi
# }

# instalar_nginx() {
#     local version=$1
#     local puerto=$2

#     echo "Instalando Nginx en puerto $puerto..."
#     pkill -9 nginx 2>/dev/null
#     dnf install -y -q nginx &>/dev/null

#     local vhost_dir="/var/www/nginx_$puerto"
#     mkdir -p "$vhost_dir"

#     # Deshabilitar default.conf de conf.d/
#     [ -f /etc/nginx/conf.d/default.conf ] && \
#         mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled

#     # FIX PRINCIPAL: nginx.conf tiene un bloque server{ listen 80; } hardcodeado
#     # dentro del bloque http{} que causa el "Address already in use".
#     # Se reemplaza nginx.conf por una version limpia sin server blocks.
#     cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak_script
#     cat > /etc/nginx/nginx.conf << 'NGINXCONF'
# user nginx;
# worker_processes auto;
# error_log /var/log/nginx/error.log notice;
# pid /run/nginx.pid;

# include /usr/share/nginx/modules/*.conf;

# events {
#     worker_connections 1024;
# }

# http {
#     log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
#                       '$status $body_bytes_sent "$http_referer" '
#                       '"$http_user_agent" "$http_x_forwarded_for"';

#     access_log  /var/log/nginx/access.log  main;

#     sendfile            on;
#     tcp_nopush          on;
#     keepalive_timeout   65;
#     types_hash_max_size 4096;
#     server_tokens       off;

#     include             /etc/nginx/mime.types;
#     default_type        application/octet-stream;

#     include /etc/nginx/conf.d/*.conf;
# }
# NGINXCONF

#     cat > /etc/nginx/conf.d/vhost_${puerto}.conf << EOF
# server {
#     listen $puerto;
#     root $vhost_dir;
#     index index.html;
#     server_name _;
#     location / {
#         try_files \$uri \$uri/ =404;
#     }
# }
# EOF

#     crear_index "$vhost_dir" "Nginx" "$version" "$puerto"
#     chcon -R -t httpd_sys_content_t "$vhost_dir" 2>/dev/null

#     if [ "$puerto" != "80" ] && [ "$puerto" != "443" ]; then
#         semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null \
#             || semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
#     fi

#     # Validar sintaxis antes de reiniciar
#     if ! nginx -t &>/dev/null; then
#         echo "  [!] Error en config nginx. Restaurando backup..."
#         cp /etc/nginx/nginx.conf.bak_script /etc/nginx/nginx.conf
#         nginx -t
#         return 1
#     fi

#     configurar_firewall "$puerto"
#     systemctl daemon-reload
#     systemctl enable nginx --now &>/dev/null
#     systemctl restart nginx

#     if systemctl is-active --quiet nginx; then
#         echo "  [OK] Nginx activo en http://192.168.56.101:$puerto"
#     else
#         echo "  [!] Nginx no inicio. Revisa: journalctl -u nginx -n 20"
#     fi
# }

# instalar_tomcat() {
#     local version=$1
#     local puerto=$2

#     echo "Instalando Tomcat en puerto $puerto..."
#     dnf install -y -q java-17-openjdk tomcat &>/dev/null

#     if [ ! -d "/etc/tomcat" ]; then
#         echo "  [!] Error: Tomcat no se instalo correctamente."
#         return 1
#     fi

#     # FIX: hacer ambos sed en un solo paso para evitar que el patron cambie
#     # entre el primer y segundo sed
#     sed -i "s/port=\"8080\"/port=\"$puerto\" server=\"Apache Tomcat\"/" /etc/tomcat/server.xml

#     mkdir -p /var/lib/tomcat/webapps/ROOT
#     crear_index "/var/lib/tomcat/webapps/ROOT" "Tomcat" "$version" "$puerto"
#     chown -R tomcat:tomcat /var/lib/tomcat/webapps
#     chmod -R 750 /var/lib/tomcat/webapps
#     chcon -R -t tomcat_var_lib_t /var/lib/tomcat/webapps 2>/dev/null

#     configurar_firewall "$puerto"
#     systemctl enable tomcat --now &>/dev/null
#     systemctl restart tomcat

#     if systemctl is-active --quiet tomcat; then
#         echo "  [OK] Tomcat activo en http://192.168.56.101:$puerto"
#     else
#         echo "  [!] Tomcat no inicio. Revisa: journalctl -u tomcat -n 20"
#     fi
# }

#!/bin/bash
# =============================================================================
# http_functions.sh — Funciones para aprovisionamiento HTTP en Fedora Server 42
# Uso: source http_functions.sh desde el main script
# =============================================================================

# IP de la VM Fedora (adaptador host-only)
readonly VM_IP="192.168.56.101"

# Puertos reservados que no se pueden usar para HTTP
readonly RESERVED_PORTS=(1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 43 53 69
    77 79 110 111 113 115 117 118 119 123 135 137 139 143 161 177 179 389
    427 445 465 512 513 514 515 526 530 531 532 540 548 554 556 563 587
    601 636 989 990 993 995 1723 2049 2222 3306 3389 5432)

declare -A SERVICIOS_RESERVADOS=(
    [20]="FTP-Data" [21]="FTP" [22]="SSH" [25]="SMTP" [53]="DNS"
    [110]="POP3" [143]="IMAP" [445]="SMB" [2222]="SSH-Alt"
    [3306]="MySQL" [5432]="PostgreSQL" [3389]="RDP"
)

# =============================================================================
# 1. DEPENDENCIAS BASE
# =============================================================================

instalar_dependencias_base() {
    echo "[*] Verificando dependencias base..."
    dnf install -y -q firewalld curl net-tools gawk iproute \
        policycoreutils-python-utils 2>/dev/null
    systemctl enable firewalld --now &>/dev/null
    echo "[OK] Dependencias listas."
}

# =============================================================================
# 2. LIMPIEZA DEL ENTORNO
# =============================================================================

liberar_entorno() {
    echo ""
    echo "[*] Iniciando limpieza profunda del entorno..."

    # Detener y deshabilitar servicios
    for svc in httpd nginx tomcat; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null
            echo "  [OK] Servicio $svc detenido."
        fi
        systemctl disable "$svc" 2>/dev/null
    done

    # Matar procesos residuales
    for proc in httpd nginx java; do
        pids=$(pgrep -f "$proc" 2>/dev/null)
        if [ -n "$pids" ]; then
            kill -9 $pids 2>/dev/null
            echo "  [OK] Proceso $proc terminado."
        fi
    done

    # Desinstalar paquetes
    dnf remove -y -q httpd nginx tomcat 2>/dev/null
    dnf autoremove -y -q 2>/dev/null

    # Limpiar configuraciones y vhosts residuales
    rm -f /etc/httpd/conf.d/vhost_*.conf
    rm -f /etc/nginx/conf.d/vhost_*.conf
    rm -rf /var/www/apache_*
    rm -rf /var/www/nginx_*

    # Limpiar puertos SELinux no estándar registrados por el script
    for port in $(semanage port -l 2>/dev/null | grep http_port_t \
        | grep -oP '\b[0-9]{4,5}\b' \
        | grep -vE '^(80|443|8080|8443)$'); do
        semanage port -d -t http_port_t -p tcp "$port" 2>/dev/null
    done

    # Limpiar reglas de firewall añadidas por el script
    for port in $(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n'); do
        firewall-cmd --permanent --remove-port="$port" 2>/dev/null
    done
    firewall-cmd --reload 2>/dev/null

    echo "[OK] Entorno liberado y limpio."
}

# =============================================================================
# 3. VALIDACIÓN DE PUERTO
# Resultado queda en variable global PUERTO_ELEGIDO
# =============================================================================

solicitarPuerto() {
    local servicio_nombre="${1:-el servicio}"

    while true; do
        read -p "  Puerto para $servicio_nombre (ej. 8080, 8081, 9090): " PUERTO_ELEGIDO

        # Validar que sea número
        if [[ ! "$PUERTO_ELEGIDO" =~ ^[0-9]+$ ]]; then
            echo "  [!] Solo se permiten números. Intenta de nuevo." >&2
            continue
        fi

        # Validar rango
        if [ "$PUERTO_ELEGIDO" -le 0 ] || [ "$PUERTO_ELEGIDO" -gt 65535 ]; then
            echo "  [!] Puerto fuera de rango (1-65535)." >&2
            continue
        fi

        # Validar que no sea puerto reservado del sistema
        if [[ " ${RESERVED_PORTS[*]} " =~ " ${PUERTO_ELEGIDO} " ]]; then
            local desc="${SERVICIOS_RESERVADOS[$PUERTO_ELEGIDO]:-Sistema Crítico}"
            echo "  [!] Puerto $PUERTO_ELEGIDO reservado para $desc. Elige otro." >&2
            continue
        fi

        # Validar que no esté en uso
        if ss -tuln 2>/dev/null | grep -q ":${PUERTO_ELEGIDO} "; then
            echo "  [!] Puerto $PUERTO_ELEGIDO ya está en uso por otro proceso." >&2
            continue
        fi

        # Puerto válido
        break
    done
}

# =============================================================================
# 4. SELECCIÓN DINÁMICA DE VERSIÓN
# Resultado queda en variable global VERSION_ELEGIDA
# =============================================================================

seleccionar_version() {
    local servicio="$1"
    local paquete_dnf

    case "$servicio" in
        apache2)  paquete_dnf="httpd"  ;;
        nginx)    paquete_dnf="nginx"  ;;
        tomcat10) paquete_dnf="tomcat" ;;
        *)        paquete_dnf="$servicio" ;;
    esac

    echo "  [*] Consultando versiones disponibles para $paquete_dnf..."

    # Consultar todas las versiones: repo activo + duplicados (--showduplicates)
    # y tambien repos de Fedora anteriores si estan disponibles
    mapfile -t todas < <(
        {
            dnf repoquery --available --showduplicates                 --queryformat '%{version}-%{release}' "$paquete_dnf" 2>/dev/null
            # Intentar repos de versiones anteriores de Fedora si existen
            dnf repoquery --available --showduplicates                 --queryformat '%{version}-%{release}' "$paquete_dnf"                 --enablerepo="*" 2>/dev/null
        } | sort -Vu | grep -v "^$"
    )

    if [ ${#todas[@]} -eq 0 ]; then
        echo "  [!] No se encontraron versiones. Usando 'latest'."
        VERSION_ELEGIDA="latest"
        return
    fi

    local total=${#todas[@]}

    # Si el repo solo tiene 1 version, informar al usuario honestamente
    # y mostrar esa version en las 3 opciones indicando que es la unica disponible
    if [ $total -eq 1 ]; then
        echo "  [!] Solo hay 1 version disponible en los repositorios configurados."
        echo "      Para tener mas versiones, activa repos adicionales (ej. Koji, COPR)."
    fi

    # Construir 3 slots: Latest=ultima, Stable=penultima o misma, Legacy=primera o misma
    local v_latest="${todas[$((total - 1))]}"
    local v_stable v_legacy

    if [ $total -ge 3 ]; then
        v_stable="${todas[$((total - 2))]}"
        v_legacy="${todas[0]}"
    elif [ $total -eq 2 ]; then
        v_stable="${todas[0]}"
        v_legacy="${todas[0]}"
    else
        v_stable="$v_latest"
        v_legacy="$v_latest"
    fi

    local opciones=("$v_latest" "$v_stable" "$v_legacy")
    local etiquetas=("Latest" "Stable" "LTS/Legacy")

    echo ""
    echo "  Versiones disponibles para $paquete_dnf (total en repos: $total):"
    for i in 0 1 2; do
        local ver="${opciones[$i]}"
        local etq="${etiquetas[$i]}"
        local dist=""
        if   [[ "$ver" == *"fc43"* ]]; then dist="[Fedora 43]"
        elif [[ "$ver" == *"fc42"* ]]; then dist="[Fedora 42]"
        elif [[ "$ver" == *"fc41"* ]]; then dist="[Fedora 41]"
        elif [[ "$ver" == *"fc40"* ]]; then dist="[Fedora 40]"
        else                                dist="[Repositorio]"
        fi
        # Indicar si hay versiones repetidas
        local nota=""
        [ "$total" -eq 1 ] && nota=" (unica disponible)"
        local ver_num
        ver_num=$(echo "$ver" | cut -d'-' -f1)
        printf "    %d) v%-12s  %-38s %s\n" "$((i+1))" "$ver_num" "$ver" "$dist"
    done
    echo ""

    while true; do
        read -p "  Selecciona la version (1-3): " seleccion

        if [[ ! "$seleccion" =~ ^[0-9]+$ ]]; then
            echo "  [!] Ingresa solo el numero." >&2
            continue
        fi

        if [ "$seleccion" -ge 1 ] && [ "$seleccion" -le 3 ]; then
            VERSION_ELEGIDA="${opciones[$((seleccion - 1))]}"
            local _vnum
            _vnum=$(echo "$VERSION_ELEGIDA" | cut -d'-' -f1)
            echo "  [OK] Version seleccionada: $_vnum  (build: $VERSION_ELEGIDA)"
            break
        fi
        echo "  [!] Opcion invalida (1-3)." >&2
    done
}

# =============================================================================
# 5. UTILIDADES COMUNES
# =============================================================================

configurar_firewall() {
    local puerto="$1"
    echo "  [*] Configurando firewall para puerto $puerto/tcp..."
    firewall-cmd --permanent --add-port="${puerto}/tcp" &>/dev/null
    firewall-cmd --reload &>/dev/null
    echo "  [OK] Puerto $puerto abierto en firewalld."
}

registrar_puerto_selinux() {
    local puerto="$1"
    if [ "$puerto" != "80" ] && [ "$puerto" != "443" ] && [ "$puerto" != "8080" ] && [ "$puerto" != "8443" ]; then
        echo "  [*] Registrando puerto $puerto en SELinux (http_port_t)..."
        semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null \
            || semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
        echo "  [OK] Puerto $puerto registrado en SELinux."
    fi
}

crear_usuario_dedicado() {
    local usuario="$1"
    local directorio="$2"

    if ! id "$usuario" &>/dev/null; then
        useradd -r -s /sbin/nologin -d "$directorio" -M "$usuario" 2>/dev/null
        echo "  [OK] Usuario dedicado '$usuario' creado."
    fi
}

crear_index() {
    local ruta="$1"
    local servicio="$2"
    local version="$3"
    local puerto="$4"

    mkdir -p "$ruta"
    cat > "$ruta/index.html" << HTML
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>$servicio — Puerto $puerto</title>
  <style>
    body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; 
           display: flex; justify-content: center; align-items: center; 
           height: 100vh; margin: 0; }
    .card { background: #16213e; border: 1px solid #0f3460; border-radius: 12px;
            padding: 40px 60px; text-align: center; box-shadow: 0 4px 20px rgba(0,0,0,0.5); }
    h1 { color: #e94560; margin-bottom: 20px; }
    .info { font-size: 1.1em; margin: 8px 0; }
    .badge { display: inline-block; background: #0f3460; border-radius: 6px;
             padding: 4px 12px; margin-top: 10px; font-family: monospace; }
  </style>
</head>
<body>
  <div class="card">
    <h1>✅ Servidor Activo</h1>
    <div class="info"><strong>Servidor:</strong> $servicio</div>
    <div class="info"><strong>Versión:</strong> $version</div>
    <div class="info"><strong>Puerto:</strong> $puerto</div>
    <div class="info"><strong>IP:</strong> $VM_IP</div>
    <div class="badge">http://$VM_IP:$puerto</div>
  </div>
</body>
</html>
HTML
}

# =============================================================================
# 6. INSTALACIÓN DE APACHE (httpd)
# =============================================================================

instalar_apache() {
    local version="$1"
    local puerto="$2"

    echo ""
    echo "[*] Instalando Apache (httpd) versión $version en puerto $puerto..."

    # Instalar paquete
    if ! dnf install -y -q httpd &>/dev/null; then
        echo "  [!] Error al instalar httpd. Revisa la conexión a repositorios."
        return 1
    fi

    # Crear usuario dedicado y directorio
    local vhost_dir="/var/www/apache_$puerto"
    crear_usuario_dedicado "apache" "$vhost_dir"
    mkdir -p "$vhost_dir"

    # Deshabilitar welcome.conf para evitar conflictos
    [ -f /etc/httpd/conf.d/welcome.conf ] && \
        mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf.disabled 2>/dev/null

    # Si el puerto elegido no es 80, comentar el Listen 80 del conf principal
    # para evitar que httpd intente escuchar en 80 si no está en uso
    if [ "$puerto" != "80" ]; then
        sed -i 's/^Listen 80$/#Listen 80 (gestionado por vhost)/' \
            /etc/httpd/conf/httpd.conf 2>/dev/null
    fi

    # Asegurar que mod_headers y mod_authz_core esten activos en httpd.conf
    sed -i 's/^#LoadModule headers_module/LoadModule headers_module/' \
        /etc/httpd/conf/httpd.conf 2>/dev/null
    sed -i 's/^#LoadModule authz_core_module/LoadModule authz_core_module/' \
        /etc/httpd/conf/httpd.conf 2>/dev/null

    # Crear VirtualHost para este puerto
    # IMPORTANTE: <LimitExcept> va DENTRO de <Directory>, nunca directamente en <VirtualHost>
    # En Fedora/RHEL httpd rechaza <LimitExcept> fuera de <Directory> con AH00526
    cat > /etc/httpd/conf.d/vhost_${puerto}.conf << EOF
# VirtualHost Apache - Puerto $puerto
Listen $puerto

<VirtualHost *:$puerto>
    ServerAdmin webmaster@localhost
    DocumentRoot ${vhost_dir}
    ErrorLog  /var/log/httpd/error_${puerto}.log
    CustomLog /var/log/httpd/access_${puerto}.log combined

    <Directory "${vhost_dir}">
        Options -Indexes -FollowSymLinks
        AllowOverride None
        Require all granted
        # Bloquear metodos peligrosos dentro de Directory (requerido por Fedora httpd)
        <LimitExcept GET POST HEAD>
            Require all denied
        </LimitExcept>
    </Directory>

    # Headers de seguridad (requiere mod_headers)
    <IfModule mod_headers.c>
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-XSS-Protection "1; mode=block"
    </IfModule>
</VirtualHost>
EOF

    # Hardening: ocultar version del servidor
    _apache_hardening_headers

    # Crear pagina de prueba
    crear_index "$vhost_dir" "Apache/httpd" "$version" "$puerto"

    # Permisos seguros
    chown -R apache:apache "$vhost_dir"
    chmod -R 750 "$vhost_dir"
    chcon -R -t httpd_sys_content_t "$vhost_dir" 2>/dev/null

    # SELinux y firewall
    registrar_puerto_selinux "$puerto"
    configurar_firewall "$puerto"

    # Validar configuracion antes de iniciar (evita arranque fallido silencioso)
    echo "  [*] Validando configuracion de Apache..."
    if ! httpd -t &>/dev/null; then
        echo "  [!] Error en la configuracion de Apache:"
        httpd -t
        return 1
    fi
    echo "  [OK] Configuracion valida."

    # Iniciar / recargar servicio
    systemctl enable httpd --now &>/dev/null
    if systemctl is-active --quiet httpd; then
        systemctl reload httpd 2>/dev/null || systemctl restart httpd
    else
        systemctl start httpd
    fi

    sleep 1
    if systemctl is-active --quiet httpd; then
        echo ""
        echo "  ╔══════════════════════════════════════════════════╗"
        echo "  ║  [OK] Apache activo                              ║"
        echo "  ║  URL: http://$VM_IP:$puerto                      "
        echo "  ║  Version: $version                               "
        echo "  ╚══════════════════════════════════════════════════╝"
    else
        echo "  [!] Apache no inicio. Diagnostico:"
        journalctl -u httpd -n 15 --no-pager
        return 1
    fi
}

_apache_hardening_headers() {
    local conf="/etc/httpd/conf/httpd.conf"

    # ServerTokens Prod — solo muestra "Apache" sin versión
    if grep -q "^ServerTokens" "$conf" 2>/dev/null; then
        sed -i 's/^ServerTokens .*/ServerTokens Prod/' "$conf"
    else
        echo "ServerTokens Prod" >> "$conf"
    fi

    # ServerSignature Off — elimina firma en páginas de error
    if grep -q "^ServerSignature" "$conf" 2>/dev/null; then
        sed -i 's/^ServerSignature .*/ServerSignature Off/' "$conf"
    else
        echo "ServerSignature Off" >> "$conf"
    fi

    echo "  [OK] Hardening Apache: ServerTokens Prod + ServerSignature Off aplicados."
}

# =============================================================================
# 7. INSTALACIÓN DE NGINX
# =============================================================================

instalar_nginx() {
    local version="$1"
    local puerto="$2"

    echo ""
    echo "[*] Instalando Nginx versión $version en puerto $puerto..."

    # Matar instancias previas
    pkill -9 nginx 2>/dev/null

    if ! dnf install -y -q nginx &>/dev/null; then
        echo "  [!] Error al instalar nginx."
        return 1
    fi

    # Directorio dedicado para este vhost
    local vhost_dir="/var/www/nginx_$puerto"
    crear_usuario_dedicado "nginx" "$vhost_dir"
    mkdir -p "$vhost_dir"

    # Deshabilitar default.conf para evitar conflicto con puerto 80
    [ -f /etc/nginx/conf.d/default.conf ] && \
        mv /etc/nginx/conf.d/default.conf \
           /etc/nginx/conf.d/default.conf.disabled 2>/dev/null

    # Reemplazar nginx.conf principal eliminando el server block hardcodeado
    # (el server block por defecto escucha en 80 y causa conflictos)
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak_$(date +%s) 2>/dev/null
    cat > /etc/nginx/nginx.conf << 'NGINXMAIN'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    sendfile            on;
    tcp_nopush          on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    # Hardening: ocultar versión de Nginx
    server_tokens off;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Todos los vhosts se cargan desde conf.d/
    include /etc/nginx/conf.d/*.conf;
}
NGINXMAIN

    # Crear vhost especifico para este puerto
    # listen 0.0.0.0:PUERTO garantiza escucha en TODAS las interfaces (host-only incluida)
    cat > /etc/nginx/conf.d/vhost_${puerto}.conf << EOF
server {
    listen 0.0.0.0:${puerto};
    listen [::]:${puerto};
    server_name _;
    root ${vhost_dir};
    index index.html;

    # Deshabilitar metodos peligrosos
    if (\$request_method !~ ^(GET|POST|HEAD)\$) {
        return 405;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Headers de seguridad
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
EOF

    # Crear pagina de prueba
    crear_index "$vhost_dir" "Nginx" "$version" "$puerto"

    # Permisos seguros
    chown -R nginx:nginx "$vhost_dir"
    chmod -R 750 "$vhost_dir"
    chcon -R -t httpd_sys_content_t "$vhost_dir" 2>/dev/null

    # Validar configuracion antes de iniciar
    echo "  [*] Validando configuracion de Nginx..."
    if ! nginx -t 2>/dev/null; then
        echo "  [!] Error en configuracion de Nginx:"
        nginx -t
        return 1
    fi
    echo "  [OK] Configuracion valida."

    # SELinux y firewall
    registrar_puerto_selinux "$puerto"
    configurar_firewall "$puerto"

    # Iniciar / recargar
    systemctl enable nginx --now &>/dev/null
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx 2>/dev/null || systemctl restart nginx
    else
        systemctl start nginx
    fi

    # Esperar hasta 8s a que el puerto aparezca en ss
    local intentos=0
    while [ $intentos -lt 8 ]; do
        sleep 1
        if ss -tuln 2>/dev/null | grep -q ":${puerto}"; then
            break
        fi
        ((intentos++))
    done

    if systemctl is-active --quiet nginx && ss -tuln 2>/dev/null | grep -q ":${puerto}"; then
        echo ""
        echo "  ╔══════════════════════════════════════════════════╗"
        echo "  ║  [OK] Nginx activo y escuchando                  ║"
        echo "  ║  URL: http://$VM_IP:$puerto                      "
        echo "  ║  Version: $version                               "
        echo "  ╚══════════════════════════════════════════════════╝"
        echo ""
        echo "  [*] Interfaces en escucha para puerto $puerto:"
        ss -tuln | grep ":${puerto}"
    else
        echo "  [!] Nginx no inicio correctamente. Diagnostico:"
        journalctl -u nginx -n 15 --no-pager
        echo "  Ultimas lineas de error.log:"
        tail -10 /var/log/nginx/error.log 2>/dev/null
        return 1
    fi
}

# =============================================================================
# 8. INSTALACIÓN DE TOMCAT
# =============================================================================

instalar_tomcat() {
    local version="$1"
    local puerto="$2"

    echo ""
    echo "[*] Instalando Tomcat version $version en puerto $puerto..."

    echo "  [*] Verificando Java..."
    if ! java -version &>/dev/null 2>&1; then
        echo "  [*] Java no encontrado. Instalando..."
        local java_ok=0
        for pkg in java-17-openjdk java-21-openjdk java-11-openjdk; do
            if dnf install -y -q "$pkg" &>/dev/null; then
                echo "  [OK] Java instalado: $pkg"
                java_ok=1
                break
            fi
        done
        if [ $java_ok -eq 0 ]; then
            echo "  [!] No se pudo instalar Java. Ejecutando visible:"
            dnf install -y java-17-openjdk
            return 1
        fi
    else
        echo "  [OK] Java detectado: $(java -version 2>&1 | head -1)"
    fi

    echo "  [*] Instalando paquete tomcat..."
    if ! dnf install -y -q tomcat &>/dev/null; then
        echo "  [!] Fallo. Reintentando visible:"
        dnf install -y tomcat
        return 1
    fi
    echo "  [OK] Tomcat instalado."

    if [ ! -d "/etc/tomcat" ]; then
        echo "  [!] /etc/tomcat no existe. Abortando."
        return 1
    fi

    # ── Configurar puerto en server.xml ──────────────────────────────────────
    # Fedora 43 server.xml tiene port= en estos sitios:
    #   port="8005"  -> shutdown del Server  -> NO tocar
    #   port="8080"  -> Connector HTTP/1.1   -> CAMBIAR (puede aparecer 2 veces)
    #   port="8443"  -> Connector SSL        -> NO tocar
    # El valor 8080 es exclusivo del Connector HTTP, asi que sed es seguro.
    echo "  [*] Configurando puerto $puerto en server.xml..."

    local xml="/etc/tomcat/server.xml"
    local bak="/etc/tomcat/server.xml.original"

    # Backup del original (solo la primera vez)
    if [ ! -f "$bak" ]; then
        cp "$xml" "$bak"
        echo "  [OK] Backup guardado en $bak"
    fi

    # Restaurar siempre desde el original (limpia ejecuciones previas)
    cp "$bak" "$xml"

    # IMPORTANTE: comillas dobles para que $puerto se expanda (simples NO expanden variables)
    sed -i "s/port=\"8080\"/port=\"${puerto}\"/g" "$xml"

    # Agregar server="Apache" para ocultar version en encabezados HTTP
    sed -i "/protocol=\"HTTP\/1\.1\"/ { /server=/ !s/protocol=\"HTTP\/1\.1\"/server=\"Apache\" protocol=\"HTTP\/1\.1\"/ }" "$xml"

    # Verificar con el numero real del puerto (no la variable literal)
    if grep -q "port=\"${puerto}\"" "$xml"; then
        echo "  [OK] Puerto $puerto configurado en server.xml."
        grep -n "port=" "$xml" | grep -v "8005\|8443\|8009"
    else
        echo "  [!] No se pudo configurar el puerto. Estado del server.xml:"
        grep -n "Connector\|port=" "$xml" | head -15
        return 1
    fi

    # ── Crear usuario y directorio web ────────────────────────────────────────
    crear_usuario_dedicado "tomcat" "/var/lib/tomcat"

    local webapp_dir="/var/lib/tomcat/webapps/ROOT"
    mkdir -p "$webapp_dir"
    crear_index "$webapp_dir" "Apache Tomcat" "$version" "$puerto"

    chown -R tomcat:tomcat /var/lib/tomcat/webapps
    chmod -R 750 /var/lib/tomcat/webapps
    chcon -R -t tomcat_var_lib_t /var/lib/tomcat/webapps 2>/dev/null

    # ── SELinux ───────────────────────────────────────────────────────────────
    echo "  [*] Registrando puerto $puerto en SELinux..."
    semanage port -a -t http_port_t   -p tcp "$puerto" 2>/dev/null \
        || semanage port -m -t http_port_t   -p tcp "$puerto" 2>/dev/null
    semanage port -a -t tomcat_port_t -p tcp "$puerto" 2>/dev/null \
        || semanage port -m -t tomcat_port_t -p tcp "$puerto" 2>/dev/null
    echo "  [OK] Puerto $puerto registrado en SELinux."

    # ── Firewall ──────────────────────────────────────────────────────────────
    configurar_firewall "$puerto"

    # ── Iniciar Tomcat ────────────────────────────────────────────────────────
    systemctl enable tomcat --now &>/dev/null
    systemctl restart tomcat

    echo "  [*] Esperando que Tomcat escuche en puerto $puerto (hasta 30s)..."
    local intentos=0
    while [ $intentos -lt 30 ]; do
        sleep 1
        # awk extrae la columna de direccion local y busca :PUERTO al final
        if ss -tuln 2>/dev/null | awk '{print $5}' | grep -qE ":${puerto}$"; then
            echo "  [OK] Puerto $puerto detectado (${intentos}s)."
            break
        fi
        ((intentos++))
    done

    sleep 1
    local puerto_ok=false
    ss -tuln 2>/dev/null | awk '{print $5}' | grep -qE ":${puerto}$" && puerto_ok=true

    if systemctl is-active --quiet tomcat && $puerto_ok; then
        echo ""
        echo "  +==================================================+"
        echo "  |  [OK] Tomcat activo y escuchando                 |"
        echo "  |  URL: http://$VM_IP:$puerto                      |"
        echo "  |  Version: $version                               |"
        echo "  +==================================================+"
        echo ""
        echo "  [*] Interfaces en escucha para puerto $puerto:"
        ss -tuln | awk '{print $5}' | grep -E ":${puerto}$"
    else
        # Fallback: curl directo por si ss no detecta bien
        sleep 2
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://127.0.0.1:${puerto}" --connect-timeout 4 2>/dev/null)
        if echo "$http_code" | grep -qE "^[23]"; then
            echo ""
            echo "  +==================================================+"
            echo "  |  [OK] Tomcat responde HTTP ($http_code)          |"
            echo "  |  URL: http://$VM_IP:$puerto                      |"
            echo "  |  Version: $version                               |"
            echo "  +==================================================+"
        else
            echo ""
            echo "  [!] Tomcat no responde en puerto $puerto."
            echo "  --- Estado del servicio ---"
            systemctl status tomcat --no-pager -n 5
            echo "  --- Log de Tomcat ---"
            journalctl -u tomcat -n 20 --no-pager
            echo "  --- Puertos en escucha ---"
            ss -tuln | head -20
            echo "  --- server.xml (Connectors) ---"
            grep -n "Connector\|port=" /etc/tomcat/server.xml | head -15
            return 1
        fi
    fi
}