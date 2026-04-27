#!/bin/sh
FECHA=$(date +%Y%m%d_%H%M%S)
ARCHIVO="/backups/backup_${FECHA}.sql"

echo "[$(date)] Iniciando respaldo de base de datos..."

pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$ARCHIVO"

if [ $? -eq 0 ]; then
    echo "[$(date)] Respaldo exitoso: $ARCHIVO"
else
    echo "[$(date)] ERROR al crear respaldo"
    exit 1
fi

find /backups -name "backup_*.sql" -mtime +7 -delete
echo "[$(date)] Limpieza de respaldos antiguos completada."
