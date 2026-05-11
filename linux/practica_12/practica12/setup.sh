#!/usr/bin/env bash
# ============================================================
#  setup.sh — Práctica 12/13 · Fedora Server
#  Servidor de correo privado + Roundcube Webmail (HTTPS real)
#  Ejecutar como: sudo bash setup.sh
# ============================================================
set -euo pipefail

USUARIO="gerardovn"
PROYECTO_DIR="/home/gerardovn/Administracion_Sistemas/linux/practica_12/practica12"
DOMAIN="reprobados.com"
MAIL_HOST="mail.reprobados.com"

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
mkdir -p "${PROYECTO_DIR}"/{certs,mail-config,logs,backups,roundcube,nginx}
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

# ── 4. Crear configuración de nginx SSL ──────────────────────
paso "Creando configuración de nginx (proxy SSL para Roundcube)..."
cat > "${PROYECTO_DIR}/nginx/roundcube-ssl.conf" << 'NGINXEOF'
server {
    listen 80;
    server_name _;
    return 301 https://$host:8443$request_uri;
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/nginx/certs/cert.pem;
    ssl_certificate_key /etc/nginx/certs/key.pem;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;

    location / {
        proxy_pass         http://roundcube:80;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        client_max_body_size 30M;
        proxy_read_timeout   120s;
    }
}
NGINXEOF
chown "${USUARIO}:${USUARIO}" "${PROYECTO_DIR}/nginx/roundcube-ssl.conf"
ok "nginx/roundcube-ssl.conf creado"

# ── 5. Configurar /etc/hosts para dominio local ──────────────
paso "Configurando resolución DNS local (modo laboratorio)..."
SERVER_IP=$(hostname -I | awk '{print $1}')

sed -i "/${DOMAIN}/d" /etc/hosts
sed -i "/${MAIL_HOST}/d" /etc/hosts
echo "${SERVER_IP}  ${MAIL_HOST}  ${DOMAIN}  mail" >> /etc/hosts
ok "/etc/hosts actualizado con ${MAIL_HOST} → ${SERVER_IP}"
echo ""
echo "  ⚠  En tu PC agrega a /etc/hosts (o drivers\\etc\\hosts en Windows):"
echo "     ${SERVER_IP}  ${MAIL_HOST}  ${DOMAIN}  mail"

# ── 6. Registros DNS de referencia ───────────────────────────
paso "Registros DNS para un dominio real:"
echo ""
echo "  MX    ${DOMAIN}.         10 ${MAIL_HOST}."
echo "  A     mail.${DOMAIN}.    ${SERVER_IP}"
echo "  TXT   ${DOMAIN}.         \"v=spf1 ip4:${SERVER_IP} -all\""
echo "  TXT   _dmarc.${DOMAIN}.  \"v=DMARC1; p=quarantine; rua=mailto:admin@${DOMAIN}\""

# ── 7. Configurar firewall ────────────────────────────────────
paso "Configurando firewalld..."
systemctl enable --now firewalld

firewall-cmd --permanent --add-port=25/tcp
firewall-cmd --permanent --add-port=587/tcp
firewall-cmd --permanent --add-port=465/tcp
firewall-cmd --permanent --add-port=143/tcp
firewall-cmd --permanent --add-port=993/tcp
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --permanent --add-port=8443/tcp
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
ok "Firewall configurado"

# ── 8. Levantar el stack ──────────────────────────────────────
paso "Levantando el stack de correo..."
cd "${PROYECTO_DIR}"
docker compose up -d

echo ""
echo "  Esperando 60 segundos para que los servicios inicien..."
sleep 60

# ── 9. Crear cuentas de correo ───────────────────────────────
paso "Creando cuentas de correo..."
source "${PROYECTO_DIR}/.env"

crear_cuenta() {
    local EMAIL="$1"
    local PASS="$2"
    echo "  Creando ${EMAIL}..."
    docker exec p12_mailserver setup email add "${EMAIL}" "${PASS}" 2>/dev/null && \
        ok "${EMAIL} creada" || echo "  (puede que ya exista, continuando...)"
}

crear_cuenta "${MAIL_USER1}" "${MAIL_PASS1}"
crear_cuenta "${MAIL_USER2}" "${MAIL_PASS2}"

# ── 10. Configurar OpenDKIM ───────────────────────────────────
paso "Configurando OpenDKIM para ${DOMAIN}..."
docker exec p12_mailserver setup config dkim domain "${DOMAIN}" 2>/dev/null || true
sleep 5
DKIM_KEY=$(docker exec p12_mailserver cat /tmp/docker-mailserver/opendkim/keys/${DOMAIN}/mail.txt 2>/dev/null || echo "no disponible aún")
echo ""
echo "  Registro DKIM:"
echo "  ${DKIM_KEY}"

# ── 11. Estado final ──────────────────────────────────────────
paso "Estado del stack:"
docker compose ps

echo ""
echo "================================================================"
echo "  ✔ Setup completado"
echo ""
echo "  ACCESOS:"
echo "  • Roundcube HTTP  → http://${SERVER_IP}:8080  (redirige a HTTPS)"
echo "  • Roundcube HTTPS → https://${SERVER_IP}:8443  ✓ TLS autofirmado"
echo ""
echo "  CUENTAS:"
echo "  • ${MAIL_USER1}  /  ${MAIL_PASS1}"
echo "  • ${MAIL_USER2}  /  ${MAIL_PASS2}"
echo ""
echo "  El navegador pedirá aceptar el certificado autofirmado."
echo "  En Chrome: 'Configuración avanzada' → 'Continuar de todas formas'"
echo ""
echo "  THUNDERBIRD / MAILSPRING:"
echo "  • IMAP: ${SERVER_IP}  Puerto: 993  SSL: Sí"
echo "  • SMTP: ${SERVER_IP}  Puerto: 587  STARTTLS: Sí"
echo "================================================================"