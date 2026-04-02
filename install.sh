#!/usr/bin/env bash
# install.sh — Instala bb-tracker en Linux
# Uso: bash install.sh
#      o bien:  curl -fsSL https://raw.githubusercontent.com/Franker26/bb-tracker/main/install.sh | bash

set -e

REPO_URL="https://github.com/Franker26/bb-tracker.git"
INSTALL_DIR="$HOME/.local/share/bb-tracker"
BIN_DIR="$HOME/.local/bin"
CMD="$BIN_DIR/bb-tracker"

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}▸${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}!${RESET} $*"; }
error()   { echo -e "${RED}✗${RESET} $*"; exit 1; }

echo -e "\n${BOLD}  bb-tracker — instalador${RESET}\n"

# ── 1. Dependencias ──────────────────────────────────────────────────────────
info "Verificando dependencias..."

command -v git    >/dev/null 2>&1 || error "git no está instalado. Instalalo con: sudo apt install git"
command -v docker >/dev/null 2>&1 || error "Docker no está instalado. Seguí: https://docs.docker.com/engine/install/"
command -v python3 >/dev/null 2>&1 || error "python3 no está instalado. Instalalo con: sudo apt install python3"
command -v pip3    >/dev/null 2>&1 || error "pip3 no está instalado. Instalalo con: sudo apt install python3-pip"

# Verificar que docker funciona (sin sudo si el user está en el grupo)
if ! docker info >/dev/null 2>&1; then
    warn "Docker requiere permisos. Probando con sudo..."
    if ! sudo docker info >/dev/null 2>&1; then
        error "No se puede conectar a Docker. Asegurate de que el servicio esté corriendo."
    fi
    DOCKER_CMD="sudo docker"
    COMPOSE_CMD="sudo docker compose"
else
    DOCKER_CMD="docker"
    COMPOSE_CMD="docker compose"
fi

# Compatibilidad docker compose vs docker-compose
if ! $DOCKER_CMD compose version >/dev/null 2>&1; then
    command -v docker-compose >/dev/null 2>&1 || error "docker compose no está disponible. Actualizá Docker o instalá docker-compose."
    COMPOSE_CMD="${DOCKER_CMD/docker/docker-compose}"
fi

success "Dependencias OK"

# ── 2. Clonar o actualizar el repositorio ────────────────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
    info "Actualizando instalación existente en $INSTALL_DIR..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    info "Clonando repositorio en $INSTALL_DIR..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi
success "Código actualizado"

# ── 3. Crear .env si no existe ───────────────────────────────────────────────
if [ ! -f "$INSTALL_DIR/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
    info ".env creado desde el ejemplo — configuralo con: bb-tracker"
fi

# ── 4. Instalar dependencias del CLI ─────────────────────────────────────────
info "Instalando dependencias Python del CLI..."
pip3 install --user -q -r "$INSTALL_DIR/requirements-cli.txt"
success "Dependencias del CLI instaladas"

# ── 5. Construir imagen Docker ───────────────────────────────────────────────
info "Construyendo imagen Docker (primera vez puede tardar ~2 min)..."
(cd "$INSTALL_DIR" && $COMPOSE_CMD build --quiet)
success "Imagen Docker lista"

# ── 6. Crear comando bb-tracker ──────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cat > "$CMD" << 'EOF'
#!/usr/bin/env bash
INSTALL_DIR="$HOME/.local/share/bb-tracker"
cd "$INSTALL_DIR"
exec python3 cli.py "$@"
EOF
chmod +x "$CMD"
success "Comando bb-tracker creado en $CMD"

# ── 7. Verificar PATH ────────────────────────────────────────────────────────
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR no está en tu PATH."
    echo
    echo "  Agregalo ejecutando:"
    echo -e "  ${BOLD}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc${RESET}"
    echo
fi

# ── 8. Arrancar el contenedor ────────────────────────────────────────────────
info "Iniciando contenedor..."
(cd "$INSTALL_DIR" && $COMPOSE_CMD up -d)
success "Contenedor en ejecución"

# ── Listo ────────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}${BOLD}  ¡Instalación completa!${RESET}"
echo
echo "  Próximos pasos:"
echo "  1. Configurá tus credenciales:  ${BOLD}bb-tracker${RESET}"
echo "  2. Abrí el dashboard:           ${BOLD}http://localhost:8000${RESET}"
echo
