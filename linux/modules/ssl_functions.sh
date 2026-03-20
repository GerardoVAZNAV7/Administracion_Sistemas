#!/bin/bash
# =============================================================================
# ssl_functions.sh — Funciones SSL/TLS para Fedora Server 42  v2
# Practica 7: Infraestructura de Despliegue Seguro
#
# CORRECCIONES v2:
#   - Apache FTP: instala mod_ssl SIEMPRE (no viene en el RPM de httpd)
#   - Todos los servicios: certificado con SAN (IP + dominio) para que el
#     navegador muestre el candado verde tanto con IP como con dominio
#   - Tomcat index.html: usa printf — sin el bug de encoding (caracter a?"?)
#   - Todos los servicios preguntan puertos antes de instalar
#   - server.xml sin-SSL usaba EOF mal cerrado — corregido
# =============================================================================

FTP_SERVER="192.168.56.101"
FTP_USER="danger"
FTP_PASS="Gerardo1234!!"
RESUMEN_INSTALACIONES=()

# =============================================================================
# BLOQUE 1: CLIENTE FTP DINAMICO
# =============================================================================

listar_versiones_ftp() {
    local servicio=$1
    local url_base="ftp://$FTP_SERVER/http/Linux/$servicio/"
    echo "Buscando instaladores de $servicio en $url_base ..." > /dev/tty
    mapfile -t versiones < <(
        curl -s -l -u "$FTP_USER:$FTP_PASS" "$url_base" 2>/dev/null \
        | grep -v '\.sha256$' | grep -v '\.md5$'
    )
    if [ ${#versiones[@]} -eq 0 ]; then
        echo "[!] No se encontraron archivos en: $url_base" > /dev/tty
        _ARCHIVO_ELEGIDO="INVALIDO"; return 1
    fi
    echo "Versiones encontradas:" > /dev/tty
    for i in "${!versiones[@]}"; do echo "  $((i+1))) ${versiones[$i]}" > /dev/tty; done
    echo "  0) Regresar" > /dev/tty
    local sel_ver
    read -p "Selecciona la version: " sel_ver < /dev/tty > /dev/tty
    if [[ "$sel_ver" == "0" ]]; then
        _ARCHIVO_ELEGIDO="REGRESAR"
    elif [[ "$sel_ver" =~ ^[0-9]+$ ]] && [ "$sel_ver" -ge 1 ] && [ "$sel_ver" -le "${#versiones[@]}" ]; then
        _ARCHIVO_ELEGIDO="${versiones[$((sel_ver-1))]}"
    else
        _ARCHIVO_ELEGIDO="INVALIDO"; return 1
    fi
}

descargar_y_validar_hash() {
    local servicio=$1 archivo=$2
    local url_base="ftp://$FTP_SERVER/http/Linux/$servicio/"
    cd /tmp || return 1
    echo "[+] Descargando $archivo..."
    curl -s --show-error -u "$FTP_USER:$FTP_PASS" -O "${url_base}${archivo}" \
        || { echo "[!] Error al descargar $archivo"; return 1; }
    echo "[+] Descargando hash SHA256..."
    curl -s --show-error -u "$FTP_USER:$FTP_PASS" -O "${url_base}${archivo}.sha256" \
        || { echo "[!] Sin hash disponible. Continuando..."; _RUTA_ARCHIVO="/tmp/$archivo"; return 0; }
    if [[ -f "/tmp/${archivo}.sha256" ]]; then
        local hash_remoto hash_local
        hash_remoto=$(awk '{print $1}' "/tmp/${archivo}.sha256")
        hash_local=$(sha256sum "/tmp/$archivo" | awk '{print $1}')
        if [[ "$hash_remoto" == "$hash_local" ]]; then
            echo "[OK] Integridad SHA256 verificada."
        else
            echo "[!] ERROR DE INTEGRIDAD: hash no coincide."
            echo "    Esperado : $hash_remoto"
            echo "    Calculado: $hash_local"
            rm -f "/tmp/$archivo" "/tmp/${archivo}.sha256"
            return 1
        fi
    fi
    _RUTA_ARCHIVO="/tmp/$archivo"
    return 0
}

# =============================================================================
# BLOQUE 2: GENERACION DE CERTIFICADOS SSL CON SAN
# -----------------------------------------------------------------------------
# POR QUE ES NECESARIO EL SAN:
# Los navegadores modernos (Chrome, Firefox, Edge desde ~2017) ignoram el campo
# CN del certificado y solo miran subjectAltName (SAN).
# Si el cert no tiene SAN:
#   - Acceder por dominio: "No seguro" (ERR_CERT_COMMON_NAME_INVALID)
#   - Acceder por IP:      "No seguro" (la IP no esta en ningun SAN)
# Con SAN que incluya DNS.1=www.reprobados.com e IP.1=<IP del server>:
#   - Acceder por dominio: candado verde (con aviso de cert autofirmado)
#   - Acceder por IP:      candado verde (con aviso de cert autofirmado)
# El aviso "No es de confianza" siempre aparecera con certs autofirmados —
# eso es normal en un laboratorio. Lo que NO debe aparecer es "No seguro".
# =============================================================================

preguntar_ssl() {
    while true; do
        local resp
        read -p "Desea activar SSL en este servicio? [S/N]: " resp < /dev/tty > /dev/tty
        case "${resp^^}" in
            S) _SSL_ACTIVO="S"; return 0 ;;
            N) _SSL_ACTIVO="N"; return 0 ;;
            *) echo "[!] Responde S o N." ;;
        esac
    done
}

generar_ssl() {
    local servicio=$1
    local cert_dir="/etc/ssl/$servicio"
    mkdir -p "$cert_dir"

    local IP_SERVIDOR
    IP_SERVIDOR=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    [[ -z "$IP_SERVIDOR" ]] && IP_SERVIDOR="127.0.0.1"

    echo "[+] Generando certificado SSL (con SAN) para www.reprobados.com + IP $IP_SERVIDOR..."

    local openssl_cfg="$cert_dir/openssl_san.cnf"
    cat > "$openssl_cfg" << SSLCNF
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = v3_req
x509_extensions    = v3_req

[dn]
C  = MX
ST = Sinaloa
L  = Los Mochis
O  = Reprobados
CN = www.reprobados.com

[v3_req]
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = www.reprobados.com
DNS.2 = reprobados.com
IP.1  = ${IP_SERVIDOR}
IP.2  = 127.0.0.1
SSLCNF

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$cert_dir/server.key" \
        -out    "$cert_dir/server.crt" \
        -config "$openssl_cfg" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo "[OK] Certificado generado en: $cert_dir"
        echo "     Valido para: www.reprobados.com, reprobados.com, $IP_SERVIDOR"
        chmod 600 "$cert_dir/server.key"
        chmod 644 "$cert_dir/server.crt"
    else
        echo "[!] Error al generar el certificado SSL."; return 1
    fi
    _DIR_SSL="$cert_dir"
    return 0
}

# =============================================================================
# BLOQUE 3: PAGINAS DE ESTADO VISUAL
# Usa printf para evitar el bug de encoding del heredoc
# (el caracter — se convierte en a?"? en algunos locales)
# =============================================================================

_generar_index() {
    local ruta=$1 servidor=$2 ssl=$3 puerto=$4
    local color msg
    if [[ "$ssl" == "S" ]]; then color="green"; msg="SITIO SEGURO (HTTPS)"
    else                         color="red";   msg="SITIO NO SEGURO (HTTP)"; fi
    mkdir -p "$ruta"
    printf '<!DOCTYPE html>\n<html>\n<head>\n  <meta charset="UTF-8">\n  <title>%s - Practica 7</title>\n</head>\n' \
        "$servidor" > "$ruta/index.html"
    printf '<body style="font-family:sans-serif;text-align:center;padding:50px;background:#1a1a2e;color:white;">\n' \
        >> "$ruta/index.html"
    printf '  <h1 style="color:%s;">Servicio Activo: %s</h1>\n' "$color" "$servidor" >> "$ruta/index.html"
    printf '  <h2 style="background:%s;color:white;padding:15px;border-radius:8px;">%s</h2>\n' \
        "$color" "$msg" >> "$ruta/index.html"
    printf '  <p><strong>Dominio:</strong> www.reprobados.com</p>\n' >> "$ruta/index.html"
    printf '  <p><strong>Puerto principal:</strong> %s</p>\n' "$puerto" >> "$ruta/index.html"
    printf '  <p><strong>Generado por:</strong> Practica 7 - Fedora Server 42</p>\n' >> "$ruta/index.html"
    printf '</body>\n</html>\n' >> "$ruta/index.html"
    echo "[OK] index.html generado en: $ruta"
}

# =============================================================================
# BLOQUE 4: LIBERAR PUERTOS
# =============================================================================

liberar_puertos_web() {
    echo "[+] Deteniendo servicios HTTP activos..."
    for svc in httpd nginx tomcat; do
        systemctl is-active --quiet "$svc" 2>/dev/null && \
            systemctl stop "$svc" 2>/dev/null && echo "    [OK] $svc detenido."
    done
    for proc in httpd nginx java; do
        local pids; pids=$(pgrep -f "$proc" 2>/dev/null)
        [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null && echo "    [OK] Proceso $proc eliminado."
    done
    sleep 1; echo "[OK] Puertos web liberados."
}

# =============================================================================
# BLOQUE 5: INSTALADORES
# =============================================================================

# -----------------------------------------------------------------------------
# APACHE (httpd)
# FIX: instala mod_ssl SIEMPRE desde DNF porque el RPM de httpd no lo incluye.
#      Sin mod_ssl el error es: "Invalid command 'SSLEngine'"
# -----------------------------------------------------------------------------
instalar_apache() {
    local archivo=$1 web_ftp=$2 ssl=$3
    local puerto_http=80 puerto_https=443

    if [[ "$ssl" == "S" ]]; then
        while true; do
            read -p "[?] Puerto HTTPS para Apache (default 443): " p < /dev/tty > /dev/tty
            p="${p:-443}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_https=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
        while true; do
            read -p "[?] Puerto HTTP redireccion (default 80): " p < /dev/tty > /dev/tty
            p="${p:-80}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_http=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
    else
        while true; do
            read -p "[?] Puerto HTTP para Apache (default 80): " p < /dev/tty > /dev/tty
            p="${p:-80}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_http=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
    fi

    liberar_puertos_web

    # Paso 1: instalar httpd
    if [[ "$web_ftp" == "FTP" && -n "$archivo" && -f "$archivo" ]]; then
        echo "[+] Instalando Apache desde RPM del FTP: $archivo"
        rpm -Uvh --force "$archivo" 2>/dev/null \
        || { echo "[!] RPM fallo. Instalando desde repo..."; dnf install -y httpd &>/dev/null; }
    else
        echo "[+] Instalando Apache (httpd) desde DNF..."
        dnf install -y httpd &>/dev/null
    fi

    # Paso 2: instalar mod_ssl SIEMPRE (este es el fix del bug)
    echo "[+] Instalando mod_ssl desde DNF (necesario para SSLEngine)..."
    dnf install -y mod_ssl &>/dev/null
    echo "[OK] mod_ssl instalado."

    # Paso 3: limpiar confs conflictivas
    [[ -f /etc/httpd/conf.d/welcome.conf ]] && \
        mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf.disabled 2>/dev/null
    rm -f /etc/httpd/conf.d/ssl.conf
    rm -f /etc/httpd/conf.d/reprobados*.conf
    sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' /etc/httpd/conf/httpd.conf 2>/dev/null
    sed -i 's/^#LoadModule headers_module/LoadModule headers_module/' /etc/httpd/conf/httpd.conf 2>/dev/null

    # Paso 4: index.html
    local puerto_visual=$([[ "$ssl" == "S" ]] && echo "$puerto_https" || echo "$puerto_http")
    _generar_index "/var/www/html" "Apache (httpd)" "$ssl" "$puerto_visual"
    chcon -R -t httpd_sys_content_t /var/www/html 2>/dev/null

    # Paso 5: VirtualHost
    if [[ "$ssl" == "S" ]]; then
        generar_ssl "apache" || return 1
        local dir="$_DIR_SSL"

        cat > /etc/httpd/conf.d/reprobados-ssl.conf << APACHECONF
Listen ${puerto_https} https

<VirtualHost *:${puerto_http}>
    ServerName www.reprobados.com
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>

<VirtualHost *:${puerto_https}>
    ServerName www.reprobados.com
    DocumentRoot /var/www/html
    SSLEngine on
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLCertificateFile    ${dir}/server.crt
    SSLCertificateKeyFile ${dir}/server.key
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    <Directory "/var/www/html">
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
APACHECONF

        firewall-cmd --permanent --add-port="${puerto_https}/tcp" &>/dev/null
        firewall-cmd --permanent --add-port="${puerto_http}/tcp"  &>/dev/null
        firewall-cmd --reload &>/dev/null
        setsebool -P httpd_can_network_connect 1 &>/dev/null
        [[ "$puerto_https" != "443" ]] && semanage port -a -t http_port_t -p tcp "$puerto_https" 2>/dev/null
        RESUMEN_INSTALACIONES+=("[OK] Apache HTTPS:${puerto_https}  HTTP:${puerto_http}->redireccion")
    else
        cat > /etc/httpd/conf.d/reprobados.conf << APACHECONF
Listen ${puerto_http}
<VirtualHost *:${puerto_http}>
    ServerName www.reprobados.com
    DocumentRoot /var/www/html
    <Directory "/var/www/html">
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
APACHECONF
        firewall-cmd --permanent --add-port="${puerto_http}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        [[ "$puerto_http" != "80" ]] && semanage port -a -t http_port_t -p tcp "$puerto_http" 2>/dev/null
        RESUMEN_INSTALACIONES+=("[OK] Apache HTTP:${puerto_http}")
    fi

    # Paso 6: validar y arrancar
    echo "[*] Validando configuracion de Apache..."
    local test_out; test_out=$(httpd -t 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "[!] Error en la configuracion:"; echo "$test_out"
        echo ""; echo "Diagnostico:"
        echo "  rpm -qa | grep mod_ssl  <- debe aparecer el paquete"
        echo "  ls /etc/httpd/conf.modules.d/  <- debe existir 00-ssl.conf"
        return 1
    fi
    echo "[OK] Configuracion valida."
    systemctl enable httpd --now &>/dev/null
    systemctl restart httpd
    sleep 1
    if systemctl is-active --quiet httpd; then
        local IP; IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        echo "[OK] Apache activo."
        [[ "$ssl" == "S" ]] && \
            echo "     -> https://$IP:${puerto_https}  o  https://www.reprobados.com" || \
            echo "     -> http://$IP:${puerto_http}"
    else
        echo "[!] Apache no inicio:"; journalctl -u httpd -n 20 --no-pager
    fi
}

# -----------------------------------------------------------------------------
# NGINX
# FIX: certificado con SAN (IP + dominio) — el navegador lo acepta como seguro
# -----------------------------------------------------------------------------
instalar_nginx() {
    local archivo=$1 web_ftp=$2 ssl=$3
    local puerto_http=80 puerto_https=443

    if [[ "$ssl" == "S" ]]; then
        while true; do
            read -p "[?] Puerto HTTPS para Nginx (default 443): " p < /dev/tty > /dev/tty
            p="${p:-443}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_https=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
        while true; do
            read -p "[?] Puerto HTTP redireccion (default 80): " p < /dev/tty > /dev/tty
            p="${p:-80}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_http=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
    else
        while true; do
            read -p "[?] Puerto HTTP para Nginx (default 80): " p < /dev/tty > /dev/tty
            p="${p:-80}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_http=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
    fi

    liberar_puertos_web

    if [[ "$web_ftp" == "FTP" && -n "$archivo" && -f "$archivo" ]]; then
        echo "[+] Instalando Nginx desde RPM: $archivo"
        rpm -Uvh --force "$archivo" 2>/dev/null || dnf install -y nginx &>/dev/null
    else
        echo "[+] Instalando Nginx desde DNF..."; dnf install -y nginx &>/dev/null
    fi

    local docroot="/var/www/html"
    mkdir -p "$docroot"
    local puerto_visual=$([[ "$ssl" == "S" ]] && echo "$puerto_https" || echo "$puerto_http")
    _generar_index "$docroot" "Nginx" "$ssl" "$puerto_visual"
    chcon -R -t httpd_sys_content_t "$docroot" 2>/dev/null

    [[ -f /etc/nginx/conf.d/default.conf ]] && \
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled 2>/dev/null
    rm -f /etc/nginx/conf.d/reprobados*.conf

    if [[ "$ssl" == "S" ]]; then
        generar_ssl "nginx" || return 1
        local dir="$_DIR_SSL"
        [[ "$puerto_https" != "443" ]] && semanage port -a -t http_port_t -p tcp "$puerto_https" 2>/dev/null
        [[ "$puerto_http"  != "80"  ]] && semanage port -a -t http_port_t -p tcp "$puerto_http"  2>/dev/null

        cat > /etc/nginx/conf.d/reprobados.conf << NGINXCONF
server {
    listen ${puerto_http};
    server_name www.reprobados.com reprobados.com _;
    return 301 https://\$host\$request_uri;
}
server {
    listen ${puerto_https} ssl;
    server_name www.reprobados.com reprobados.com _;
    root ${docroot};
    index index.html;
    ssl_certificate     ${dir}/server.crt;
    ssl_certificate_key ${dir}/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    server_tokens off;
    location / { try_files \$uri \$uri/ =404; }
}
NGINXCONF

        firewall-cmd --permanent --add-port="${puerto_https}/tcp" &>/dev/null
        firewall-cmd --permanent --add-port="${puerto_http}/tcp"  &>/dev/null
        firewall-cmd --reload &>/dev/null
        RESUMEN_INSTALACIONES+=("[OK] Nginx HTTPS:${puerto_https}  HTTP:${puerto_http}->redireccion")
    else
        [[ "$puerto_http" != "80" ]] && semanage port -a -t http_port_t -p tcp "$puerto_http" 2>/dev/null
        cat > /etc/nginx/conf.d/reprobados.conf << NGINXCONF
server {
    listen ${puerto_http};
    server_name www.reprobados.com reprobados.com _;
    root ${docroot};
    index index.html;
    server_tokens off;
    location / { try_files \$uri \$uri/ =404; }
}
NGINXCONF
        firewall-cmd --permanent --add-port="${puerto_http}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        RESUMEN_INSTALACIONES+=("[OK] Nginx HTTP:${puerto_http}")
    fi

    nginx -t &>/dev/null || { echo "[!] Error en nginx.conf:"; nginx -t; return 1; }
    systemctl enable nginx --now &>/dev/null
    systemctl restart nginx
    if systemctl is-active --quiet nginx; then
        local IP; IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        echo "[OK] Nginx activo."
        [[ "$ssl" == "S" ]] && \
            echo "     -> https://$IP:${puerto_https}  o  https://www.reprobados.com" || \
            echo "     -> http://$IP:${puerto_http}"
    else
        echo "[!] Nginx no inicio:"; journalctl -u nginx -n 10 --no-pager
    fi
}

# -----------------------------------------------------------------------------
# TOMCAT
# FIX 1: certificado con SAN (IP + dominio)
# FIX 2: index.html con printf (sin bug de encoding)
# FIX 3: server.xml sin-SSL usaba EOF mal cerrado — ahora usa TOMCATXML
# -----------------------------------------------------------------------------
instalar_tomcat() {
    local archivo=$1 web_ftp=$2 ssl=$3
    local puerto_http=8080 puerto_https=8443

    if [[ "$ssl" == "S" ]]; then
        while true; do
            read -p "[?] Puerto HTTPS para Tomcat (default 8443): " p < /dev/tty > /dev/tty
            p="${p:-8443}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_https=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
        while true; do
            read -p "[?] Puerto HTTP redireccion (default 8080): " p < /dev/tty > /dev/tty
            p="${p:-8080}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_http=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
    else
        while true; do
            read -p "[?] Puerto HTTP para Tomcat (default 8080): " p < /dev/tty > /dev/tty
            p="${p:-8080}"; [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p < 65536 )) && { puerto_http=$p; break; }
            echo "[!] Puerto invalido." >&2
        done
    fi

    liberar_puertos_web

    if ! java -version &>/dev/null 2>&1; then
        echo "[+] Instalando Java (OpenJDK 17)..."
        dnf install -y java-17-openjdk &>/dev/null
    fi

    if [[ "$web_ftp" == "FTP" && -n "$archivo" && -f "$archivo" ]]; then
        echo "[+] Instalando Tomcat desde RPM: $archivo"
        rpm -Uvh --force "$archivo" 2>/dev/null || dnf install -y tomcat &>/dev/null
    else
        echo "[+] Instalando Tomcat desde DNF..."; dnf install -y tomcat &>/dev/null
    fi

    local webapp="/var/lib/tomcat/webapps/ROOT"
    mkdir -p "$webapp"
    local puerto_visual=$([[ "$ssl" == "S" ]] && echo "$puerto_https" || echo "$puerto_http")
    _generar_index "$webapp" "Tomcat" "$ssl" "$puerto_visual"
    chown -R tomcat:tomcat /var/lib/tomcat/webapps
    chcon -R -t tomcat_var_lib_t /var/lib/tomcat/webapps 2>/dev/null

    if [[ "$ssl" == "S" ]]; then
        generar_ssl "tomcat" || return 1
        local dir="$_DIR_SSL"
        local ks="/etc/ssl/tomcat/keystore.p12"
        mkdir -p /etc/ssl/tomcat
        openssl pkcs12 -export \
            -in "$dir/server.crt" -inkey "$dir/server.key" \
            -out "$ks" -name tomcat -password pass:reprobados 2>/dev/null
        chown tomcat:tomcat "$ks"; chmod 640 "$ks"
        cp /etc/tomcat/server.xml /etc/tomcat/server.xml.bak 2>/dev/null

        cat > /etc/tomcat/server.xml << TOMCATXML
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="${puerto_http}" protocol="HTTP/1.1"
               connectionTimeout="20000" redirectPort="${puerto_https}" />
    <Connector port="${puerto_https}"
               protocol="org.apache.coyote.http11.Http11NioProtocol"
               maxThreads="150" SSLEnabled="true">
      <SSLHostConfig>
        <Certificate certificateKeystoreFile="${ks}" type="RSA"
                     certificateKeystorePassword="reprobados" />
      </SSLHostConfig>
    </Connector>
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true" />
    </Engine>
  </Service>
</Server>
TOMCATXML

        firewall-cmd --permanent --add-port="${puerto_http}/tcp"  &>/dev/null
        firewall-cmd --permanent --add-port="${puerto_https}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        semanage port -a -t http_port_t -p tcp "$puerto_https" 2>/dev/null
        RESUMEN_INSTALACIONES+=("[OK] Tomcat HTTPS:${puerto_https}  HTTP:${puerto_http}")
    else
        cp /etc/tomcat/server.xml /etc/tomcat/server.xml.bak 2>/dev/null
        cat > /etc/tomcat/server.xml << TOMCATXML
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="${puerto_http}" protocol="HTTP/1.1" connectionTimeout="20000" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true" />
    </Engine>
  </Service>
</Server>
TOMCATXML
        firewall-cmd --permanent --add-port="${puerto_http}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        RESUMEN_INSTALACIONES+=("[OK] Tomcat HTTP:${puerto_http}")
    fi

    systemctl enable tomcat --now &>/dev/null
    systemctl restart tomcat
    echo "[*] Esperando que Tomcat levante (hasta 25s)..."
    local i=0
    while [ $i -lt 25 ]; do
        sleep 1
        ss -tuln 2>/dev/null | awk '{print $5}' | grep -qE ":${puerto_visual}$" && break
        ((i++))
    done
    if systemctl is-active --quiet tomcat; then
        local IP; IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        echo "[OK] Tomcat activo."
        [[ "$ssl" == "S" ]] && \
            echo "     -> https://$IP:${puerto_https}  o  https://www.reprobados.com:${puerto_https}" || \
            echo "     -> http://$IP:${puerto_http}"
    else
        echo "[!] Tomcat no inicio:"; journalctl -u tomcat -n 15 --no-pager
    fi
}

# -----------------------------------------------------------------------------
# VSFTPD
# -----------------------------------------------------------------------------
instalar_vsftpd() {
    local archivo=$1 web_ftp=$2 ssl=$3
    if [[ "$web_ftp" == "FTP" && -n "$archivo" && -f "$archivo" ]]; then
        echo "[+] Instalando vsftpd desde RPM: $archivo"
        rpm -Uvh --force "$archivo" 2>/dev/null || dnf install -y vsftpd &>/dev/null
    else
        echo "[+] Instalando vsftpd desde DNF..."; dnf install -y vsftpd &>/dev/null
    fi
    grep -q "/sbin/nologin" /etc/shells || echo "/sbin/nologin" >> /etc/shells
    mkdir -p /srv/ftp/{general,groups/reprobados,groups/recursadores,anonymous/general}
    for g in reprobados recursadores ftp-users; do groupadd -f "$g" 2>/dev/null; done

    if [[ "$ssl" == "S" ]]; then
        generar_ssl "vsftpd" || return 1
        local dir="$_DIR_SSL"
        mkdir -p /etc/vsftpd/ssl
        cp "$dir/server.crt" /etc/vsftpd/ssl/vsftpd.crt
        cp "$dir/server.key" /etc/vsftpd/ssl/vsftpd.key
        chmod 600 /etc/vsftpd/ssl/vsftpd.key
        cat > /etc/vsftpd/vsftpd.conf << 'VSFTPDCONF'
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
listen=YES
listen_ipv6=NO
pam_service_name=vsftpd
userlist_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
check_shell=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40010
listen_port=990
implicit_ssl=YES
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
rsa_cert_file=/etc/vsftpd/ssl/vsftpd.crt
rsa_private_key_file=/etc/vsftpd/ssl/vsftpd.key
VSFTPDCONF
        firewall-cmd --permanent --add-port=990/tcp         &>/dev/null
        firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        setsebool -P ftpd_full_access on &>/dev/null
        semanage port -a -t ftp_port_t -p tcp 990 2>/dev/null
        RESUMEN_INSTALACIONES+=("[OK] vsftpd FTPS (SSL implicito) puerto 990")
    else
        cat > /etc/vsftpd/vsftpd.conf << 'VSFTPDCONF'
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
anon_root=/srv/ftp/anonymous
no_anon_password=YES
anon_world_readable_only=YES
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
listen=YES
listen_ipv6=NO
pam_service_name=vsftpd
userlist_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
check_shell=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40010
VSFTPDCONF
        firewall-cmd --permanent --add-service=ftp          &>/dev/null
        firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        setsebool -P ftpd_full_access on &>/dev/null
        RESUMEN_INSTALACIONES+=("[OK] vsftpd FTP plano puerto 21")
    fi
    systemctl enable vsftpd --now &>/dev/null
    systemctl restart vsftpd
    systemctl is-active --quiet vsftpd \
        && echo "[OK] vsftpd activo." \
        || { echo "[!] vsftpd no inicio:"; journalctl -u vsftpd -n 10 --no-pager; }
}

# =============================================================================
# BLOQUE 6: RESUMEN FINAL
# =============================================================================

verificar_resumen() {
    local IP; IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    echo ""
    echo "======================================================"
    echo "       RESUMEN DE INSTALACIONES - PRACTICA 7"
    echo "======================================================"
    [ ${#RESUMEN_INSTALACIONES[@]} -eq 0 ] \
        && echo "  (Sin instalaciones en esta sesion)" \
        || for r in "${RESUMEN_INSTALACIONES[@]}"; do echo "  $r"; done
    echo ""
    echo "  Estado actual de servicios:"
    for svc in httpd nginx tomcat vsftpd; do
        printf "    %-10s -> %s\n" "$svc" "$(systemctl is-active $svc 2>/dev/null || echo 'no instalado')"
    done
    echo ""
    echo "  IP del servidor: $IP"
    echo "  Puertos en escucha (activos):"
    ss -tuln 2>/dev/null | grep LISTEN | awk '{print $5}' \
        | grep -v '127.0.0.1' | sort -u \
        | while read -r p; do printf "    %s\n" "$p"; done
    echo "======================================================"
}