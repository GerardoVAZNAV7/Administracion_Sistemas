#!/bin/bash
# =============================================================================
# setup_repositorio_ftp.sh
# Propósito: Preparar el servidor FTP de Fedora para la Práctica 7
#
# Este script hace TODO lo siguiente:
#   1. Instala vsftpd si no está instalado
#   2. Crea el usuario "danger" con contraseña "Gerardo1234!!"
#   3. Crea la estructura de carpetas del repositorio FTP
#   4. Descarga los archivos RPM necesarios (Apache, Nginx, Tomcat, vsftpd)
#   5. Genera los archivos .sha256 de cada instalador
#   6. Configura vsftpd para que el usuario danger acceda al repositorio
#   7. Abre los puertos en el firewall
#
# USO:
#   sudo bash setup_repositorio_ftp.sh
#
# NOTA SOBRE LAS DESCARGAS:
#   Los archivos se descargan directo de los repositorios oficiales de Fedora.
#   Necesitas conexión a internet para que funcione.
# =============================================================================

set -e   # Si algo falla, el script se detiene inmediatamente

# ── Colores para mensajes ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[*]${NC}  $1"; }
warn() { echo -e "${YELLOW}[!]${NC}  $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Verificar root ───────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    err "Ejecuta como root: sudo bash $0"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   SETUP REPOSITORIO FTP — PRÁCTICA 7 — FEDORA SERVER 42     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# PASO 1: INSTALAR DEPENDENCIAS
# =============================================================================
info "PASO 1: Instalando dependencias..."

dnf install -y vsftpd curl openssl &>/dev/null
ok "vsftpd, curl y openssl instalados."

# =============================================================================
# PASO 2: CREAR USUARIO "danger"
# =============================================================================
info "PASO 2: Creando usuario 'danger'..."

USUARIO="danger"
CONTRASENA="Gerardo1234!!"

# Verificar si ya existe
if id "$USUARIO" &>/dev/null; then
    warn "El usuario '$USUARIO' ya existe. Actualizando contraseña..."
    echo "$USUARIO:$CONTRASENA" | chpasswd
    ok "Contraseña de '$USUARIO' actualizada."
else
    # useradd:
    #   -m  = crear carpeta home (/home/danger)
    #   -s /sbin/nologin = el usuario puede autenticarse en FTP
    #                      pero NO puede abrir una terminal SSH
    #                      (esto es una medida de seguridad)
    useradd -m -s /sbin/nologin "$USUARIO"
    echo "$USUARIO:$CONTRASENA" | chpasswd
    ok "Usuario '$USUARIO' creado con contraseña 'Gerardo1234!!'."
fi

# Agregar /sbin/nologin a /etc/shells
# vsftpd requiere que el shell del usuario esté en /etc/shells
grep -q "/sbin/nologin" /etc/shells || echo "/sbin/nologin" >> /etc/shells
ok "/sbin/nologin registrado en /etc/shells."

# =============================================================================
# PASO 3: CREAR ESTRUCTURA DE CARPETAS DEL REPOSITORIO
# =============================================================================
info "PASO 3: Creando estructura del repositorio FTP..."

# La estructura que necesita mainSSL.sh es:
#   /srv/ftp/http/Linux/Apache/
#   /srv/ftp/http/Linux/Nginx/
#   /srv/ftp/http/Linux/Tomcat/
#   /srv/ftp/http/Linux/vsftpd/
#
# El home de vsftpd con chroot apuntará a /home/danger
# Dentro creamos un symlink/bind mount a /srv/ftp
# para que "danger" vea la estructura completa

REPO_BASE="/srv/ftp/http/Linux"

mkdir -p "$REPO_BASE/Apache"
mkdir -p "$REPO_BASE/Nginx"
mkdir -p "$REPO_BASE/Tomcat"
mkdir -p "$REPO_BASE/vsftpd"

ok "Estructura de carpetas creada en /srv/ftp/http/Linux/"

# El home del usuario danger apuntará a /srv/ftp para que
# cuando se conecte por FTP vea directamente /http/Linux/
# Hacemos que su home SEA /srv/ftp
usermod -d /srv/ftp "$USUARIO"

# Permisos: la carpeta home DEBE ser de root (vsftpd con chroot lo exige)
# Si danger es dueño de /srv/ftp, vsftpd lanza error "500 OOPS: vsftpd: refusing"
chown root:root /srv/ftp
chmod 755       /srv/ftp

# Las carpetas internas sí pueden ser de danger para que pueda subir archivos
chown -R danger:danger "$REPO_BASE"
chmod -R 755            "$REPO_BASE"

ok "Permisos configurados correctamente."

# =============================================================================
# PASO 4: DESCARGAR LOS INSTALADORES
# =============================================================================
# ─────────────────────────────────────────────────────────────────────────────
# ¿DE DÓNDE SE DESCARGAN?
#
# Fedora publica los RPM en el repositorio oficial:
#   https://dl.fedoraproject.org/pub/fedora/linux/releases/42/Everything/x86_64/os/Packages/
#
# También puedes usar dnf download para descargar sin instalar:
#   dnf download httpd       -> descarga el RPM del Apache de tu versión de Fedora
#   dnf download nginx       -> descarga el RPM de Nginx
#   dnf download tomcat      -> descarga el RPM de Tomcat
#   dnf download vsftpd      -> descarga el RPM de vsftpd
#
# Esto es MÁS CONFIABLE que un URL fijo porque dnf ya sabe qué versión
# es compatible con tu sistema.
# ─────────────────────────────────────────────────────────────────────────────

info "PASO 4: Descargando instaladores RPM..."
info "        (Usando 'dnf download' — descarga sin instalar)"

# Directorio temporal para las descargas
TMP_DOWNLOAD="/tmp/practica7_downloads"
mkdir -p "$TMP_DOWNLOAD"

# Función auxiliar para descargar un paquete y moverlo a su carpeta destino
descargar_rpm() {
    local paquete=$1      # nombre del paquete dnf (ej: httpd)
    local destino=$2      # carpeta destino (ej: /srv/ftp/http/Linux/Apache)
    local etiqueta=$3     # nombre para mostrar (ej: Apache)

    info "Descargando $etiqueta ($paquete)..."

    cd "$TMP_DOWNLOAD"

    # dnf download: descarga el RPM sin instalarlo
    # --resolve: incluye las dependencias (útil si quieres instalar offline)
    # Sin --resolve: solo descarga el paquete principal (más limpio para el repo)
    if dnf download "$paquete" --destdir="$TMP_DOWNLOAD" &>/dev/null; then
        # Mover el RPM descargado a la carpeta del repositorio
        local archivo_rpm
        archivo_rpm=$(ls "$TMP_DOWNLOAD"/${paquete}-*.rpm 2>/dev/null | head -1)

        if [[ -n "$archivo_rpm" ]]; then
            mv "$archivo_rpm" "$destino/"
            local nombre_final
            nombre_final=$(basename "$archivo_rpm")
            ok "$etiqueta descargado: $nombre_final"

            # Generar el .sha256
            # sha256sum genera: <hash>  <nombre_archivo>
            # Guardamos solo el hash (primera columna) para mayor compatibilidad
            sha256sum "$destino/$nombre_final" | awk '{print $1}' \
                > "$destino/$nombre_final.sha256"
            ok "Hash SHA256 generado: $nombre_final.sha256"
        else
            warn "No se encontró el RPM de $paquete en $TMP_DOWNLOAD"
            warn "Buscando con nombre alternativo..."
            ls "$TMP_DOWNLOAD/"*.rpm 2>/dev/null | head -5
        fi
    else
        warn "dnf download falló para $paquete. Intentando con curl directo..."
        _descargar_con_curl "$paquete" "$destino" "$etiqueta"
    fi
}

# Función de respaldo: descargar directamente desde el repo de Fedora
# Se usa si dnf download no funciona
_descargar_con_curl() {
    local paquete=$1
    local destino=$2
    local etiqueta=$3

    # Obtener la URL del paquete desde dnf
    local url
    url=$(dnf repoquery --location "$paquete" 2>/dev/null | head -1)

    if [[ -z "$url" ]]; then
        err "No se pudo obtener la URL de $paquete. Verifica tu conexión a internet."
        err "También puedes descargarlo manualmente desde:"
        err "  https://dl.fedoraproject.org/pub/fedora/linux/releases/42/Everything/x86_64/os/Packages/"
        return 1
    fi

    local nombre_archivo
    nombre_archivo=$(basename "$url")

    curl -L -o "$destino/$nombre_archivo" "$url" --progress-bar
    ok "$etiqueta descargado: $nombre_archivo"

    sha256sum "$destino/$nombre_archivo" | awk '{print $1}' \
        > "$destino/$nombre_archivo.sha256"
    ok "Hash SHA256 generado."
}

# ── Descargar cada paquete ───────────────────────────────────────────────────
descargar_rpm "httpd"   "$REPO_BASE/Apache"  "Apache (httpd)"
descargar_rpm "nginx"   "$REPO_BASE/Nginx"   "Nginx"
descargar_rpm "tomcat"  "$REPO_BASE/Tomcat"  "Tomcat"
descargar_rpm "vsftpd"  "$REPO_BASE/vsftpd"  "vsftpd"

# Limpiar temporales
rm -rf "$TMP_DOWNLOAD"
ok "Archivos temporales eliminados."

# =============================================================================
# PASO 5: VERIFICAR LO QUE SE DESCARGÓ
# =============================================================================
info "PASO 5: Verificando contenido del repositorio..."

echo ""
echo "  Contenido del repositorio FTP:"
find /srv/ftp/http -type f | sort | while read -r archivo; do
    local_size=$(du -sh "$archivo" 2>/dev/null | cut -f1)
    printf "    %-60s %s\n" "$archivo" "$local_size"
done
echo ""

# =============================================================================
# PASO 6: CONFIGURAR VSFTPD PARA EL REPOSITORIO
# =============================================================================
info "PASO 6: Configurando vsftpd..."

# Hacer backup del vsftpd.conf actual
[[ -f /etc/vsftpd/vsftpd.conf ]] && \
    cp /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.bak_setup

# ─────────────────────────────────────────────────────────────────────────────
# EXPLICACIÓN de las opciones clave de vsftpd.conf:
#
# anonymous_enable=NO     → Los anónimos NO pueden acceder al repositorio
#                           (solo el usuario "danger" autenticado)
# local_enable=YES        → Permite login con usuarios del sistema Linux
# write_enable=YES        → Permite subir archivos al FTP
#                           (necesario para poder agregar instaladores)
# chroot_local_user=YES   → El usuario queda "encerrado" en su home (/srv/ftp)
#                           No puede navegar hacia / ni ver otros directorios
# allow_writeable_chroot  → Sin esto, vsftpd rechaza el chroot si el home
#                           es escribible. Como /srv/ftp es de root (755),
#                           esta opción no es estrictamente necesaria pero
#                           la dejamos por si acaso.
# pasv_enable=YES         → Modo pasivo: el cliente abre conexiones de datos
#                           (necesario cuando hay NAT/firewall entre cliente y server)
# ─────────────────────────────────────────────────────────────────────────────

cat > /etc/vsftpd/vsftpd.conf << 'VSFTPD_CONF'
# ── Autenticación ────────────────────────────────────────────────────────────
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022

# ── Aislamiento (chroot) ─────────────────────────────────────────────────────
chroot_local_user=YES
allow_writeable_chroot=YES
check_shell=NO

# ── Mensajes y logs ──────────────────────────────────────────────────────────
dirmessage_enable=YES
xferlog_enable=YES
xferlog_std_format=YES
connect_from_port_20=YES

# ── Modo de escucha (IPv4 solamente) ─────────────────────────────────────────
listen=YES
listen_ipv6=NO

# ── Autenticación PAM ────────────────────────────────────────────────────────
pam_service_name=vsftpd
userlist_enable=YES

# ── Modo pasivo (NECESARIO para clientes detrás de NAT/firewall) ─────────────
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40010
# IMPORTANTE: cambia esta IP a la IP real de tu servidor Fedora
# (la IP que ven los clientes desde fuera)
# Si no la pones, los clientes en modo pasivo no podrán transferir datos
# pasv_address=192.168.56.104   # ← descomenta y ajusta si es necesario
VSFTPD_CONF

ok "vsftpd.conf configurado."

# Configurar SELinux para vsftpd
info "Configurando SELinux para vsftpd..."
setsebool -P ftpd_full_access on &>/dev/null
ok "SELinux: ftpd_full_access activado."

# =============================================================================
# PASO 7: ABRIR PUERTOS EN FIREWALL
# =============================================================================
info "PASO 7: Configurando firewall..."

firewall-cmd --permanent --add-service=ftp             &>/dev/null
firewall-cmd --permanent --add-port=40000-40010/tcp    &>/dev/null
firewall-cmd --reload                                  &>/dev/null

ok "Puerto 21 (FTP) abierto."
ok "Puertos 40000-40010 (modo pasivo) abiertos."

# =============================================================================
# PASO 8: INICIAR/REINICIAR VSFTPD
# =============================================================================
info "PASO 8: Iniciando vsftpd..."

systemctl enable vsftpd &>/dev/null
systemctl restart vsftpd

sleep 2

if systemctl is-active --quiet vsftpd; then
    ok "vsftpd está corriendo correctamente."
else
    err "vsftpd NO inició. Revisa el error:"
    journalctl -u vsftpd -n 15 --no-pager
    exit 1
fi

# =============================================================================
# RESUMEN FINAL
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                  SETUP COMPLETADO EXITOSAMENTE                  ║"
echo "╠══════════════════════════════════════════════════════════════════╣"

IP_SERVIDOR=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

echo "║  Usuario FTP : danger                                           ║"
echo "║  Contraseña  : Gerardo1234!!                                    ║"
echo "║  IP Servidor : $IP_SERVIDOR"
echo "║  Puerto FTP  : 21                                               ║"
echo "║                                                                  ║"
echo "║  Estructura del repositorio:                                     ║"
echo "║    /http/Linux/Apache/   ← Instaladores Apache (.rpm)           ║"
echo "║    /http/Linux/Nginx/    ← Instaladores Nginx (.rpm)            ║"
echo "║    /http/Linux/Tomcat/   ← Instaladores Tomcat (.rpm)           ║"
echo "║    /http/Linux/vsftpd/   ← Instaladores vsftpd (.rpm)           ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Para probar la conexión desde otra máquina:                    ║"
echo "║    ftp $IP_SERVIDOR                               "
echo "║    Usuario: danger  Contraseña: Gerardo1234!!                   ║"
echo "║                                                                  ║"
echo "║  O con curl (como lo hace mainSSL.sh):                          ║"
echo "║    curl -l -u danger:Gerardo1234!! ftp://$IP_SERVIDOR/http/Linux/Apache/"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  SIGUIENTE PASO: Actualizar FTP_USER y FTP_PASS en             ║"
echo "║  ssl_functions.sh con estos valores:                            ║"
echo "║    FTP_USER=\"danger\"                                            ║"
echo "║    FTP_PASS=\"Gerardo1234!!\"                                     ║"
echo "║    FTP_SERVER=\"$IP_SERVIDOR\"                    "
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

info "Archivos en el repositorio:"
find /srv/ftp/http -type f -name "*.rpm" -o -name "*.sha256" | sort | \
    while read -r f; do
        printf "    %s\n" "$f"
    done
echo ""