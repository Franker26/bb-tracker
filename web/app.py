"""
FastAPI app — dashboard web local.
"""

import os
from collections import defaultdict
from datetime import datetime, timezone

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates

import config
import db.store as store

app = FastAPI(title="Blackboard Tracker")

_TEMPLATES_DIR = os.path.join(os.path.dirname(__file__), "templates")
templates = Jinja2Templates(directory=_TEMPLATES_DIR)

# Referencia al sync_fn que inyecta main.py para no crear dependencias circulares
_sync_fn = None


def register_sync(fn):
    """Registra la función de sincronización para el endpoint /refresh."""
    global _sync_fn
    _sync_fn = fn


def _group_by_course(activities: list[dict]) -> dict[str, list[dict]]:
    grouped = defaultdict(list)
    for a in activities:
        grouped[a["course_name"]].append(a)
    return dict(grouped)


def _format_due(iso_str: str | None) -> str:
    if not iso_str:
        return "Sin fecha"
    try:
        dt = datetime.fromisoformat(iso_str)
        return dt.strftime("%d/%m/%Y %H:%M")
    except ValueError:
        return iso_str


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    activities = store.get_all_activities(config.DB_PATH)
    last_updated = store.get_last_updated(config.DB_PATH)

    for a in activities:
        a["due_date_fmt"] = _format_due(a.get("due_date"))

    grouped = _group_by_course(activities)

    last_updated_fmt = "Nunca"
    if last_updated:
        try:
            dt = datetime.fromisoformat(last_updated)
            last_updated_fmt = dt.strftime("%d/%m/%Y %H:%M:%S")
        except ValueError:
            last_updated_fmt = last_updated

    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "grouped": grouped,
            "last_updated": last_updated_fmt,
            "total": len(activities),
        },
    )


@app.post("/refresh")
async def refresh():
    if _sync_fn is None:
        return JSONResponse({"error": "sync no registrado"}, status_code=500)
    try:
        await _sync_fn()
        return JSONResponse({"status": "ok"})
    except NotImplementedError as e:
        return JSONResponse({"error": str(e)}, status_code=501)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


@app.get("/api/activities")
async def api_activities():
    return store.get_all_activities(config.DB_PATH)


@app.get("/api/courses")
async def api_courses():
    return store.get_all_courses(config.DB_PATH)
