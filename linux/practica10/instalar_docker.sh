#!/usr/bin/env bash
# =============================================================================
# instalar_docker.sh — Instala Docker en Fedora/RHEL/Rocky/AlmaLinux
#                      y deja la Práctica 10 lista para ejecutar.
#
# Uso: sudo bash instalar_docker.sh
# =============================================================================

set -e

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
BOLD='\033[1m'
ok()   { echo -e "${GREEN}  ✔  $*${NC}"; }
info() { echo -e "${CYAN}  →  $*${NC}"; }
fail() { echo -e "${RED}  ✘  $*${NC}"; exit 1; }
warn() { echo -e "${YELLOW}  ⚠  $*${NC}"; }
sep()  { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

echo ""
sep
echo -e "  ${BOLD}${CYAN}Instalador Docker — Práctica 10${NC}"
sep
echo ""

# ── Detectar distro ────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  fail "Ejecuta este script como root: sudo bash instalar_docker.sh"
fi

if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version)
  ok "Docker ya instalado: $DOCKER_VER"
else
  info "Instalando Docker..."

  # Detectar si es Fedora o RHEL/Rocky/Alma
  if grep -qi "fedora" /etc/os-release 2>/dev/null; then
    info "Detectado: Fedora"
    dnf -y install dnf-plugins-core
    dnf config-manager --add-repo \
      https://download.docker.com/linux/fedora/docker-ce.repo
    dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif grep -qiE "rhel|rocky|alma|centos" /etc/os-release 2>/dev/null; then
    info "Detectado: RHEL/Rocky/AlmaLinux"
    dnf -y install dnf-plugins-core
    dnf config-manager --add-repo \
      https://download.docker.com/linux/rhel/docker-ce.repo
    dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
    info "Detectado: Ubuntu/Debian"
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    fail "Distribución no reconocida. Instala Docker manualmente desde https://docs.docker.com/engine/install/"
  fi

  ok "Docker instalado correctamente."
fi

# ── Habilitar y arrancar el servicio ──────────────────────────────────────────
info "Habilitando y arrancando dockerd..."
systemctl enable docker
systemctl start docker
ok "Servicio Docker activo."

# ── Agregar usuario actual al grupo docker ────────────────────────────────────
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  usermod -aG docker "$REAL_USER"
  ok "Usuario '$REAL_USER' agregado al grupo docker."
  warn "Cierra sesión y vuelve a entrar para usar docker sin sudo."
fi

# ── Instalar curl (necesario para pruebas FTP) ────────────────────────────────
if ! command -v curl &>/dev/null; then
  info "Instalando curl..."
  if command -v dnf &>/dev/null; then
    dnf -y install curl
  elif command -v apt-get &>/dev/null; then
    apt-get install -y curl
  fi
  ok "curl instalado."
else
  ok "curl ya disponible."
fi

# ── Crear directorio de backups en el host ────────────────────────────────────
mkdir -p /srv/backups/postgres
chmod 777 /srv/backups/postgres
ok "Directorio /srv/backups/postgres creado."

# ── Verificar versión final ───────────────────────────────────────────────────
echo ""
sep
docker --version && docker compose version
sep
echo ""
ok "Todo listo. Ahora ejecuta:"
echo ""
echo -e "  ${CYAN}cd practica10${NC}"
echo -e "  ${CYAN}docker compose up -d --build${NC}"
echo -e "  ${CYAN}./test_practica10.sh${NC}"
echo ""
