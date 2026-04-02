# bb-tracker

Scraper y dashboard local para hacer seguimiento de actividades y entregas en Blackboard (Palermo University).

## ¿Qué hace?

- Se loguea a Blackboard con tus credenciales
- Extrae todos tus cursos y sus actividades con fecha de entrega
- Las guarda en SQLite y las muestra en un dashboard web en `http://localhost:8000`
- Se re-sincroniza automáticamente cada 30 minutos
- Incluye un CLI interactivo para configurar credenciales y seleccionar qué cursos sincronizar

## Instalación rápida (Linux)

**Requisitos:** `git`, `docker`, `python3`, `pip3`

```bash
curl -fsSL https://raw.githubusercontent.com/Franker26/bb-tracker/main/install.sh | bash
```

Luego abrí el menú interactivo:

```bash
bb-tracker
```

> Si `bb-tracker` no se encuentra, agregá `~/.local/bin` al PATH:
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

## Instalación manual

```bash
git clone https://github.com/Franker26/bb-tracker.git
cd bb-tracker
cp .env.example .env
docker compose up --build -d
pip3 install --user -r requirements-cli.txt
ln -s "$(pwd)/bb-tracker" ~/.local/bin/bb-tracker
bb-tracker   # configurá credenciales y cursos
```

## Stack

- **Scraper**: Playwright (browser headless + fetch autenticado sobre la API de Blackboard)
- **Backend**: FastAPI + APScheduler + SQLite
- **Dashboard**: Jinja2 + HTML/CSS
- **CLI**: Rich + Questionary + Pyfiglet

## Configuración (.env)

```env
BB_BASE_URL=https://palermo.blackboard.com
BB_EMAIL=tu_usuario
BB_PASSWORD=tu_contraseña

# IDs de cursos a sincronizar (se configura desde el CLI).
# Vacío = todos los cursos.
BB_SELECTED_COURSE_IDS=

# Palabras clave alternativas (fallback si no hay IDs configurados).
BB_COURSE_KEYWORDS=

REFRESH_INTERVAL_MINUTES=30
LOG_LEVEL=INFO
DB_PATH=/data/blackboard.db
```

## Endpoints API

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/` | Dashboard web |
| `GET` | `/api/activities` | Lista de actividades en JSON |
| `GET` | `/api/courses` | Lista de cursos en JSON |
| `POST` | `/refresh` | Fuerza un sync inmediato |

## Estructura

```
bb-tracker/
├── install.sh            # Instalador automático
├── main.py               # Entrypoint (scheduler + uvicorn)
├── config.py             # Variables de entorno
├── cli.py                # CLI interactivo (bb-tracker)
├── scraper/
│   └── sync.py           # Login Playwright + fetch autenticado
├── db/
│   ├── schema.sql
│   └── store.py          # SQLite CRUD
├── web/
│   ├── app.py            # FastAPI routes
│   └── templates/
│       └── index.html    # Dashboard
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── requirements-cli.txt
```

## Notas técnicas

El scraper usa Playwright para autenticarse (formulario web) y luego hace llamadas directas a la API REST interna de Blackboard (`/learn/api/v1/...`) usando las cookies de sesión del browser. No necesita conocer los endpoints de antemano ni reverse-engineering previo.

Los tipos de contenido que se rastrean:
- `resource/x-bb-asmt-test-link` (evaluaciones/parciales)
- `resource/x-bb-assignment` (trabajos prácticos)
- `resource/x-bb-blti-link` (LTI externo, ej. Turnitin)
- `resource/x-turnitin-assignment`
