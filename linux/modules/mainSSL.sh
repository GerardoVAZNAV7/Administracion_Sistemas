#!/bin/bash
# =============================================================================
# mainSSL.sh — Orquestador de instalación híbrida SSL/TLS para Fedora Server 42
# Práctica 7: Infraestructura de Despliegue Seguro
#
# USO:
#   sudo bash linux/modules/mainSSL.sh
#
# REQUIERE:
#   - Ejecutar como root
#   - ssl_functions.sh en el mismo directorio
#   - curl instalado (dnf install -y curl)
#   - openssl instalado (dnf install -y openssl)
# =============================================================================

# Obtener la ruta real de este script para cargar ssl_functions.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar todas las funciones de SSL
source "$SCRIPT_DIR/ssl_functions.sh"

# ── Verificar privilegios root ───────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Este script requiere privilegios root."
    echo "        Usa: sudo bash $0"
    exit 1
fi

# ── Verificar dependencias mínimas ───────────────────────────────────────────
echo "[*] Verificando dependencias..."

for cmd in curl openssl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[*] Instalando $cmd..."
        dnf install -y "$cmd" &>/dev/null
    fi
done

echo "[OK] Dependencias verificadas."
echo ""

# Inicializar arreglo global para el resumen
export RESUMEN_INSTALACIONES=()

# =============================================================================
# FUNCIÓN: Preguntar fuente de instalación y ejecutar
# =============================================================================

preguntar_fuente_y_ejecutar() {
    local servicio=$1        # Nombre legible: "Apache", "Nginx", etc.
    local func_instalar=$2   # Nombre de la función a llamar

    echo ""
    echo "----------------------------------------------------------"
    echo "  Configuración para: $servicio"
    echo "----------------------------------------------------------"
    echo "  Selecciona la FUENTE de instalación:"
    echo "    1) WEB  — Repositorio oficial (dnf)"
    echo "    2) FTP  — Repositorio privado (tu servidor FTP de Práctica 5)"
    echo "    0) Regresar al menú"
    echo ""

    local fuente_opcion
    read -p "  Opción: " fuente_opcion

    case "$fuente_opcion" in
        0) return 0 ;;
        1) fuente="WEB"; archivo_a_instalar="" ;;
        2)
            fuente="FTP"
            # Navegar por el repositorio FTP y descargar el instalador
            listar_versiones_ftp "$servicio"

            case "$_ARCHIVO_ELEGIDO" in
                "REGRESAR") return 0 ;;
                "INVALIDO")
                    echo "[!] No se pudo obtener el instalador desde el FTP."
                    echo "[?] ¿Quieres instalar desde WEB en su lugar? (s/n)"
                    local alt; read alt
                    if [[ "${alt,,}" == "s" ]]; then
                        fuente="WEB"; archivo_a_instalar=""
                    else
                        return 1
                    fi
                    ;;
                *)
                    # Descargar y verificar integridad
                    descargar_y_validar_hash "$servicio" "$_ARCHIVO_ELEGIDO"
                    if [[ $? -ne 0 ]]; then
                        echo "[!] La verificación de integridad falló. Abortando."
                        return 1
                    fi
                    archivo_a_instalar="$_RUTA_ARCHIVO"
                    ;;
            esac
            ;;
        *)
            echo "[!] Opción inválida."
            return 1
            ;;
    esac

    # Preguntar SSL
    echo ""
    preguntar_ssl
    local ssl="$_SSL_ACTIVO"

    echo ""
    echo "[*] Iniciando instalación de $servicio (Fuente: $fuente, SSL: $ssl)..."
    echo ""

    # Llamar a la función de instalación correspondiente
    "$func_instalar" "$archivo_a_instalar" "$fuente" "$ssl"
}

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================

mostrar_menu() {
    clear
    echo "=========================================================="
    echo "    PRÁCTICA 7 — DESPLIEGUE SEGURO SSL/TLS (FEDORA)"
    echo "=========================================================="
    echo "  Instalar con opción de SSL:"
    echo "  1) Apache  (httpd)  — HTTP/HTTPS"
    echo "  2) Nginx            — HTTP/HTTPS"
    echo "  3) Tomcat           — HTTP(8080)/HTTPS(8443)"
    echo "  4) vsftpd           — FTP/FTPS"
    echo "  5) Ver resumen de instalaciones"
    echo "  0) Salir"
    echo "=========================================================="
    echo ""
}

# =============================================================================
# BUCLE PRINCIPAL
# =============================================================================

while true; do
    mostrar_menu
    read -p "  Selecciona una opción: " opcion

    case "$opcion" in
        1) preguntar_fuente_y_ejecutar "Apache"  "instalar_apache"  ;;
        2) preguntar_fuente_y_ejecutar "Nginx"   "instalar_nginx"   ;;
        3) preguntar_fuente_y_ejecutar "Tomcat"  "instalar_tomcat"  ;;
        4) preguntar_fuente_y_ejecutar "vsftpd"  "instalar_vsftpd"  ;;
        5)
            verificar_resumen
            echo ""
            read -p "  Presiona Enter para continuar..."
            continue
            ;;
        0)
            echo ""
            verificar_resumen
            echo "[*] Saliendo del orquestador."
            exit 0
            ;;
        *)
            echo "[!] Opción inválida."
            sleep 1
            continue
            ;;
    esac

    echo ""
    read -p "  ¿Instalar otro servicio? (s/n): " continuar
    [[ "${continuar,,}" != "s" ]] && { verificar_resumen; break; }
done