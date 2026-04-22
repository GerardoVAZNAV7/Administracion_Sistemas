#!/bin/bash
# instalar_dominio.sh
# Ejecutar: sudo bash instalar_dominio.sh

echo "================================================="
echo "  INSTALACION DE PAQUETES PARA UNIRSE AL DOMINIO"
echo "================================================="

apt-get update -qq

apt-get install -y \
    realmd \
    sssd \
    sssd-tools \
    adcli \
    krb5-user \
    packagekit \
    samba-common-bin \
    oddjob \
    oddjob-mkhomedir

echo ""
echo "================================================="
echo " INSTALACION COMPLETADA"
echo " Ahora ejecuta: sudo bash configurar_dominio.sh"
echo "================================================="