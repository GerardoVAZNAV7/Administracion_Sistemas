#!/bin/bash
# Ejecutar como root: sudo bash unir_dominio.sh

set -e

# ============================================================
DOMINIO="baja.com"
DOMINIO_UPPER="BAJA.COM"
SERVIDOR_AD="192.168.10.10"
ADMIN_USER="Administrator"
# ============================================================

echo "[1/6] Configurando DNS..."
# Quitar protección si existe
chattr -i /etc/resolv.conf 2>/dev/null || true

cat > /etc/resolv.conf << EOF
nameserver 192.168.10.10
nameserver 8.8.8.8
search baja.com
EOF

chattr +i /etc/resolv.conf
echo "      DNS configurado."

echo "[2/6] Instalando paquetes..."
apt-get update -qq
apt-get install -y realmd sssd sssd-tools adcli samba-common-bin \
                   oddjob oddjob-mkhomedir packagekit krb5-user
echo "      Paquetes instalados."

echo "[3/6] Uniendo al dominio baja.com..."
echo "      Ingresa la contraseña de Administrator cuando se pida"
realm join --user=Administrator baja.com
echo "      Unido al dominio."

echo "[4/6] Configurando sssd.conf..."
cat > /etc/sssd/sssd.conf << EOF
[sssd]
domains = baja.com
config_file_version = 2
services = nss, pam

[domain/baja.com]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = BAJA.COM
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = baja.com
use_fully_qualified_names = True
ldap_id_mapping = True
access_provider = ad
EOF

chmod 600 /etc/sssd/sssd.conf
echo "      sssd.conf configurado."

echo "[5/6] Habilitando home automático al login..."
pam-auth-update --enable mkhomedir
echo "      mkhomedir habilitado."

echo "[6/6] Configurando sudo para AD..."
cat > /etc/sudoers.d/ad-admins << EOF
# Admins del dominio baja.com
%domain\ admins@baja.com  ALL=(ALL) ALL
%Grupo_Cuates@baja.com    ALL=(ALL) ALL
EOF

chmod 440 /etc/sudoers.d/ad-admins
echo "      Sudoers configurado."

echo "Reiniciando servicios..."
systemctl restart sssd
systemctl enable sssd
systemctl restart oddjobd
systemctl enable oddjobd

echo ""
echo "=========================================="
echo "   LISTO - Ubuntu unido a baja.com"
echo "=========================================="
echo "  Verifica:  id Administrator@baja.com"
echo "  Login:     su - usuario@baja.com"
echo "=========================================="