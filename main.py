"""
Entrypoint principal.

Arranca:
  1. La DB (crea tablas si no existen)
  2. El scheduler (sync cada REFRESH_INTERVAL_MINUTES)
  3. El servidor web FastAPI en http://127.0.0.1:8000
"""

import asyncio
import logging

import uvicorn
from apscheduler.schedulers.asyncio import AsyncIOScheduler

import config
import db.store as store
from scraper.sync import sync_all
from web.app import app, register_sync

log_level = logging.DEBUG if config.LOG_LEVEL == "DEBUG" else logging.INFO
logging.basicConfig(
    level=log_level,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)


async def _main() -> None:
    store.init_db(config.DB_PATH)
    register_sync(sync_all)

    scheduler = AsyncIOScheduler()
    scheduler.add_job(
        sync_all,
        trigger="interval",
        minutes=config.REFRESH_INTERVAL_MINUTES,
        id="sync_all",
        replace_existing=True,
    )
    scheduler.start()

    logger.info("Sync inicial...")
    try:
        await sync_all()
    except Exception as e:
        logger.error("Error en sync inicial: %s", e)

    server = uvicorn.Server(
        uvicorn.Config(
            app=app,
            host="0.0.0.0",
            port=8000,
            log_level="warning",
        )
    )

    logger.info("Dashboard disponible en http://localhost:8000")
    await server.serve()
    scheduler.shutdown()


if __name__ == "__main__":
    asyncio.run(_main())
