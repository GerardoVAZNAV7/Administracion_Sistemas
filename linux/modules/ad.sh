#!/bin/bash
# Ejecutar como root: sudo bash unir_dominio.sh
# REQUISITO: paquetes ya instalados, ejecutar SIN NAT solo con red interna

set -e

echo "[1/3] Sincronizando reloj..."
ntpdate 192.168.10.10
echo "      Reloj sincronizado."

echo "[2/3] Uniendo al dominio baja.com..."
echo "      Ingresa la contraseña de Administrator cuando se pida"
realm join --user=Administrator baja.com
echo "      Unido al dominio."

echo "[3/3] Configurando sssd, sudo y servicios..."
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

cat > /etc/sudoers.d/ad-admins << EOF
%domain\ admins@baja.com  ALL=(ALL) ALL
%Grupo_Cuates@baja.com    ALL=(ALL) ALL
EOF
chmod 440 /etc/sudoers.d/ad-admins

pam-auth-update --enable mkhomedir
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