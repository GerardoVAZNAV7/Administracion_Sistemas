#!/bin/bash
# =============================================================================
# ftp_functions.sh — Funciones del servidor FTP (vsftpd) para Fedora
# Ubicacion: linux/modules/ftp_functions.sh
# =============================================================================

validar_contrasena() {
    local pass="$1"
    local ok=true

    [[ ${#pass} -lt 8 ]]             && echo "  [!] Minimo 8 caracteres."                   && ok=false
    [[ ${#pass} -gt 15 ]]            && echo "  [!] Maximo 15 caracteres."                   && ok=false
    [[ ! "$pass" =~ [A-Z] ]]         && echo "  [!] Necesita al menos una mayuscula."        && ok=false
    [[ ! "$pass" =~ [a-z] ]]         && echo "  [!] Necesita al menos una minuscula."        && ok=false
    [[ ! "$pass" =~ [0-9] ]]         && echo "  [!] Necesita al menos un numero."            && ok=false
    [[ ! "$pass" =~ [^a-zA-Z0-9] ]] && echo "  [!] Necesita al menos un caracter especial." && ok=false

    [[ "$ok" == "true" ]] && return 0 || return 1
}

capturar_contrasena() {
    _RESULT_PASS=""
    local pass
    while true; do
        read -s -p "  Contrasena (8-15, May, min, num, especial): " pass
        echo
        if validar_contrasena "$pass"; then
            _RESULT_PASS="$pass"
            return 0
        fi
        echo "  Intentelo de nuevo."
    done
}

validar_nombre_usuario() {
    local nombre="$1"
    [[ -z "$nombre" ]]                   && echo "  [!] El nombre no puede estar vacio."   && return 1
    [[ ! "$nombre" =~ ^[a-zA-Z0-9]+$ ]] && echo "  [!] Solo letras y numeros."            && return 1
    [[ "$nombre" =~ ^[0-9] ]]           && echo "  [!] No puede comenzar con un numero."  && return 1
    [[ ${#nombre} -gt 15 ]]             && echo "  [!] Maximo 15 caracteres."              && return 1
    id "$nombre" &>/dev/null            && echo "  [!] El usuario '$nombre' ya existe."   && return 1
    return 0
}

capturar_usuario_valido() {
    local prompt="$1"
    _RESULT_USUARIO=""
    local nombre
    while true; do
        read -p "  $prompt: " nombre
        if validar_nombre_usuario "$nombre"; then
            _RESULT_USUARIO="$nombre"
            return 0
        fi
    done
}

capturar_grupo_ftp() {
    _RESULT_GRUPO=""
    local opcion
    while true; do
        echo "  Seleccione el grupo:"
        echo "    1) reprobados"
        echo "    2) recursadores"
        read -p "  Opcion: " opcion
        case "$opcion" in
            1) _RESULT_GRUPO="reprobados";   return 0 ;;
            2) _RESULT_GRUPO="recursadores"; return 0 ;;
            *) echo "  [!] Opcion invalida. Ingrese 1 o 2." ;;
        esac
    done
}

aplicar_acl_heredable() {
    local ruta="$1"
    local entidad="$2"
    local permisos="$3"

    sudo setfacl -R    -m "${entidad}:${permisos}" "$ruta"
    sudo setfacl -R -d -m "${entidad}:${permisos}" "$ruta"
}

# -----------------------------------------------------------------------------
# PROTEGER CARPETAS PRINCIPALES (anti-rename/delete)
# chattr +i sobre la carpeta: impide renombrar, mover o borrar el directorio
# aunque el usuario tenga rwx en el padre. Solo root puede quitar +i.
# Se aplica SOLO al directorio en si, no recursivo (-R), para no bloquear
# la escritura de archivos dentro de el.
# -----------------------------------------------------------------------------

proteger_carpetas_usuario() {
    local user="$1"
    local group="$2"
    local home="/home/$user"

    # Quitar inmutabilidad primero (por idempotencia al reconfigurar)
    sudo chattr -i "${home}/${user}"   2>/dev/null
    sudo chattr -i "${home}/general"   2>/dev/null
    sudo chattr -i "${home}/${group}"  2>/dev/null

    # Aplicar inmutabilidad solo al directorio (no a su contenido)
    sudo chattr +i "${home}/${user}"
    sudo chattr +i "${home}/general"
    sudo chattr +i "${home}/${group}"

    echo "  [OK] Carpetas protegidas contra renombrado/eliminacion."
}

desproteger_carpetas_usuario() {
    local user="$1"
    local group="$2"
    local home="/home/$user"

    sudo chattr -i "${home}/${user}"   2>/dev/null
    sudo chattr -i "${home}/general"   2>/dev/null
    sudo chattr -i "${home}/${group}"  2>/dev/null
}

inicializar_sistema() {
    echo ""
    echo "================================================="
    echo "  CONFIGURACION INICIAL DEL SERVIDOR FTP"
    echo "================================================="

    echo "[1/7] Instalando dependencias..."
    sudo dnf install -y vsftpd util-linux acl &>/dev/null
    echo "  OK"

    echo "[2/7] Creando estructura de directorios..."
    sudo mkdir -p /srv/ftp/general
    sudo mkdir -p /srv/ftp/groups/reprobados
    sudo mkdir -p /srv/ftp/groups/recursadores
    sudo mkdir -p /srv/ftp/anonymous/general
    echo "  OK"

    echo "[3/7] Verificando grupos del sistema..."
    sudo groupadd -f reprobados
    sudo groupadd -f recursadores
    sudo groupadd -f ftp-users
    echo "  OK"

    echo "[4/7] Aplicando permisos base y ACLs heredables en /srv/ftp..."

    sudo chown root:ftp-users /srv/ftp/general
    sudo chmod 2775 /srv/ftp/general
    aplicar_acl_heredable /srv/ftp/general "g:ftp-users" "rwx"
    aplicar_acl_heredable /srv/ftp/general "u:root"      "rwx"
    aplicar_acl_heredable /srv/ftp/general "other"       "r-x"

    sudo chown root:reprobados /srv/ftp/groups/reprobados
    sudo chmod 2770 /srv/ftp/groups/reprobados
    aplicar_acl_heredable /srv/ftp/groups/reprobados "g:reprobados" "rwx"
    aplicar_acl_heredable /srv/ftp/groups/reprobados "u:root"       "rwx"

    sudo chown root:recursadores /srv/ftp/groups/recursadores
    sudo chmod 2770 /srv/ftp/groups/recursadores
    aplicar_acl_heredable /srv/ftp/groups/recursadores "g:recursadores" "rwx"
    aplicar_acl_heredable /srv/ftp/groups/recursadores "u:root"         "rwx"

    echo "  OK"

    echo "[5/7] Configurando acceso anonimo (solo lectura en /general)..."

    sudo chown root:root /srv/ftp/anonymous
    sudo chmod 755 /srv/ftp/anonymous

    if mountpoint -q /srv/ftp/anonymous/general; then
        sudo umount /srv/ftp/anonymous/general
    fi
    sudo mount --bind /srv/ftp/general /srv/ftp/anonymous/general
    sudo mount -o remount,ro,bind /srv/ftp/anonymous/general
    sudo chmod 755 /srv/ftp/anonymous/general
    sudo chcon -R -t public_content_t /srv/ftp/anonymous &>/dev/null

    if ! grep -qF "/srv/ftp/anonymous/general" /etc/fstab; then
        printf '%s\n' "/srv/ftp/general /srv/ftp/anonymous/general none bind,ro 0 0" \
            | sudo tee -a /etc/fstab > /dev/null
    fi

    echo "  OK"

    echo "[6/7] Escribiendo /etc/vsftpd/vsftpd.conf..."
    sudo tee /etc/vsftpd/vsftpd.conf > /dev/null << 'VSFTPD_EOF'
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=002
chroot_local_user=YES
allow_writeable_chroot=YES
check_shell=NO
user_sub_token=$USER
local_root=/home/$USER
anon_root=/srv/ftp/anonymous
no_anon_password=YES
anon_world_readable_only=YES
pasv_min_port=40000
pasv_max_port=40010
listen=NO
listen_ipv6=YES
pam_service_name=vsftpd
VSFTPD_EOF
    echo "  OK"

    echo "[7/7] Configurando Firewall y SELinux..."
    sudo firewall-cmd --permanent --add-service=ftp          &>/dev/null
    sudo firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
    sudo firewall-cmd --reload                                &>/dev/null

    sudo setsebool -P ftpd_full_access on &>/dev/null
    sudo setsebool -P tftp_home_dir    on &>/dev/null

    sudo chcon -R -t public_content_rw_t /srv/ftp/general             &>/dev/null
    sudo chcon -R -t public_content_rw_t /srv/ftp/groups/reprobados   &>/dev/null
    sudo chcon -R -t public_content_rw_t /srv/ftp/groups/recursadores &>/dev/null

    grep -qF "/sbin/nologin" /etc/shells \
        || echo "/sbin/nologin" | sudo tee -a /etc/shells > /dev/null

    sudo systemctl restart vsftpd
    sudo systemctl enable vsftpd &>/dev/null
    echo "  OK"

    echo ""
    echo "  Servidor FTP listo."
    echo "================================================="
}

crear_usuario() {
    local user="$1"
    local pass="$2"
    local group="$3"

    if id "$user" &>/dev/null; then
        echo "  [!] El usuario '$user' ya existe."
        return 1
    fi

    sudo useradd -m -g ftp-users -G "$group" -s /sbin/nologin "$user"
    printf '%s:%s\n' "$user" "$pass" | sudo chpasswd

    _configurar_home "$user" "$group"

    echo "  [OK] Usuario '$user' creado en el grupo '$group'."
}

_configurar_home() {
    local user="$1"
    local group="$2"
    local home="/home/$user"

    # Quitar inmutabilidad antes de tocar las carpetas (por idempotencia)
    desproteger_carpetas_usuario "$user" "$group"

    sudo mkdir -p "${home}/${user}"
    sudo mkdir -p "${home}/general"
    sudo mkdir -p "${home}/${group}"

    # Raiz chroot: root dueno (vsftpd lo requiere)
    sudo chown root:root "$home"
    sudo chmod 755 "$home"

    # Carpeta personal del usuario
    sudo chown "${user}:ftp-users" "${home}/${user}"
    sudo chmod 700 "${home}/${user}"
    aplicar_acl_heredable "${home}/${user}" "u:${user}" "rwx"
    sudo chcon -R -t user_home_t "${home}/${user}" &>/dev/null

    # Bind-mounts (desmontar primero por idempotencia)
    sudo umount "${home}/general"       2>/dev/null
    sudo umount "${home}/reprobados"    2>/dev/null
    sudo umount "${home}/recursadores"  2>/dev/null

    sudo mount --bind /srv/ftp/general           "${home}/general"
    sudo mount --bind "/srv/ftp/groups/${group}" "${home}/${group}"

    aplicar_acl_heredable "${home}/general"  "u:${user}" "rwx"
    aplicar_acl_heredable "${home}/${group}" "u:${user}" "rwx"

    sudo chcon -R -t public_content_rw_t "${home}/general"  &>/dev/null
    sudo chcon -R -t public_content_rw_t "${home}/${group}" &>/dev/null

    local entry_gen="/srv/ftp/general ${home}/general none bind 0 0"
    local entry_grp="/srv/ftp/groups/${group} ${home}/${group} none bind 0 0"

    grep -qF "$entry_gen" /etc/fstab \
        || printf '%s\n' "$entry_gen" | sudo tee -a /etc/fstab > /dev/null
    grep -qF "$entry_grp" /etc/fstab \
        || printf '%s\n' "$entry_grp" | sudo tee -a /etc/fstab > /dev/null

    # Proteger las tres carpetas principales contra renombrado/eliminacion
    proteger_carpetas_usuario "$user" "$group"
}

modificar_grupo_usuario() {
    local user="$1"
    local new_group="$2"
    local home="/home/$user"

    if ! id "$user" &>/dev/null; then
        echo "  [!] El usuario '$user' no existe."
        return 1
    fi

    local old_group=""
    id "$user" | grep -q "reprobados"   && old_group="reprobados"
    id "$user" | grep -q "recursadores" && old_group="recursadores"

    if [[ "$old_group" == "$new_group" ]]; then
        echo "  [!] El usuario ya pertenece al grupo '$new_group'."
        return 0
    fi

    # Quitar inmutabilidad de la carpeta del grupo viejo para poder desmontarla
    if [[ -n "$old_group" ]]; then
        sudo chattr -i "${home}/${old_group}" 2>/dev/null
        sudo umount "${home}/${old_group}"    2>/dev/null
        sudo rm -rf "${home:?}/${old_group}"
        sudo sed -i "\|${home}/${old_group}|d" /etc/fstab
    fi

    sudo usermod -G "ftp-users,${new_group}" "$user"

    sudo mkdir -p "${home}/${new_group}"
    sudo mount --bind "/srv/ftp/groups/${new_group}" "${home}/${new_group}"
    aplicar_acl_heredable "${home}/${new_group}" "u:${user}" "rwx"
    sudo chcon -R -t public_content_rw_t "${home}/${new_group}" &>/dev/null

    local entry_grp="/srv/ftp/groups/${new_group} ${home}/${new_group} none bind 0 0"
    grep -qF "$entry_grp" /etc/fstab \
        || printf '%s\n' "$entry_grp" | sudo tee -a /etc/fstab > /dev/null

    # Re-proteger la nueva carpeta de grupo
    sudo chattr +i "${home}/${new_group}"

    echo "  [OK] '$user' movido de '${old_group:-ninguno}' a '$new_group'."
}

eliminar_usuario() {
    local user="$1"
    local home="/home/$user"

    if ! id "$user" &>/dev/null; then
        echo "  [!] El usuario '$user' no existe."
        return 1
    fi

    # Quitar inmutabilidad antes de eliminar
    desproteger_carpetas_usuario "$user" "reprobados"
    desproteger_carpetas_usuario "$user" "recursadores"

    sudo umount "${home}/general"       2>/dev/null
    sudo umount "${home}/reprobados"    2>/dev/null
    sudo umount "${home}/recursadores"  2>/dev/null

    sudo sed -i "\|${home}/|d" /etc/fstab
    sudo userdel -r "$user" 2>/dev/null

    echo "  [OK] Usuario '$user' eliminado."
}

listar_usuarios_ftp() {
    echo ""
    echo "--- [ USUARIOS REGISTRADOS EN FTP ] ---"
    printf "%-20s | %-20s\n" "USUARIO" "GRUPO ACADEMICO"
    echo "------------------------------------------------"

    local ftp_gid
    ftp_gid=$(grep "^ftp-users:" /etc/group | cut -d: -f3)

    if [[ -z "$ftp_gid" ]]; then
        echo "  No se encontro el grupo ftp-users."
    else
        local members
        members=$(awk -F: -v gid="$ftp_gid" '$4 == gid {print $1}' /etc/passwd)
        if [[ -z "$members" ]]; then
            echo "  No hay usuarios registrados aun."
        else
            for u in $members; do
                local gr="Sin Grupo"
                id "$u" | grep -q "reprobados"   && gr="reprobados"
                id "$u" | grep -q "recursadores" && gr="recursadores"
                printf "%-20s | %-20s\n" "$u" "$gr"
            done
        fi
    fi
    echo "------------------------------------------------"
}

verificar_servicio_ftp() {
    echo ""
    echo "--- [ DIAGNOSTICO DEL SERVICIO FTP ] ---"

    if systemctl is-active --quiet vsftpd; then
        echo -e "Estado: \e[32m[ EN EJECUCION ]\e[0m"
    else
        echo -e "Estado: \e[31m[ DETENIDO ]\e[0m"
    fi

    echo -n "Puertos: "
    ss -tunlp | grep -E '(:21|:4000[0-9]|:40010)' | awk '{print $5}' | tr '\n' ' '
    echo ""

    echo -n "Montaje anonimo: "
    mountpoint -q /srv/ftp/anonymous/general \
        && echo -e "\e[32m[ OK ]\e[0m" \
        || echo -e "\e[31m[ FALLO - use opcion Reset ]\e[0m"

    echo -n "IP (enp0s9): "
    local ip
    ip=$(ip -4 addr show enp0s9 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    [[ -z "$ip" ]] && ip=$(ip -4 addr show | grep -v 127.0.0.1 \
                            | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    [[ -n "$ip" ]] \
        && echo -e "\e[34m$ip\e[0m" \
        || echo -e "\e[31m[ No encontrada ]\e[0m"

    echo "---------------------------------------"
}