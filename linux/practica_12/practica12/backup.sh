#!/usr/bin/env bash
# ============================================================
#  backup.sh — Respaldo de buzones · Práctica 12
#  Copia comprimida de /var/mail cada ejecución
#  Instalar como cron o systemd timer (ver instrucciones abajo)
# ============================================================
set -euo pipefail

PROYECTO_DIR="/home/gerardovn/practica12"
BACKUP_DIR="${PROYECTO_DIR}/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/mail_backup_${TIMESTAMP}.tar.gz"
RETENTION_DAYS=7   # días que se conservan los backups
MAX_BACKUPS=10      # máximo de archivos de backup

# ── Colores ───────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}✔${NC} $1"; }
err()  { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}✘${NC} $1"; }

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ══ Iniciando respaldo de buzones ══"

# ── Verificar que el contenedor esté corriendo ───────────────
if ! docker inspect --format='{{.State.Status}}' p12_mailserver 2>/dev/null | grep -q "running"; then
    err "El contenedor p12_mailserver no está corriendo. Abortando."
    exit 1
fi

mkdir -p "${BACKUP_DIR}"

# ── Exportar buzones desde el volumen Docker ─────────────────
ok "Creando backup: ${BACKUP_FILE}"
docker run --rm \
    -v practica12_mail_data:/mail_data:ro \
    -v "${BACKUP_DIR}":/backup \
    alpine:latest \
    tar czf "/backup/mail_backup_${TIMESTAMP}.tar.gz" -C /mail_data .

# ── Verificar integridad del backup ──────────────────────────
if tar tzf "${BACKUP_FILE}" > /dev/null 2>&1; then
    SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
    ok "Backup verificado correctamente — Tamaño: ${SIZE}"
else
    err "El backup está corrupto: ${BACKUP_FILE}"
    rm -f "${BACKUP_FILE}"
    exit 1
fi

# ── Log de auditoría ─────────────────────────────────────────
LOG_FILE="${BACKUP_DIR}/backup.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] BACKUP OK — ${BACKUP_FILE} (${SIZE})" >> "${LOG_FILE}"

# ── Limpiar backups antiguos (retención) ─────────────────────
ok "Limpiando backups con más de ${RETENTION_DAYS} días..."
find "${BACKUP_DIR}" -name "mail_backup_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

# Si hay más de MAX_BACKUPS, eliminar los más viejos
TOTAL=$(find "${BACKUP_DIR}" -name "mail_backup_*.tar.gz" | wc -l)
if [[ ${TOTAL} -gt ${MAX_BACKUPS} ]]; then
    EXCESO=$((TOTAL - MAX_BACKUPS))
    find "${BACKUP_DIR}" -name "mail_backup_*.tar.gz" | sort | head -n "${EXCESO}" | xargs rm -f
    ok "Eliminados ${EXCESO} backups viejos (límite: ${MAX_BACKUPS})"
fi

ok "Backups disponibles:"
ls -lh "${BACKUP_DIR}"/mail_backup_*.tar.gz 2>/dev/null || echo "  (ninguno)"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ══ Respaldo completado ══"
