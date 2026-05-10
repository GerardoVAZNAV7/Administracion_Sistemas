#!/usr/bin/env bash
# ============================================================
#  setup.sh — Práctica 11 · Fedora Server
#  Configura firewall y levanta el stack completo
#  Ejecutar como: sudo bash setup.sh
# ============================================================
set -euo pipefail

USUARIO="gerardovn"
PROYECTO_DIR="/home/${USUARIO}/practica11"

echo "================================================================"
echo "  PRÁCTICA 11 — Setup en Fedora Server"
echo "================================================================"

# ── 1. Verificar dependencias ─────────────────────────────────────
echo ""
echo "► Verificando Docker y Docker Compose..."
docker --version  || { echo "ERROR: Docker no encontrado"; exit 1; }
docker compose version || { echo "ERROR: Docker Compose no encontrado"; exit 1; }

# ── 2. Crear carpeta del proyecto si no existe ────────────────────
echo ""
echo "► Preparando directorio del proyecto en ${PROYECTO_DIR}..."
mkdir -p "${PROYECTO_DIR}"
chown "${USUARIO}:${USUARIO}" "${PROYECTO_DIR}"

# ── 3. Configurar firewall con firewalld ──────────────────────────
echo ""
echo "► Configurando firewalld..."

# Asegura que firewalld esté activo
systemctl enable --now firewalld

# Permitir SSH (imprescindible para no perder acceso)
firewall-cmd --permanent --add-service=ssh

# Permitir el puerto 80 (nginx público)
firewall-cmd --permanent --add-port=80/tcp

# Bloquear acceso directo a puertos internos desde el exterior
# (pgAdmin y Postgres no tienen puerto en host, así que ya están
#  protegidos por Docker. Estas reglas son defensa en profundidad.)
firewall-cmd --permanent --remove-port=5432/tcp 2>/dev/null || true
firewall-cmd --permanent --remove-port=5050/tcp 2>/dev/null || true
firewall-cmd --permanent --remove-port=8080/tcp 2>/dev/null || true

# Aplicar cambios
firewall-cmd --reload

echo "  ✔ Firewall configurado:"
firewall-cmd --list-all

# ── 4. Levantar el stack ──────────────────────────────────────────
echo ""
echo "► Levantando el stack con Docker Compose..."
cd "${PROYECTO_DIR}"
docker compose up -d --build

echo ""
echo "► Esperando 15 segundos para que los servicios inicien..."
sleep 15

# ── 5. Resumen de estado ──────────────────────────────────────────
echo ""
echo "► Estado de los contenedores:"
docker compose ps

echo ""
echo "================================================================"
echo "  ✔ Setup completado"
echo ""
echo "  Accesos:"
echo "  • Web pública  → http://$(hostname -I | awk '{print $1}')"
echo "  • pgAdmin      → solo vía túnel SSH:"
echo ""
echo "    Desde tu PC ejecuta:"
echo "    ssh -L 8080:p11_pgadmin:80 ${USUARIO}@$(hostname -I | awk '{print $1}')"
echo "    Luego abre: http://localhost:8080"
echo "================================================================"
