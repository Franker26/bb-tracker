"""
Motor de sincronización basado en Playwright.

Flujo:
  1. Login en Blackboard (formulario web)
  2. Intercepta la response de cursos (memberships) que la app dispara sola
  3. Por cada curso, usa fetch autenticado para obtener todos los contenidos
     (con paginación y recursión en carpetas)
  4. Filtra actividades con entrega y las persiste en SQLite
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timezone

from playwright.async_api import async_playwright, Page, Response, BrowserContext

import config
import db.store as store

logger = logging.getLogger(__name__)

BB = config.BB_BASE_URL  # https://palermo.blackboard.com

# Tipos de contenido que indican actividad entregable.
ACTIVITY_HANDLERS = {
    "resource/x-bb-assignment",
    "resource/x-bb-blti-link",
    "resource/x-turnitin-assignment",
    "resource/x-bb-asmt-test-link",
}

# ──────────────────────────────────────────────────────────────────────────────


@dataclass
class _Course:
    id: str
    name: str
    ultra_url: str


@dataclass
class _Activity:
    id: str
    title: str
    course_id: str
    course_name: str
    due_date: datetime | None
    status: str
    url: str


def _parse_iso(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def _status(due: datetime | None, submitted: bool) -> str:
    if submitted:
        return "submitted"
    if due and datetime.now(tz=timezone.utc) > due:
        return "overdue"
    return "pending"


async def _parse_courses(data: dict) -> list[_Course]:
    courses = []
    if isinstance(data, list):
        results = data
    else:
        results = data.get("results", [])
    for item in results:
        if not isinstance(item, dict):
            continue
        cid = (
            item.get("courseId")
            or item.get("course", {}).get("id")
            or item.get("id")
        )
        name = (
            item.get("course", {}).get("displayName")
            or item.get("course", {}).get("name")
            or item.get("displayName")
            or item.get("name")
            or cid
        )
        if cid:
            ultra_url = f"{BB}/ultra/courses/{cid}/outline"
            courses.append(_Course(id=cid, name=name, ultra_url=ultra_url))
    return courses


def _parse_activity_item(item: dict, course: "_Course") -> "_Activity | None":
    if not isinstance(item, dict):
        return None
    handler = ""
    ch = item.get("contentHandler")
    if isinstance(ch, dict):
        handler = ch.get("id", "")
    elif isinstance(ch, str):
        handler = ch
    handler = handler or item.get("type", "")

    if handler not in ACTIVITY_HANDLERS:
        return None

    content_id = item.get("id", "")
    title = item.get("title", "Sin título")
    due_raw = (
        item.get("dueDate")
        or item.get("genericReadOnlyData", {}).get("dueDate")
        or item.get("availability", {}).get("adaptiveRelease", {}).get("end")
    )
    due = _parse_iso(due_raw)

    if due is None:
        logger.debug("Sin fecha — ignorando: %s", title)
        return None

    submitted = bool(item.get("submitted") or item.get("score") is not None)
    url = f"{BB}/ultra/courses/{course.id}/outline"
    return _Activity(
        id=content_id,
        title=title,
        course_id=course.id,
        course_name=course.name,
        due_date=due,
        status=_status(due, submitted),
        url=url,
    )


async def _fetch_contents_recursive(page: Page, course: _Course) -> list[_Activity]:
    """
    Usa fetch autenticado del browser para obtener todos los contenidos del curso
    con paginación y recursión en carpetas.
    """
    js = """
    async ([baseUrl, courseId]) => {
        const FOLDER_HANDLERS = [
            'resource/x-bb-folder',
            'resource/x-bb-module',
            'resource/x-bb-moduletemplate',
            'resource/x-bb-lesson',
        ];
        const allItems = [];
        const visited = new Set();

        async function fetchChildren(contentId) {
            if (visited.has(contentId)) return;
            visited.add(contentId);

            let nextPage = `/learn/api/v1/courses/${courseId}/contents/${contentId}/children?limit=200&expand=assignedGroups,gradebookCategory,genericReadOnlyData,contentDetail`;
            while (nextPage) {
                try {
                    const resp = await fetch(baseUrl + nextPage);
                    if (!resp.ok) break;
                    const data = await resp.json();
                    const results = Array.isArray(data) ? data : (data.results || []);
                    for (const item of results) {
                        if (!item || typeof item !== 'object') continue;
                        allItems.push(item);
                        const handler = (item.contentHandler && item.contentHandler.id) || item.contentHandler || '';
                        if (FOLDER_HANDLERS.some(f => handler.includes(f.split('/').pop()))) {
                            await fetchChildren(item.id);
                        }
                    }
                    nextPage = (data.paging && data.paging.nextPage) ? data.paging.nextPage : null;
                } catch(e) {
                    break;
                }
            }
        }

        await fetchChildren('ROOT');
        return allItems;
    }
    """
    try:
        items = await page.evaluate(js, [BB, course.id])
        logger.debug("Curso %s: %d items raw del API", course.name, len(items))

        # Loguear handlers únicos para diagnóstico
        handlers_found = set()
        for item in items:
            if not isinstance(item, dict):
                continue
            ch = item.get("contentHandler")
            if isinstance(ch, dict):
                h = ch.get("id", "")
            elif isinstance(ch, str):
                h = ch
            else:
                h = item.get("type", "sin-handler")
            if h:
                handlers_found.add(h)
        if handlers_found:
            logger.debug("Handlers en %s: %s", course.name, handlers_found)

        # Loguear estructura de los primeros items de tipo asmt/assignment
        import json
        for item in items:
            if not isinstance(item, dict):
                continue
            ch = item.get("contentHandler")
            h = (ch.get("id", "") if isinstance(ch, dict) else ch) or ""
            if "asmt-test-link" in h or "assignment" in h:
                logger.debug("SAMPLE item (%s): %s", h, json.dumps(item, default=str))
                break

        activities = []
        for item in items:
            act = _parse_activity_item(item, course)
            if act:
                activities.append(act)
        return activities
    except Exception as e:
        logger.warning("Error fetching contenidos para %s: %s", course.name, e)
        return []


async def _login(page: Page) -> None:
    logger.info("Navegando al login...")
    await page.goto(f"{BB}/webapps/login/", wait_until="networkidle")
    logger.info("Login page — URL: %s", page.url)

    # Cerrar cualquier dialog/popup
    try:
        await page.keyboard.press("Escape")
        await page.wait_for_timeout(500)
    except Exception:
        pass

    await page.fill("#user_id", config.BB_EMAIL)
    await page.fill("#password", config.BB_PASSWORD)
    logger.info("Formulario llenado. Enviando...")

    await page.press("#password", "Enter")
    await page.wait_for_timeout(2_000)

    if "webapps/login" in page.url:
        await page.click("#entry-login", force=True)

    await page.wait_for_load_state("networkidle", timeout=45_000)
    current_url = page.url
    logger.info("Post-login — URL: %s", current_url)

    if "webapps/login" in current_url:
        error_text = ""
        try:
            error_el = page.locator("#loginErrorMessage, .alert, .error")
            if await error_el.count() > 0:
                error_text = await error_el.first.inner_text()
        except Exception:
            pass
        raise RuntimeError(f"Login fallido. Error: '{error_text}'")

    if "/ultra" not in current_url:
        await page.goto(f"{BB}/ultra/", wait_until="networkidle", timeout=30_000)

    logger.info("Login exitoso. URL final: %s", page.url)


async def sync_all() -> None:
    """Punto de entrada principal del sync."""
    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=True)
        context: BrowserContext = await browser.new_context()
        page = await context.new_page()

        courses: list[_Course] = []

        # Interceptar la respuesta de memberships para obtener los cursos
        async def on_response(response: Response) -> None:
            if response.status != 200:
                return
            if "memberships" in response.url and not courses:
                try:
                    data = await response.json()
                    parsed = await _parse_courses(data)
                    if parsed:
                        logger.info("Cursos interceptados (%d) desde: %s", len(parsed), response.url)
                        courses.extend(parsed)
                except Exception as e:
                    logger.debug("Error parseando memberships: %s", e)

        page.on("response", on_response)

        await _login(page)

        # Esperar a que el dashboard dispare el request de cursos
        await page.wait_for_timeout(4_000)

        if not courses:
            logger.warning("No se interceptaron cursos.")

        await browser.close()

    # ── Filtrar cursos ─────────────────────────────────────────────────────────
    original_count = len(courses)
    if config.SELECTED_COURSE_IDS:
        courses = [c for c in courses if c.id in config.SELECTED_COURSE_IDS]
        logger.info("Filtro por IDs: %d → %d cursos.", original_count, len(courses))
    elif config.COURSE_KEYWORDS:
        courses = [
            c for c in courses
            if any(kw.lower() in c.name.lower() or kw.lower() in c.id.lower()
                   for kw in config.COURSE_KEYWORDS)
        ]
        logger.info("Filtro por keywords (%s): %d → %d cursos.",
                    ", ".join(config.COURSE_KEYWORDS), original_count, len(courses))
    else:
        logger.info("Sin filtro — sincronizando todos (%d).", original_count)

    # ── Fetching de actividades por curso (fuera del browser) ──────────────────
    # Re-abrimos el browser para hacer las llamadas API autenticadas
    all_activities: list[_Activity] = []

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=True)
        context = await browser.new_context()
        page = await context.new_page()

        # Login de nuevo para tener sesión activa
        await _login(page)
        await page.wait_for_timeout(2_000)

        for course in courses:
            logger.info("Procesando curso: %s", course.name)
            acts = await _fetch_contents_recursive(page, course)
            logger.info("  → %d actividades encontradas", len(acts))
            all_activities.extend(acts)

        await browser.close()

    # ── Persistir en SQLite ────────────────────────────────────────────────────
    from scraper.courses import Course as DBCourse
    from scraper.activities import Activity as DBActivity

    for course in courses:
        store.upsert_course(config.DB_PATH, DBCourse(id=course.id, name=course.name))

    # Limpiar actividades de cursos que ya no están en la selección
    if config.SELECTED_COURSE_IDS or config.COURSE_KEYWORDS:
        synced_ids = [c.id for c in courses]
        deleted = store.delete_activities_not_in_courses(config.DB_PATH, synced_ids)
        if deleted:
            logger.info("Limpieza: %d actividades eliminadas de cursos no seleccionados.", deleted)

    for act in all_activities:
        store.upsert_activity(
            config.DB_PATH,
            DBActivity(
                id=act.id,
                title=act.title,
                course_id=act.course_id,
                course_name=act.course_name,
                due_date=act.due_date,
                status=act.status,
                url=act.url,
            ),
        )

    logger.info("Sync completo — %d cursos, %d actividades.", len(courses), len(all_activities))
