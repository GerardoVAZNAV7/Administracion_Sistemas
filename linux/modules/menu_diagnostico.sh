#!/bin/bash
# =====================================================
# MENU DIAGNOSTICO - FEDORA SERVER
# Requiere: source core_utils.sh
# =====================================================

menu_diagnostico() {
    clear
    echo "====================================="
    echo " PRACTICA 1 - DIAGNOSTICO DEL SISTEMA"
    echo "====================================="

    echo ""
    echo "=== NOMBRE DEL EQUIPO ==="
    obtener_hostname

    echo ""
    echo "=== DIRECCION IPv4 ==="
    obtener_ipv4

    echo ""
    echo "=== USO DE DISCO ==="
    obtener_uso_disco

    echo ""
    echo "Diagnostico completado"
    read -p "Enter para continuar..."
}