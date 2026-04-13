#!/bin/bash
# Ejecutar como root: sudo bash unir_dominio.sh

set -e

echo "[1/5] Instalando paquetes..."
apt-get update -qq
apt-get install -y realmd sssd sssd-tools adcli samba-common-bin \
                   oddjob oddjob-mkhomedir packagekit krb5-user
echo "      Paquetes instalados."

echo "[2/5] Uniendo al dominio baja.com..."
echo "      Ingresa la contraseña de Administrator cuando se pida"
realm join --user=Administrator baja.com
echo "      Unido al dominio."

echo "[3/5] Configurando sssd.conf..."
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

echo "[4/5] Habilitando home automático al login..."
pam-auth-update --enable mkhomedir
echo "      mkhomedir habilitado."

echo "[5/5] Configurando sudo para AD..."
cat > /etc/sudoers.d/ad-admins << EOF
# Admins del dominio baja.com
%domain\ admins@baja.com  ALL=(ALL) ALL
%Grupo_Cuates@baja.com    ALL=(ALL) ALL
EOF

chmod 440 /etc/sudoers.d/ad-admins
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