#!/bin/bash
# =============================================================================
# limpiar_entorno.sh — Limpieza TOTAL del entorno de la Práctica 7 en Fedora
#
# Qué limpia:
#   - Detiene y desinstala: httpd, nginx, tomcat, vsftpd
#   - Elimina configuraciones personalizadas (/etc/httpd/conf.d/reprobados*)
#   - Elimina certificados generados (/etc/ssl/apache, nginx, tomcat, vsftpd)
#   - Elimina el index.html de /var/www/html
#   - Elimina el webapp de Tomcat
#   - Restaura el vsftpd.conf de la Práctica 5 si existe backup
#   - Cierra puertos abiertos en firewalld
#   - NO toca: usuario danger, repositorio FTP, archivos RPM
#
# USO:
#   sudo bash linux/modules/limpiar_entorno.sh
# =============================================================================

GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
info() { echo -e "${CYAN}[*]${NC}    $1"; }
warn() { echo -e "${YELLOW}[!]${NC}    $1"; }

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Ejecuta como root: sudo bash $0"; exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   LIMPIEZA ENTORNO PRÁCTICA 7 — FEDORA SERVER 42     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# 1. DETENER Y DESHABILITAR SERVICIOS
# =============================================================================
info "Deteniendo servicios..."

for svc in httpd nginx tomcat vsftpd; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop    "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
        ok "$svc detenido."
    else
        warn "$svc no estaba activo."
    fi
done

# Matar procesos residuales
for proc in httpd nginx java; do
    pids=$(pgrep -f "$proc" 2>/dev/null)
    [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null && ok "Proceso $proc eliminado."
done

sleep 1

# =============================================================================
# 2. ELIMINAR CONFIGURACIONES PERSONALIZADAS DE APACHE
# =============================================================================
info "Limpiando configuraciones de Apache..."

rm -f /etc/httpd/conf.d/reprobados*.conf
ok "Archivos reprobados*.conf eliminados."

# Restaurar welcome.conf si lo deshabilitamos
if [[ -f /etc/httpd/conf.d/welcome.conf.disabled ]]; then
    mv /etc/httpd/conf.d/welcome.conf.disabled \
       /etc/httpd/conf.d/welcome.conf 2>/dev/null
    ok "welcome.conf restaurado."
fi

# Restaurar ssl.conf de mod_ssl si teníamos backup
# (mod_ssl instala /etc/httpd/conf.d/ssl.conf por defecto, lo eliminamos al configurar)
if ! [[ -f /etc/httpd/conf.d/ssl.conf ]]; then
    # Regenerarlo desde el paquete mod_ssl
    rpm -qf /etc/httpd/conf.d/ssl.conf &>/dev/null || \
        dnf reinstall -y mod_ssl &>/dev/null && \
        ok "ssl.conf de mod_ssl restaurado."
fi

# =============================================================================
# 3. ELIMINAR CONFIGURACIONES DE NGINX
# =============================================================================
info "Limpiando configuraciones de Nginx..."

rm -f /etc/nginx/conf.d/reprobados*.conf

# Restaurar default.conf si lo deshabilitamos
if [[ -f /etc/nginx/conf.d/default.conf.disabled ]]; then
    mv /etc/nginx/conf.d/default.conf.disabled \
       /etc/nginx/conf.d/default.conf 2>/dev/null
    ok "nginx default.conf restaurado."
fi
ok "Configuraciones de Nginx limpiadas."

# =============================================================================
# 4. RESTAURAR SERVER.XML DE TOMCAT
# =============================================================================
info "Restaurando Tomcat..."

if [[ -f /etc/tomcat/server.xml.bak ]]; then
    cp /etc/tomcat/server.xml.bak /etc/tomcat/server.xml
    ok "server.xml de Tomcat restaurado desde backup."
fi

# Limpiar webapp creado por la práctica
rm -f /var/lib/tomcat/webapps/ROOT/index.html
ok "index.html de Tomcat eliminado."

# =============================================================================
# 5. ELIMINAR CERTIFICADOS GENERADOS
# =============================================================================
info "Eliminando certificados SSL generados..."

for srv in apache nginx tomcat vsftpd; do
    if [[ -d /etc/ssl/$srv ]]; then
        rm -rf /etc/ssl/$srv
        ok "Certificados de $srv eliminados."
    fi
done

# Eliminar keystore de Tomcat
rm -f /etc/ssl/tomcat/keystore.p12 2>/dev/null

# =============================================================================
# 6. LIMPIAR CONTENIDO WEB
# =============================================================================
info "Limpiando /var/www/html..."

rm -f /var/www/html/index.html
ok "/var/www/html/index.html eliminado."

# =============================================================================
# 7. RESTAURAR VSFTPD (si había backup de la Práctica 5)
# =============================================================================
info "Revisando vsftpd..."

if [[ -f /etc/vsftpd/vsftpd.conf.bak_setup ]]; then
    cp /etc/vsftpd/vsftpd.conf.bak_setup /etc/vsftpd/vsftpd.conf
    systemctl restart vsftpd 2>/dev/null
    ok "vsftpd.conf restaurado desde backup de setup."
else
    warn "No hay backup de vsftpd.conf. Se deja como está."
fi

# =============================================================================
# 8. LIMPIAR REGLAS DE FIREWALL AÑADIDAS POR LOS SCRIPTS
# =============================================================================
info "Limpiando reglas de firewall..."

# Quitar puertos que abrimos durante las pruebas
# (conservamos ssh y ftp que son de práctica 5)
for port_proto in $(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n'); do
    port=$(echo "$port_proto" | cut -d'/' -f1)
    # Conservar solo FTP (21) y pasivos (40000-40010)
    if [[ "$port" != "21" ]] && \
       [[ "$port" != "40000-40010" ]] && \
       [[ "$port" != "990" ]]; then
        firewall-cmd --permanent --remove-port="$port_proto" &>/dev/null \
            && ok "Puerto $port_proto eliminado del firewall."
    fi
done

# Quitar https si lo abrimos como servicio (pero dejar http y ssh)
firewall-cmd --permanent --remove-service=https &>/dev/null
firewall-cmd --reload &>/dev/null
ok "Firewall limpio."

# =============================================================================
# RESUMEN
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              LIMPIEZA COMPLETADA                             ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Lo que se limpió:                                          ║"
echo "║    httpd/nginx/tomcat - detenidos y sin configs propias     ║"
echo "║    Certificados SSL   - eliminados de /etc/ssl/             ║"
echo "║    index.html         - eliminado de /var/www/html          ║"
echo "║    Reglas firewall    - puertos HTTP/HTTPS cerrados         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Lo que NO se tocó:                                         ║"
echo "║    Usuario danger     - sigue existiendo                    ║"
echo "║    Repositorio FTP    - /srv/ftp/http intacto               ║"
echo "║    vsftpd             - restaurado o sin cambios            ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Para volver a empezar:                                     ║"
echo "║    sudo bash linux/modules/mainSSL.sh                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

info "Estado actual de servicios:"
for svc in httpd nginx tomcat vsftpd; do
    estado=$(systemctl is-active "$svc" 2>/dev/null || echo "inactivo")
    printf "    %-10s → %s\n" "$svc" "$estado"
done
echo ""