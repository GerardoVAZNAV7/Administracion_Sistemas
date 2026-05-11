#!/usr/bin/env bash
# ============================================================
#  restore.sh — Restauración de buzones · Práctica 12
#  Uso: sudo bash restore.sh [archivo_backup.tar.gz]
# ============================================================
set -euo pipefail

PROYECTO_DIR="/home/gerardovn/Administracion_Sistemas/linux/practica_12/practica12"
BACKUP_DIR="${PROYECTO_DIR}/backups"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "[$(date '+%H:%M:%S')] ${GREEN}✔${NC} $1"; }
err()  { echo -e "[$(date '+%H:%M:%S')] ${RED}✘${NC} $1"; exit 1; }
info() { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}ℹ${NC}  $1"; }

# ── Seleccionar backup ────────────────────────────────────────
if [[ $# -ge 1 ]] && [[ -f "$1" ]]; then
    BACKUP_FILE="$1"
else
    # Usar el más reciente
    BACKUP_FILE=$(ls -t "${BACKUP_DIR}"/mail_backup_*.tar.gz 2>/dev/null | head -1 || true)
    [[ -z "${BACKUP_FILE}" ]] && err "No se encontraron backups en ${BACKUP_DIR}"
fi

echo "============================================================"
echo "  RESTAURACIÓN DE BUZONES"
echo "  Archivo: $(basename ${BACKUP_FILE})"
echo "============================================================"

# ── Verificar integridad antes de restaurar ───────────────────
info "Verificando integridad del backup..."
tar tzf "${BACKUP_FILE}" > /dev/null 2>&1 && ok "Backup íntegro" || err "Backup corrupto"

# ── Detener el stack ──────────────────────────────────────────
info "Deteniendo el stack..."
cd "${PROYECTO_DIR}"
docker compose down
ok "Stack detenido"

# ── Recrear volumen limpio ────────────────────────────────────
info "Recreando volumen practica12_mail_data..."
docker volume rm practica12_mail_data 2>/dev/null || true
docker volume create practica12_mail_data
ok "Volumen recreado"

# ── Restaurar datos ───────────────────────────────────────────
info "Restaurando buzones desde backup..."
docker run --rm \
    -v practica12_mail_data:/mail_data \
    -v "${BACKUP_DIR}":/backup:ro \
    alpine:latest \
    tar xzf "/backup/$(basename ${BACKUP_FILE})" -C /mail_data

ok "Datos restaurados en el volumen"

# ── Levantar el stack ─────────────────────────────────────────
info "Iniciando el stack..."
docker compose up -d
ok "Stack iniciado"

echo ""
info "Esperando 45 segundos para que los servicios arranquen..."
sleep 45

docker compose ps

echo ""
echo "============================================================"
echo "  ✔ Restauración completada"
echo "  Verifica tus correos en Roundcube o tu cliente de correo"
echo "============================================================"
