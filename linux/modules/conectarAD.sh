#!/bin/bash
# ==============================================================
#  unirse_dominio_baja.sh
#  Script para unir Ubuntu al dominio baja.com
#  Servidor DC: 192.168.10.10
#  Ejecutar como root: sudo bash unirse_dominio_baja.sh
# ==============================================================

set -e  # Detener si hay error

DOMINIO="baja.com"
DOMINIO_UPPER="BAJA.COM"
DC_IP="192.168.10.10"
ADMIN_USER="Administrador"   # Usuario administrador del dominio

# ─────────────────────────────────────────────
# PASO 1 — Verificar que se ejecuta como root
# ─────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Ejecuta el script como root: sudo bash $0"
    exit 1
fi

echo ""
echo "=========================================="
echo "   UNIÓN AL DOMINIO baja.com — UBUNTU     "
echo "=========================================="

# ─────────────────────────────────────────────
# PASO 2 — Configurar DNS apuntando al DC
# ─────────────────────────────────────────────
echo ""
echo "[1/6] Configurando DNS hacia el DC ($DC_IP)..."

# Detectar interfaz de red activa
INTERFAZ=$(ip route | grep default | awk '{print $5}' | head -1)

if [ -z "$INTERFAZ" ]; then
    echo "[ERROR] No se detectó interfaz de red. Verifica la conectividad."
    exit 1
fi

echo "      Interfaz detectada: $INTERFAZ"

# Configurar resolv.conf
cat > /etc/resolv.conf << EOF
search baja.com
nameserver $DC_IP
EOF

# Hacer resolv.conf inmutable para que no lo sobreescriba el sistema
chattr +i /etc/resolv.conf 2>/dev/null || true

echo "      DNS configurado: $DC_IP"

# Verificar conectividad con el DC
echo "      Verificando ping al DC..."
if ! ping -c 2 -W 3 "$DC_IP" &>/dev/null; then
    echo "[ERROR] No hay conectividad con el servidor $DC_IP"
    echo "        Verifica la red interna en VirtualBox."
    exit 1
fi
echo "      Ping exitoso al DC."

# ─────────────────────────────────────────────
# PASO 3 — Instalar paquetes necesarios
# ─────────────────────────────────────────────
echo ""
echo "[2/6] Instalando paquetes (realmd, sssd, adcli, krb5)..."
echo "      NOTA: Necesitas conexión a internet o los paquetes pre-descargados."
echo ""

apt-get update -qq

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    realmd \
    sssd \
    sssd-tools \
    adcli \
    krb5-user \
    packagekit \
    samba-common-bin \
    oddjob \
    oddjob-mkhomedir \
    policykit-1 2>/dev/null || apt-get install -y \
    realmd \
    sssd \
    sssd-tools \
    adcli \
    krb5-user \
    packagekit \
    samba-common-bin \
    oddjob \
    oddjob-mkhomedir

echo "      Paquetes instalados correctamente."

# ─────────────────────────────────────────────
# PASO 4 — Descubrir y unirse al dominio
# ─────────────────────────────────────────────
echo ""
echo "[3/6] Descubriendo el dominio $DOMINIO..."

if realm discover "$DOMINIO" &>/dev/null; then
    echo "      Dominio encontrado: $DOMINIO"
else
    echo "[ERROR] No se pudo descubrir el dominio $DOMINIO"
    echo "        Verifica que el DC esté encendido y el DNS apunte a $DC_IP"
    exit 1
fi

echo ""
echo "[4/6] Uniéndose al dominio baja.com..."
echo "      Se te pedirá la contraseña del Administrador del dominio."
echo ""

realm join --user="$ADMIN_USER" "$DOMINIO"

echo "      Unión al dominio completada."

# ─────────────────────────────────────────────
# PASO 5 — Configurar sssd.conf
# ─────────────────────────────────────────────
echo ""
echo "[5/6] Configurando sssd.conf..."

cat > /etc/sssd/sssd.conf << EOF
[sssd]
domains = $DOMINIO
config_file_version = 2
services = nss, pam

[domain/$DOMINIO]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = $DOMINIO_UPPER
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = $DOMINIO
use_fully_qualified_names = True
ldap_id_mapping = True
access_provider = ad
EOF

chmod 600 /etc/sssd/sssd.conf
echo "      sssd.conf configurado con fallback_homedir = /home/%u@%d"

# ─────────────────────────────────────────────
# PASO 6 — Crear home automático al login
# ─────────────────────────────────────────────
echo ""
echo "[6/6] Activando creación automática de carpeta home..."

# Para sistemas con pam-auth-update
pam-auth-update --enable mkhomedir 2>/dev/null || true

# Por si acaso, también en common-session directamente
if ! grep -q "pam_mkhomedir" /etc/pam.d/common-session; then
    echo "session required pam_mkhomedir.so skel=/etc/skel/ umask=0077" \
        >> /etc/pam.d/common-session
fi

echo "      Home automático activado."

# ─────────────────────────────────────────────
# SUDO para todos los usuarios de AD
# ─────────────────────────────────────────────
echo ""
echo "[+] Configurando sudo para todos los usuarios de AD..."

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/ad-admins << EOF
# Permisos sudo para todos los usuarios del dominio baja.com
%domain\ users@baja.com ALL=(ALL) ALL
EOF

chmod 440 /etc/sudoers.d/ad-admins
echo "      Archivo /etc/sudoers.d/ad-admins creado."

# ─────────────────────────────────────────────
# Reiniciar servicios
# ─────────────────────────────────────────────
echo ""
echo "[+] Reiniciando servicios sssd y oddjobd..."
systemctl enable sssd   && systemctl restart sssd
systemctl enable oddjobd && systemctl restart oddjobd 2>/dev/null || true

# ─────────────────────────────────────────────
# VERIFICACIÓN FINAL
# ─────────────────────────────────────────────
echo ""
echo "=========================================="
echo "   VERIFICACIÓN FINAL                     "
echo "=========================================="

sleep 2  # Dar tiempo a sssd para iniciar

echo ""
echo "Estado del reino (realm list):"
realm list

echo ""
echo "Probando resolución de un usuario AD (id):"
echo "  Escribe: id usuario@baja.com"
echo "  (reemplaza 'usuario' por uno de tu CSV)"

echo ""
echo "=========================================="
echo "   UBUNTU UNIDO AL DOMINIO baja.com ✓    "
echo "=========================================="
echo ""
echo "PRÓXIMOS PASOS:"
echo "  1. Cierra sesión y entra con: usuario@baja.com"
echo "  2. La carpeta home se crea en /home/usuario@baja.com"
echo "  3. Todos los usuarios AD tienen sudo."
echo ""
echo "  IMPORTANTE: Si instalaste paquetes con internet,"
echo "  puedes volver a Red Interna en VirtualBox."
echo ""