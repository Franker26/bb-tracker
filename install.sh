#!/usr/bin/env bash
# install.sh — Instala bb-tracker en Linux (Ubuntu/Debian)
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

# ── Detectar gestor de paquetes ───────────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    PKG_INSTALL="sudo apt-get install -y -q"
    PKG_UPDATE="sudo apt-get update -q"
elif command -v dnf >/dev/null 2>&1; then
    PKG_INSTALL="sudo dnf install -y -q"
    PKG_UPDATE=""
elif command -v pacman >/dev/null 2>&1; then
    PKG_INSTALL="sudo pacman -S --noconfirm --quiet"
    PKG_UPDATE="sudo pacman -Sy --quiet"
else
    warn "No se reconoció el gestor de paquetes. Instalá manualmente: git, docker, python3, pip3"
    PKG_INSTALL=""
    PKG_UPDATE=""
fi

pkg_install() {
    local pkg="$1"
    if [ -n "$PKG_INSTALL" ]; then
        info "Instalando $pkg..."
        [ -n "$PKG_UPDATE" ] && $PKG_UPDATE 2>/dev/null || true
        $PKG_INSTALL "$pkg"
    else
        error "$pkg no está instalado y no se puede instalar automáticamente."
    fi
}

# ── 1. git ───────────────────────────────────────────────────────────────────
if ! command -v git >/dev/null 2>&1; then
    pkg_install git
fi
success "git OK"

# ── 2. python3 + pip3 ────────────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
    pkg_install python3
fi
if ! command -v pip3 >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        pkg_install python3-pip
    else
        pkg_install python3-pip
    fi
fi
success "python3 OK"

# ── 3. Docker ────────────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    info "Instalando Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    warn "Docker instalado. Para usarlo sin sudo, cerrá sesión y volvé a entrar (o ejecutá: newgrp docker)"
fi
success "docker OK"

# Detectar si necesitamos sudo para docker
if docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=""
else
    warn "Usando sudo para Docker (no estás en el grupo docker aún)."
    DOCKER_PREFIX="sudo"
fi

# Detectar docker compose (plugin v2 o binario v1)
if $DOCKER_PREFIX docker compose version >/dev/null 2>&1; then
    COMPOSE="$DOCKER_PREFIX docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="${DOCKER_PREFIX:+sudo }docker-compose"
else
    info "Instalando Docker Compose plugin..."
    if command -v apt-get >/dev/null 2>&1; then
        pkg_install docker-compose-plugin
    else
        # Instalar binario standalone
        COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        sudo curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
             -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    COMPOSE="${DOCKER_PREFIX:+sudo }docker-compose"
fi
success "docker compose OK"

# ── 4. Clonar o actualizar el repositorio ────────────────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
    info "Actualizando instalación existente en $INSTALL_DIR..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    info "Clonando repositorio en $INSTALL_DIR..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi
success "Código listo"

# ── 5. Crear .env si no existe ───────────────────────────────────────────────
if [ ! -f "$INSTALL_DIR/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
fi

# ── 6. Instalar dependencias Python del CLI (venv) ───────────────────────────
info "Instalando dependencias Python del CLI..."
VENV_DIR="$INSTALL_DIR/.venv"
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y -q python3-full 2>/dev/null || sudo apt-get install -y -q python3-venv python3-pip
fi
python3 -m venv --clear "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install -q -r "$INSTALL_DIR/requirements-cli.txt"
success "Dependencias del CLI instaladas"

# ── 7. Construir imagen Docker ───────────────────────────────────────────────
info "Construyendo imagen Docker (primera vez puede tardar ~2 min)..."
(cd "$INSTALL_DIR" && $COMPOSE build --quiet)
success "Imagen Docker lista"

# ── 8. Crear comando bb-tracker ──────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cat > "$CMD" << 'WRAPPER'
#!/usr/bin/env bash
INSTALL_DIR="$HOME/.local/share/bb-tracker"
cd "$INSTALL_DIR"
exec "$INSTALL_DIR/.venv/bin/python" cli.py "$@"
WRAPPER
chmod +x "$CMD"
success "Comando bb-tracker creado"

# ── 9. Verificar PATH ────────────────────────────────────────────────────────
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    SHELL_RC="$HOME/.bashrc"
    [[ "$SHELL" == */zsh ]] && SHELL_RC="$HOME/.zshrc"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
    export PATH="$HOME/.local/bin:$PATH"
    success "PATH actualizado en $SHELL_RC"
fi

# ── 10. Arrancar el contenedor ───────────────────────────────────────────────
info "Iniciando contenedor..."
(cd "$INSTALL_DIR" && $COMPOSE up -d)
success "Contenedor en ejecución"

# ── Listo ────────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}${BOLD}  ¡Instalación completa!${RESET}"
echo
echo "  Próximos pasos:"
echo "  1. Configurá tus credenciales:  ${BOLD}bb-tracker${RESET}"
echo "  2. Abrí el dashboard:           ${BOLD}http://localhost:8000${RESET}"
echo
