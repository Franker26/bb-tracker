#!/usr/bin/env bash
# install.sh — Instala bb-tracker en Linux
# curl -fsSL https://raw.githubusercontent.com/Franker26/bb-tracker/main/install.sh | bash

set -e

REPO_URL="https://github.com/Franker26/bb-tracker.git"
INSTALL_DIR="$HOME/.local/share/bb-tracker"
BIN_DIR="$HOME/.local/bin"
CMD="$BIN_DIR/bb-tracker"

# ── Colores ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m'
M='\033[0;35m' B='\033[0;34m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
W='\033[1;37m'

# ── Spinner ───────────────────────────────────────────────────────────────────
_spin_pid=""
start_spin() {
    local msg="$1"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    (
        local i=0
        while true; do
            printf "\r  ${C}${frames[$i]}${RESET}  %s   " "$msg"
            i=$(( (i+1) % ${#frames[@]} ))
            sleep 0.08
        done
    ) &
    _spin_pid=$!
    disown
}
stop_spin() {
    local msg="$1"
    if [ -n "$_spin_pid" ]; then
        kill "$_spin_pid" 2>/dev/null || true
        _spin_pid=""
    fi
    printf "\r  ${G}✔${RESET}  %s\n" "$msg"
}
fail_spin() {
    local msg="$1"
    if [ -n "$_spin_pid" ]; then
        kill "$_spin_pid" 2>/dev/null || true
        _spin_pid=""
    fi
    printf "\r  ${R}✘${RESET}  %s\n" "$msg"
    exit 1
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo
echo -e "  ${B}${BOLD}██████╗ ██████╗       ████████╗██████╗  █████╗  ██████╗██╗  ██╗███████╗██████╗ ${RESET}"
echo -e "  ${B}${BOLD}██╔══██╗██╔══██╗         ██╔══╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗${RESET}"
echo -e "  ${B}${BOLD}██████╔╝██████╔╝         ██║   ██████╔╝███████║██║     █████╔╝ █████╗  ██████╔╝${RESET}"
echo -e "  ${B}${BOLD}██╔══██╗██╔══██╗         ██║   ██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗${RESET}"
echo -e "  ${B}${BOLD}██████╔╝██████╔╝         ██║   ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║${RESET}"
echo -e "  ${B}${BOLD}╚═════╝ ╚═════╝          ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝${RESET}"
echo
echo -e "  ${DIM}Blackboard activity tracker — by ${W}Franker26${RESET}"
echo -e "  ${DIM}────────────────────────────────────────────${RESET}"
echo

# ── Gestor de paquetes ────────────────────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    PKG_INSTALL="sudo apt-get install -y -q"
elif command -v dnf >/dev/null 2>&1; then
    PKG_INSTALL="sudo dnf install -y -q"
elif command -v pacman >/dev/null 2>&1; then
    PKG_INSTALL="sudo pacman -S --noconfirm --quiet"
else
    PKG_INSTALL=""
fi

pkg_install() {
    $PKG_INSTALL "$@" >/dev/null 2>&1 || true
}

# ── 1. git ────────────────────────────────────────────────────────────────────
start_spin "Verificando git..."
if ! command -v git >/dev/null 2>&1; then
    pkg_install git || fail_spin "No se pudo instalar git"
fi
stop_spin "git"

# ── 2. Python ─────────────────────────────────────────────────────────────────
start_spin "Verificando Python..."
if ! command -v python3 >/dev/null 2>&1; then
    pkg_install python3 || fail_spin "No se pudo instalar python3"
fi
pkg_install python3-full python3-venv >/dev/null 2>&1 || true
stop_spin "Python"

# ── 3. Docker ─────────────────────────────────────────────────────────────────
start_spin "Verificando Docker..."
if ! command -v docker >/dev/null 2>&1; then
    stop_spin "Instalando Docker..."
    curl -fsSL https://get.docker.com | sudo sh >/dev/null 2>&1
    sudo usermod -aG docker "$USER" 2>/dev/null || true
fi
if docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=""
else
    DOCKER_PREFIX="sudo"
fi
if $DOCKER_PREFIX docker compose version >/dev/null 2>&1; then
    COMPOSE="$DOCKER_PREFIX docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="${DOCKER_PREFIX} docker-compose"
    COMPOSE="${COMPOSE# }"
else
    pkg_install docker-compose-plugin
    COMPOSE="$DOCKER_PREFIX docker compose"
fi
stop_spin "Docker"

# ── 4. Repositorio ────────────────────────────────────────────────────────────
start_spin "Descargando bb-tracker..."
if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" pull --ff-only -q
else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone -q "$REPO_URL" "$INSTALL_DIR"
fi
[ ! -f "$INSTALL_DIR/.env" ] && cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
stop_spin "Código descargado"

# ── 5. Dependencias CLI ───────────────────────────────────────────────────────
start_spin "Instalando dependencias del CLI..."
VENV_DIR="$INSTALL_DIR/.venv"
python3 -m venv --clear "$VENV_DIR" >/dev/null 2>&1
find "$VENV_DIR" -name "EXTERNALLY-MANAGED" -delete
"$VENV_DIR/bin/python" -m pip install -q -r "$INSTALL_DIR/requirements-cli.txt" >/dev/null 2>&1 \
    || fail_spin "Error instalando dependencias del CLI"
stop_spin "Dependencias del CLI"

# ── 6. Imagen Docker ──────────────────────────────────────────────────────────
start_spin "Construyendo imagen Docker..."
(cd "$INSTALL_DIR" && $COMPOSE build -q 2>/dev/null) \
    || fail_spin "Error construyendo imagen Docker"
stop_spin "Imagen Docker lista"

# ── 7. Comando bb-tracker ─────────────────────────────────────────────────────
start_spin "Creando comando bb-tracker..."
mkdir -p "$BIN_DIR"
cat > "$CMD" << 'WRAPPER'
#!/usr/bin/env bash
INSTALL_DIR="$HOME/.local/share/bb-tracker"
cd "$INSTALL_DIR"
exec "$INSTALL_DIR/.venv/bin/python" cli.py "$@"
WRAPPER
chmod +x "$CMD"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    SHELL_RC="$HOME/.bashrc"
    [[ "$SHELL" == */zsh ]] && SHELL_RC="$HOME/.zshrc"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
    export PATH="$HOME/.local/bin:$PATH"
fi
stop_spin "Comando bb-tracker instalado"

# ── 8. Contenedor ─────────────────────────────────────────────────────────────
start_spin "Iniciando contenedor..."
# Detener cualquier contenedor que ocupe el puerto 8000
$DOCKER_PREFIX docker ps -q --filter "publish=8000" | xargs -r $DOCKER_PREFIX docker stop >/dev/null 2>&1 || true
(cd "$INSTALL_DIR" && $COMPOSE down 2>/dev/null || true)
(cd "$INSTALL_DIR" && $COMPOSE up -d 2>/dev/null) \
    || fail_spin "Error iniciando el contenedor"
stop_spin "Contenedor en ejecución"

# ── Listo ─────────────────────────────────────────────────────────────────────
echo
echo -e "  ${G}${BOLD}✔  ¡Instalación completa!${RESET}"
echo
echo -e "  ${DIM}Próximos pasos:${RESET}"
echo -e "  ${C}1.${RESET} Configurá tus credenciales  →  ${BOLD}bb-tracker${RESET}"
echo -e "  ${C}2.${RESET} Abrí el dashboard           →  ${BOLD}http://localhost:8000${RESET}"
echo
