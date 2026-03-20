#!/bin/bash

FTP_SERVER="192.168.56.104"
FTP_USER="chofis"
FTP_PASS="3006"
RESUMEN_INSTALACIONES=()

listar_versiones_ftp() {
    local servicio=$1
    echo "Buscando instaladores de $servicio en /http/Linux/$servicio/ ..." > /dev/tty
    mapfile -t versiones < <(curl -s -l -u "$FTP_USER:$FTP_PASS" "ftp://$FTP_SERVER/http/Linux/$servicio/" | grep -v '\.sha256$' | grep -v '\.md5$')
    if [ ${#versiones[@]} -eq 0 ]; then
        echo "No se encontraron versiones." > /dev/tty
        echo "INVALIDO"
        return 1
    fi
    echo "Versiones encontradas:" > /dev/tty
    for i in "${!versiones[@]}"; do echo "$((i + 1))) ${versiones[$i]}" > /dev/tty; done
    echo "0) Regresar" > /dev/tty
    local sel_ver
    read -p "Selecciona la version: " sel_ver < /dev/tty > /dev/tty
    if [[ "$sel_ver" == "0" ]]; then echo "REGRESAR"
    elif [[ "$sel_ver" =~ ^[0-9]+$ ]] && [ "$sel_ver" -ge 1 ] && [ "$sel_ver" -le "${#versiones[@]}" ]; then
        echo "${versiones[$((sel_ver-1))]}"
    else echo "INVALIDO"; fi
}

descargar_y_validar_hash() {
    local servicio=$1
    local archivo=$2
    local ruta="ftp://$FTP_SERVER/http/Linux/$servicio/"
    cd /tmp || exit 1
    curl -s -u "$FTP_USER:$FTP_PASS" -O "${ruta}${archivo}"
    curl -s -u "$FTP_USER:$FTP_PASS" -O "${ruta}${archivo}.sha256"
    if [[ -f "${archivo}.sha256" ]]; then
        local hash_remoto=$(cat "${archivo}.sha256" | awk '{print $1}')
        local hash_local=$(sha256sum "$archivo" | awk '{print $1}')
        if [ "$hash_remoto" != "$hash_local" ]; then
            echo "ERROR DE INTEGRIDAD: El hash no coincide." > /dev/tty
            return 1
        fi
    fi
}

preguntar_ssl() {
    while true; do
        local resp
        read -p "Desea activar SSL en este servicio? [S/N] (o '0' para regresar): " resp < /dev/tty > /dev/tty
        if [[ "$resp" =~ ^[sS]$ ]]; then echo "S"; return; fi
        if [[ "$resp" =~ ^[nN]$ ]]; then echo "N"; return; fi
        if [[ "$resp" == "0" ]]; then echo "REGRESAR"; return; fi
    done
}

generar_ssl() {
    local servicio=$1
    local cert_dir="/etc/ssl/$servicio"
    sudo mkdir -p "$cert_dir"
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$cert_dir/server.key" -out "$cert_dir/server.crt" \
        -subj "/C=MX/ST=Sinaloa/L=Los Mochis/O=Reprobados/CN=www.reprobados.com" > /dev/null 2>&1
    echo "$cert_dir"
}

liberar_puertos_web() {
    echo "Liberando puertos y limpiando entorno..."
    sudo systemctl stop apache2 > /dev/null 2>&1
    sudo systemctl stop nginx > /dev/null 2>&1
    sudo systemctl stop tomcat10 > /dev/null 2>&1
    sudo rm -rf /var/www/html/*
    sudo mkdir -p /var/www/html
}

actualizar_index_visual() {
    local servidor=$1
    local ssl_status=$2
    local color="red"; local msg="SITIO NO SEGURO (HTTP)"; local puerto="80"
    if [[ "$ssl_status" == "S" ]]; then
        color="green"; msg="SITIO SEGURO (HTTPS)"; puerto="443"
    fi
    sudo bash -c "cat > /var/www/html/index.html" <<EOF
<html>
<body style='font-family: sans-serif; text-align: center; padding: 50px;'>
    <h1 style='color: $color;'>Servicio activo: $servidor</h1>
    <h2 style='background: $color; color: white; padding: 10px;'>$msg</h2>
    <p>Dominio: www.reprobados.com</p>
    <p>Puerto: $puerto</p>
</body>
</html>
EOF
}

instalar_apache() {
    local archivo=$1; local web_ftp=$2; local ssl=$3
    liberar_puertos_web
    [[ "$web_ftp" == "FTP" ]] && descargar_y_validar_hash "Apache" "$archivo"
    sudo apt-get install -y apache2 > /dev/null
    actualizar_index_visual "Apache2" "$ssl"
    if [[ "$ssl" == "S" ]]; then
        sudo a2enmod ssl rewrite headers > /dev/null
        local dir=$(generar_ssl "apache")
        sudo bash -c "cat > /etc/apache2/sites-available/000-default.conf" <<EOF
<VirtualHost *:80>
    ServerName www.reprobados.com
    Redirect permanent / https://www.reprobados.com/
</VirtualHost>
<VirtualHost *:443>
    ServerName www.reprobados.com
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile $dir/server.crt
    SSLCertificateKeyFile $dir/server.key
</VirtualHost>
EOF
    else
        sudo a2dismod ssl > /dev/null 2>&1
        sudo bash -c "cat > /etc/apache2/sites-available/000-default.conf" <<EOF
<VirtualHost *:80>
    ServerName www.reprobados.com
    DocumentRoot /var/www/html
</VirtualHost>
EOF
    fi
    sudo systemctl restart apache2
    RESUMEN_INSTALACIONES+=("Apache -> Completado (SSL: $ssl)")
}

instalar_nginx() {
    local archivo=$1; local web_ftp=$2; local ssl=$3
    liberar_puertos_web
    [[ "$web_ftp" == "FTP" ]] && descargar_y_validar_hash "Nginx" "$archivo"
    sudo apt-get install -y nginx > /dev/null
    actualizar_index_visual "Nginx" "$ssl"
    if [[ "$ssl" == "S" ]]; then
        local dir=$(generar_ssl "nginx")
        sudo bash -c "cat > /etc/nginx/sites-available/default" <<EOF
server {
    listen 80;
    server_name www.reprobados.com;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name www.reprobados.com;
    ssl_certificate $dir/server.crt;
    ssl_certificate_key $dir/server.key;
    root /var/www/html;
    index index.html;
}
EOF
    else
        sudo bash -c "cat > /etc/nginx/sites-available/default" <<EOF
server {
    listen 80;
    server_name www.reprobados.com;
    root /var/www/html;
}
EOF
    fi
    sudo systemctl restart nginx
    RESUMEN_INSTALACIONES+=("Nginx -> Completado (SSL: $ssl)")
}

instalar_tomcat() {
    local archivo=$1; local web_ftp=$2; local ssl=$3
    liberar_puertos_web
    [[ "$web_ftp" == "FTP" ]] && descargar_y_validar_hash "Tomcat" "$archivo"
    
    echo "Instalando Tomcat 10 y dependencias..."
    sudo apt-get update > /dev/null
    sudo apt-get install -y default-jdk tomcat10 authbind > /dev/null
    
    # 1. DETECCION AGRESIVA DE USUARIO
    # Buscamos el usuario que corre el servicio de tomcat10
    local T_USER=$(ps -ef | grep tomcat | grep -v grep | awk '{print $1}' | head -n 1)
    if [ -z "$T_USER" ]; then
        T_USER=$(grep -E '^tomcat' /etc/passwd | cut -d: -f1 | head -n 1)
    fi
    # Si aun asi falla, forzamos tomcat10 que es el estandar en Trixie
    if [ -z "$T_USER" ]; then T_USER="tomcat10"; fi
    
    echo "Configurando Authbind para el usuario: $T_USER"
    sudo mkdir -p /etc/authbind/byport/
    sudo touch /etc/authbind/byport/80 /etc/authbind/byport/443
    # Aplicamos permisos totales a los archivos de puerto para Authbind
    sudo chown $T_USER:$T_USER /etc/authbind/byport/80 /etc/authbind/byport/443
    sudo chmod 755 /etc/authbind/byport/80 /etc/authbind/byport/443
    
    # 2. HABILITAR AUTHBIND EN EL ENTORNO
    if [ -f "/etc/default/tomcat10" ]; then
        sudo sed -i 's/#AUTHBIND=no/AUTHBIND=yes/' /etc/default/tomcat10
    fi

    # 3. PREPARAR CONTENIDO VISUAL
    actualizar_index_visual "Tomcat 10" "$ssl"
    sudo mkdir -p /var/lib/tomcat10/webapps/ROOT
    sudo cp /var/www/html/index.html /var/lib/tomcat10/webapps/ROOT/index.html
    sudo chown -R $T_USER:$T_USER /var/lib/tomcat10/webapps/ROOT

    # 4. CONFIGURACION DE PUERTOS Y SSL (SERVER.XML)
    if [[ "$ssl" == "S" ]]; then
        local dir=$(generar_ssl "tomcat")
        local ks="/etc/ssl/tomcat/keystore.p12"
        # Generar keystore de Java para el SSL
        sudo openssl pkcs12 -export -in "$dir/server.crt" -inkey "$dir/server.key" -out "$ks" -name tomcat -password pass:reprobados -passout pass:reprobados
        sudo chown $T_USER:$T_USER "$ks"
        
        sudo bash -c "cat > /etc/tomcat10/server.xml" <<EOF
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="80" protocol="HTTP/1.1" connectionTimeout="20000" redirectPort="443" />
    <Connector port="443" protocol="org.apache.coyote.http11.Http11NioProtocol" maxThreads="150" SSLEnabled="true">
      <SSLHostConfig><Certificate certificateKeystoreFile="$ks" type="RSA" certificateKeystorePassword="reprobados" /></SSLHostConfig>
    </Connector>
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true" />
    </Engine>
  </Service>
</Server>
EOF
    else
        sudo bash -c "cat > /etc/tomcat10/server.xml" <<EOF
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="80" protocol="HTTP/1.1" connectionTimeout="20000" />
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true" />
    </Engine>
  </Service>
</Server>
EOF
    fi

    echo "Reiniciando Tomcat 10 y esperando arranque..."
    sudo systemctl restart tomcat10
    # Esperamos 10 segundos a que Java levante el puerto
    sleep 10
    RESUMEN_INSTALACIONES+=("Tomcat 10 -> Completado (SSL: $ssl)")
}

instalar_vsftpd() {
    local archivo=$1; local web_ftp=$2; local ssl=$3
    echo "Integrando logica de directorios con el tunel FTPS..." > /dev/tty
    
    [[ "$web_ftp" == "FTP" ]] && descargar_y_validar_hash "vsftpd" "$archivo"
    sudo apt-get install -y vsftpd openssl > /dev/null

    # Asegurar que el usuario tenga una Shell valida
    if ! grep -q "/bin/bash" /etc/shells; then
        sudo bash -c "echo /bin/bash >> /etc/shells"
    fi

    # Preparar estructura de carpetas de tu mainFTP.sh por precaucion
    sudo mkdir -p /srv/ftp/{anon,autenticados,grupos/general,grupos/reprobados,grupos/recursadores}

    # Configuracion de Certificados
    sudo mkdir -p /etc/vsftpd/ssl
    if [[ "$ssl" == "S" ]]; then
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/vsftpd/ssl/vsftpd.key -out /etc/vsftpd/ssl/vsftpd.crt \
            -subj "/C=MX/ST=Sinaloa/L=Los Mochis/O=Reprobados/CN=www.reprobados.com" > /dev/null 2>&1
    fi

    # Escribimos el vsftpd.conf fusionando tu logica y el SSL
    sudo bash -c 'cat > /etc/vsftpd.conf' <<EOF
# Configuracion base y logica de tu mainFTP.sh
local_enable=YES
write_enable=YES
local_umask=002
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
listen=YES
listen_ipv6=NO
pam_service_name=vsftpd

# Logica de enrutamiento y permisos de tu script (CRUCIAL)
user_sub_token=\$USER
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=/srv/ftp/autenticados/\$USER

# Modo Pasivo
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
pasv_address=192.168.56.104
EOF

    if [[ "$ssl" == "S" ]]; then
        sudo bash -c 'cat >> /etc/vsftpd.conf' <<EOF
# Configuracion del Tunel FTPS
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
    else
        sudo bash -c 'cat >> /etc/vsftpd.conf' <<EOF
# Configuracion para anónimos (Solo si no hay SSL)
anonymous_enable=YES
anon_root=/srv/ftp/anon
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO
EOF
    fi

    # Apertura de Firewall
    sudo ufw allow 20/tcp > /dev/null
    sudo ufw allow 21/tcp > /dev/null
    sudo ufw allow 990/tcp > /dev/null
    sudo ufw allow 40000:50000/tcp > /dev/null
    sudo ufw reload > /dev/null

    sudo systemctl restart vsftpd
    RESUMEN_INSTALACIONES+=("vsftpd -> Completado (SSL: $ssl)")
}
verificar_resumen() {
    echo "=========================================================="
    echo "             RESUMEN AUTOMATIZADO DE SERVICIOS            "
    echo "=========================================================="
    for r in "${RESUMEN_INSTALACIONES[@]}"; do echo "-> $r"; done
}
navegar_y_descargar_ftp() {
    local ftp_user="linux"
    local ftp_pass="1234"
    local ip_servidor="192.168.56.104"
    local base_path="/http/Linux"
    local url_base="ftps://$ip_servidor$base_path/"
    local dir_descargas="/tmp/descargas_ftp"

    mkdir -p "$dir_descargas"

    echo "-------------------------------------------------"
    echo " PASO 1: Conectando al FTP (Ruta: $base_path)"
    echo " Listando las carpetas de servicios disponibles..."
    echo "-------------------------------------------------"

    # Aqui usamos curl de forma no interactiva para listar las carpetas
    mapfile -t carpetas_servicios < <(curl -s -l --insecure -u "$ftp_user:$ftp_pass" "$url_base")

    if [ ${#carpetas_servicios[@]} -eq 0 ]; then
        echo "Error: No se encontraron carpetas en el repositorio."
        return 1
    fi

    for i in "${!carpetas_servicios[@]}"; do
        servicio=$(echo "${carpetas_servicios[$i]}" | tr -d '\r')
        echo "$((i+1))) $servicio"
    done

    # Cumpliendo: "permitir la seleccion"
    read -p "Selecciona el numero de la carpeta a entrar: " sel_serv
    local index_serv=$((sel_serv-1))
    local servicio_elegido=$(echo "${carpetas_servicios[$index_serv]}" | tr -d '\r')

    local url_versiones="$url_base$servicio_elegido/"

    echo "-------------------------------------------------"
    echo " PASO 2: Entrando a la carpeta /$servicio_elegido"
    echo " Listando los archivos binarios (.deb, .tar.gz)..."
    echo "-------------------------------------------------"

    # Cumpliendo: "entrar a esa carpeta, listar los archivos binarios"
    mapfile -t archivos_versiones < <(curl -s -l --insecure -u "$ftp_user:$ftp_pass" "$url_versiones" | grep -v '\.sha256$')

    if [ ${#archivos_versiones[@]} -eq 0 ]; then
        echo "No se encontraron archivos binarios en esta ruta."
        return 1
    fi

    for i in "${!archivos_versiones[@]}"; do
        archivo=$(echo "${archivos_versiones[$i]}" | tr -d '\r')
        echo "$((i+1))) $archivo"
    done

    # Cumpliendo: "descargar la version elegida"
    read -p "Selecciona la version binaria a descargar: " sel_ver
    local index_ver=$((sel_ver-1))
    local archivo_elegido=$(echo "${archivos_versiones[$index_ver]}" | tr -d '\r')

    echo "-------------------------------------------------"
    echo " PASO 3: Descargando version elegida y validando..."
    echo "-------------------------------------------------"

    curl -s --show-error --insecure -u "$ftp_user:$ftp_pass" "$url_versiones$archivo_elegido" -o "$dir_descargas/$archivo_elegido"
    curl -s --show-error --insecure -u "$ftp_user:$ftp_pass" "$url_versiones$archivo_elegido.sha256" -o "$dir_descargas/$archivo_elegido.sha256"

    cd "$dir_descargas" || return 1
    if sha256sum -c "$archivo_elegido.sha256" > /dev/null 2>&1; then
        echo "Validacion SHA256 exitosa."
        echo "Procediendo a la instalacion manual/silenciosa..."
        PAQUETE_DESCARGADO="$dir_descargas/$archivo_elegido"
        cd - > /dev/null || return 1
        return 0
    else
        echo "Error: El archivo binario esta corrupto o incompleto."
        cd - > /dev/null || return 1
        return 1
    fi
}