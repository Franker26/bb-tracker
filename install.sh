#!/usr/bin/env bash
# install.sh — Instala bb-tracker en Linux
# curl -fsSL https://raw.githubusercontent.com/Franker26/bb-tracker/main/install.sh | bash

set -euo pipefail

REPO_URL="https://github.com/Franker26/bb-tracker.git"
INSTALL_DIR="$HOME/.local/share/bb-tracker"
BIN_DIR="$HOME/.local/bin"
CMD="$BIN_DIR/bb-tracker"

# ── Colores ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m'
BOLD='\033[1m' DIM='\033[2m' W='\033[1;37m' RESET='\033[0m'
CLR='\r\033[2K'   # vuelve al inicio y borra la línea completa

# ── Spinner ───────────────────────────────────────────────────────────────────
_spin_pid=""
_spin_msg=""

start_spin() {
    _spin_msg="$1"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    (
        local i=0
        while true; do
            printf "${CLR}  ${C}${frames[$i]}${RESET}  %s" "$_spin_msg"
            i=$(( (i+1) % 10 ))
            sleep 0.08
        done
    ) &
    _spin_pid=$!
    disown
}

stop_spin() {
    if [ -n "$_spin_pid" ]; then
        kill "$_spin_pid" 2>/dev/null
        wait "$_spin_pid" 2>/dev/null
        _spin_pid=""
    fi
    printf "${CLR}  ${G}✔${RESET}  %s\n" "$1"
}

# ── Limpieza en caso de error ─────────────────────────────────────────────────
_installed=false
on_error() {
    [ -n "$_spin_pid" ] && kill "$_spin_pid" 2>/dev/null && _spin_pid=""
    printf "${CLR}  ${R}✘${RESET}  Instalación fallida\n\n"
    if [ "$_installed" = false ]; then
        printf "  ${DIM}Limpiando archivos instalados...${RESET}\n"
        (cd "$INSTALL_DIR" 2>/dev/null && $COMPOSE down -v 2>/dev/null) || true
        rm -rf "$INSTALL_DIR"
        rm -f "$CMD"
        printf "  ${DIM}Limpieza completa.${RESET}\n"
    fi
    echo
}
trap on_error ERR

# ── Gestor de paquetes ────────────────────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    PKG="sudo apt-get install -y -q"
elif command -v dnf >/dev/null 2>&1; then
    PKG="sudo dnf install -y -q"
elif command -v pacman >/dev/null 2>&1; then
    PKG="sudo pacman -S --noconfirm --quiet"
else
    PKG=""
fi
pkg() { [ -n "$PKG" ] && $PKG "$@" >/dev/null 2>&1 || true; }

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo
echo -e "  ${BOLD}${C}██████╗ ██████╗       ████████╗██████╗  █████╗  ██████╗██╗  ██╗███████╗██████╗ ${RESET}"
echo -e "  ${BOLD}${C}██╔══██╗██╔══██╗         ██╔══╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗${RESET}"
echo -e "  ${BOLD}${C}██████╔╝██████╔╝         ██║   ██████╔╝███████║██║     █████╔╝ █████╗  ██████╔╝${RESET}"
echo -e "  ${BOLD}${C}██╔══██╗██╔══██╗         ██║   ██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗${RESET}"
echo -e "  ${BOLD}${C}██████╔╝██████╔╝         ██║   ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║${RESET}"
echo -e "  ${BOLD}${C}╚═════╝ ╚═════╝          ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝${RESET}"
echo
echo -e "  ${DIM}Blackboard activity tracker  ·  by ${W}Franker26${RESET}"
echo -e "  ${DIM}──────────────────────────────────────────────${RESET}"
echo

# ── 1. git ────────────────────────────────────────────────────────────────────
start_spin "git..."
command -v git >/dev/null 2>&1 || pkg git
stop_spin "git"

# ── 2. Python ─────────────────────────────────────────────────────────────────
start_spin "Python..."
command -v python3 >/dev/null 2>&1 || pkg python3
pkg python3-full python3-venv
stop_spin "Python"

# ── 3. Docker ─────────────────────────────────────────────────────────────────
start_spin "Docker..."
if ! command -v docker >/dev/null 2>&1; then
    stop_spin "Instalando Docker..."
    curl -fsSL https://get.docker.com | sudo sh >/dev/null 2>&1
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    start_spin "Docker..."
fi
if docker info >/dev/null 2>&1; then
    DC="docker"
else
    DC="sudo docker"
fi
# Preferir docker-compose v1 si está disponible (evita conflictos de nombres)
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
    [ "$DC" = "sudo docker" ] && COMPOSE="sudo docker-compose"
elif $DC compose version >/dev/null 2>&1; then
    COMPOSE="$DC compose"
else
    pkg docker-compose-plugin
    COMPOSE="$DC compose"
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
stop_spin "bb-tracker descargado"

# ── 5. Dependencias CLI ───────────────────────────────────────────────────────
start_spin "Dependencias del CLI..."
VENV="$INSTALL_DIR/.venv"
python3 -m venv --clear "$VENV" >/dev/null 2>&1
find "$VENV" -name "EXTERNALLY-MANAGED" -delete 2>/dev/null || true
"$VENV/bin/python" -m pip install -q -r "$INSTALL_DIR/requirements-cli.txt" >/dev/null 2>&1
stop_spin "Dependencias del CLI"

# ── 6. Imagen Docker ──────────────────────────────────────────────────────────
start_spin "Imagen Docker..."
(cd "$INSTALL_DIR" && $COMPOSE build -q 2>/dev/null)
stop_spin "Imagen Docker"

# ── 7. Comando bb-tracker ─────────────────────────────────────────────────────
start_spin "Comando bb-tracker..."
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
    [[ "${SHELL:-}" == */zsh ]] && SHELL_RC="$HOME/.zshrc"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
    export PATH="$HOME/.local/bin:$PATH"
fi
stop_spin "Comando bb-tracker"

# ── 8. Contenedor ─────────────────────────────────────────────────────────────
start_spin "Iniciando contenedor..."

# Detener cualquier contenedor que use el puerto 8000
docker ps --format '{{.ID}} {{.Ports}}' 2>/dev/null \
  | grep '8000' \
  | awk '{print $1}' \
  | xargs -r docker stop >/dev/null 2>&1 || true

sudo docker ps --format '{{.ID}} {{.Ports}}' 2>/dev/null \
  | grep '8000' \
  | awk '{print $1}' \
  | xargs -r sudo docker stop >/dev/null 2>&1 || true

(cd "$INSTALL_DIR" && $COMPOSE down --remove-orphans 2>/dev/null) || true
sleep 2
(cd "$INSTALL_DIR" && $COMPOSE up -d 2>/dev/null)

stop_spin "Contenedor en ejecución"

# ── Listo ─────────────────────────────────────────────────────────────────────
_installed=true
echo
echo -e "  ${G}${BOLD}✔  ¡Instalación completa!${RESET}"
echo
echo -e "  ${DIM}Próximos pasos:${RESET}"
echo -e "  ${C}1.${RESET} Configurá tus credenciales  →  ${BOLD}bb-tracker${RESET}"
echo -e "  ${C}2.${RESET} Abrí el dashboard           →  ${BOLD}http://localhost:8000${RESET}"
echo
