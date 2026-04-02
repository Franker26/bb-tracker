import os
from dotenv import load_dotenv

load_dotenv()

BB_BASE_URL: str = os.environ["BB_BASE_URL"]
BB_EMAIL: str = os.environ["BB_EMAIL"]
BB_PASSWORD: str = os.environ["BB_PASSWORD"]
REFRESH_INTERVAL_MINUTES: int = int(os.getenv("REFRESH_INTERVAL_MINUTES", "30"))
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()

DB_PATH: str = os.getenv("DB_PATH", os.path.join(os.path.dirname(__file__), "blackboard.db"))

# IDs exactos de cursos a sincronizar (configurado por el CLI).
# Tiene prioridad sobre BB_COURSE_KEYWORDS.
_raw_ids = os.getenv("BB_SELECTED_COURSE_IDS", "")
SELECTED_COURSE_IDS: list[str] = [i.strip() for i in _raw_ids.split(",") if i.strip()]

# Palabras clave fallback (legacy / manual).
_raw_keywords = os.getenv("BB_COURSE_KEYWORDS", "")
COURSE_KEYWORDS: list[str] = [k.strip() for k in _raw_keywords.split(",") if k.strip()]
