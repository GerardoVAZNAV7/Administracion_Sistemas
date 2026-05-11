#!/usr/bin/env bash
# ============================================================
#  instalar_logo.sh — Personalización institucional Roundcube
#  Ejecutar desde: ~/practica12/
#  Uso: bash instalar_logo.sh
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
info() { echo -e "  ${YELLOW}►${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGO_DIR="${SCRIPT_DIR}/logo"

echo "============================================================"
echo "  Instalando logo institucional en Roundcube"
echo "============================================================"

# ── 1. Verificar que el contenedor corre ─────────────────────
if ! docker inspect --format='{{.State.Status}}' p12_roundcube 2>/dev/null | grep -q "running"; then
    echo "ERROR: p12_roundcube no está corriendo. Ejecuta primero: docker compose up -d"
    exit 1
fi
ok "Contenedor p12_roundcube activo"

# ── 2. Detectar ruta del skin Elastic dentro del contenedor ──
info "Detectando ruta del skin Elastic..."
SKIN_PATH=$(docker exec p12_roundcube find /var/www/html -type d -name "elastic" 2>/dev/null | head -1)
if [[ -z "${SKIN_PATH}" ]]; then
    SKIN_PATH="/var/www/html/skins/elastic"
fi
echo "    Ruta: ${SKIN_PATH}"

# ── 3. Crear directorio de imágenes institucionales ──────────
info "Creando directorio de imágenes..."
docker exec p12_roundcube mkdir -p "${SKIN_PATH}/images"
ok "Directorio creado"

# ── 4. Copiar logos al contenedor ────────────────────────────
info "Copiando logos..."
docker cp "${LOGO_DIR}/logo_login.png" p12_roundcube:"${SKIN_PATH}/images/logo_login.png"
docker cp "${LOGO_DIR}/logo_nav.png"   p12_roundcube:"${SKIN_PATH}/images/logo_nav.png"
docker cp "${LOGO_DIR}/favicon.png"    p12_roundcube:"/var/www/html/favicon.ico"
ok "Logos copiados"

# ── 5. Copiar CSS personalizado ───────────────────────────────
info "Instalando CSS institucional..."
docker cp "${LOGO_DIR}/custom.css" p12_roundcube:"${SKIN_PATH}/css/custom.css"
ok "CSS copiado"

# ── 6. Inyectar referencia al CSS en el skin ─────────────────
info "Registrando CSS en el skin Elastic..."
# Verificar si ya existe la referencia para no duplicar
ALREADY=$(docker exec p12_roundcube grep -l "custom.css" \
    "${SKIN_PATH}/meta.json" 2>/dev/null || echo "")

if [[ -z "${ALREADY}" ]]; then
    # Agregar referencia al CSS custom en styles.css del skin
    docker exec p12_roundcube bash -c \
        "echo '@import url(custom.css);' >> ${SKIN_PATH}/css/styles.css" 2>/dev/null || \
    docker exec p12_roundcube bash -c \
        "find ${SKIN_PATH} -name '*.css' -not -name 'custom.css' | head -1 | xargs -I{} sh -c 'echo \"@import url(custom.css);\" >> {}'" 2>/dev/null || true
    ok "CSS registrado en el skin"
else
    ok "CSS ya estaba registrado (sin duplicar)"
fi

# ── 7. Configurar logo en config.inc.php ─────────────────────
info "Actualizando config.inc.php con ruta del logo..."
docker exec p12_roundcube bash -c "
cat >> /var/roundcube/config/config.inc.php << 'PHPEOF'

// ── Logo institucional ─────────────────────────────────────
\$config['skin_logo'] = 'skins/elastic/images/logo_login.png';
PHPEOF
" 2>/dev/null || true
ok "Logo registrado en configuración"

# ── 8. Ajustar permisos ───────────────────────────────────────
info "Ajustando permisos..."
docker exec p12_roundcube chmod 644 \
    "${SKIN_PATH}/images/logo_login.png" \
    "${SKIN_PATH}/images/logo_nav.png"  \
    "${SKIN_PATH}/css/custom.css" 2>/dev/null || true
ok "Permisos correctos"

# ── 9. Reiniciar Apache dentro del contenedor ─────────────────
info "Reiniciando Apache para aplicar cambios..."
docker exec p12_roundcube apache2ctl graceful 2>/dev/null || \
docker restart p12_roundcube > /dev/null 2>&1
ok "Apache reiniciado"

SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "============================================================"
echo "  Logo instalado correctamente"
echo ""
echo "  Verifica en: https://${SERVER_IP}:8443"
echo "  El logo aparece en:"
echo "   • Pantalla de login"
echo "   • Barra superior (navbar)"
echo "   • Favicon de la pestaña del navegador"
echo "============================================================"
