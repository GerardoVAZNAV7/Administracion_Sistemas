
echo "*******************************************"
echo "   PRACTICA 1 ADMINISTRACIOIN DE SISTEMAS"
echo "*******************************************"

# Nombre del equipo
echo "Nombre del equipo:"
hostname
echo ""

# Dirección IP (compatible con Fedora)
echo "Dirección IP:"
ip -4 addr show | awk '/inet / {print $2}' | cut -d/ -f1 | grep -v 127.0.0.1
echo ""

# Espacio en disco
echo "Espacio en disco:"
df -h /
echo ""

echo "*************************************"
echo "          FIN DE PRACTICA            "
echo "*************************************"
