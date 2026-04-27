#!/usr/bin/env bash
# =============================================================================
# upload_ftp.sh — Sube archivos al servidor FTP del contenedor ftp_server
# y verifica que la web los sirva correctamente.
#
# Uso:
#   ./upload_ftp.sh archivo1.txt imagen.png ...
#   ./upload_ftp.sh              (modo interactivo)
#
# Dependencias: curl
# =============================================================================

set -euo pipefail

FTP_HOST="${FTP_HOST:-127.0.0.1}"
FTP_PORT="${FTP_PORT:-21}"
FTP_USER="${FTP_USER:-ftpuser}"
FTP_PASS="${FTP_PASS:-ftp12345}"
WEB_URL="${WEB_URL:-http://localhost}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✔  $*${NC}"; }
info() { echo -e "${CYAN}  →  $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${NC}"; }
fail() { echo -e "${RED}  ✘  $*${NC}"; }
sep()  { echo -e "${CYAN}──────────────────────────────────────────────${NC}"; }

upload_with_curl() {
  local file="$1"
  local name
  name=$(basename "$file")
  info "Subiendo '$name' vía curl FTP pasivo..."
  if curl -s --ftp-pasv \
      --connect-timeout 10 \
      -u "${FTP_USER}:${FTP_PASS}" \
      -T "$file" \
      "ftp://${FTP_HOST}:${FTP_PORT}/${name}"; then
    ok "Subido: $name"
    return 0
  else
    fail "Error al subir $name"
    return 1
  fi
}

verify_web() {
  local name="$1"
  info "Verificando acceso web: ${WEB_URL}/files/${name}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 \
    "${WEB_URL}/files/${name}" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    ok "Accesible en la web → ${WEB_URL}/files/${name}"
  else
    warn "HTTP $code — puede tardar unos segundos en aparecer."
    warn "Prueba manual: curl -I ${WEB_URL}/files/${name}"
  fi
}

echo ""
sep
echo -e "  ${CYAN}FTP Uploader — Práctica 10 Docker${NC}"
sep
echo ""

if ! command -v curl &>/dev/null; then
  fail "curl no encontrado. Instala: sudo dnf install curl"
  exit 1
fi

info "Servidor: ${FTP_HOST}:${FTP_PORT}  |  Usuario: ${FTP_USER}"
echo ""

FILES=("$@")
if [[ ${#FILES[@]} -eq 0 ]]; then
  read -rp "  Ruta del archivo a subir: " INPUT_FILE
  FILES=("$INPUT_FILE")
fi

TOTAL=0; FAILED=0
for f in "${FILES[@]}"; do
  sep
  if [[ ! -f "$f" ]]; then
    fail "Archivo no encontrado: $f"
    ((FAILED++)); continue
  fi
  NAME=$(basename "$f")
  SIZE=$(du -sh "$f" | cut -f1)
  info "Archivo: $NAME  (${SIZE})"
  if upload_with_curl "$f"; then
    sleep 1
    verify_web "$NAME"
    ((TOTAL++))
  else
    ((FAILED++))
  fi
done

sep
echo ""
if [[ $FAILED -eq 0 ]]; then
  ok "Completado: $TOTAL archivo(s) subido(s) exitosamente."
  echo -e "  ${CYAN}Ver en el navegador → ${WEB_URL}${NC}"
else
  warn "Completado con errores: $TOTAL OK, $FAILED fallidos."
fi
echo ""
