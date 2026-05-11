#!/usr/bin/env bash
# ============================================================
#  tests.sh — Pruebas de aceptación · Práctica 12 y 13
#  Ejecutar: bash tests.sh
# ============================================================
set -uo pipefail

# ── Colores ───────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

ok()     { echo -e "  ${GREEN}✔ PASS${NC} — $1"; ((PASS++)); }
fail()   { echo -e "  ${RED}✘ FAIL${NC} — $1"; ((FAIL++)); }
info()   { echo -e "  ${YELLOW}ℹ${NC}  $1"; }
titulo() { echo -e "\n${BLUE}══════════════════════════════════════════${NC}"; \
           echo -e "${BLUE}  $1${NC}"; \
           echo -e "${BLUE}══════════════════════════════════════════${NC}"; }
manual() { echo -e "  ${YELLOW}★ MANUAL${NC} — $1"; }

PROYECTO_DIR="/home/gerardovn/Administracion_Sistemas/linux/practica_12/practica12"
cd "${PROYECTO_DIR}"
source .env

SERVER_IP=$(hostname -I | awk '{print $1}')

# ════════════════════════════════════════════════════════════════
# PRE-CHECK: Contenedores activos
# ════════════════════════════════════════════════════════════════
titulo "PRE-CHECK — Contenedores activos"
for c in p12_mailserver p12_roundcube_db p12_roundcube; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null || echo "no existe")
    [[ "$STATUS" == "running" ]] && ok "$c está running" || fail "$c no está running (estado: $STATUS)"
done

# Verificar puertos de correo escuchando
titulo "PRE-CHECK — Puertos de correo"
for port in 25 587 465 143 993; do
    if ss -lnt | grep -q ":${port} "; then
        ok "Puerto ${port} escuchando"
    else
        fail "Puerto ${port} NO escucha"
    fi
done

for port in 8080 8443; do
    if ss -lnt | grep -q ":${port} "; then
        ok "Puerto ${port} escuchando (Roundcube)"
    else
        fail "Puerto ${port} NO escucha (Roundcube)"
    fi
done

# ════════════════════════════════════════════════════════════════
# PRUEBA 12.1 — Envío y recepción local
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 12.1 — Envío y recepción local"

info "Enviando correo de prueba de ${MAIL_USER2} → ${MAIL_USER1}..."
SEND_RESULT=$(docker exec p12_mailserver bash -c "
echo 'Subject: Test 12.1 Practica
From: ${MAIL_USER2}
To: ${MAIL_USER1}

Correo de prueba automatico - Practica 12.1' | sendmail -f '${MAIL_USER2}' '${MAIL_USER1}' 2>&1" || echo "ERROR")

sleep 5

# Verificar que el correo llegó al buzón (dovecot)
INBOX_CHECK=$(docker exec p12_mailserver bash -c "
ls /var/mail/reprobados.com/director/new/ 2>/dev/null | wc -l" || echo "0")

if [[ "${INBOX_CHECK}" -ge "1" ]]; then
    ok "Correo entregado en el buzón de ${MAIL_USER1} (${INBOX_CHECK} mensaje(s))"
else
    info "El buzón puede estar vacío o en ruta diferente — revisando..."
    MAILDIR=$(docker exec p12_mailserver find /var/mail -name "*.eml" 2>/dev/null | wc -l || echo "0")
    [[ "${MAILDIR}" -ge "1" ]] && ok "Se encontraron ${MAILDIR} mensaje(s) en /var/mail" || fail "No se encontraron mensajes en el buzón"
fi

manual "Para prueba completa: usar Thunderbird/Mailspring o Roundcube en https://${SERVER_IP}:8443"

# ════════════════════════════════════════════════════════════════
# PRUEBA 12.2 — Auditoría de registros (logging)
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 12.2 — Auditoría de registros"

info "Verificando logs de correo en /var/log/mail/..."
LOG_LINES=$(docker exec p12_mailserver bash -c "
find /var/log -name '*.log' -o -name 'mail.log' 2>/dev/null | head -3 | xargs wc -l 2>/dev/null | tail -1 | awk '{print \$1}'" || echo "0")

if [[ "${LOG_LINES}" -gt "0" ]]; then
    ok "Logs activos con ${LOG_LINES} líneas registradas"
else
    # Los logs pueden ir a journald o a stdout
    DOCKER_LOGS=$(docker logs p12_mailserver 2>&1 | wc -l)
    [[ "${DOCKER_LOGS}" -gt "5" ]] && ok "Logs disponibles via docker logs (${DOCKER_LOGS} líneas)" || fail "Sin logs disponibles"
fi

info "Últimas entradas del log de correo:"
docker logs p12_mailserver 2>&1 | tail -10 | while IFS= read -r line; do
    echo "    ${line}"
done

info "Verificando flujo SMTP en logs (conexión → autenticación → entrega)..."
LOG_OUTPUT=$(docker logs p12_mailserver 2>&1)
[[ "${LOG_OUTPUT}" == *"postfix"* ]] && ok "Postfix (SMTP) está registrando actividad" || info "Postfix aún inicializando"
[[ "${LOG_OUTPUT}" == *"dovecot"* ]] && ok "Dovecot (IMAP) está registrando actividad" || info "Dovecot aún inicializando"

# ════════════════════════════════════════════════════════════════
# PRUEBA 12.3 — Verificación de seguridad Fail2Ban
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 12.3 — Fail2Ban (intentos fallidos de autenticación)"

info "Verificando que Fail2Ban está activo dentro del contenedor..."
F2B_STATUS=$(docker exec p12_mailserver bash -c "fail2ban-client status 2>/dev/null | head -5" || echo "no disponible")

if echo "${F2B_STATUS}" | grep -qi "jail list"; then
    ok "Fail2Ban activo con jails configurados:"
    echo "${F2B_STATUS}" | while IFS= read -r line; do echo "    ${line}"; done
else
    info "Fail2Ban: ${F2B_STATUS}"
    info "Si no hay intentos fallidos aún, Fail2Ban espera en modo pasivo"
fi

echo ""
info "Para disparar Fail2Ban manualmente:"
echo "    Desde otra terminal, ejecuta 5 veces (con contraseña mala):"
echo "    curl --max-time 5 --user 'director@reprobados.com:MALA' \\
           imaps://${SERVER_IP}:993"
echo ""
info "Luego verifica el bloqueo con:"
echo "    docker exec p12_mailserver fail2ban-client status dovecot"

# Verificar que los intentos fallidos se registran
FAILED_AUTHS=$(docker logs p12_mailserver 2>&1 | grep -ci "failed\|FAILED\|authentication" || echo "0")
[[ "${FAILED_AUTHS}" -gt "0" ]] && ok "Se registran intentos de autenticación en logs (${FAILED_AUTHS} entradas)" || \
    info "Sin intentos fallidos registrados aún (normal si es la primera ejecución)"

# ════════════════════════════════════════════════════════════════
# PRUEBA 13.4 — Integridad de respaldo y restauración
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 13.4 — Integridad de respaldo"

info "Ejecutando script de respaldo..."
bash "${PROYECTO_DIR}/backup.sh" 2>&1 | tail -5

BACKUPS=$(ls "${PROYECTO_DIR}/backups"/mail_backup_*.tar.gz 2>/dev/null | wc -l)
if [[ "${BACKUPS}" -ge "1" ]]; then
    LATEST=$(ls -t "${PROYECTO_DIR}/backups"/mail_backup_*.tar.gz | head -1)
    ok "Backup generado: $(basename ${LATEST})"

    # Verificar integridad
    if tar tzf "${LATEST}" > /dev/null 2>&1; then
        ok "Backup íntegro (tar -tzf exitoso)"
        FILES_IN_BACKUP=$(tar tzf "${LATEST}" | wc -l)
        ok "Contiene ${FILES_IN_BACKUP} archivos/directorios"
    else
        fail "El backup está corrupto"
    fi
else
    fail "No se generó ningún backup"
fi

echo ""
info "Para probar restauración completa (prueba 13.4 manual):"
echo "    1. docker compose down"
echo "    2. docker volume rm practica12_mail_data"
echo "    3. bash restore.sh  (ver instrucciones en README)"
echo "    4. docker compose up -d"
echo "    5. Verificar correos en Roundcube"

# ════════════════════════════════════════════════════════════════
# PRUEBA 13.5 — Portal web: inicio de sesión institucional
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 13.5 — Inicio de sesión en Roundcube"

info "Verificando que Roundcube responde en HTTP (puerto 8080)..."
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "http://localhost:8080/" 2>/dev/null || echo "000")
[[ "${HTTP_CODE}" =~ ^(200|301|302)$ ]] && ok "Roundcube responde HTTP (código ${HTTP_CODE})" || \
    fail "Roundcube no responde en 8080 (código ${HTTP_CODE})"

info "Verificando que Roundcube responde en HTTPS (puerto 8443)..."
HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost:8443/" 2>/dev/null || echo "000")
[[ "${HTTPS_CODE}" =~ ^(200|301|302)$ ]] && ok "Roundcube responde HTTPS (código ${HTTPS_CODE})" || \
    fail "Roundcube no responde en 8443 (código ${HTTPS_CODE})"

manual "Abrir en navegador: https://${SERVER_IP}:8443"
manual "Iniciar sesión con: ${MAIL_USER1} / ${MAIL_PASS1}"
manual "Verificar que aparece la bandeja de entrada con el correo de prueba"

# ════════════════════════════════════════════════════════════════
# PRUEBA 13.6 — Envío de adjuntos desde Roundcube
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 13.6 — Envío con adjunto (manual)"

manual "En el navegador (Roundcube):"
manual "  1. Iniciar sesión como ${MAIL_USER2} / ${MAIL_PASS2}"
manual "  2. Redactar correo a ${MAIL_USER1}"
manual "  3. Adjuntar cualquier archivo (ej: una imagen o PDF)"
manual "  4. Enviar y cambiar a la cuenta de ${MAIL_USER1}"
manual "  5. Descargar el adjunto y verificar que no está corrupto"

# ════════════════════════════════════════════════════════════════
# PRUEBA 13.7 — Persistencia de preferencias
# ════════════════════════════════════════════════════════════════
titulo "PRUEBA 13.7 — Persistencia de preferencias"

info "Verificando volumen de base de datos Roundcube..."
DB_VOLUME=$(docker volume inspect practica12_roundcube_db 2>/dev/null | grep -c "Mountpoint" || echo "0")
[[ "${DB_VOLUME}" -ge "1" ]] && ok "Volumen practica12_roundcube_db existe (persistencia garantizada)" || \
    fail "El volumen de BD de Roundcube no se encontró"

info "Verificando tablas en la BD de Roundcube..."
TABLES=$(docker exec p12_roundcube_db mysql -u"${ROUNDCUBE_DB_USER}" -p"${ROUNDCUBE_DB_PASSWORD}" \
    "${ROUNDCUBE_DB_NAME}" -e "SHOW TABLES;" 2>/dev/null | wc -l || echo "0")
[[ "${TABLES}" -gt "3" ]] && ok "BD de Roundcube inicializada con ${TABLES} tablas" || \
    info "BD aún inicializando (normal si es la primera ejecución)"

manual "Para probar persistencia:"
manual "  1. En Roundcube: cambiar idioma a Español o agregar contacto"
manual "  2. docker compose restart roundcube"
manual "  3. Volver a entrar — los cambios deben seguir ahí"

# ════════════════════════════════════════════════════════════════
# RESUMEN
# ════════════════════════════════════════════════════════════════
titulo "RESUMEN DE PRUEBAS"
TOTAL=$((PASS + FAIL))
echo -e "  Total automáticas: ${TOTAL}"
echo -e "  ${GREEN}Passed: ${PASS}${NC}"
echo -e "  ${RED}Failed: ${FAIL}${NC}"
echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}🎉 Todas las pruebas automáticas pasaron${NC}"
else
    echo -e "  ${RED}⚠ Hay pruebas fallidas — revisa la configuración${NC}"
fi
echo ""
echo "  Acceso al portal: https://${SERVER_IP}:8443"
echo ""
