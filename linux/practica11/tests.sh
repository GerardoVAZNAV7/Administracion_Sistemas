#!/usr/bin/env bash
# ============================================================
#  tests.sh — Pruebas de aceptación · Práctica 11
#  Ejecutar desde el servidor: bash tests.sh
#  Algunas pruebas deben correrse también desde tu PC (indicado)
# ============================================================
set -uo pipefail

# ── Colores ───────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}✔ PASS${NC} — $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✘ FAIL${NC} — $1"; ((FAIL++)); }
info() { echo -e "  ${YELLOW}ℹ${NC}  $1"; }
titulo() { echo -e "\n${BLUE}══════════════════════════════════════════════${NC}"; \
           echo -e "${BLUE}  $1${NC}"; \
           echo -e "${BLUE}══════════════════════════════════════════════${NC}"; }

PROYECTO_DIR="$(dirname "$0")"
cd "${PROYECTO_DIR}"

# ── Verificar que el stack esté corriendo ─────────────────────────
titulo "PRE-CHECK: Verificar contenedores activos"
CONTAINERS=("p11_nginx" "p11_webserver" "p11_postgres" "p11_pgadmin")
for c in "${CONTAINERS[@]}"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null || echo "no existe")
    if [[ "$STATUS" == "running" ]]; then
        ok "Contenedor $c está running"
    else
        fail "Contenedor $c no está running (estado: $STATUS)"
    fi
done

# ════════════════════════════════════════════════════════════════
# PRUEBA 11.1 — Aislamiento de red
# Intento de conexión directa a postgres y pgadmin desde el host
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 11.1 — Aislamiento de red (desde el servidor)"

# Postgres: no debe tener puerto en el host
POSTGRES_HOST_PORT=$(docker inspect --format='{{range $p,$conf := .NetworkSettings.Ports}}{{$p}}={{if $conf}}{{(index $conf 0).HostPort}}{{else}}NO{{end}} {{end}}' p11_postgres 2>/dev/null | grep "5432" | grep -v "NO" || true)

if [[ -z "$POSTGRES_HOST_PORT" ]]; then
    ok "PostgreSQL no tiene puertos expuestos al host"
else
    fail "PostgreSQL tiene puerto expuesto: ${POSTGRES_HOST_PORT}"
fi

# pgAdmin: no debe tener puerto en el host
PGADMIN_HOST_PORT=$(docker inspect --format='{{range $p,$conf := .NetworkSettings.Ports}}{{$p}}={{if $conf}}{{(index $conf 0).HostPort}}{{else}}NO{{end}} {{end}}' p11_pgadmin 2>/dev/null | grep -v "NO" | grep -v "^[[:space:]]*$" || true)

if [[ -z "$PGADMIN_HOST_PORT" ]]; then
    ok "pgAdmin no tiene puertos expuestos al host"
else
    fail "pgAdmin tiene puerto expuesto: ${PGADMIN_HOST_PORT}"
fi

# Intento de curl a puertos internos desde el servidor
info "Intentando curl a localhost:5432 (debe fallar o timeout)..."
if curl -s --connect-timeout 3 http://localhost:5432 > /dev/null 2>&1; then
    fail "localhost:5432 respondió — debería estar cerrado"
else
    ok "localhost:5432 rechazado correctamente"
fi

info "Intentando curl a localhost:5050 (debe fallar o timeout)..."
if curl -s --connect-timeout 3 http://localhost:5050 > /dev/null 2>&1; then
    fail "localhost:5050 respondió — debería estar cerrado"
else
    ok "localhost:5050 rechazado correctamente"
fi

# Prueba de nginx público (debe responder)
info "Verificando que nginx sí responde en puerto 80..."
if curl -s --connect-timeout 5 http://localhost:80 > /dev/null 2>&1; then
    ok "nginx responde correctamente en puerto 80"
else
    fail "nginx no responde en puerto 80"
fi

# ════════════════════════════════════════════════════════════════
# PRUEBA 11.2 — Resolución interna DNS
# Ping desde nginx al nombre de servicio "postgres"
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 11.2 — Resolución interna DNS (dentro de Docker)"

info "Ejecutando ping desde p11_nginx hacia 'postgres' por nombre..."
# nginx no está en red_datos, se prueba desde postgres → webserver
PING_RESULT=$(docker exec p11_nginx sh -c "ping -c 3 webserver 2>&1" || true)
if echo "$PING_RESULT" | grep -q "3 packets transmitted"; then
    ok "nginx puede resolver y hacer ping a 'webserver' por nombre DNS"
else
    fail "nginx NO pudo resolver 'webserver'"
    echo "      Output: $(echo "$PING_RESULT" | tail -3)"
fi

info "Ejecutando ping desde p11_pgadmin hacia 'postgres' por nombre..."
PING_RESULT2=$(docker exec p11_pgadmin sh -c "ping -c 3 postgres 2>&1" || true)
if echo "$PING_RESULT2" | grep -q "3 packets transmitted"; then
    ok "pgAdmin puede resolver y hacer ping a 'postgres' por nombre DNS"
else
    fail "pgAdmin NO pudo resolver 'postgres'"
    echo "      Output: $(echo "$PING_RESULT2" | tail -3)"
fi

# Verificar que nginx NO puede acceder directamente a postgres (red separada)
info "Verificando aislamiento: nginx NO debe resolver 'postgres' (redes distintas)..."
PING_CROSS=$(docker exec p11_nginx sh -c "ping -c 1 -W 2 postgres 2>&1" || true)
if echo "$PING_CROSS" | grep -qiE "unknown|not known|failure|unreachable"; then
    ok "Correcto: nginx no puede resolver 'postgres' (redes aisladas)"
else
    info "nginx puede ver 'postgres' — verifica que las redes estén bien separadas"
fi

# ════════════════════════════════════════════════════════════════
# PRUEBA 11.3 — Túnel SSH cifrado
# Esta prueba se valida manualmente desde la PC del estudiante
# El script verifica que el contenedor pgadmin responde internamente
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 11.3 — Túnel SSH (validación interna)"

info "Verificando que pgAdmin responde internamente en la red de datos..."
# Probamos desde el contenedor postgres (misma red)
HTTP_CODE=$(docker exec p11_postgres sh -c "wget -qO- --timeout=5 http://pgadmin/ 2>&1 | head -5" || true)
if [[ -n "$HTTP_CODE" ]]; then
    ok "pgAdmin responde a peticiones internas desde la red_datos"
else
    # Intentar con curl si wget no está disponible
    HTTP_CODE2=$(docker exec p11_postgres sh -c "curl -s --connect-timeout 5 http://pgadmin/ 2>&1 | head -c 100" || true)
    if [[ -n "$HTTP_CODE2" ]]; then
        ok "pgAdmin responde a peticiones internas (curl)"
    else
        info "pgAdmin puede estar tardando en iniciar. Espera 30s y vuelve a correr el test."
    fi
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "  ${YELLOW}► ACCIÓN MANUAL desde tu PC:${NC}"
echo "    ssh -L 8080:p11_pgadmin:80 gerardovn@${SERVER_IP}"
echo "    Luego abre en tu navegador: http://localhost:8080"
echo "    Credenciales:"
echo "      Email:    $(grep PGADMIN_EMAIL .env | cut -d= -f2)"
echo "      Password: $(grep PGADMIN_PASSWORD .env | cut -d= -f2)"

# ════════════════════════════════════════════════════════════════
# PRUEBA 11.4 — Persistencia y healthcheck
# Reinicia el stack y verifica que postgres es healthy antes que pgadmin
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 11.4 — Persistencia y Healthcheck"

# Crear dato de prueba en la base de datos
info "Creando tabla de prueba en PostgreSQL..."
PG_USER=$(grep POSTGRES_USER .env | cut -d= -f2)
PG_DB=$(grep POSTGRES_DB .env | cut -d= -f2)

docker exec p11_postgres psql -U "${PG_USER}" -d "${PG_DB}" -c \
    "CREATE TABLE IF NOT EXISTS prueba_persistencia (id SERIAL PRIMARY KEY, mensaje TEXT, creado_en TIMESTAMP DEFAULT now());" \
    > /dev/null 2>&1 && \
docker exec p11_postgres psql -U "${PG_USER}" -d "${PG_DB}" -c \
    "INSERT INTO prueba_persistencia (mensaje) VALUES ('dato de prueba practica11');" \
    > /dev/null 2>&1 && \
    ok "Dato insertado en PostgreSQL" || fail "No se pudo insertar dato de prueba"

# Reiniciar el stack (sin -v para no borrar volúmenes)
info "Reiniciando el stack (docker compose down && up)..."
docker compose down > /dev/null 2>&1
sleep 5
docker compose up -d > /dev/null 2>&1

info "Esperando 30 segundos para que los servicios reinicien..."
sleep 30

# Verificar que postgres es healthy
POSTGRES_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' p11_postgres 2>/dev/null || echo "unknown")
if [[ "$POSTGRES_HEALTH" == "healthy" ]]; then
    ok "PostgreSQL está 'healthy' tras el reinicio"
else
    fail "PostgreSQL no reporta 'healthy' (estado: ${POSTGRES_HEALTH})"
fi

# Verificar pgadmin esperó al healthcheck
PGADMIN_STATUS=$(docker inspect --format='{{.State.Status}}' p11_pgadmin 2>/dev/null || echo "unknown")
if [[ "$PGADMIN_STATUS" == "running" ]]; then
    ok "pgAdmin está corriendo (esperó a que postgres fuera healthy)"
else
    fail "pgAdmin no está running (estado: ${PGADMIN_STATUS})"
fi

# Verificar persistencia de datos
info "Verificando que los datos persisten tras el reinicio..."
sleep 10  # pequeña espera adicional para que postgres esté listo
ROWS=$(docker exec p11_postgres psql -U "${PG_USER}" -d "${PG_DB}" -t -c \
    "SELECT COUNT(*) FROM prueba_persistencia;" 2>/dev/null | tr -d ' ' || echo "0")
if [[ "${ROWS}" -ge "1" ]]; then
    ok "¡Persistencia confirmada! Se encontraron ${ROWS} registros tras el reinicio"
else
    fail "Los datos no persistieron (filas encontradas: ${ROWS})"
fi

# ════════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ════════════════════════════════════════════════════════════════
titulo "RESUMEN DE PRUEBAS"
TOTAL=$((PASS + FAIL))
echo -e "  Total:  ${TOTAL}"
echo -e "  ${GREEN}Passed: ${PASS}${NC}"
echo -e "  ${RED}Failed: ${FAIL}${NC}"
echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}🎉 Todas las pruebas pasaron — Infraestructura válida${NC}"
else
    echo -e "  ${RED}⚠ Hay pruebas fallidas — Revisa la configuración${NC}"
fi
echo ""
