#!/usr/bin/env bash
# install.sh — Instala bb-tracker en Linux
# curl -fsSL https://raw.githubusercontent.com/Franker26/bb-tracker/main/install.sh | bash

REPO_URL="https://github.com/Franker26/bb-tracker.git"
INSTALL_DIR="$HOME/.local/share/bb-tracker"
BIN_DIR="$HOME/.local/bin"
CMD="$BIN_DIR/bb-tracker"

# ── Colores ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' C='\033[0;36m'
BOLD='\033[1m' DIM='\033[2m' W='\033[1;37m' RESET='\033[0m'
CLR='\r\033[2K'

# ── Spinner ───────────────────────────────────────────────────────────────────
_spin_pid=""
start_spin() {
    local msg="$1" i=0
    local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    ( while true; do
        printf "${CLR}  ${C}${f[$i]}${RESET}  %s" "$msg"
        i=$(( (i+1) % 10 )); sleep 0.08
      done ) &
    _spin_pid=$!
    disown
}
stop_spin() {
    [ -n "$_spin_pid" ] && { kill "$_spin_pid" 2>/dev/null; wait "$_spin_pid" 2>/dev/null; _spin_pid=""; }
    printf "${CLR}  ${G}✔${RESET}  %s\n" "$1"
}
fail_step() {
    [ -n "$_spin_pid" ] && { kill "$_spin_pid" 2>/dev/null; wait "$_spin_pid" 2>/dev/null; _spin_pid=""; }
    printf "${CLR}  ${R}✘${RESET}  %s\n" "$1"
    [ -n "$2" ] && { echo; echo "$2" | sed 's/^/    /'; }
    echo
    # Limpieza
    [ -f "$INSTALL_DIR/docker-compose.yml" ] && (cd "$INSTALL_DIR" && $COMPOSE down -v 2>/dev/null) || true
    rm -rf "$INSTALL_DIR"
    rm -f "$CMD"
    printf "  ${DIM}Limpieza completa.${RESET}\n\n"
    exit 1
}

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
pkg() { [ -n "$PKG" ] && $PKG "$@" >/dev/null 2>&1; return 0; }

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
command -v git >/dev/null 2>&1 || fail_step "git no encontrado y no se pudo instalar"
stop_spin "git"

# ── 2. Python ─────────────────────────────────────────────────────────────────
start_spin "Python..."
command -v python3 >/dev/null 2>&1 || pkg python3
pkg python3-full python3-venv
command -v python3 >/dev/null 2>&1 || fail_step "python3 no encontrado y no se pudo instalar"
stop_spin "Python"

# ── 3. Docker ─────────────────────────────────────────────────────────────────
start_spin "Docker..."
if ! command -v docker >/dev/null 2>&1; then
    stop_spin "Instalando Docker..."
    curl -fsSL https://get.docker.com | sudo sh >/dev/null 2>&1 || fail_step "No se pudo instalar Docker"
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    start_spin "Docker..."
fi
if docker info >/dev/null 2>&1; then
    DC="docker"
elif sudo docker info >/dev/null 2>&1; then
    DC="sudo docker"
else
    fail_step "Docker no está corriendo. Inicialo con: sudo systemctl start docker"
fi
# Detectar docker-compose o docker compose
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
    [ "$DC" = "sudo docker" ] && COMPOSE="sudo docker-compose"
elif $DC compose version >/dev/null 2>&1; then
    COMPOSE="$DC compose"
else
    pkg docker-compose-plugin || pkg docker-compose
    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE="docker-compose"
    elif $DC compose version >/dev/null 2>&1; then
        COMPOSE="$DC compose"
    else
        fail_step "docker compose no disponible. Instalalo manualmente."
    fi
fi
stop_spin "Docker  (${COMPOSE})"

# ── 4. Repositorio ────────────────────────────────────────────────────────────
start_spin "bb-tracker..."
mkdir -p "$(dirname "$INSTALL_DIR")"
if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" pull --ff-only -q || true
else
    git clone -q "$REPO_URL" "$INSTALL_DIR" || fail_step "No se pudo clonar el repositorio"
fi
[ ! -f "$INSTALL_DIR/.env" ] && cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
stop_spin "bb-tracker descargado"

# ── 5. Dependencias CLI ───────────────────────────────────────────────────────
start_spin "Dependencias del CLI..."
VENV="$INSTALL_DIR/.venv"
python3 -m venv --clear "$VENV" >/dev/null 2>&1 || fail_step "No se pudo crear el entorno virtual Python"
find "$VENV" -name "EXTERNALLY-MANAGED" -delete 2>/dev/null || true
"$VENV/bin/python" -m pip install -q -r "$INSTALL_DIR/requirements-cli.txt" >/dev/null 2>&1 \
    || fail_step "No se pudieron instalar las dependencias del CLI"
stop_spin "Dependencias del CLI"

# ── 6. Imagen Docker ──────────────────────────────────────────────────────────
start_spin "Imagen Docker..."
BUILD_OUT=$( (cd "$INSTALL_DIR" && $COMPOSE build) 2>&1 )
BUILD_EXIT=$?
[ "$BUILD_EXIT" -ne 0 ] && fail_step "Error construyendo la imagen Docker" "$BUILD_OUT"
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

# Buscar un puerto libre desde 8000
PORT=8000
while ss -tlnp 2>/dev/null | grep -q ":${PORT} " || \
      lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
    PORT=$(( PORT + 1 ))
done

# Escribir BB_PORT en el .env
if grep -q '^BB_PORT=' "$INSTALL_DIR/.env" 2>/dev/null; then
    sed -i "s/^BB_PORT=.*/BB_PORT=${PORT}/" "$INSTALL_DIR/.env"
else
    echo "BB_PORT=${PORT}" >> "$INSTALL_DIR/.env"
fi

# Detener contenedores previos del proyecto
(cd "$INSTALL_DIR" && $COMPOSE down --remove-orphans 2>/dev/null) || true
sleep 1

UP_OUT=$( (cd "$INSTALL_DIR" && $COMPOSE up -d) 2>&1 )
UP_EXIT=$?
[ "$UP_EXIT" -ne 0 ] && fail_step "Error iniciando el contenedor" "$UP_OUT"
stop_spin "Contenedor en ejecución  (puerto ${PORT})"

# ── Listo ─────────────────────────────────────────────────────────────────────
echo
echo -e "  ${G}${BOLD}✔  ¡Instalación completa!${RESET}"
echo
echo -e "  ${DIM}Próximos pasos:${RESET}"
echo -e "  ${C}1.${RESET} Configurá tus credenciales  →  ${BOLD}bb-tracker${RESET}"
echo -e "  ${C}2.${RESET} Abrí el dashboard           →  ${BOLD}http://localhost:${PORT}${RESET}"
echo
