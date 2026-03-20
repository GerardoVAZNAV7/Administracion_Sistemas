#!/bin/bash
# =============================================================================
# poblar_repositorio.sh
# Descarga los instaladores y los coloca en el FTP de Fedora
#
# EXPLICACIÓN SIMPLE:
#   Este script hace lo mismo que ir a una página web, descargar un archivo
#   y moverlo a una carpeta. Solo que lo hace automático.
#
# USO:
#   sudo bash poblar_repositorio.sh
# =============================================================================

# ── Colores ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
info() { echo -e "${CYAN}[*]${NC}    $1"; }
warn() { echo -e "${YELLOW}[!]${NC}    $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ "$EUID" -ne 0 ]]; then
    err "Ejecuta como root: sudo bash $0"; exit 1
fi

# =============================================================================
# CARPETAS DESTINO
# Esta es la estructura que necesita mainSSL.sh para encontrar los archivos
# =============================================================================
REPO_BASE="/srv/ftp/http/Linux"
mkdir -p "$REPO_BASE"/{Apache,Nginx,Tomcat,vsftpd}

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   POBLANDO REPOSITORIO FTP — FEDORA SERVER 42        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# FUNCIÓN PRINCIPAL
# Descarga un paquete y genera su .sha256
# =============================================================================
descargar_y_colocar() {
    local paquete=$1      # nombre en dnf: httpd, nginx, tomcat, vsftpd
    local carpeta=$2      # dónde guardarlo: /srv/ftp/http/Linux/Apache
    local etiqueta=$3     # nombre bonito para mostrar

    info "Procesando: $etiqueta"
    echo "    Carpeta destino: $carpeta"

    # ─────────────────────────────────────────────────────────────────────────
    # MÉTODO 1: dnf download
    # Esto le dice a Fedora "dame el RPM de este paquete pero no lo instales"
    # Es exactamente lo mismo que cuando dnf install descarga antes de instalar,
    # pero aquí nos quedamos solo con el archivo descargado.
    # ─────────────────────────────────────────────────────────────────────────
    local tmp="/tmp/dnf_descarga_$$"
    mkdir -p "$tmp"

    info "  Intentando descargar con 'dnf download $paquete'..."

    if dnf download "$paquete" --destdir="$tmp" &>/dev/null; then
        # Buscar el .rpm descargado (puede tener cualquier versión en el nombre)
        local rpm_file
        rpm_file=$(find "$tmp" -name "*.rpm" | head -1)

        if [[ -n "$rpm_file" ]]; then
            local nombre_archivo
            nombre_archivo=$(basename "$rpm_file")

            # Mover a la carpeta del FTP
            mv "$rpm_file" "$carpeta/$nombre_archivo"
            ok "  Descargado: $nombre_archivo"
            ok "  Guardado en: $carpeta/"

            # Generar el hash SHA256
            # sha256sum genera una línea como:
            #   abc123...  nombre_archivo.rpm
            # Guardamos solo el hash (awk '{print $1}') porque mainSSL.sh
            # compara solo el hash, no la línea completa
            sha256sum "$carpeta/$nombre_archivo" \
                | awk '{print $1}' \
                > "$carpeta/$nombre_archivo.sha256"
            ok "  Hash SHA256 generado: $nombre_archivo.sha256"

            rm -rf "$tmp"
            return 0
        fi
    fi

    rm -rf "$tmp"

    # ─────────────────────────────────────────────────────────────────────────
    # MÉTODO 2: descargar directo del repositorio de Fedora con curl
    # Si dnf download falla (sin internet, repo roto, etc.) usamos este método.
    # dnf repoquery --location nos da la URL directa del .rpm
    # ─────────────────────────────────────────────────────────────────────────
    warn "  dnf download falló. Intentando obtener URL directa..."

    local url
    url=$(dnf repoquery --location "$paquete" 2>/dev/null | grep "\.rpm" | head -1)

    if [[ -n "$url" ]]; then
        local nombre_archivo
        nombre_archivo=$(basename "$url")

        info "  URL encontrada: $url"
        info "  Descargando con curl..."

        if curl -L --progress-bar -o "$carpeta/$nombre_archivo" "$url"; then
            ok "  Descargado: $nombre_archivo"

            sha256sum "$carpeta/$nombre_archivo" \
                | awk '{print $1}' \
                > "$carpeta/$nombre_archivo.sha256"
            ok "  Hash SHA256 generado."
            return 0
        fi
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # MÉTODO 3: instrucciones manuales
    # Si nada funciona, le decimos al usuario exactamente qué hacer
    # ─────────────────────────────────────────────────────────────────────────
    err "  No se pudo descargar $etiqueta automáticamente."
    echo ""
    echo "  ┌─ DESCARGA MANUAL ─────────────────────────────────────────┐"
    echo "  │ Haz esto en tu Fedora:                                    │"
    echo "  │                                                           │"
    echo "  │   dnf download $paquete                                   "
    echo "  │   # Esto crea un archivo .rpm en la carpeta actual        │"
    echo "  │   # Por ejemplo: httpd-2.4.62-1.fc42.x86_64.rpm          │"
    echo "  │                                                           │"
    echo "  │   # Luego muévelo:                                        │"
    echo "  │   mv *.rpm $carpeta/                                      "
    echo "  │                                                           │"
    echo "  │   # Y genera el hash:                                     │"
    echo "  │   sha256sum $carpeta/*.rpm | awk '{print \$1}' \\          │"
    echo "  │       > $carpeta/*.rpm.sha256                             "
    echo "  └───────────────────────────────────────────────────────────┘"
    echo ""
    return 1
}

# =============================================================================
# DESCARGAR CADA PAQUETE
# =============================================================================
descargar_y_colocar "httpd"   "$REPO_BASE/Apache"  "Apache (httpd)"
echo ""
descargar_y_colocar "nginx"   "$REPO_BASE/Nginx"   "Nginx"
echo ""
descargar_y_colocar "tomcat"  "$REPO_BASE/Tomcat"  "Tomcat"
echo ""
descargar_y_colocar "vsftpd"  "$REPO_BASE/vsftpd"  "vsftpd"
echo ""

# =============================================================================
# APLICAR PERMISOS AL REPOSITORIO
# El usuario "danger" necesita poder leer estos archivos por FTP
# =============================================================================
info "Aplicando permisos al repositorio..."

chown -R root:root /srv/ftp          # la raíz DEBE ser de root (vsftpd lo exige)
chmod 755          /srv/ftp
chown -R danger:danger "$REPO_BASE"  # las subcarpetas pueden ser de danger
chmod -R 755            "$REPO_BASE"

# Contexto SELinux: los archivos del FTP deben tener el tipo public_content_t
chcon -R -t public_content_t "$REPO_BASE" 2>/dev/null \
    || restorecon -R "$REPO_BASE" 2>/dev/null

ok "Permisos aplicados."

# =============================================================================
# MOSTRAR RESULTADO FINAL
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║           REPOSITORIO FTP LISTO — CONTENIDO ACTUAL              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Mostrar árbol de archivos con tamaños
find /srv/ftp/http -type f | sort | while read -r archivo; do
    tamanio=$(du -sh "$archivo" 2>/dev/null | cut -f1)
    # Quitar el prefijo /srv/ftp para que sea más legible
    ruta_relativa="${archivo#/srv/ftp}"
    printf "    %-55s %s\n" "$ruta_relativa" "$tamanio"
done

echo ""
echo "  Para verificar que el FTP funciona, ejecuta desde OTRA máquina:"
IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
echo "    curl -l -u danger:Gerardo1234!! ftp://$IP/http/Linux/Apache/"
echo ""
echo "  Deberías ver el nombre del .rpm listado."
echo ""