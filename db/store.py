"""
Capa de persistencia SQLite.
Todas las operaciones son síncronas (sqlite3 nativo).
"""

import sqlite3
import os
from datetime import datetime, timezone
from scraper.activities import Activity
from scraper.courses import Course

_SCHEMA_PATH = os.path.join(os.path.dirname(__file__), "schema.sql")


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(db_path: str) -> None:
    """Crea las tablas si no existen."""
    with open(_SCHEMA_PATH) as f:
        schema = f.read()
    with _connect(db_path) as conn:
        conn.executescript(schema)


def upsert_course(db_path: str, course: Course) -> None:
    with _connect(db_path) as conn:
        conn.execute(
            "INSERT INTO courses (id, name) VALUES (?, ?) "
            "ON CONFLICT(id) DO UPDATE SET name = excluded.name",
            (course.id, course.name),
        )


def upsert_activity(db_path: str, activity: Activity) -> None:
    now = datetime.now(tz=timezone.utc).isoformat()
    due_str = activity.due_date.isoformat() if activity.due_date else None
    with _connect(db_path) as conn:
        conn.execute(
            """
            INSERT INTO activities (id, title, course_id, due_date, status, url, last_updated)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title        = excluded.title,
                due_date     = excluded.due_date,
                status       = excluded.status,
                url          = excluded.url,
                last_updated = excluded.last_updated
            """,
            (activity.id, activity.title, activity.course_id, due_str, activity.status, activity.url, now),
        )


def get_all_activities(db_path: str) -> list[dict]:
    """
    Retorna todas las actividades ordenadas por due_date ASC (nulos al final),
    enriquecidas con el nombre del curso.
    """
    with _connect(db_path) as conn:
        rows = conn.execute(
            """
            SELECT
                a.id,
                a.title,
                a.course_id,
                c.name  AS course_name,
                a.due_date,
                a.status,
                a.url,
                a.last_updated
            FROM activities a
            JOIN courses c ON c.id = a.course_id
            ORDER BY
                CASE WHEN a.due_date IS NULL THEN 1 ELSE 0 END,
                a.due_date ASC
            """
        ).fetchall()
    return [dict(r) for r in rows]


def delete_activities_not_in_courses(db_path: str, course_ids: list[str]) -> int:
    """Elimina actividades de cursos que no están en la lista. Retorna filas borradas."""
    if not course_ids:
        return 0
    placeholders = ",".join("?" * len(course_ids))
    with _connect(db_path) as conn:
        cur = conn.execute(
            f"DELETE FROM activities WHERE course_id NOT IN ({placeholders})",
            course_ids,
        )
    return cur.rowcount


def get_all_courses(db_path: str) -> list[dict]:
    with _connect(db_path) as conn:
        rows = conn.execute("SELECT id, name FROM courses ORDER BY name").fetchall()
    return [dict(r) for r in rows]


def get_last_updated(db_path: str) -> str | None:
    """Retorna el timestamp de la última sincronización."""
    with _connect(db_path) as conn:
        row = conn.execute(
            "SELECT MAX(last_updated) AS ts FROM activities"
        ).fetchone()
    return row["ts"] if row else None
