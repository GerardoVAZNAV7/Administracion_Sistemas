#!/bin/bash

# --- Configuración Inicial e Idempotencia ---
function inicializar_sistema() {
    echo "[+] Instalando dependencias en Fedora..."
    sudo dnf install -y vsftpd util-linux acl &>/dev/null

    # Configuración de vsftpd CORREGIDA para FileZilla
    cat <<EOF | sudo tee /etc/vsftpd/vsftpd.conf > /dev/null
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
check_shell=NO
anon_root=/srv/ftp/anonymous
no_anon_password=YES
anon_world_readable_only=YES
pasv_min_port=40000
pasv_max_port=40010
listen=NO
listen_ipv6=YES
pam_service_name=vsftpd
EOF

    # Estructura de directorios
    sudo mkdir -p /srv/ftp/{groups/reprobados,groups/recursadores,general,anonymous/general,users}
    
    if ! mountpoint -q /srv/ftp/anonymous/general; then
        sudo mount --bind /srv/ftp/general /srv/ftp/anonymous/general
        sudo mount -o remount,ro,bind /srv/ftp/anonymous/general
    fi

    sudo groupadd -f reprobados
    sudo groupadd -f recursadores
    sudo groupadd -f ftp-users

    sudo setfacl -R -m g:ftp-users:rwx /srv/ftp/general
    sudo setfacl -R -d -m g:ftp-users:rwx /srv/ftp/general
    sudo chmod 755 /srv/ftp/general

    configurar_seguridad_ftp

    sudo systemctl restart vsftpd
    sudo systemctl enable vsftpd &>/dev/null
    echo "[✓] Sistema inicializado y listo para FileZilla."
}

# --- Crear Usuario y Estructura ---
function crear_usuario() {
    local user=$1
    local pass=$2
    local group=$3

    if id "$user" &>/dev/null; then
        echo "[!] El usuario $user ya existe."
        return
    fi

    sudo useradd -m -g ftp-users -G "$group" -s /sbin/nologin "$user"
    echo "$user:$pass" | sudo chpasswd

    configurar_montajes "$user" "$group"
    aplicar_permisos_personales "$user" "$group"
    echo "[✓] Usuario $user creado y configurado."
}

# --- Lógica de Montajes (Punto Clave) ---
function configurar_montajes() {
    local user=$1
    local group=$2
    local home="/home/$user"

    sudo mkdir -p "$home/general" "$home/$group" "$home/$user"

    # Limpiar montajes previos si existen (Evita errores de duplicados)
    sudo umount "$home/general" 2>/dev/null
    sudo umount "$home/reprobados" 2>/dev/null
    sudo umount "$home/recursadores" 2>/dev/null

    # Montajes actuales
    sudo mount --bind /srv/ftp/general "$home/general"
    sudo mount --bind /srv/ftp/groups/"$group" "$home/$group"
}

function aplicar_permisos_personales() {
    local user=$1
    local group=$2
    local home="/home/$user"

    # Carpeta personal: solo el dueño escribe
    sudo chown "$user":"$group" "$home/$user"
    sudo chmod 700 "$home/$user"

    # ACLs para las carpetas de grupo en /srv/ftp
    sudo setfacl -R -m g:"$group":rwx /srv/ftp/groups/"$group"
    sudo setfacl -R -d -m g:"$group":rwx /srv/ftp/groups/"$group"
}

# --- Modificar Grupo ---
function modificar_grupo_usuario() {
    local user=$1
    local new_group=$2

    if ! id "$user" &>/dev/null; then
        echo "[!] El usuario no existe."
        return
    fi

    # Cambiar grupo en el sistema
    sudo usermod -G "$new_group" "$user"
    
    # Limpiar carpetas viejas en el home del usuario
    sudo umount "/home/$user/reprobados" 2>/dev/null
    sudo umount "/home/$user/recursadores" 2>/dev/null
    sudo rm -rf "/home/$user/reprobados" "/home/$user/recursadores"

    # Reconfigurar con el nuevo grupo
    configurar_montajes "$user" "$new_group"
    aplicar_permisos_personales "$user" "$new_group"
    echo "[✓] Usuario $user movido a $new_group con éxito."
}

# --- Verificación del Servicio ---
function verificar_servicio_ftp() {
    echo -e "\n--- [ DIAGNÓSTICO DEL SERVICIO FTP ] ---"
    
    # 1. Estado del Servicio
    if systemctl is-active --quiet vsftpd; then
        echo -e "Estado: \e[32m[ EN EJECUCIÓN ]\e[0m"
    else
        echo -e "Estado: \e[31m[ DETENIDO ]\e[0m"
    fi

    # 2. Puertos Escuchando (Control y Pasivos)
    echo -n "Puertos: "
    ss -tunlp | grep -E '(:21|:4000[0-9]|:40010)' | awk '{print $5}' | tr '\n' ' '
    echo ""

    # 3. Verificación de Montajes
    echo -n "Montaje Anónimo: "
    if mountpoint -q /srv/ftp/anonymous/general; then
        echo -e "\e[32m[ OK ]\e[0m"
    else
        echo -e "\e[31m[ FALLÓ ]\e[0m"
    fi

    # 4. IP del Servidor (Para conectar desde FileZilla)
   echo -n "IP del servidor (enp0s9): "
    
    # Intentamos obtener la IP de enp0s9 específicamente
    IP_ENP0S9=$(ip -4 addr show enp0s9 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    if [ -z "$IP_ENP0S9" ]; then
        echo -e "\e[31m[ No se encontró IP en enp0s9 ]\e[0m"
    else
        echo -e "\e[34m$IP_ENP0S9\e[0m"
    fi

    # 5. Usuarios Conectados actualmente
    echo "Conexiones actuales: $(who | grep -c ftp 2>/dev/null || echo 0)"
    echo "---------------------------------------"
}

function configurar_seguridad_ftp() {
    echo "[+] Configurando Firewall (firewalld)..."
    sudo firewall-cmd --permanent --add-service=ftp &>/dev/null
    sudo firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
    sudo firewall-cmd --reload &>/dev/null

    echo "[+] Ajustando políticas de SELinux..."
    sudo setsebool -P ftpd_full_access on &>/dev/null
    sudo setsebool -P tftp_home_dir on &>/dev/null
    
    # Asegurar que nologin sea una shell válida para vsftpd
    if ! grep -q "/sbin/nologin" /etc/shells; then
        echo "/sbin/nologin" | sudo tee -a /etc/shells > /dev/null
    fi
}

# --- Listar Usuarios del Servicio ---
function listar_usuarios_ftp() {
    echo -e "\n--- [ USUARIOS REGISTRADOS EN FTP ] ---"
    printf "%-20s | %-20s\n" "USUARIO" "GRUPO ACADÉMICO"
    echo "------------------------------------------------"
    
    # Buscamos en /etc/passwd todos los usuarios cuyo GID corresponda al de ftp-users
    FTP_GID=$(grep "^ftp-users:" /etc/group | cut -d: -f3)
    
    if [ -z "$FTP_GID" ]; then
        echo "No se encontró el grupo ftp-users."
    else
        # Listamos usuarios cuyo GID primario sea el de ftp-users
        members=$(awk -F: -v gid="$FTP_GID" '$4 == gid {print $1}' /etc/passwd)
        
        if [ -z "$members" ]; then
            echo "No hay usuarios registrados aún."
        else
            for u in $members; do
                # Detectar grupo académico (estos suelen ser secundarios)
                if id "$u" | grep -q "reprobados"; then
                    gr="reprobados"
                elif id "$u" | grep -q "recursadores"; then
                    gr="recursadores"
                else
                    gr="General / Sin Grupo"
                fi
                printf "%-20s | %-20s\n" "$u" "$gr"
            done
        fi
    fi
    echo "------------------------------------------------"
}