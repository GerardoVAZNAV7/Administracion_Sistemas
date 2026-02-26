#!/bin/bash
# =====================================================
# SSH FUNCTIONS - FEDORA SERVER
# Requiere: core_utils.sh
# =====================================================

# =====================================================
# INSTALAR OPENSSH SERVER
# =====================================================

instalar_ssh() {
    verificar_root
    print_section "INSTALANDO OPENSSH SERVER"

    if paquete_instalado "openssh-server"; then
        print_warn "OpenSSH ya esta instalado"
        return
    fi

    instalar_paquete "openssh-server"
    print_ok "OpenSSH instalado correctamente"
}

# =====================================================
# CONFIGURACION COMPLETA AUTOMATICA
# =====================================================

configurar_ssh() {
    verificar_root
    print_section "CONFIGURACION AUTOMATICA SSH"

    habilitar_servicio "sshd"
    reiniciar_servicio "sshd"

    # Configurar firewall
    firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1

    print_ok "SSH configurado y listo para acceso remoto"
}

# =====================================================
# VERIFICAR SERVICIO
# =====================================================

verificar_ssh() {
    print_section "ESTADO DEL SERVICIO SSH"

    paquete_instalado "openssh-server" && print_ok "Paquete instalado" || {
        print_error "OpenSSH no instalado"
        return
    }

    servicio_activo "sshd" && print_ok "Servicio en ejecucion" || print_warn "Servicio detenido"

    echo ""
    print_section "PUERTO 22 ESCUCHANDO"
    ss -tlnp | grep :22
}

# =====================================================
# MOSTRAR DATOS DE CONEXION
# =====================================================

mostrar_datos_conexion() {
    print_section "DATOS DE CONEXION SSH"

    IP=$(hostname -I | awk '{print $1}')
    USUARIO=$(whoami)

    echo ""
    echo "IP del servidor: $IP"
    echo "Puerto: 22"
    echo "Usuario Linux: $USUARIO"
    echo ""

    echo "==== CONEXION DESDE TU PC ===="
    echo "PuTTY:"
    echo "Host Name: $IP"
    echo "Port: 22"
    echo ""

    echo "Terminal Windows:"
    echo "ssh $USUARIO@$IP"
    echo ""

    echo "==== TRANSFERENCIA DE ARCHIVOS ===="
    echo "Enviar archivo desde tu PC al servidor:"
    echo "scp archivo.txt $USUARIO@$IP:/home/$USUARIO/"
    echo ""

    echo "Descargar archivo del servidor a tu PC:"
    echo "scp $USUARIO@$IP:/home/$USUARIO/archivo.txt ."
}