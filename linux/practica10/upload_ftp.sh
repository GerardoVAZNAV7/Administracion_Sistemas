#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# upload_ftp.sh — Sube archivos al servidor FTP del contenedor ftp_server
# y verifica que la web los sirva correctamente.
#
# Uso:
#   ./upload_ftp.sh archivo1.txt imagen.png ...
#   ./upload_ftp.sh              (modo interactivo, pide el archivo)
#
# Dependencias: curl, wget o ncftp (se detecta automáticamente)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuración ─────────────────────────────────────────────────────────────
FTP_HOST="${FTP_HOST:-127.0.0.1}"
FTP_PORT="${FTP_PORT:-21}"
FTP_USER="${FTP_USER:-ftpuser}"
FTP_PASS="${FTP_PASS:-ftp12345}"
WEB_URL="${WEB_URL:-http://localhost}"

# ── Colores ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✔  $*${NC}"; }
info() { echo -e "${CYAN}  →  $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${NC}"; }
fail() { echo -e "${RED}  ✘  $*${NC}"; }
sep()  { echo -e "${CYAN}──────────────────────────────────────────────${NC}"; }

# ── Detectar herramienta FTP ──────────────────────────────────────────────────
detect_tool() {
  if command -v curl &>/dev/null; then echo "curl"
  elif command -v ncftpput &>/dev/null; then echo "ncftpput"
  elif command -v ftp &>/dev/null; then echo "ftp"
  else echo ""; fi
}

upload_with_curl() {
  local file="$1"
  local name
  name=$(basename "$file")
  info "Subiendo '$name' vía curl..."
  curl -s --ftp-pasv \
    -u "${FTP_USER}:${FTP_PASS}" \
    -T "$file" \
    "ftp://${FTP_HOST}:${FTP_PORT}/${name}" && ok "Subido: $name" || { fail "Error al subir $name"; return 1; }
}

upload_with_ncftp() {
  local file="$1"
  local name
  name=$(basename "$file")
  info "Subiendo '$name' vía ncftpput..."
  ncftpput -u "$FTP_USER" -p "$FTP_PASS" -P "$FTP_PORT" "$FTP_HOST" / "$file" \
    && ok "Subido: $name" || { fail "Error al subir $name"; return 1; }
}

upload_with_ftp() {
  local file="$1"
  local name
  name=$(basename "$file")
  info "Subiendo '$name' vía ftp..."
  ftp -n "$FTP_HOST" "$FTP_PORT" <<EOF
user $FTP_USER $FTP_PASS
binary
put $file $name
bye
EOF
  ok "Subido: $name"
}

verify_web() {
  local name="$1"
  info "Verificando acceso web: ${WEB_URL}/files/${name}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "${WEB_URL}/files/${name}" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    ok "Accesible en la web → ${WEB_URL}/files/${name}"
  else
    warn "HTTP $code — El archivo puede tardar unos segundos en aparecer."
    warn "Prueba manualmente: curl -I ${WEB_URL}/files/${name}"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
sep
echo -e "  ${CYAN}FTP Uploader — Práctica 10 Docker${NC}"
sep
echo ""

TOOL=$(detect_tool)
if [[ -z "$TOOL" ]]; then
  fail "No se encontró curl, ncftpput ni ftp. Instala curl: sudo dnf install curl"
  exit 1
fi
info "Usando: $TOOL  |  Servidor: ${FTP_HOST}:${FTP_PORT}  |  Usuario: ${FTP_USER}"
echo ""

# Determinar archivos a subir
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

  case "$TOOL" in
    curl)     upload_with_curl "$f" ;;
    ncftpput) upload_with_ncftp "$f" ;;
    ftp)      upload_with_ftp "$f" ;;
  esac

  if [[ $? -eq 0 ]]; then
    sleep 1   # pequeño delay para que el volumen se sincronice
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
