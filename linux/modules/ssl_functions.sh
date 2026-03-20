#!/bin/bash
# =============================================================================
# ssl_functions.sh — Funciones de instalación SSL/TLS para Fedora Server 42
# Práctica 7: Infraestructura de Despliegue Seguro
# =============================================================================
# DIFERENCIAS CON LA VERSIÓN DEBIAN:
#   - apt-get      → dnf
#   - apache2      → httpd
#   - tomcat10     → tomcat
#   - a2enmod      → edición directa de httpd.conf
#   - ufw          → firewall-cmd
#   - /etc/apache2 → /etc/httpd
#   - authbind     → no existe en Fedora, usamos SELinux + firewalld
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURACIÓN GLOBAL
# Ajusta estas variables según tu entorno real
# ─────────────────────────────────────────────────────────────────────────────
FTP_SERVER="192.168.56.101"   # IP del servidor FTP (Práctica 5)
FTP_USER="danger"             # Usuario FTP del repositorio privado
FTP_PASS="Gerardo1234!!"               # Contraseña FTP
RESUMEN_INSTALACIONES=()      # Arreglo para el resumen final


# =============================================================================
# BLOQUE 1: CLIENTE FTP DINÁMICO
# Navega por /http/Linux/<Servicio>/ y descarga el instalador elegido
# =============================================================================

# -----------------------------------------------------------------------------
# listar_versiones_ftp <servicio>
# Conecta al FTP, lista archivos en /http/Linux/<servicio>/ y
# devuelve el nombre del archivo elegido.
# El resultado queda en la variable global $_ARCHIVO_ELEGIDO
# -----------------------------------------------------------------------------
listar_versiones_ftp() {
    local servicio=$1
    local url_base="ftp://$FTP_SERVER/http/Linux/$servicio/"

    echo "Buscando instaladores de $servicio en $url_base ..." > /dev/tty

    # curl -l lista solo los nombres de archivos (no fechas ni tamaños)
    # -s = silencioso (sin barra de progreso)
    # grep -v filtra los archivos .sha256 y .md5 para no mostrarlos como opciones
    mapfile -t versiones < <(
        curl -s -l \
             --ftp-ssl-reqd \
             -u "$FTP_USER:$FTP_PASS" \
             "$url_base" 2>/dev/null \
        | grep -v '\.sha256$' \
        | grep -v '\.md5$'
    )

    # Si no hay archivos, intentar sin SSL (por si el FTP no tiene FTPS)
    if [ ${#versiones[@]} -eq 0 ]; then
        mapfile -t versiones < <(
            curl -s -l \
                 -u "$FTP_USER:$FTP_PASS" \
                 "$url_base" 2>/dev/null \
            | grep -v '\.sha256$' \
            | grep -v '\.md5$'
        )
    fi

    if [ ${#versiones[@]} -eq 0 ]; then
        echo "[!] No se encontraron archivos en: $url_base" > /dev/tty
        echo "[!] Verifica:" > /dev/tty
        echo "    1. Que el servidor FTP esté corriendo (systemctl status vsftpd)" > /dev/tty
        echo "    2. Que la ruta /http/Linux/$servicio/ exista" > /dev/tty
        echo "    3. Que el usuario $FTP_USER tenga acceso a esa carpeta" > /dev/tty
        _ARCHIVO_ELEGIDO="INVALIDO"
        return 1
    fi

    echo "Versiones encontradas:" > /dev/tty
    for i in "${!versiones[@]}"; do
        echo "  $((i + 1))) ${versiones[$i]}" > /dev/tty
    done
    echo "  0) Regresar" > /dev/tty

    local sel_ver
    read -p "Selecciona la versión: " sel_ver < /dev/tty > /dev/tty

    if [[ "$sel_ver" == "0" ]]; then
        _ARCHIVO_ELEGIDO="REGRESAR"
        return 0
    elif [[ "$sel_ver" =~ ^[0-9]+$ ]] \
      && [ "$sel_ver" -ge 1 ] \
      && [ "$sel_ver" -le "${#versiones[@]}" ]; then
        _ARCHIVO_ELEGIDO="${versiones[$((sel_ver-1))]}"
        return 0
    else
        echo "[!] Selección inválida." > /dev/tty
        _ARCHIVO_ELEGIDO="INVALIDO"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# descargar_y_validar_hash <servicio> <nombre_archivo>
# Descarga el archivo y su .sha256 desde el FTP
# Verifica la integridad antes de continuar
# El archivo queda en /tmp/<nombre_archivo>
# -----------------------------------------------------------------------------
descargar_y_validar_hash() {
    local servicio=$1
    local archivo=$2
    local url_base="ftp://$FTP_SERVER/http/Linux/$servicio/"
    local destino="/tmp"

    echo "[+] Descargando $archivo desde el FTP..."
    cd "$destino" || return 1

    # Intentar con FTPS primero, luego sin cifrado
    if ! curl -s --show-error --ftp-ssl-reqd \
              -u "$FTP_USER:$FTP_PASS" \
              -O "${url_base}${archivo}" 2>/dev/null; then
        curl -s --show-error \
             -u "$FTP_USER:$FTP_PASS" \
             -O "${url_base}${archivo}" \
        || { echo "[!] Error al descargar $archivo"; return 1; }
    fi

    echo "[+] Descargando archivo de hash ($archivo.sha256)..."
    if ! curl -s --show-error --ftp-ssl-reqd \
              -u "$FTP_USER:$FTP_PASS" \
              -O "${url_base}${archivo}.sha256" 2>/dev/null; then
        curl -s --show-error \
             -u "$FTP_USER:$FTP_PASS" \
             -O "${url_base}${archivo}.sha256" \
        || { echo "[!] Error al descargar el hash"; return 1; }
    fi

    # Verificar integridad
    if [[ -f "$destino/${archivo}.sha256" ]]; then
        echo "[+] Verificando integridad SHA256..."

        # El archivo .sha256 puede tener formato:
        #   <hash>  <nombre_archivo>   (sha256sum -c lo entiende)
        # O solo:
        #   <hash>
        # Manejamos ambos casos:
        local hash_remoto
        hash_remoto=$(awk '{print $1}' "$destino/${archivo}.sha256")

        local hash_local
        hash_local=$(sha256sum "$destino/$archivo" | awk '{print $1}')

        if [[ "$hash_remoto" == "$hash_local" ]]; then
            echo "[OK] Integridad verificada: SHA256 coincide."
        else
            echo "[!] ERROR DE INTEGRIDAD: el archivo fue corrompido durante la transferencia."
            echo "    Hash esperado : $hash_remoto"
            echo "    Hash calculado: $hash_local"
            rm -f "$destino/$archivo" "$destino/${archivo}.sha256"
            return 1
        fi
    else
        echo "[!] Advertencia: no se encontró archivo .sha256. Continuando sin verificar."
    fi

    echo "[OK] Archivo listo en: $destino/$archivo"
    _RUTA_ARCHIVO="$destino/$archivo"
    return 0
}


# =============================================================================
# BLOQUE 2: GENERACIÓN DE CERTIFICADOS SSL
# =============================================================================

# -----------------------------------------------------------------------------
# preguntar_ssl
# Pregunta si se desea activar SSL. Resultado en $_SSL_ACTIVO ("S" o "N")
# -----------------------------------------------------------------------------
preguntar_ssl() {
    while true; do
        local resp
        read -p "¿Desea activar SSL en este servicio? [S/N]: " resp < /dev/tty > /dev/tty
        case "${resp^^}" in
            S) _SSL_ACTIVO="S"; return 0 ;;
            N) _SSL_ACTIVO="N"; return 0 ;;
            *) echo "[!] Responde S o N." ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# generar_ssl <nombre_servicio>
# Genera certificado autofirmado para www.reprobados.com
# Los archivos quedan en /etc/ssl/<nombre_servicio>/
# Resultado (ruta del directorio) en $_DIR_SSL
# -----------------------------------------------------------------------------
generar_ssl() {
    local servicio=$1
    local cert_dir="/etc/ssl/$servicio"

    mkdir -p "$cert_dir"

    echo "[+] Generando certificado SSL para www.reprobados.com..."

    # openssl req -x509 : crear certificado autofirmado
    # -nodes            : sin contraseña en la clave privada
    # -days 365         : válido por 1 año
    # -newkey rsa:2048  : clave RSA de 2048 bits
    # -subj             : datos del certificado sin prompt interactivo
    openssl req -x509 \
                -nodes \
                -days 365 \
                -newkey rsa:2048 \
                -keyout "$cert_dir/server.key" \
                -out    "$cert_dir/server.crt" \
                -subj "/C=MX/ST=Sinaloa/L=Los Mochis/O=Reprobados/CN=www.reprobados.com" \
                2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo "[OK] Certificado generado en: $cert_dir"
        echo "     → Clave:       $cert_dir/server.key"
        echo "     → Certificado: $cert_dir/server.crt"
        chmod 600 "$cert_dir/server.key"  # Solo root puede leer la clave privada
        chmod 644 "$cert_dir/server.crt"
    else
        echo "[!] Error al generar el certificado SSL."
        return 1
    fi

    _DIR_SSL="$cert_dir"
    return 0
}


# =============================================================================
# BLOQUE 3: PÁGINA DE ESTADO VISUAL
# =============================================================================

# -----------------------------------------------------------------------------
# actualizar_index_visual <servidor> <ssl_activo>
# Crea un index.html que muestra si el sitio es HTTP o HTTPS
# -----------------------------------------------------------------------------
actualizar_index_visual() {
    local servidor=$1
    local ssl_status=$2

    local color="red"
    local msg="SITIO NO SEGURO (HTTP)"
    local puerto="80"

    if [[ "$ssl_status" == "S" ]]; then
        color="green"
        msg="SITIO SEGURO (HTTPS)"
        puerto="443"
    fi

    # En Fedora el DocumentRoot de httpd es /var/www/html
    # Para nginx también
    local docroot="/var/www/html"
    mkdir -p "$docroot"

    cat > "$docroot/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>$servidor — Práctica 7</title>
</head>
<body style='font-family: sans-serif; text-align: center; padding: 50px;
             background: #1a1a2e; color: white;'>
    <h1 style='color: $color;'>Servicio Activo: $servidor</h1>
    <h2 style='background: $color; color: white; padding: 15px;
               border-radius: 8px;'>$msg</h2>
    <p><strong>Dominio:</strong> www.reprobados.com</p>
    <p><strong>Puerto principal:</strong> $puerto</p>
    <p><strong>Generado por:</strong> Práctica 7 — Fedora Server 42</p>
</body>
</html>
EOF
    echo "[OK] index.html actualizado en $docroot"
}

# Misma función pero apuntando a una ruta personalizada
actualizar_index_en() {
    local ruta=$1
    local servidor=$2
    local ssl_status=$3

    local color="red"; local msg="HTTP"; local puerto="80"
    [[ "$ssl_status" == "S" ]] && { color="green"; msg="HTTPS"; puerto="443"; }

    mkdir -p "$ruta"
    cat > "$ruta/index.html" << EOF
<!DOCTYPE html>
<html>
<body style='font-family:sans-serif;text-align:center;padding:50px;
             background:#1a1a2e;color:white;'>
  <h1 style='color:$color;'>$servidor</h1>
  <h2 style='background:$color;color:white;padding:10px;border-radius:8px;'>$msg</h2>
  <p>www.reprobados.com — Puerto $puerto</p>
</body>
</html>
EOF
}


# =============================================================================
# BLOQUE 4: LIBERAR PUERTOS (LIMPIEZA PREVIA)
# =============================================================================

# En Fedora NO existe ufw. Usamos firewall-cmd y systemctl.
liberar_puertos_web() {
    echo "[+] Liberando puertos web (deteniendo servicios HTTP)..."

    for svc in httpd nginx tomcat; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null
            echo "    [OK] $svc detenido."
        fi
    done

    # Matar procesos residuales
    for proc in httpd nginx java; do
        local pids
        pids=$(pgrep -f "$proc" 2>/dev/null)
        if [[ -n "$pids" ]]; then
            kill -9 $pids 2>/dev/null
            echo "    [OK] Proceso $proc eliminado."
        fi
    done

    sleep 1
    echo "[OK] Puertos web liberados."
}


# =============================================================================
# BLOQUE 5: INSTALADORES (Adaptados para Fedora)
# =============================================================================

# -----------------------------------------------------------------------------
# instalar_apache <archivo_ftp_o_vacio> <fuente: WEB|FTP> <ssl: S|N>
# En Fedora: httpd (no apache2)
# Conf:      /etc/httpd/conf.d/  (no /etc/apache2/sites-available/)
# SSL mod:   edición directa de httpd.conf (no a2enmod)
# -----------------------------------------------------------------------------
instalar_apache() {
    local archivo=$1
    local web_ftp=$2
    local ssl=$3

    liberar_puertos_web

    # ── Instalación del paquete ──────────────────────────────────────────────
    if [[ "$web_ftp" == "FTP" && -n "$archivo" && -f "$archivo" ]]; then
        # Instalación desde RPM descargado por FTP
        echo "[+] Instalando Apache desde RPM: $archivo"
        dnf install -y "$archivo" &>/dev/null \
        || rpm -ivh "$archivo" 2>/dev/null \
        || { echo "[!] No se pudo instalar el RPM. Instalando desde repo..."; dnf install -y httpd &>/dev/null; }
    else
        echo "[+] Instalando Apache (httpd) desde repositorio DNF..."
        dnf install -y httpd mod_ssl &>/dev/null
    fi

    # ── Deshabilitar welcome.conf para no interferir ─────────────────────────
    [[ -f /etc/httpd/conf.d/welcome.conf ]] && \
        mv /etc/httpd/conf.d/welcome.conf \
           /etc/httpd/conf.d/welcome.conf.disabled 2>/dev/null

    # ── Página visual ────────────────────────────────────────────────────────
    actualizar_index_visual "Apache (httpd)" "$ssl"
    chcon -R -t httpd_sys_content_t /var/www/html 2>/dev/null

    # ── Configuración según SSL ──────────────────────────────────────────────
    if [[ "$ssl" == "S" ]]; then
        generar_ssl "apache" || return 1
        local dir="$_DIR_SSL"

        # En Fedora, mod_ssl se activa instalando el paquete mod_ssl
        # y configurando el VirtualHost en /etc/httpd/conf.d/ssl.conf
        # Eliminamos el ssl.conf por defecto y ponemos el nuestro:
        rm -f /etc/httpd/conf.d/ssl.conf

        cat > /etc/httpd/conf.d/reprobados-ssl.conf << EOF
# Redirigir HTTP → HTTPS (HSTS)
<VirtualHost *:80>
    ServerName www.reprobados.com
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>

# VirtualHost HTTPS
<VirtualHost *:443>
    ServerName www.reprobados.com
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile    $dir/server.crt
    SSLCertificateKeyFile $dir/server.key

    # HSTS: decirle al navegador que use HTTPS por 1 año
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

    <Directory "/var/www/html">
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF

        # Habilitar módulos necesarios en httpd.conf
        sed -i 's/#LoadModule ssl_module/LoadModule ssl_module/'         /etc/httpd/conf/httpd.conf 2>/dev/null
        sed -i 's/#LoadModule rewrite_module/LoadModule rewrite_module/' /etc/httpd/conf/httpd.conf 2>/dev/null
        sed -i 's/#LoadModule headers_module/LoadModule headers_module/' /etc/httpd/conf/httpd.conf 2>/dev/null

        # Abrir puerto 443 en firewalld
        firewall-cmd --permanent --add-service=https &>/dev/null
        firewall-cmd --permanent --add-service=http  &>/dev/null
        firewall-cmd --reload &>/dev/null

        # SELinux: permitir Apache en 443
        setsebool -P httpd_can_network_connect 1 &>/dev/null

        RESUMEN_INSTALACIONES+=("[OK] Apache (httpd) con HTTPS en puerto 443 — HSTS activado.")
    else
        # Sin SSL: solo HTTP en 80
        cat > /etc/httpd/conf.d/reprobados.conf << EOF
<VirtualHost *:80>
    ServerName www.reprobados.com
    DocumentRoot /var/www/html
    <Directory "/var/www/html">
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF
        firewall-cmd --permanent --add-service=http &>/dev/null
        firewall-cmd --reload &>/dev/null

        RESUMEN_INSTALACIONES+=("[OK] Apache (httpd) HTTP en puerto 80 — Sin SSL.")
    fi

    # ── Iniciar servicio ─────────────────────────────────────────────────────
    systemctl enable httpd --now &>/dev/null
    systemctl restart httpd

    if systemctl is-active --quiet httpd; then
        echo "[OK] Apache httpd iniciado correctamente."
    else
        echo "[!] Apache no inició. Revisa:"
        journalctl -u httpd -n 10 --no-pager
    fi
}

# -----------------------------------------------------------------------------
# instalar_nginx <archivo_ftp_o_vacio> <fuente: WEB|FTP> <ssl: S|N>
# En Fedora: nginx (igual que en Debian, pero sin apt-get)
# Conf: /etc/nginx/conf.d/  (igual)
# -----------------------------------------------------------------------------
instalar_nginx() {
    local archivo=$1
    local web_ftp=$2
    local ssl=$3

    liberar_puertos_web

    if [[ "$web_ftp" == "FTP" && -n "$archivo" && -f "$archivo" ]]; then
        echo "[+] Instalando Nginx desde RPM: $archivo"
        dnf install -y "$archivo" &>/dev/null \
        || rpm -ivh "$archivo" 2>/dev/null \
        || { echo "[!] Instalando desde repo..."; dnf install -y nginx &>/dev/null; }
    else
        echo "[+] Instalando Nginx desde repositorio DNF..."
        dnf install -y nginx &>/dev/null
    fi

    # Crear directorio de contenido
    local docroot="/var/www/html"
    mkdir -p "$docroot"
    actualizar_index_visual "Nginx" "$ssl"
    chcon -R -t httpd_sys_content_t "$docroot" 2>/dev/null

    # Deshabilitar default.conf
    [[ -f /etc/nginx/conf.d/default.conf ]] && \
        mv /etc/nginx/conf.d/default.conf \
           /etc/nginx/conf.d/default.conf.disabled 2>/dev/null

    if [[ "$ssl" == "S" ]]; then
        generar_ssl "nginx" || return 1
        local dir="$_DIR_SSL"

        # Registrar puerto 443 en SELinux
        semanage port -a -t http_port_t -p tcp 443 2>/dev/null

        cat > /etc/nginx/conf.d/reprobados.conf << EOF
# Redirigir HTTP → HTTPS
server {
    listen 80;
    server_name www.reprobados.com;
    return 301 https://\$host\$request_uri;
}

# HTTPS
server {
    listen 443 ssl;
    server_name www.reprobados.com;
    root $docroot;
    index index.html;

    ssl_certificate     $dir/server.crt;
    ssl_certificate_key $dir/server.key;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Ocultar versión de Nginx
    server_tokens off;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

        firewall-cmd --permanent --add-service=https &>/dev/null
        firewall-cmd --permanent --add-service=http  &>/dev/null
        firewall-cmd --reload &>/dev/null

        RESUMEN_INSTALACIONES+=("[OK] Nginx con HTTPS en puerto 443 — HSTS activado.")
    else
        cat > /etc/nginx/conf.d/reprobados.conf << EOF
server {
    listen 80;
    server_name www.reprobados.com;
    root $docroot;
    index index.html;
    server_tokens off;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        firewall-cmd --permanent --add-service=http &>/dev/null
        firewall-cmd --reload &>/dev/null

        RESUMEN_INSTALACIONES+=("[OK] Nginx HTTP en puerto 80 — Sin SSL.")
    fi

    # Validar configuración
    nginx -t &>/dev/null || { echo "[!] Error en nginx.conf:"; nginx -t; return 1; }

    systemctl enable nginx --now &>/dev/null
    systemctl restart nginx

    systemctl is-active --quiet nginx \
        && echo "[OK] Nginx iniciado correctamente." \
        || { echo "[!] Nginx no inició."; journalctl -u nginx -n 10 --no-pager; }
}

# -----------------------------------------------------------------------------
# instalar_tomcat <archivo_ftp_o_vacio> <fuente: WEB|FTP> <ssl: S|N>
# En Fedora: tomcat (NO tomcat10, NO tomcat9)
# Conf: /etc/tomcat/server.xml
# Webapps: /var/lib/tomcat/webapps/ROOT/
# NOTA: Fedora no tiene authbind. Para puerto 80 se usa firewalld DNAT
#       o simplemente se usa el puerto 8080 y se redirige con firewalld.
# -----------------------------------------------------------------------------
instalar_tomcat() {
    local archivo=$1
    local web_ftp=$2
    local ssl=$3

    liberar_puertos_web

    # Verificar Java
    if ! java -version &>/dev/null 2>&1; then
        echo "[+] Instalando Java (OpenJDK 17)..."
        dnf install -y java-17-openjdk &>/dev/null
    fi

    if [[ "$web_ftp" == "FTP" && -n "$archivo" && -f "$archivo" ]]; then
        echo "[+] Instalando Tomcat desde RPM: $archivo"
        dnf install -y "$archivo" &>/dev/null \
        || rpm -ivh "$archivo" 2>/dev/null \
        || { echo "[!] Instalando desde repo..."; dnf install -y tomcat &>/dev/null; }
    else
        echo "[+] Instalando Tomcat desde repositorio DNF..."
        dnf install -y tomcat &>/dev/null
    fi

    # Página visual
    local webapp="/var/lib/tomcat/webapps/ROOT"
    mkdir -p "$webapp"
    actualizar_index_en "$webapp" "Tomcat" "$ssl"
    chown -R tomcat:tomcat /var/lib/tomcat/webapps
    chcon -R -t tomcat_var_lib_t /var/lib/tomcat/webapps 2>/dev/null

    if [[ "$ssl" == "S" ]]; then
        generar_ssl "tomcat" || return 1
        local dir="$_DIR_SSL"
        local ks="/etc/ssl/tomcat/keystore.p12"

        # Crear keystore PKCS12 a partir del certificado PEM
        # Tomcat necesita el certificado en formato keystore, no PEM directo
        openssl pkcs12 -export \
            -in  "$dir/server.crt" \
            -inkey "$dir/server.key" \
            -out "$ks" \
            -name tomcat \
            -password pass:reprobados \
            2>/dev/null
        chown tomcat:tomcat "$ks"

        # En Fedora el server.xml está en /etc/tomcat/server.xml
        # Hacemos backup y configuramos HTTPS en 8443 + HTTP en 8080
        cp /etc/tomcat/server.xml /etc/tomcat/server.xml.bak 2>/dev/null

        cat > /etc/tomcat/server.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">

    <!-- HTTP en 8080 que redirige a HTTPS -->
    <Connector port="8080"
               protocol="HTTP/1.1"
               connectionTimeout="20000"
               redirectPort="8443" />

    <!-- HTTPS en 8443 con nuestro certificado -->
    <Connector port="8443"
               protocol="org.apache.coyote.http11.Http11NioProtocol"
               maxThreads="150"
               SSLEnabled="true">
      <SSLHostConfig>
        <Certificate certificateKeystoreFile="$ks"
                     type="RSA"
                     certificateKeystorePassword="reprobados" />
      </SSLHostConfig>
    </Connector>

    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps"
            unpackWARs="true" autoDeploy="true" />
    </Engine>
  </Service>
</Server>
EOF

        firewall-cmd --permanent --add-port=8080/tcp &>/dev/null
        firewall-cmd --permanent --add-port=8443/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null

        semanage port -a -t http_port_t -p tcp 8443 2>/dev/null

        RESUMEN_INSTALACIONES+=("[OK] Tomcat con HTTPS en puerto 8443 (HTTP:8080→8443).")
    else
        # Solo HTTP en 8080
        cp /etc/tomcat/server.xml /etc/tomcat/server.xml.bak 2>/dev/null

        cat > /etc/tomcat/server.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="8080"
               protocol="HTTP/1.1"
               connectionTimeout="20000" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps"
            unpackWARs="true" autoDeploy="true" />
    </Engine>
  </Service>
</Server>
EOF

        firewall-cmd --permanent --add-port=8080/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null

        RESUMEN_INSTALACIONES+=("[OK] Tomcat HTTP en puerto 8080 — Sin SSL.")
    fi

    systemctl enable tomcat --now &>/dev/null
    systemctl restart tomcat

    echo "[*] Esperando que Tomcat levante (hasta 20s)..."
    local i=0
    while [ $i -lt 20 ]; do
        sleep 1
        if ss -tuln 2>/dev/null | grep -q ":808"; then break; fi
        ((i++))
    done

    systemctl is-active --quiet tomcat \
        && echo "[OK] Tomcat iniciado correctamente." \
        || { echo "[!] Tomcat no inició."; journalctl -u tomcat -n 10 --no-pager; }
}

# -----------------------------------------------------------------------------
# instalar_vsftpd <archivo_ftp_o_vacio> <fuente: WEB|FTP> <ssl: S|N>
# FTPS = FTP sobre SSL
# En Fedora: configuración en /etc/vsftpd/vsftpd.conf
# SIN authbind (no existe en Fedora)
# -----------------------------------------------------------------------------
instalar_vsftpd() {
    local archivo=$1
    local web_ftp=$2
    local ssl=$3

    if [[ "$web_ftp" == "FTP" && -n "$archivo" && -f "$archivo" ]]; then
        echo "[+] Instalando vsftpd desde RPM: $archivo"
        dnf install -y "$archivo" &>/dev/null \
        || rpm -ivh "$archivo" 2>/dev/null \
        || dnf install -y vsftpd &>/dev/null
    else
        echo "[+] Instalando vsftpd desde repositorio DNF..."
        dnf install -y vsftpd &>/dev/null
    fi

    # Asegurar que /sbin/nologin está en /etc/shells (requerido por vsftpd)
    grep -q "/sbin/nologin" /etc/shells || echo "/sbin/nologin" >> /etc/shells

    # Directorios base del servidor FTP (reutilizando estructura de Práctica 5)
    mkdir -p /srv/ftp/{general,groups/reprobados,groups/recursadores,anonymous/general}
    for g in reprobados recursadores ftp-users; do
        groupadd -f "$g" 2>/dev/null
    done

    if [[ "$ssl" == "S" ]]; then
        # FTPS: FTP sobre SSL
        generar_ssl "vsftpd" || return 1
        local dir="$_DIR_SSL"

        # Copiar certificados a /etc/vsftpd/ssl/
        mkdir -p /etc/vsftpd/ssl
        cp "$dir/server.crt" /etc/vsftpd/ssl/vsftpd.crt
        cp "$dir/server.key" /etc/vsftpd/ssl/vsftpd.key
        chmod 600 /etc/vsftpd/ssl/vsftpd.key

        cat > /etc/vsftpd/vsftpd.conf << 'EOF'
# Configuración base
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES
listen=YES
listen_ipv6=NO
pam_service_name=vsftpd
userlist_enable=YES

# Aislamiento de usuarios
chroot_local_user=YES
allow_writeable_chroot=YES
check_shell=NO

# Modo pasivo
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40010

# FTPS (FTP sobre SSL implícito en puerto 990)
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
EOF

        # Firewall: FTPS usa puerto 990 (no 21)
        firewall-cmd --permanent --add-port=990/tcp  &>/dev/null
        firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null

        # SELinux para FTPS
        setsebool -P ftpd_full_access on &>/dev/null
        semanage port -a -t ftp_port_t -p tcp 990 2>/dev/null

        RESUMEN_INSTALACIONES+=("[OK] vsftpd con FTPS (SSL implícito) en puerto 990.")
    else
        # FTP normal (sin cifrado)
        cat > /etc/vsftpd/vsftpd.conf << 'EOF'
# Configuración base sin SSL
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
anon_root=/srv/ftp/anonymous
no_anon_password=YES
anon_world_readable_only=YES
anon_upload_enable=NO
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
EOF

        firewall-cmd --permanent --add-service=ftp &>/dev/null
        firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        setsebool -P ftpd_full_access on &>/dev/null

        RESUMEN_INSTALACIONES+=("[OK] vsftpd FTP plano en puerto 21 — Sin SSL.")
    fi

    systemctl enable vsftpd --now &>/dev/null
    systemctl restart vsftpd

    systemctl is-active --quiet vsftpd \
        && echo "[OK] vsftpd iniciado correctamente." \
        || { echo "[!] vsftpd no inició."; journalctl -u vsftpd -n 10 --no-pager; }
}


# =============================================================================
# BLOQUE 6: RESUMEN FINAL
# =============================================================================

verificar_resumen() {
    echo ""
    echo "======================================================"
    echo "       RESUMEN AUTOMATIZADO DE INSTALACIONES"
    echo "======================================================"
    if [ ${#RESUMEN_INSTALACIONES[@]} -eq 0 ]; then
        echo "  (Sin instalaciones registradas en esta sesión)"
    else
        for r in "${RESUMEN_INSTALACIONES[@]}"; do
            echo "  $r"
        done
    fi
    echo ""
    echo "  Estado actual de servicios:"
    for svc in httpd nginx tomcat vsftpd; do
        local estado
        estado=$(systemctl is-active "$svc" 2>/dev/null || echo "no instalado")
        printf "    %-10s → %s\n" "$svc" "$estado"
    done
    echo "======================================================"
}