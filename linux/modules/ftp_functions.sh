#!/bin/bash
# =============================================================================
# ftp_functions.sh — Funciones del servidor FTP (vsftpd) para Fedora
# Ubicacion: linux/modules/ftp_functions.sh
# =============================================================================

# -----------------------------------------------------------------------------
# VALIDACION DE ENTRADA
# -----------------------------------------------------------------------------

validar_contrasena() {
    local pass="$1"
    local ok=true

    [[ ${#pass} -lt 8 ]]               && echo "  [!] Minimo 8 caracteres."              && ok=false
    [[ ${#pass} -gt 15 ]]              && echo "  [!] Maximo 15 caracteres."              && ok=false
    [[ ! "$pass" =~ [A-Z] ]]           && echo "  [!] Necesita al menos una mayuscula."   && ok=false
    [[ ! "$pass" =~ [a-z] ]]           && echo "  [!] Necesita al menos una minuscula."   && ok=false
    [[ ! "$pass" =~ [0-9] ]]           && echo "  [!] Necesita al menos un numero."       && ok=false
    [[ ! "$pass" =~ [^a-zA-Z0-9] ]]   && echo "  [!] Necesita al menos un caracter especial." && ok=false

    [[ "$ok" == "true" ]] && return 0 || return 1
}

capturar_contrasena() {
    local pass
    while true; do
        read -s -p "  Contrasena (8-15, May, min, num, especial): " pass; echo
        if validar_contrasena "$pass"; then
            echo "$pass"
            return 0
        fi
        echo "  Intentelo de nuevo."
    done
}

validar_nombre_usuario() {
    local nombre="$1"
    [[ -z "$nombre" ]]                     && echo "  [!] El nombre no puede estar vacio."              && return 1
    [[ ! "$nombre" =~ ^[a-zA-Z0-9]+$ ]]   && echo "  [!] Solo letras y numeros permitidos."            && return 1
    [[ "$nombre" =~ ^[0-9] ]]             && echo "  [!] No puede comenzar con un numero."             && return 1
    [[ ${#nombre} -gt 15 ]]               && echo "  [!] Maximo 15 caracteres."                        && return 1
    id "$nombre" &>/dev/null              && echo "  [!] El usuario '$nombre' ya existe."              && return 1
    return 0
}

capturar_usuario_valido() {
    local prompt="$1"
    local nombre
    while true; do
        read -p "  $prompt: " nombre
        if validar_nombre_usuario "$nombre"; then
            echo "$nombre"
            return 0
        fi
    done
}

capturar_grupo_ftp() {
    local opcion
    while true; do
        echo "  Seleccione el grupo:"
        echo "    1) reprobados"
        echo "    2) recursadores"
        read -p "  Opcion: " opcion
        case "$opcion" in
            1) echo "reprobados";  return 0 ;;
            2) echo "recursadores"; return 0 ;;
            *) echo "  [!] Opcion invalida. Ingrese 1 o 2." ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# HELPER: Aplicar ACLs con herencia default (recursiva e indefinida)
#
# Las "default ACL" en Linux son la clave para la herencia indefinida:
# cualquier archivo o directorio creado DENTRO de un directorio con default
# ACL hereda esas ACL automaticamente, y si es un directorio tambien hereda
# las default ACL, propagandose sin limite de profundidad.
#
# Usamos dos comandos siempre juntos:
#   setfacl -R  -m <entry>   -> aplica a todo lo existente ahora
#   setfacl -R  -d -m <entry> -> establece la default (herencia futura)
# -----------------------------------------------------------------------------

aplicar_acl_heredable() {
    local ruta="$1"
    local entidad="$2"   # "u:alice" o "g:reprobados"
    local permisos="$3"  # "rwx", "r-x", etc.

    # Aplica a todo lo existente (recursivo)
    sudo setfacl -R  -m "${entidad}:${permisos}"   "$ruta"
    # Establece herencia para todo lo que se cree en el futuro (recursivo)
    sudo setfacl -R  -d -m "${entidad}:${permisos}" "$ruta"
}

# -----------------------------------------------------------------------------
# CONFIGURACION INICIAL DEL SERVIDOR FTP  (idempotente)
# -----------------------------------------------------------------------------

inicializar_sistema() {
    echo ""
    echo "================================================="
    echo "  CONFIGURACION INICIAL DEL SERVIDOR FTP"
    echo "================================================="

    # ------------------------------------------------------------------
    # 1. Dependencias
    # ------------------------------------------------------------------
    echo "[1/7] Instalando dependencias..."
    sudo dnf install -y vsftpd util-linux acl &>/dev/null
    echo "  OK"

    # ------------------------------------------------------------------
    # 2. Estructura de directorios
    #
    # /srv/ftp/
    #   general/                  <- compartido de lectura/escritura para autenticados
    #   groups/reprobados/        <- compartido del grupo reprobados
    #   groups/recursadores/      <- compartido del grupo recursadores
    #   anonymous/
    #     general/                <- bind-mount readonly de /srv/ftp/general
    # /home/<usuario>/            <- raiz de chroot del usuario autenticado
    #   <usuario>/                <- carpeta personal (solo el dueno)
    #   general/                  <- bind-mount rw de /srv/ftp/general
    #   <grupo>/                  <- bind-mount rw de /srv/ftp/groups/<grupo>
    # ------------------------------------------------------------------
    echo "[2/7] Creando estructura de directorios..."
    sudo mkdir -p /srv/ftp/general
    sudo mkdir -p /srv/ftp/groups/reprobados
    sudo mkdir -p /srv/ftp/groups/recursadores
    sudo mkdir -p /srv/ftp/anonymous/general
    sudo mkdir -p /srv/ftp/users
    echo "  OK"

    # ------------------------------------------------------------------
    # 3. Grupos del sistema
    # ------------------------------------------------------------------
    echo "[3/7] Verificando grupos del sistema..."
    sudo groupadd -f reprobados
    sudo groupadd -f recursadores
    sudo groupadd -f ftp-users
    echo "  OK"

    # ------------------------------------------------------------------
    # 4. Permisos base en /srv/ftp
    #
    # La carpeta raiz de cada recurso compartido necesita:
    #   - setgid bit (2xxx): los archivos nuevos heredan el grupo
    #   - ACL default: los subdirectorios y archivos heredan permisos rwx
    #
    # Esto garantiza herencia recursiva e indefinida.
    # ------------------------------------------------------------------
    echo "[4/7] Aplicando permisos base y ACLs heredables en /srv/ftp..."

    # --- general ---
    sudo chown root:ftp-users /srv/ftp/general
    sudo chmod 2770 /srv/ftp/general        # setgid + rwx para grupo
    aplicar_acl_heredable /srv/ftp/general "g:ftp-users" "rwx"
    # Administrators (root) siempre tiene acceso total
    aplicar_acl_heredable /srv/ftp/general "u:root" "rwx"

    # --- groups/reprobados ---
    sudo chown root:reprobados /srv/ftp/groups/reprobados
    sudo chmod 2770 /srv/ftp/groups/reprobados
    aplicar_acl_heredable /srv/ftp/groups/reprobados "g:reprobados" "rwx"
    aplicar_acl_heredable /srv/ftp/groups/reprobados "u:root" "rwx"

    # --- groups/recursadores ---
    sudo chown root:recursadores /srv/ftp/groups/recursadores
    sudo chmod 2770 /srv/ftp/groups/recursadores
    aplicar_acl_heredable /srv/ftp/groups/recursadores "g:recursadores" "rwx"
    aplicar_acl_heredable /srv/ftp/groups/recursadores "u:root" "rwx"

    echo "  OK"

    # ------------------------------------------------------------------
    # 5. Carpeta anonymous: bind-mount de solo lectura
    #
    # El usuario anonimo queda enjaulado en /srv/ftp/anonymous.
    # Dentro solo puede ver /general (bind-mount readonly).
    # NO puede escribir en absoluto.
    # ------------------------------------------------------------------
    echo "[5/7] Configurando acceso anonimo (solo lectura en /general)..."

    # Permisos del chroot anonimo: root es dueno, otros solo lectura
    sudo chown root:root /srv/ftp/anonymous
    sudo chmod 755 /srv/ftp/anonymous       # vsftpd requiere que el chroot no sea writable por el usuario

    if mountpoint -q /srv/ftp/anonymous/general; then
        sudo umount /srv/ftp/anonymous/general
    fi
    sudo mount --bind /srv/ftp/general /srv/ftp/anonymous/general
    sudo mount -o remount,ro,bind /srv/ftp/anonymous/general

    # Contexto SELinux para el punto de montaje anonimo
    sudo chcon -R -t public_content_t /srv/ftp/anonymous &>/dev/null

    # Persistir en /etc/fstab (idempotente)
    if ! grep -q "/srv/ftp/anonymous/general" /etc/fstab; then
        echo "/srv/ftp/general  /srv/ftp/anonymous/general  none  bind,ro  0 0" | sudo tee -a /etc/fstab > /dev/null
    fi

    echo "  OK"

    # ------------------------------------------------------------------
    # 6. Configuracion vsftpd
    # ------------------------------------------------------------------
    echo "[6/7] Escribiendo /etc/vsftpd/vsftpd.conf..."
    cat <<'EOF' | sudo tee /etc/vsftpd/vsftpd.conf > /dev/null
# --- Acceso general ---
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=002          # umask 002: archivos nuevos = 664, dirs nuevos = 775
                          # con setgid+ACL default esto garantiza herencia de grupo

# --- Aislamiento (chroot) ---
chroot_local_user=YES
allow_writeable_chroot=YES   # necesario porque el home es writable para el usuario
check_shell=NO
user_sub_token=$USER
local_root=/home/$USER       # cada usuario autenticado va a /home/<usuario>

# --- Anonimo ---
anon_root=/srv/ftp/anonymous
no_anon_password=YES
anon_world_readable_only=YES  # anonimo: solo puede leer

# --- Puertos pasivos (para FileZilla detras de NAT) ---
pasv_min_port=40000
pasv_max_port=40010

# --- Protocolo ---
listen=NO
listen_ipv6=YES
pam_service_name=vsftpd
EOF
    echo "  OK"

    # ------------------------------------------------------------------
    # 7. Firewall y SELinux
    # ------------------------------------------------------------------
    echo "[7/7] Configurando Firewall y SELinux..."
    sudo firewall-cmd --permanent --add-service=ftp &>/dev/null
    sudo firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
    sudo firewall-cmd --reload &>/dev/null

    # ftpd_full_access: permite a vsftpd leer/escribir en cualquier parte
    # con el contexto SELinux correcto
    sudo setsebool -P ftpd_full_access on &>/dev/null
    sudo setsebool -P tftp_home_dir on &>/dev/null

    # Contextos SELinux para directorios de escritura
    # public_content_rw_t = lectura y escritura para FTP con ftpd_full_access
    sudo chcon -R -t public_content_rw_t /srv/ftp/general             &>/dev/null
    sudo chcon -R -t public_content_rw_t /srv/ftp/groups/reprobados   &>/dev/null
    sudo chcon -R -t public_content_rw_t /srv/ftp/groups/recursadores &>/dev/null

    # Los home de usuarios: user_home_t + ftpd_full_access = acceso total
    # Se aplica al crearse cada usuario; aqui solo aseguramos el directorio base
    sudo chcon -t user_home_dir_t /home &>/dev/null

    if ! grep -q "/sbin/nologin" /etc/shells; then
        echo "/sbin/nologin" | sudo tee -a /etc/shells > /dev/null
    fi

    sudo systemctl restart vsftpd
    sudo systemctl enable vsftpd &>/dev/null
    echo "  OK"

    echo ""
    echo "  Servidor FTP configurado exitosamente."
    echo "================================================="
    echo ""
    echo "  RESUMEN DE ACCESOS:"
    echo "  - Anonimo (anonymous / sin password): solo lectura en /general"
    echo "  - Usuario autenticado: ve su /personal, /general y /grupo"
    echo "  - Permisos heredables indefinidamente en todas las carpetas"
    echo "================================================="
}

# -----------------------------------------------------------------------------
# CREAR USUARIO
# -----------------------------------------------------------------------------

crear_usuario() {
    local user="$1"
    local pass="$2"
    local group="$3"

    if id "$user" &>/dev/null; then
        echo "  [!] El usuario '$user' ya existe."
        return 1
    fi

    # Crear usuario del sistema:
    #   -m           : crear /home/<usuario>
    #   -g ftp-users : grupo primario (necesario para acceder a /general)
    #   -G <grupo>   : grupo secundario (acceso a carpeta de grupo)
    #   -s /sbin/nologin : sin acceso a shell
    sudo useradd -m -g ftp-users -G "$group" -s /sbin/nologin "$user"
    echo "$user:$pass" | sudo chpasswd

    _configurar_home "$user" "$group"

    echo "  [OK] Usuario '$user' creado en el grupo '$group'."
}

# Helper interno: construye y permisa el home del usuario
_configurar_home() {
    local user="$1"
    local group="$2"
    local home="/home/$user"

    # ------------------------------------------------------------------
    # Estructura del home (raiz de chroot):
    #   /home/<user>/           <- chroot root: NO writable por el usuario
    #   /home/<user>/<user>/    <- carpeta personal exclusiva
    #   /home/<user>/general/   <- bind-mount rw de /srv/ftp/general
    #   /home/<user>/<group>/   <- bind-mount rw de /srv/ftp/groups/<group>
    #
    # vsftpd con chroot_local_user=YES requiere que la raiz del chroot
    # NO sea writable por el usuario (o tener allow_writeable_chroot=YES).
    # Usamos allow_writeable_chroot=YES para simplificar, pero igualmente
    # el usuario no puede salir del chroot.
    # ------------------------------------------------------------------

    sudo mkdir -p "$home/$user"
    sudo mkdir -p "$home/general"
    sudo mkdir -p "$home/$group"

    # --- Permisos del chroot root ---
    # El directorio raiz pertenece a root para que vsftpd este seguro,
    # pero el usuario puede entrar a sus subdirectorios.
    sudo chown root:root "$home"
    sudo chmod 755 "$home"

    # --- Carpeta personal: solo el dueno tiene acceso total ---
    sudo chown "$user":"$user" "$home/$user"
    sudo chmod 700 "$home/$user"
    # ACL default para que cualquier subcarpeta/archivo que el usuario
    # cree dentro también sea suyo con rwx heredable
    aplicar_acl_heredable "$home/$user" "u:$user" "rwx"
    # Contexto SELinux para el home personal
    sudo chcon -R -t user_home_t "$home/$user" &>/dev/null

    # --- Bind-mounts ---
    # Desmontar si ya estaban montados (idempotencia)
    sudo umount "$home/general"     2>/dev/null
    sudo umount "$home/reprobados"  2>/dev/null
    sudo umount "$home/recursadores" 2>/dev/null

    sudo mount --bind /srv/ftp/general         "$home/general"
    sudo mount --bind /srv/ftp/groups/"$group" "$home/$group"

    # Tras el bind-mount, las ACLs del directorio origen ya estan activas.
    # Solo necesitamos asegurar que el usuario especifico también tenga
    # acceso explicito (por si no pertenecia al grupo en el momento de
    # crear /srv/ftp/general).
    aplicar_acl_heredable "$home/general" "u:$user" "rwx"
    aplicar_acl_heredable "$home/$group"  "u:$user" "rwx"

    # Contexto SELinux en los puntos de montaje del home
    sudo chcon -R -t public_content_rw_t "$home/general" &>/dev/null
    sudo chcon -R -t public_content_rw_t "$home/$group"  &>/dev/null

    # --- Persistir bind-mounts en /etc/fstab ---
    local fstab_general="/srv/ftp/general  $home/general  none  bind  0 0"
    local fstab_group="/srv/ftp/groups/$group  $home/$group  none  bind  0 0"

    grep -qF "$fstab_general" /etc/fstab || echo "$fstab_general" | sudo tee -a /etc/fstab > /dev/null
    grep -qF "$fstab_group"   /etc/fstab || echo "$fstab_group"   | sudo tee -a /etc/fstab > /dev/null
}

# -----------------------------------------------------------------------------
# MODIFICAR GRUPO
# -----------------------------------------------------------------------------

modificar_grupo_usuario() {
    local user="$1"
    local new_group="$2"

    if ! id "$user" &>/dev/null; then
        echo "  [!] El usuario '$user' no existe."
        return 1
    fi

    local old_group
    if id "$user" | grep -q "reprobados"; then
        old_group="reprobados"
    elif id "$user" | grep -q "recursadores"; then
        old_group="recursadores"
    else
        old_group=""
    fi

    if [[ "$old_group" == "$new_group" ]]; then
        echo "  [!] El usuario ya pertenece al grupo '$new_group'."
        return 0
    fi

    local home="/home/$user"

    # Desmontar y eliminar carpeta del grupo anterior
    if [[ -n "$old_group" ]]; then
        sudo umount "$home/$old_group" 2>/dev/null
        sudo rm -rf "$home/$old_group"
        # Quitar de fstab la entrada del grupo viejo
        sudo sed -i "\|$home/$old_group|d" /etc/fstab
    fi

    # Cambiar grupo secundario (mantener ftp-users como primario)
    sudo usermod -G "ftp-users,$new_group" "$user"

    # Crear y montar nueva carpeta de grupo
    sudo mkdir -p "$home/$new_group"
    sudo mount --bind /srv/ftp/groups/"$new_group" "$home/$new_group"
    aplicar_acl_heredable "$home/$new_group" "u:$user" "rwx"
    sudo chcon -R -t public_content_rw_t "$home/$new_group" &>/dev/null

    # Persistir en fstab
    local fstab_group="/srv/ftp/groups/$new_group  $home/$new_group  none  bind  0 0"
    grep -qF "$fstab_group" /etc/fstab || echo "$fstab_group" | sudo tee -a /etc/fstab > /dev/null

    echo "  [OK] '$user' movido de '$old_group' a '$new_group'."
}

# -----------------------------------------------------------------------------
# ELIMINAR USUARIO
# -----------------------------------------------------------------------------

eliminar_usuario() {
    local user="$1"
    local home="/home/$user"

    if ! id "$user" &>/dev/null; then
        echo "  [!] El usuario '$user' no existe."
        return 1
    fi

    # Desmontar bind-mounts del usuario
    sudo umount "$home/general"      2>/dev/null
    sudo umount "$home/reprobados"   2>/dev/null
    sudo umount "$home/recursadores" 2>/dev/null

    # Limpiar entradas de fstab del usuario
    sudo sed -i "\|$home/|d" /etc/fstab

    # Eliminar usuario y su home
    sudo userdel -r "$user" 2>/dev/null

    echo "  [OK] Usuario '$user' eliminado del servidor."
}

# -----------------------------------------------------------------------------
# LISTAR USUARIOS FTP
# -----------------------------------------------------------------------------

listar_usuarios_ftp() {
    echo ""
    echo "--- [ USUARIOS REGISTRADOS EN FTP ] ---"
    printf "%-20s | %-20s\n" "USUARIO" "GRUPO ACADEMICO"
    echo "------------------------------------------------"

    local ftp_gid
    ftp_gid=$(grep "^ftp-users:" /etc/group | cut -d: -f3)

    if [[ -z "$ftp_gid" ]]; then
        echo "No se encontro el grupo ftp-users."
    else
        local members
        members=$(awk -F: -v gid="$ftp_gid" '$4 == gid {print $1}' /etc/passwd)

        if [[ -z "$members" ]]; then
            echo "No hay usuarios registrados aun."
        else
            for u in $members; do
                local gr="General / Sin Grupo"
                id "$u" | grep -q "reprobados"   && gr="reprobados"
                id "$u" | grep -q "recursadores" && gr="recursadores"
                printf "%-20s | %-20s\n" "$u" "$gr"
            done
        fi
    fi
    echo "------------------------------------------------"
}

# -----------------------------------------------------------------------------
# VERIFICAR SERVICIO
# -----------------------------------------------------------------------------

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

    echo -n "Montaje Anonimo (/srv/ftp/anonymous/general): "
    if mountpoint -q /srv/ftp/anonymous/general; then
        echo -e "\e[32m[ OK ]\e[0m"
    else
        echo -e "\e[31m[ FALLIDO - ejecutar opcion Reset ]\e[0m"
    fi

    echo -n "IP del servidor (enp0s9): "
    local ip
    ip=$(ip -4 addr show enp0s9 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [[ -z "$ip" ]]; then
        # Fallback: primera interfaz no loopback
        ip=$(ip -4 addr show | grep -v "127.0.0.1" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    fi
    [[ -n "$ip" ]] && echo -e "\e[34m$ip\e[0m" || echo -e "\e[31m[ No encontrada ]\e[0m"

    echo "Conexiones actuales: $(ss -tnp | grep -c ':21' || echo 0)"
    echo "---------------------------------------"
}