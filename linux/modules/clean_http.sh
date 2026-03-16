#!/bin/bash
# =============================================================================
# cleanup_fedora.sh — Limpieza profunda para Fedora Server 42
# Deja el sistema listo para ejecutar main_linux.sh desde cero
# Uso: sudo bash cleanup_fedora.sh
# =============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Ejecuta como root: sudo bash $0"
    exit 1
fi

echo ""
echo "  ╔═════════════════════════════════════════════╗"
echo "  ║    Limpieza Profunda — Fedora Server 42     ║"
echo "  ╚═════════════════════════════════════════════╝"
echo ""

# =============================================================================
# 1. DETENER Y DESHABILITAR TODOS LOS SERVICIOS HTTP
# =============================================================================
echo "[1/9] Deteniendo servicios HTTP..."

for svc in httpd apache2 nginx tomcat tomcat9 tomcat10; do
    if systemctl list-units --type=service --all 2>/dev/null | grep -q "^  ${svc}.service"; then
        systemctl stop    "$svc" 2>/dev/null && echo "  [OK] $svc detenido."
        systemctl disable "$svc" 2>/dev/null
        systemctl reset-failed "$svc" 2>/dev/null
    fi
done

# =============================================================================
# 2. MATAR PROCESOS RESIDUALES
# =============================================================================
echo "[2/9] Matando procesos residuales..."

for proc in httpd nginx java tomcat; do
    pids=$(pgrep -f "$proc" 2>/dev/null)
    if [ -n "$pids" ]; then
        kill -9 $pids 2>/dev/null
        echo "  [OK] Proceso '$proc' terminado (PIDs: $pids)."
    fi
done

# Esperar que liberen los puertos
sleep 2

# =============================================================================
# 3. DESINSTALAR PAQUETES
# =============================================================================
echo "[3/9] Desinstalando paquetes HTTP..."

dnf remove -y -q httpd httpd-core httpd-tools \
    nginx nginx-core nginx-filesystem \
    tomcat tomcat-webapps \
    2>/dev/null

dnf autoremove -y -q 2>/dev/null
echo "  [OK] Paquetes eliminados."

# =============================================================================
# 4. LIMPIAR CONFIGURACIONES RESIDUALES
# =============================================================================
echo "[4/9] Eliminando configuraciones residuales..."

# Apache / httpd
rm -rf /etc/httpd/conf.d/vhost_*.conf
rm -f  /etc/httpd/conf.d/welcome.conf.disabled
# Restaurar welcome.conf si fue deshabilitado por scripts anteriores
if [ -f /etc/httpd/conf.d/welcome.conf.disabled ]; then
    mv /etc/httpd/conf.d/welcome.conf.disabled \
       /etc/httpd/conf.d/welcome.conf 2>/dev/null
fi
# Restaurar Listen 80 en httpd.conf si fue comentado
if [ -f /etc/httpd/conf/httpd.conf ]; then
    sed -i 's/^#Listen 80.*$/Listen 80/' /etc/httpd/conf/httpd.conf 2>/dev/null
    # Quitar líneas de hardening añadidas por scripts anteriores
    sed -i '/^ServerTokens Prod/d' /etc/httpd/conf/httpd.conf 2>/dev/null
    sed -i '/^ServerSignature Off/d' /etc/httpd/conf/httpd.conf 2>/dev/null
    echo "  [OK] httpd.conf restaurado."
fi

# Nginx — restaurar backup si existe, o borrar conf.d limpia
if ls /etc/nginx/nginx.conf.bak_* 1>/dev/null 2>&1; then
    # Tomar el backup más antiguo (el original)
    oldest_bak=$(ls /etc/nginx/nginx.conf.bak_* | sort | head -1)
    cp "$oldest_bak" /etc/nginx/nginx.conf 2>/dev/null
    rm -f /etc/nginx/nginx.conf.bak_*
    echo "  [OK] nginx.conf restaurado desde $oldest_bak."
fi
rm -f /etc/nginx/conf.d/vhost_*.conf
rm -f /etc/nginx/conf.d/default.conf.disabled
# Restaurar default.conf de nginx si fue deshabilitado
if [ -f /etc/nginx/conf.d/default.conf.disabled ]; then
    mv /etc/nginx/conf.d/default.conf.disabled \
       /etc/nginx/conf.d/default.conf 2>/dev/null
fi

# Tomcat
if [ -f /etc/tomcat/server.xml ]; then
    # Restaurar puerto 8080 original si fue cambiado
    sed -i 's/port="[0-9]*" server="Apache Tomcat"/port="8080"/' \
        /etc/tomcat/server.xml 2>/dev/null
    sed -i 's/port="[0-9]*"\(.*protocol="HTTP\/1\.1"\)/port="8080"\1/' \
        /etc/tomcat/server.xml 2>/dev/null
    echo "  [OK] server.xml de Tomcat restaurado."
fi

echo "  [OK] Configuraciones limpiadas."

# =============================================================================
# 5. LIMPIAR DIRECTORIOS WEB CREADOS POR SCRIPTS ANTERIORES
# =============================================================================
echo "[5/9] Eliminando directorios web residuales..."

# Directorios creados por scripts anteriores (patrones conocidos)
rm -rf /var/www/apache_*
rm -rf /var/www/nginx_*
rm -rf /var/www/html_*
rm -rf /var/lib/tomcat/webapps/ROOT/*

# Limpiar logs residuales
rm -f /var/log/httpd/error_*.log
rm -f /var/log/httpd/access_*.log

echo "  [OK] Directorios web limpiados."

# =============================================================================
# 6. LIMPIAR PUERTOS SELinux NO ESTÁNDAR
# =============================================================================
echo "[6/9] Limpiando contextos SELinux de puertos no estándar..."

# Obtener todos los puertos registrados como http_port_t que NO son estándar
puertos_selinux=$(semanage port -l 2>/dev/null \
    | grep http_port_t \
    | grep -oP '\b[0-9]{4,5}\b' \
    | grep -vE '^(80|443|8080|8443|8888|9000)$')

for port in $puertos_selinux; do
    semanage port -d -t http_port_t -p tcp "$port" 2>/dev/null \
        && echo "  [OK] Puerto SELinux $port eliminado."
done

echo "  [OK] Contextos SELinux limpios."

# =============================================================================
# 7. LIMPIAR REGLAS DE FIREWALL AÑADIDAS POR SCRIPTS ANTERIORES
# =============================================================================
echo "[7/9] Limpiando reglas de firewall personalizadas..."

# Eliminar todos los puertos que no sean los servicios base del sistema
for port_proto in $(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n'); do
    port=$(echo "$port_proto" | cut -d'/' -f1)
    # Conservar solo puertos estándar del sistema (22 SSH ya está como servicio)
    if [ "$port" != "80" ] && [ "$port" != "443" ]; then
        firewall-cmd --permanent --remove-port="$port_proto" 2>/dev/null \
            && echo "  [OK] Puerto $port_proto eliminado del firewall."
    fi
done

firewall-cmd --reload 2>/dev/null
echo "  [OK] Firewall limpio. Solo SSH activo."

# =============================================================================
# 8. VERIFICAR PUERTOS LIBRES
# =============================================================================
echo "[8/9] Verificando que los puertos HTTP estén libres..."

puertos_a_verificar=(80 443 8080 8443 8888)
todos_libres=true

for p in "${puertos_a_verificar[@]}"; do
    if ss -tuln 2>/dev/null | grep -q ":${p} "; then
        echo "  [!] ADVERTENCIA: Puerto $p todavía en uso."
        ss -tuln | grep ":${p} "
        todos_libres=false
    else
        echo "  [OK] Puerto $p libre."
    fi
done

if [ "$todos_libres" = true ]; then
    echo "  [OK] Todos los puertos HTTP están libres."
fi

# =============================================================================
# 9. REINSTALAR DEPENDENCIAS BASE NECESARIAS PARA EL NUEVO SCRIPT
# =============================================================================
echo "[9/9] Instalando dependencias base para el nuevo script..."

dnf install -y -q \
    firewalld \
    curl \
    net-tools \
    gawk \
    iproute \
    policycoreutils-python-utils \
    2>/dev/null

systemctl enable firewalld --now &>/dev/null
echo "  [OK] Dependencias base instaladas."

# =============================================================================
# RESUMEN FINAL
# =============================================================================
echo ""
echo "  ╔═════════════════════════════════════════════╗"
echo "  ║           ✅ Limpieza Completada            ║"
echo "  ╠═════════════════════════════════════════════╣"
echo "  ║  El sistema está listo para:                ║"
echo "  ║  sudo bash main_linux.sh                    ║"
echo "  ╚═════════════════════════════════════════════╝"
echo ""
echo "  Estado actual de servicios HTTP:"
for svc in httpd nginx tomcat; do
    estado=$(systemctl is-active "$svc" 2>/dev/null || echo "inactivo")
    echo "    $svc: $estado"
done
echo ""
echo "  Puertos en escucha (solo debe aparecer SSH/22):"
ss -tuln 2>/dev/null | grep LISTEN | grep -v "127.0.0.1" | \
    awk '{print "   ", $5}' | sort -u
echo ""