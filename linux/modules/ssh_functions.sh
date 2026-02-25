#!/bin/bash
# =====================================================
# SSH FUNCTIONS - FEDORA SERVER
# Requiere: source core_utils.sh
# =====================================================

SSH_CONFIG="/etc/ssh/sshd_config"


# =====================================================
# INSTALAR OPENSSH SERVER
# =====================================================

ssh_instalar() {
    verificar_root || return

    if paquete_instalado "openssh-server"; then
        echo "OpenSSH ya esta instalado"
    else
        echo "Instalando OpenSSH Server..."
        instalar_paquete "openssh-server"
        echo "Instalacion completada"
    fi
}


# =====================================================
# CONFIGURAR SSH PARA ACCESO REMOTO
# =====================================================

# =====================================================
# CONFIGURACION COMPLETA SSH (INSTALA + CONFIGURA + ACTIVA + FIREWALL)
# =====================================================

ssh_configurar() {
    verificar_root || return

    echo "======================================"
    echo "CONFIGURANDO SERVICIO SSH COMPLETO"
    echo "======================================"

    #  INSTALAR OPENSSH SI NO EXISTE
    if paquete_instalado "openssh-server"; then
        echo "OpenSSH ya esta instalado"
    else
        echo "Instalando OpenSSH Server..."
        instalar_paquete "openssh-server"
    fi

    # CONFIGURAR ARCHIVO SSH
    echo "Configurando archivo sshd_config..."

    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' $SSH_CONFIG
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' $SSH_CONFIG

    sed -i 's/^#PermitRootLogin yes/PermitRootLogin yes/' $SSH_CONFIG
    sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin yes/' $SSH_CONFIG

    #  ACTIVAR SERVICIO Y ARRANQUE AUTOMATICO
    echo "Activando servicio SSH..."
    systemctl enable sshd
    systemctl restart sshd

    #  CONFIGURAR FIREWALL
    if systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
        echo "Firewall configurado para SSH"
    else
        echo "Firewalld no esta activo"
    fi

    # MOSTRAR IP
    SERVER_IP=$(obtener_ip_principal)

    echo ""
    echo "======================================"
    echo "SSH CONFIGURADO CORRECTAMENTE"
    echo "======================================"
    echo "El servicio iniciara automaticamente al encender el servidor"
    echo "IP del servidor: $SERVER_IP"
    echo ""
}


# =====================================================
# HABILITAR SERVICIO Y ARRANQUE AUTOMATICO
# =====================================================

ssh_activar_servicio() {
    verificar_root || return

    systemctl enable sshd
    systemctl restart sshd

    echo "Servicio SSH activo y configurado al arranque"
}


# =====================================================
# ABRIR FIREWALL
# =====================================================

ssh_configurar_firewall() {
    verificar_root || return

    if systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
        echo "Puerto 22 habilitado en firewall"
    else
        echo "Firewalld no esta activo"
    fi
}


# =====================================================
# VERIFICAR SERVICIO
# =====================================================

ssh_verificar() {
    echo "=== ESTADO DEL SERVICIO SSH ==="

    if paquete_instalado "openssh-server"; then
        echo "OpenSSH instalado"
    else
        echo "OpenSSH NO instalado"
        return
    fi

    echo ""
    echo "Estado del servicio:"
    systemctl is-active sshd

    echo ""
    echo "Puerto 22 escuchando:"
    ss -tlnp | grep :22
}


# =====================================================
# MOSTRAR DATOS DE CONEXION
# =====================================================

ssh_mostrar_conexion() {
    IP=$(obtener_ip_principal)

    echo ""
    echo "======================================"
    echo "DATOS PARA CONEXION DESDE TU PC"
    echo "======================================"
    echo "IP del servidor: $IP"
    echo "Puerto: 22"
    echo "Usuario: $(whoami)"
    echo ""
    echo "Conexion desde terminal:"
    echo "ssh usuario@$IP"
    echo ""
    echo "Transferir archivo desde tu PC:"
    echo "scp archivo.txt usuario@$IP:/home/usuario/"
    echo ""
}