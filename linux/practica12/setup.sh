#!/usr/bin/env bash
# ============================================================
#  setup.sh — Práctica 12/13 · Fedora Server
#  Servidor de correo privado + Roundcube Webmail
#  Ejecutar como: sudo bash setup.sh
# ============================================================
set -euo pipefail

USUARIO="gerardovn"
PROYECTO_DIR="/home/${USUARIO}/practica12"
DOMAIN="reprobados.com"
MAIL_HOST="mail.reprobados.com"

# ── Colores ───────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
paso() { echo -e "\n${BLUE}► $1${NC}"; }
ok()   { echo -e "  ${GREEN}✔ $1${NC}"; }

echo "================================================================"
echo "  PRÁCTICA 12/13 — Servidor de Correo Privado + Webmail"
echo "  Dominio: ${DOMAIN}"
echo "================================================================"

# ── 1. Verificar dependencias ─────────────────────────────────
paso "Verificando dependencias..."
docker --version              && ok "Docker disponible"
docker compose version        && ok "Docker Compose disponible"
openssl version               && ok "OpenSSL disponible"

# ── 2. Crear estructura de directorios ───────────────────────
paso "Creando estructura de directorios..."
mkdir -p "${PROYECTO_DIR}"/{certs,mail-config,logs,backups,roundcube}
chown -R "${USUARIO}:${USUARIO}" "${PROYECTO_DIR}"
ok "Directorios creados"

# ── 3. Generar certificados TLS autofirmados ─────────────────
paso "Generando certificados TLS autofirmados para ${MAIL_HOST}..."
CERT_DIR="${PROYECTO_DIR}/certs"

openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "${CERT_DIR}/key.pem" \
    -out    "${CERT_DIR}/cert.pem" \
    -subj "/C=MX/ST=Sinaloa/L=Los Mochis/O=Reprobados/CN=${MAIL_HOST}" \
    -addext "subjectAltName=DNS:${MAIL_HOST},DNS:${DOMAIN},DNS:mail,IP:127.0.0.1"

chmod 600 "${CERT_DIR}/key.pem"
chmod 644 "${CERT_DIR}/cert.pem"
chown -R "${USUARIO}:${USUARIO}" "${CERT_DIR}"
ok "Certificados generados en ${CERT_DIR}"

# ── 4. Configurar /etc/hosts para dominio local (lab) ────────
paso "Configurando resolución DNS local (modo laboratorio)..."
SERVER_IP=$(hostname -I | awk '{print $1}')

# Eliminar entradas previas del dominio
sed -i "/${DOMAIN}/d" /etc/hosts
sed -i "/${MAIL_HOST}/d" /etc/hosts

# Agregar entradas
echo "${SERVER_IP}  ${MAIL_HOST}  ${DOMAIN}  mail" >> /etc/hosts
ok "/etc/hosts actualizado con ${MAIL_HOST} → ${SERVER_IP}"
echo ""
echo "  ⚠  En tu PC también agrega esta línea a /etc/hosts (o C:\\Windows\\System32\\drivers\\etc\\hosts):"
echo "     ${SERVER_IP}  ${MAIL_HOST}  ${DOMAIN}  mail"

# ── 5. Simular registros DNS (mostrar lo que iría en DNS real) ─
paso "Registros DNS que configurarías en un dominio real:"
echo ""
echo "  Tipo  | Nombre              | Valor"
echo "  ------|---------------------|----------------------------------------"
echo "  MX    | ${DOMAIN}.          | 10 ${MAIL_HOST}."
echo "  A     | mail.${DOMAIN}.     | ${SERVER_IP}"
echo "  TXT   | ${DOMAIN}.          | \"v=spf1 ip4:${SERVER_IP} -all\""
echo "  TXT   | _dmarc.${DOMAIN}.   | \"v=DMARC1; p=quarantine; rua=mailto:admin@${DOMAIN}\""
echo "  (DKIM se genera al iniciar mailserver — ver setup DKIM más abajo)"
echo ""

# ── 6. Configurar firewall (coexistencia con práctica 11) ────
paso "Configurando firewalld (coexistencia con práctica 11)..."
systemctl enable --now firewalld

# Correo
firewall-cmd --permanent --add-port=25/tcp     # SMTP
firewall-cmd --permanent --add-port=587/tcp    # SMTP Submission
firewall-cmd --permanent --add-port=465/tcp    # SMTPS
firewall-cmd --permanent --add-port=143/tcp    # IMAP
firewall-cmd --permanent --add-port=993/tcp    # IMAPS
firewall-cmd --permanent --add-port=8080/tcp   # Roundcube HTTP
firewall-cmd --permanent --add-port=8443/tcp   # Roundcube HTTPS

# SSH (garantizar acceso)
firewall-cmd --permanent --add-service=ssh

firewall-cmd --reload
ok "Firewall configurado"
firewall-cmd --list-ports

# ── 7. Levantar el stack ──────────────────────────────────────
paso "Levantando el stack de correo..."
cd "${PROYECTO_DIR}"
docker compose up -d

echo ""
echo "  Esperando 60 segundos para que los servicios inicien..."
sleep 60

# ── 8. Crear cuentas de correo ───────────────────────────────
paso "Creando cuentas de correo..."

# Leer credenciales del .env
source "${PROYECTO_DIR}/.env"

# Función para crear cuenta
crear_cuenta() {
    local EMAIL="$1"
    local PASS="$2"
    echo "  Creando ${EMAIL}..."
    docker exec p12_mailserver setup email add "${EMAIL}" "${PASS}" 2>/dev/null && \
        ok "${EMAIL} creada" || \
        echo "  (puede que ya exista, continuando...)"
}

crear_cuenta "${MAIL_USER1}" "${MAIL_PASS1}"
crear_cuenta "${MAIL_USER2}" "${MAIL_PASS2}"

# ── 9. Configurar OpenDKIM ────────────────────────────────────
paso "Configurando OpenDKIM para ${DOMAIN}..."
docker exec p12_mailserver setup config dkim domain "${DOMAIN}" 2>/dev/null || true
sleep 5

DKIM_KEY=$(docker exec p12_mailserver cat /tmp/docker-mailserver/opendkim/keys/${DOMAIN}/mail.txt 2>/dev/null || echo "no disponible aún")
echo ""
echo "  Registro DKIM para agregar a tu DNS:"
echo "  ${DKIM_KEY}"
echo ""

# ── 10. Estado final ─────────────────────────────────────────
paso "Estado del stack:"
docker compose ps

echo ""
echo "================================================================"
echo "  ✔ Setup completado"
echo ""
echo "  ACCESOS:"
echo "  • Roundcube (HTTP)  → http://${SERVER_IP}:8080"
echo "  • Roundcube (HTTPS) → https://${SERVER_IP}:8443"
echo ""
echo "  CUENTAS CREADAS:"
echo "  • ${MAIL_USER1}  /  ${MAIL_PASS1}"
echo "  • ${MAIL_USER2}  /  ${MAIL_PASS2}"
echo ""
echo "  THUNDERBIRD / MAILSPRING (configuración manual):"
echo "  • Servidor IMAP: ${SERVER_IP}  Puerto: 993  SSL: Sí"
echo "  • Servidor SMTP: ${SERVER_IP}  Puerto: 587  STARTTLS: Sí"
echo "================================================================"
