#!/usr/bin/env python3
"""
bb-tracker — CLI de configuración para Blackboard Tracker
Uso:  python cli.py
      bb-tracker          (si está en el PATH)
"""

import os
import re
import subprocess
import sys
import time
from pathlib import Path

# ── Verificar dependencias ────────────────────────────────────────────────────
_missing = []
for _pkg in ["questionary", "rich", "requests", "pyfiglet"]:
    try:
        __import__(_pkg)
    except ImportError:
        _missing.append(_pkg)

if _missing:
    print(f"\n  Faltan dependencias CLI. Instalá con:")
    print(f"\n    pip install {' '.join(_missing)}\n")
    sys.exit(1)

import pyfiglet
import questionary
import requests
from questionary import Style
from rich import box
from rich.console import Console
from rich.panel import Panel

# ── Constantes ────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).parent.resolve()
ENV_PATH = SCRIPT_DIR / ".env"
COMPOSE_FILE = str(SCRIPT_DIR / "docker-compose.yml")
APP_URL = "http://localhost:8000"

console = Console()

STYLE = Style([
    ("qmark",       "fg:#00d7ff bold"),
    ("question",    "bold"),
    ("answer",      "fg:#00d7ff bold"),
    ("pointer",     "fg:#00d7ff bold"),
    ("highlighted", "fg:#00d7ff bold"),
    ("selected",    "fg:#00ff87"),
    ("separator",   "fg:#555555"),
    ("instruction", "fg:#555555 italic"),
])

# ── Helpers ───────────────────────────────────────────────────────────────────

def show_banner() -> None:
    console.clear()
    art = pyfiglet.figlet_format("BB-TRACKER", font="slant")
    console.print(f"[bold cyan]{art}[/bold cyan]", end="")
    console.print(Panel(
        "[dim]Blackboard Tracker  ·  Palermo University  ·  v1.0[/dim]",
        border_style="cyan",
        box=box.ROUNDED,
        padding=(0, 2),
    ))
    console.print()


def read_env() -> dict[str, str]:
    env: dict[str, str] = {}
    if ENV_PATH.exists():
        for line in ENV_PATH.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip()
    return env


def write_env_key(key: str, value: str) -> None:
    """Actualiza o agrega una clave en .env preservando comentarios y orden."""
    text = ENV_PATH.read_text() if ENV_PATH.exists() else ""
    lines = text.splitlines()
    pattern = re.compile(rf"^{re.escape(key)}\s*=")
    found = False
    new_lines = []
    for line in lines:
        if pattern.match(line):
            new_lines.append(f"{key}={value}")
            found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"{key}={value}")
    ENV_PATH.write_text("\n".join(new_lines) + "\n")


def restart_container() -> None:
    console.print("\n  [yellow]Reiniciando contenedor...[/yellow]")
    # Intenta sin sudo primero; si falla, usa el grupo docker
    cmd = ["docker-compose", "-f", COMPOSE_FILE, "restart"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        result = subprocess.run(
            ["bash", "-c", f"newgrp docker <<< 'docker-compose -f {COMPOSE_FILE} restart'"],
            capture_output=True, text=True,
        )
    if result.returncode == 0:
        console.print("  [green]✓ Contenedor reiniciado.[/green]")
    else:
        console.print(f"  [red]Error al reiniciar:[/red] {result.stderr.strip()}")
        console.print("  [dim]Podés reiniciarlo manualmente con:[/dim]")
        console.print(f"  [dim]  docker-compose -f {COMPOSE_FILE} restart[/dim]")
    time.sleep(2)


def get_courses() -> list[dict] | None:
    try:
        r = requests.get(f"{APP_URL}/api/courses", timeout=5)
        return r.json() if r.status_code == 200 else None
    except requests.ConnectionError:
        return None


def wait_for_input(msg: str = "\n  Presioná [bold]Enter[/bold] para continuar...") -> None:
    console.print(msg)
    input()


# ── Secciones ─────────────────────────────────────────────────────────────────

def section_credentials() -> None:
    show_banner()
    console.print(Panel("[bold]  Credenciales[/bold]", border_style="cyan",
                        box=box.ROUNDED, padding=(0, 2)))
    console.print()

    env = read_env()
    cur_email = env.get("BB_EMAIL", "")
    cur_pass  = env.get("BB_PASSWORD", "")

    console.print(f"  Usuario actual  : [cyan]{cur_email}[/cyan]")
    console.print(f"  Contraseña actual: [cyan]{'●' * min(len(cur_pass), 12)}[/cyan]")
    console.print()

    new_email = questionary.text(
        "Usuario (email):", default=cur_email, style=STYLE,
    ).ask()
    if new_email is None:
        return

    new_pass = questionary.password(
        "Contraseña (Enter para no cambiar):", style=STYLE,
    ).ask()
    if new_pass is None:
        return
    if not new_pass:
        new_pass = cur_pass

    changed = new_email != cur_email or new_pass != cur_pass
    if not changed:
        console.print("\n  [dim]Sin cambios.[/dim]")
        wait_for_input()
        return

    write_env_key("BB_EMAIL", new_email)
    write_env_key("BB_PASSWORD", new_pass)
    console.print("\n  [green]✓ Credenciales guardadas.[/green]")

    if questionary.confirm("¿Reiniciar el contenedor para aplicar?",
                           default=True, style=STYLE).ask():
        restart_container()
    wait_for_input()


def section_courses() -> None:
    show_banner()
    console.print(Panel("[bold]  Selección de cursos[/bold]", border_style="cyan",
                        box=box.ROUNDED, padding=(0, 2)))
    console.print()

    courses = get_courses()
    if courses is None:
        console.print("  [red]✗ No se pudo conectar a la app en localhost:8000.[/red]")
        console.print("  [dim]  Asegurate de que el contenedor esté corriendo.[/dim]")
        wait_for_input()
        return

    if not courses:
        console.print("  [yellow]No hay cursos en la base de datos todavía.[/yellow]")
        console.print("  [dim]  Hacé un sync primero desde el menú principal.[/dim]")
        wait_for_input()
        return

    env = read_env()
    selected_ids = set(
        i.strip() for i in env.get("BB_SELECTED_COURSE_IDS", "").split(",") if i.strip()
    )
    # Si no hay IDs configurados, todos pre-seleccionados
    pre_select_all = not selected_ids

    console.print(f"  [dim]{len(courses)} cursos disponibles. "
                  "ESPACIO = toggle · ENTER = confirmar · Ctrl+C = cancelar[/dim]\n")

    choices = [
        questionary.Choice(
            title=c["name"],
            value=c["id"],
            checked=pre_select_all or (c["id"] in selected_ids),
        )
        for c in sorted(courses, key=lambda x: x["name"])
    ]

    selected = questionary.checkbox(
        "Cursos a sincronizar:", choices=choices, style=STYLE,
    ).ask()
    if selected is None:
        return

    write_env_key("BB_SELECTED_COURSE_IDS", ",".join(selected))
    write_env_key("BB_COURSE_KEYWORDS", "")   # reemplazado por IDs

    console.print(f"\n  [green]✓ {len(selected)} curso(s) seleccionado(s).[/green]")

    if questionary.confirm("¿Reiniciar el contenedor para aplicar?",
                           default=True, style=STYLE).ask():
        restart_container()
    wait_for_input()


def section_sync() -> None:
    show_banner()
    console.print(Panel("[bold]  Sincronizar ahora[/bold]", border_style="cyan",
                        box=box.ROUNDED, padding=(0, 2)))
    console.print()

    console.print("  [yellow]Iniciando sync... (puede tardar ~3 min)[/yellow]")
    try:
        r = requests.post(f"{APP_URL}/refresh", timeout=360)
        if r.status_code == 200:
            console.print("  [green]✓ Sync completado. Revisá el dashboard en http://localhost:8000[/green]")
        else:
            console.print(f"  [red]Error:[/red] {r.json().get('error', r.text)}")
    except requests.ConnectionError:
        console.print("  [red]✗ No se pudo conectar a la app.[/red]")
    except requests.Timeout:
        console.print("  [yellow]Timeout — el sync sigue corriendo en segundo plano.[/yellow]")
        console.print("  [dim]  Seguí en http://localhost:8000[/dim]")

    wait_for_input()


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    while True:
        show_banner()

        choice = questionary.select(
            "¿Qué querés hacer?",
            choices=[
                questionary.Choice("  🔑  Credenciales",      value="creds"),
                questionary.Choice("  📚  Cursos",            value="courses"),
                questionary.Separator("─" * 30),
                questionary.Choice("  🔄  Sincronizar ahora", value="sync"),
                questionary.Separator("─" * 30),
                questionary.Choice("  ✖   Salir",             value="exit"),
            ],
            style=STYLE,
        ).ask()

        if choice is None or choice == "exit":
            console.print("\n  [dim]Hasta luego.[/dim]\n")
            break
        elif choice == "creds":
            section_credentials()
        elif choice == "courses":
            section_courses()
        elif choice == "sync":
            section_sync()


if __name__ == "__main__":
    main()
