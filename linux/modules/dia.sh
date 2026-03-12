#!/bin/bash
# =============================================================================
# reset_ftp_fedora.sh — Limpieza TOTAL del entorno FTP vsftpd en Fedora
# Ejecutar como root: sudo bash reset_ftp_fedora.sh
# =============================================================================

BASE="/srv/ftp"
FSTAB="/etc/fstab"

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Ejecutar como root: sudo bash $0"
    exit 1
fi

echo ""
echo "========================================="
echo "   LIMPIEZA TOTAL DEL ENTORNO FTP FEDORA"
echo "========================================="

# ─────────────────────────────────────────────
# 1. DETENER VSFTPD
# ─────────────────────────────────────────────
echo "[1] Deteniendo vsftpd..."
systemctl stop    vsftpd 2>/dev/null
systemctl disable vsftpd 2>/dev/null
echo "    [OK]"

# ─────────────────────────────────────────────
# 2. DESMONTAR TODOS LOS BIND MOUNTS FTP
# ─────────────────────────────────────────────
echo "[2] Desmontando bind mounts..."

# Usuarios del grupo ftp-users
ftp_gid=$(getent group ftp-users | cut -d: -f3 2>/dev/null)
if [[ -n "$ftp_gid" ]]; then
    members=$(awk -F: -v gid="$ftp_gid" '$4 == gid {print $1}' /etc/passwd 2>/dev/null)
    for u in $members; do
        for dir in general reprobados recursadores; do
            mountpoint -q "/home/$u/$dir" 2>/dev/null && \
                umount -l "/home/$u/$dir" 2>/dev/null && \
                echo "    [OK] Desmontado /home/$u/$dir"
        done
    done
fi

# Montaje anonimo
mountpoint -q "$BASE/anonymous/general" 2>/dev/null && \
    umount -l "$BASE/anonymous/general" 2>/dev/null && \
    echo "    [OK] Desmontado $BASE/anonymous/general"

# Residuos bajo /home y /srv/ftp
for mp in $(findmnt -rn -o TARGET 2>/dev/null | grep -E '^(/home|/srv/ftp)' | sort -r); do
    umount -l "$mp" 2>/dev/null && echo "    [OK] Desmontado residual: $mp"
done
echo "    [OK] Bind mounts limpios."

# ─────────────────────────────────────────────
# 3. ELIMINAR USUARIOS FTP
# ─────────────────────────────────────────────
echo "[3] Eliminando usuarios FTP..."

# Detectar el usuario real que ejecuto sudo para NO eliminarlo
SUDO_USER_REAL="${SUDO_USER:-}"
if [[ -z "$SUDO_USER_REAL" ]]; then
    SUDO_USER_REAL=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)
fi
echo "    [~] Usuario del sistema protegido: '$SUDO_USER_REAL'"

EXCLUIR=(root daemon bin sys sync games man lp mail news uucp proxy
         www-data backup list irc gnats nobody systemd-network
         systemd-resolve syslog messagebus _apt ftp vsftpd
         "$SUDO_USER_REAL")

if [[ -n "$ftp_gid" && -n "$members" ]]; then
    for u in $members; do
        skip=false
        for e in "${EXCLUIR[@]}"; do [[ "$u" == "$e" ]] && skip=true && break; done
        if [[ "$skip" == "false" ]]; then
            # Quitar inmutabilidad antes de borrar home
            for dir in general reprobados recursadores "$u"; do
                chattr -i "/home/$u/$dir" 2>/dev/null
            done
            userdel -r "$u" 2>/dev/null
            echo "    [OK] Usuario '$u' eliminado."
        fi
    done
else
    echo "    [!] Sin usuarios FTP que eliminar."
fi

# ─────────────────────────────────────────────
# 4. ELIMINAR GRUPOS FTP
# ─────────────────────────────────────────────
echo "[4] Eliminando grupos FTP..."
for g in reprobados recursadores ftp-users; do
    if getent group "$g" &>/dev/null; then
        groupdel "$g" 2>/dev/null
        echo "    [OK] Grupo '$g' eliminado."
    else
        echo "    [!] Grupo '$g' no existia."
    fi
done

# ─────────────────────────────────────────────
# 5. QUITAR ATRIBUTOS INMUTABLES Y BORRAR /srv/ftp
# ─────────────────────────────────────────────
echo "[5] Eliminando /srv/ftp..."
if [[ -d "$BASE" ]]; then
    find "$BASE" -type d 2>/dev/null | while read -r d; do chattr -i "$d" 2>/dev/null; done
    find "$BASE" -type f 2>/dev/null | while read -r f; do chattr -i "$f" 2>/dev/null; done
    rm -rf "$BASE"
    echo "    [OK] /srv/ftp eliminado."
else
    echo "    [!] /srv/ftp no existia."
fi

# ─────────────────────────────────────────────
# 6. LIMPIAR /etc/fstab
# ─────────────────────────────────────────────
echo "[6] Limpiando /etc/fstab..."
cp "$FSTAB" "${FSTAB}.bak_ftp_reset" 2>/dev/null
sed -i '\|/srv/ftp|d' "$FSTAB"
sed -i '\|ftp.*bind|d'  "$FSTAB"
# Limpiar entradas de homes de usuarios FTP residuales
sed -i '\|/home/.*/general|d'      "$FSTAB"
sed -i '\|/home/.*/reprobados|d'   "$FSTAB"
sed -i '\|/home/.*/recursadores|d' "$FSTAB"
echo "    [OK] Entradas FTP eliminadas. Backup: ${FSTAB}.bak_ftp_reset"

# ─────────────────────────────────────────────
# 7. RESTAURAR vsftpd.conf A VALORES POR DEFECTO
# ─────────────────────────────────────────────
echo "[7] Restaurando vsftpd.conf..."
if [[ -f /etc/vsftpd/vsftpd.conf ]]; then
    cp /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.bak_reset 2>/dev/null
    cat > /etc/vsftpd/vsftpd.conf << 'DEFAULT'
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES
listen=NO
listen_ipv6=YES
pam_service_name=vsftpd
userlist_enable=YES
DEFAULT
    echo "    [OK] vsftpd.conf restablecido."
else
    echo "    [!] vsftpd.conf no encontrado."
fi

# ─────────────────────────────────────────────
# 8. LIMPIAR /etc/shells
# ─────────────────────────────────────────────
echo "[8] Limpiando /etc/shells..."
nologin_count=$(grep -c "/sbin/nologin" /etc/shells 2>/dev/null)
if [[ "$nologin_count" -gt 1 ]]; then
    awk '!/\/sbin\/nologin/{print} /\/sbin\/nologin/ && !seen{print; seen=1}' \
        /etc/shells > /tmp/shells_clean && mv /tmp/shells_clean /etc/shells
    echo "    [OK] Entradas duplicadas eliminadas."
else
    echo "    [!] Sin cambios necesarios."
fi

# ─────────────────────────────────────────────
# 9. RECARGAR SYSTEMD
# ─────────────────────────────────────────────
echo "[9] Recargando systemd..."
systemctl daemon-reload
echo "    [OK]"

echo ""
echo "========================================="
echo "   LIMPIEZA COMPLETADA EXITOSAMENTE"
echo "========================================="
echo "Entorno listo. Ejecuta el script principal:"
echo "   sudo bash ftp_server.sh"
echo ""