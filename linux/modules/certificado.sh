#!/bin/bash
# =============================================================================
# ver_certificado.sh
# Muestra informacion de los certificados SSL generados por la Practica 7
#
# USO: sudo bash ver_certificado.sh
# =============================================================================

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
info() { echo -e "${CYAN}[*]${NC}    $1"; }
warn() { echo -e "${YELLOW}[!]${NC}    $1"; }

echo ""
echo "  +============================================================+"
echo "  |        CERTIFICADOS SSL - PRACTICA 7 - FEDORA             |"
echo "  +============================================================+"

IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

# =============================================================================
# METODO 1: Ver archivos de certificado en disco
# Los certificados se guardan en /etc/ssl/<servicio>/
# =============================================================================
echo ""
echo -e "  ${YELLOW}--- Certificados en disco (/etc/ssl/) ---${NC}"
echo ""

for servicio in apache nginx tomcat vsftpd; do
    cert="/etc/ssl/$servicio/server.crt"
    if [[ -f "$cert" ]]; then
        ok "Certificado encontrado: $cert"
        echo ""
        # openssl x509 -text muestra todo el contenido del certificado
        # -noout suprime la version codificada en base64 (solo nos interesa el texto)
        openssl x509 -in "$cert" -noout -text 2>/dev/null | grep -A2 -E \
            "Subject:|Issuer:|Not Before|Not After|DNS:|IP Address" \
            | sed 's/^/      /'
        echo ""

        # Verificar si tiene SAN
        san=$(openssl x509 -in "$cert" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name")
        if [[ -n "$san" ]]; then
            echo -e "      ${GREEN}[OK] Tiene SAN - el navegador puede mostrar candado verde${NC}"
        else
            echo -e "      ${RED}[!] SIN SAN - el navegador dira No seguro${NC}"
        fi

        # Verificar si esta vencido
        vencimiento=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        echo "      Vence: $vencimiento"

        # Comparar con la fecha actual
        fecha_venc=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        if openssl x509 -in "$cert" -noout -checkend 0 &>/dev/null; then
            echo -e "      ${GREEN}Estado: VALIDO${NC}"
        else
            echo -e "      ${RED}Estado: VENCIDO${NC}"
        fi
        echo ""
    fi
done

# =============================================================================
# METODO 2: Conectarse al servidor y ver el certificado como lo ve el navegador
# Esto muestra exactamente lo que recibe el cliente
# =============================================================================
echo -e "  ${YELLOW}--- Certificado recibido por el cliente (como lo ve el navegador) ---${NC}"
echo ""

declare -A puertos=( ["httpd"]="443" ["nginx"]="443" ["tomcat"]="8443" ["vsftpd"]="990" )

for servicio in "${!puertos[@]}"; do
    puerto="${puertos[$servicio]}"
    if systemctl is-active --quiet "$servicio" 2>/dev/null; then
        echo -e "  ${CYAN}Probando $servicio en $IP:$puerto ...${NC}"

        if [[ "$servicio" == "vsftpd" ]]; then
            # Para FTP usamos openssl s_client con protocolo FTP
            resultado=$(echo "QUIT" | timeout 5 openssl s_client \
                -connect "$IP:$puerto" \
                -starttls ftp 2>/dev/null | \
                openssl x509 -noout -text 2>/dev/null | \
                grep -E "Subject:|Not After|DNS:|IP Address" | head -10)
        else
            # Para HTTPS usamos openssl s_client directamente
            resultado=$(echo "" | timeout 5 openssl s_client \
                -connect "$IP:$puerto" \
                -servername "www.reprobados.com" 2>/dev/null | \
                openssl x509 -noout -text 2>/dev/null | \
                grep -E "Subject:|Not After|DNS:|IP Address" | head -10)
        fi

        if [[ -n "$resultado" ]]; then
            ok "Certificado recibido de $servicio:$puerto"
            echo "$resultado" | sed 's/^/      /'

            # Verificar SAN en la respuesta
            if echo "$resultado" | grep -q "DNS:\|IP Address:"; then
                echo -e "      ${GREEN}Tiene SAN: el navegador puede mostrar el candado${NC}"
                # Verificar si la IP del server esta en el SAN
                if echo "$resultado" | grep -q "IP Address:$IP"; then
                    echo -e "      ${GREEN}La IP $IP esta en el SAN: funciona por IP directa${NC}"
                else
                    warn "La IP $IP NO esta en el SAN. Solo funciona por dominio."
                fi
            else
                echo -e "      ${RED}Sin SAN: el navegador dira No seguro${NC}"
            fi
        else
            warn "$servicio en puerto $puerto no responde o no tiene SSL."
        fi
        echo ""
    fi
done

# =============================================================================
# RESUMEN: como acceder correctamente
# =============================================================================
echo "  +============================================================+"
echo "  |  Resumen de acceso desde tu PC host:                      |"
echo "  +------------------------------------------------------------+"
printf "  |  Servidor    Puerto  URL de acceso                        |\n"
echo "  +------------------------------------------------------------+"

declare -A acceso=(
    ["Apache/httpd"]="https://$IP:443  o  https://www.reprobados.com"
    ["Nginx"]="https://$IP:443  o  https://www.reprobados.com"
    ["Tomcat"]="https://$IP:8443  o  https://www.reprobados.com:8443"
    ["vsftpd"]="FileZilla -> ftps://$IP:990 (SSL implicito)"
)

for srv in "${!acceso[@]}"; do
    printf "  |  %-12s  %s\n" "$srv" "${acceso[$srv]}"
done

echo "  +------------------------------------------------------------+"
echo "  |  Recuerda: el navegador siempre advertira sobre el cert   |"
echo "  |  autofirmado. Haz click en Avanzado -> Continuar          |"
echo "  +============================================================+"
echo ""