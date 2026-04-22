#!/bin/bash
# configurar_dominio.sh
# Ejecutar: sudo bash configurar_dominio.sh

DOMINIO="practica.local"
DOMINIO_UPPER="PRACTICA"
ADMIN_USER="administrator"

echo "================================================="
echo "  CONFIGURACION Y UNION AL DOMINIO $DOMINIO"
echo "================================================="

# 1. Verificar que el dominio es visible
echo -e "\n[1] Verificando contacto con el dominio..."
realm discover $DOMINIO || {
    echo "[-] No se puede contactar el dominio."
    echo "    Verifica que el DC esta encendido y el DNS esta bien configurado."
    exit 1
}

# 2. Unir al dominio
echo -e "\n[2] Uniendo al dominio..."
echo "    Se pedira la contrasena de $ADMIN_USER (P@ssw0rdDelegado!)"
realm join --user=$ADMIN_USER $DOMINIO

# 3. Configurar SSSD
echo -e "\n[3] Configurando SSSD..."
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
fallback_homedir = /home/%u
ad_domain = $DOMINIO
use_fully_qualified_names = False
ldap_id_mapping = True
access_provider = ad
EOF

chmod 600 /etc/sssd/sssd.conf

# 4. Activar home automatico
echo -e "\n[4] Activando creacion automatica de carpeta home..."
pam-auth-update --enable mkhomedir

# 5. Reiniciar y habilitar SSSD
echo -e "\n[5] Reiniciando servicios..."
systemctl restart sssd
systemctl enable sssd

# 6. Verificacion final
echo -e "\n[6] Verificacion..."
realm list | grep -E "domain-name|configured|permitted"

id admin_identidad 2>/dev/null && \
    echo -e "\n[+] Usuario admin_identidad reconocido correctamente." || \
    echo -e "\n[!] Espera unos segundos y ejecuta: id admin_identidad"

echo ""
echo "================================================="
echo " UBUNTU UNIDO AL DOMINIO $DOMINIO"
echo "================================================="
echo " Prueba SSH con:"
echo "   ssh admin_identidad@192.168.50.10"
echo "================================================="