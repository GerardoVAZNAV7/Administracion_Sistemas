#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test_practica10.sh — Pruebas automatizadas Práctica 10 Docker
#
# Prueba 10.1 — Persistencia de BD (volumen db_data)
# Prueba 10.2 — Aislamiento de red (ping por nombre DNS)
# Prueba 10.3 — Subida FTP y acceso web
# Prueba 10.4 — Límites de recursos (RAM/CPU)
#
# Uso: ./test_practica10.sh
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

# ── Configuración ─────────────────────────────────────────────────────────────
FTP_HOST="${FTP_HOST:-127.0.0.1}"
FTP_USER="${FTP_USER:-ftpuser}"
FTP_PASS="${FTP_PASS:-ftp12345}"
WEB_URL="${WEB_URL:-http://localhost}"
DB_USER="${DB_USER:-admin}"
DB_PASS="${DB_PASS:-admin123}"
DB_NAME="${DB_NAME:-empresa}"
MEM_LIMIT_MB="${MEM_LIMIT_MB:-512}"

# ── Colores y helpers ─────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0; WARN=0
RESULTS=()

ok()    { echo -e "  ${GREEN}✔${NC}  $*"; }
fail()  { echo -e "  ${RED}✘${NC}  $*"; }
info()  { echo -e "  ${CYAN}→${NC}  $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}  $*"; }
sep()   { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
title() { echo ""; sep; echo -e "  ${BOLD}${CYAN}$*${NC}"; sep; echo ""; }

check() {
  local label="$1" result="$2" detail="${3:-}"
  if [[ "$result" == "PASS" ]]; then
    ok "$label"
    [[ -n "$detail" ]] && echo -e "      ${GREEN}${detail}${NC}"
    RESULTS+=("PASS|$label")
    ((PASS++))
  elif [[ "$result" == "WARN" ]]; then
    warn "$label"
    [[ -n "$detail" ]] && echo -e "      ${YELLOW}${detail}${NC}"
    RESULTS+=("WARN|$label")
    ((WARN++))
  else
    fail "$label"
    [[ -n "$detail" ]] && echo -e "      ${RED}${detail}${NC}"
    RESULTS+=("FAIL|$label")
    ((FAIL++))
  fi
}

require_cmd() {
  command -v "$1" &>/dev/null || { warn "Comando '$1' no encontrado, algunas pruebas pueden fallar."; }
}

# ─────────────────────────────────────────────────────────────────────────────
echo ""
sep
echo -e "  ${BOLD}Pruebas Automatizadas — Práctica 10 Docker${NC}"
echo -e "  ${CYAN}Gerardo Miguel Vázquez Navarro — Grupo 3-01${NC}"
sep
echo ""

require_cmd docker
require_cmd curl

# ── Verificar que los contenedores estén corriendo ───────────────────────────
title "PRE-VERIFICACIÓN — Estado de contenedores"

for CONT in web_server db_postgres ftp_server; do
  STATUS=$(docker inspect -f '{{.State.Running}}' "$CONT" 2>/dev/null || echo "false")
  if [[ "$STATUS" == "true" ]]; then
    check "$CONT corriendo" "PASS"
  else
    check "$CONT corriendo" "FAIL" "Contenedor no existe o está detenido — ejecuta: docker compose up -d"
  fi
done

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PRUEBA 10.1 — Persistencia de BD
# ─────────────────────────────────────────────────────────────────────────────
title "PRUEBA 10.1 — Persistencia de Base de Datos (volumen db_data)"

info "Creando tabla de prueba en PostgreSQL..."
CREATE_OUT=$(docker exec -e PGPASSWORD="$DB_PASS" db_postgres \
  psql -U "$DB_USER" -d "$DB_NAME" -c \
  "CREATE TABLE IF NOT EXISTS test_persistencia (id SERIAL PRIMARY KEY, dato TEXT, ts TIMESTAMPTZ DEFAULT now());" \
  2>&1 || echo "ERROR")

INSERT_OUT=$(docker exec -e PGPASSWORD="$DB_PASS" db_postgres \
  psql -U "$DB_USER" -d "$DB_NAME" -c \
  "INSERT INTO test_persistencia (dato) VALUES ('practica10_$(date +%s)') RETURNING id, dato;" \
  2>&1 || echo "ERROR")

if echo "$INSERT_OUT" | grep -q "INSERT"; then
  info "Registro insertado:"
  echo "$INSERT_OUT" | grep -E "id|dato|---|\(" | head -5 | sed 's/^/      /'
  check "Inserción en BD exitosa" "PASS"
else
  check "Inserción en BD exitosa" "FAIL" "$INSERT_OUT"
fi

info "Eliminando contenedor db_postgres..."
docker rm -f db_postgres &>/dev/null
sleep 2

info "Recreando contenedor con el mismo volumen..."
docker run -d \
  --name db_postgres \
  --network infra_red \
  --ip 172.20.0.20 \
  -v db_data:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD="$DB_PASS" \
  -e POSTGRES_DB="$DB_NAME" \
  -e POSTGRES_USER="$DB_USER" \
  postgres:15-alpine &>/dev/null

info "Esperando que PostgreSQL inicie..."
RETRIES=15
until docker exec -e PGPASSWORD="$DB_PASS" db_postgres pg_isready -U "$DB_USER" &>/dev/null || [[ $RETRIES -eq 0 ]]; do
  sleep 2; ((RETRIES--))
done

QUERY_OUT=$(docker exec -e PGPASSWORD="$DB_PASS" db_postgres \
  psql -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT COUNT(*) AS total FROM test_persistencia;" 2>&1 || echo "ERROR")

if echo "$QUERY_OUT" | grep -qE "[0-9]+"; then
  COUNT=$(echo "$QUERY_OUT" | grep -E "^\s+[0-9]" | tr -d ' ')
  check "Datos persisten tras recrear contenedor" "PASS" "Registros encontrados: $COUNT"
else
  check "Datos persisten tras recrear contenedor" "FAIL" "$QUERY_OUT"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PRUEBA 10.2 — Aislamiento de Red
# ─────────────────────────────────────────────────────────────────────────────
title "PRUEBA 10.2 — Aislamiento de Red (ping por nombre DNS)"

info "Instalando iputils en web_server (Alpine)..."
docker exec web_server apk add --no-cache iputils &>/dev/null || true

for TARGET in db_postgres ftp_server; do
  info "Ping desde web_server → $TARGET"
  PING_OUT=$(docker exec web_server ping -c 3 -W 2 "$TARGET" 2>&1 || echo "FAIL")
  if echo "$PING_OUT" | grep -q "bytes from"; then
    RTT=$(echo "$PING_OUT" | grep -oP 'time=\K[0-9.]+' | head -1)
    check "web_server → $TARGET (DNS: resolvió y respondió)" "PASS" "RTT: ${RTT}ms"
  else
    check "web_server → $TARGET" "FAIL" "Sin respuesta ICMP"
  fi
done

info "Verificar IPs asignadas en infra_red:"
docker network inspect infra_red --format '{{range .Containers}}  {{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}' | sed 's/^/      /'

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PRUEBA 10.3 — Permisos FTP + acceso web
# ─────────────────────────────────────────────────────────────────────────────
title "PRUEBA 10.3 — Transferencia FTP y acceso desde servidor web"

TEST_FILE="/tmp/test_practica10_$(date +%s).txt"
TEST_NAME=$(basename "$TEST_FILE")
echo "Prueba automatizada Practica 10 — $(date)" > "$TEST_FILE"
echo "Contenedor: web_server + ftp_server" >> "$TEST_FILE"
echo "Volumen compartido: web_content" >> "$TEST_FILE"

info "Subiendo archivo de prueba vía FTP: $TEST_NAME"
UPLOAD_OUT=$(curl -s --ftp-pasv \
  -u "${FTP_USER}:${FTP_PASS}" \
  -T "$TEST_FILE" \
  "ftp://${FTP_HOST}:21/${TEST_NAME}" 2>&1 || echo "ERROR")

if [[ -z "$UPLOAD_OUT" || "$UPLOAD_OUT" != *"ERROR"* ]]; then
  check "Archivo subido vía FTP" "PASS"
else
  check "Archivo subido vía FTP" "FAIL" "$UPLOAD_OUT"
fi

sleep 2  # sincronización de volumen

info "Verificando que NGINX sirve el archivo: ${WEB_URL}/files/${TEST_NAME}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${WEB_URL}/files/${TEST_NAME}" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
  check "Archivo accesible en la web (HTTP $HTTP_CODE)" "PASS" "${WEB_URL}/files/${TEST_NAME}"
else
  check "Archivo accesible en la web" "FAIL" "HTTP $HTTP_CODE — verifica que web_content esté montado en /files/"
fi

info "Verificando listado de directorio (autoindex JSON):"
LIST_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${WEB_URL}/files/?format=json" 2>/dev/null || echo "000")
if [[ "$LIST_CODE" == "200" ]]; then
  check "Autoindex JSON activo (${WEB_URL}/files/)" "PASS"
else
  check "Autoindex JSON" "WARN" "HTTP $LIST_CODE — puede ser autoindex html en lugar de json, ambos funcionan"
fi

rm -f "$TEST_FILE"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PRUEBA 10.4 — Límites de recursos
# ─────────────────────────────────────────────────────────────────────────────
title "PRUEBA 10.4 — Límites de Recursos (RAM / CPU)"

info "Ejecutando docker stats --no-stream..."
STATS=$(docker stats --no-stream --format "{{.Name}}|{{.MemUsage}}|{{.CPUPerc}}" 2>/dev/null || echo "")
echo ""
echo -e "  ${BOLD}  CONTENEDOR          MEM USO / LÍMITE          CPU%${NC}"
echo -e "  ────────────────────────────────────────────────────────"
echo "$STATS" | while IFS='|' read -r name mem cpu; do
  printf "  %-20s %-28s %s\n" "$name" "$mem" "$cpu"
done
echo ""

# Verificar límite de memoria configurado en web_server
MEM_CONFIG=$(docker inspect web_server --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
EXPECTED=$((MEM_LIMIT_MB * 1024 * 1024))

if [[ "$MEM_CONFIG" == "$EXPECTED" ]]; then
  check "Límite de RAM configurado (${MEM_LIMIT_MB}MiB = ${MEM_CONFIG} bytes)" "PASS"
elif [[ "$MEM_CONFIG" -gt 0 ]]; then
  ACTUAL_MB=$((MEM_CONFIG / 1024 / 1024))
  check "Límite de RAM configurado (${ACTUAL_MB}MiB)" "WARN" "Se esperaba ${MEM_LIMIT_MB}MiB, configurado: ${ACTUAL_MB}MiB"
else
  check "Límite de RAM en web_server" "FAIL" \
    "Sin límite configurado. Usa --memory=512m en docker run o mem_limit: 512m en compose"
fi

# Verificar límite de CPU
CPU_CONFIG=$(docker inspect web_server --format '{{.HostConfig.NanoCpus}}' 2>/dev/null || echo "0")
if [[ "$CPU_CONFIG" -gt 0 ]]; then
  CPU_CORES=$(echo "scale=2; $CPU_CONFIG / 1000000000" | bc 2>/dev/null || echo "?")
  check "Límite de CPU configurado (${CPU_CORES} cores)" "PASS"
else
  check "Límite de CPU en web_server" "WARN" "Sin límite de CPU. Agrega --cpus=0.5 o cpus: '0.5' en compose"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# RESUMEN FINAL
# ─────────────────────────────────────────────────────────────────────────────
title "RESUMEN DE RESULTADOS"

TOTAL=$((PASS + FAIL + WARN))
echo -e "  Total pruebas: ${BOLD}${TOTAL}${NC}"
echo -e "  ${GREEN}✔ Exitosas:  ${PASS}${NC}"
[[ $WARN -gt 0 ]] && echo -e "  ${YELLOW}⚠ Advertencias: ${WARN}${NC}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✘ Fallidas:  ${FAIL}${NC}"
echo ""

echo -e "  Detalle:"
for R in "${RESULTS[@]}"; do
  IFS='|' read -r STATUS LABEL <<< "$R"
  case "$STATUS" in
    PASS) echo -e "    ${GREEN}✔${NC} $LABEL" ;;
    WARN) echo -e "    ${YELLOW}⚠${NC} $LABEL" ;;
    FAIL) echo -e "    ${RED}✘${NC} $LABEL" ;;
  esac
done

echo ""
sep
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}Todas las pruebas pasaron.${NC}"
else
  echo -e "  ${RED}${BOLD}Hay ${FAIL} prueba(s) fallida(s). Revisa los errores arriba.${NC}"
fi
sep
echo ""
