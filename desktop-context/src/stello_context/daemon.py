"""Stello desktop-context daemon — entrypoint.

Stage 2: loads config + opens SQLite on lifespan-startup and exposes their
state via /healthz. Signal-safe shutdown closes the DB.

Later steps wire in:
  - MLX client (step 3)
  - FSEvents watcher + enrich queue (steps 4–7)
  - NSWorkspace + AX poll (step 8)
  - Safari + Sketch introspection (steps 9–11)
  - /related endpoint (step 12)
"""
from __future__ import annotations

import logging
import os
import signal
import sqlite3
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from fastapi import FastAPI

from . import config as config_mod
from . import store as store_mod

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("stello-context")


class State:
    """Process-global runtime state. Populated in the lifespan startup hook."""

    config: config_mod.Config | None = None
    db: sqlite3.Connection | None = None
    db_path: Path | None = None
    config_path: Path | None = None


@asynccontextmanager
async def _lifespan(_app: FastAPI):
    # --- startup ---
    State.config_path = Path(
        os.environ.get("STELLO_CTX_CONFIG", str(config_mod.DEFAULT_CONFIG_PATH))
    )
    State.config = config_mod.load()
    State.db_path = Path(
        os.environ.get("STELLO_CTX_DB", str(store_mod.DEFAULT_DB_PATH))
    )
    State.db = store_mod.open_db()
    logger.info(
        "config: %s (%d watched folder(s), %d blocklist entries)",
        State.config_path,
        len(State.config.watched_folders),
        len(State.config.safari_blocklist),
    )
    logger.info(
        "db:     %s (schema v%d)",
        State.db_path,
        store_mod.schema_version(State.db),
    )
    yield
    # --- shutdown ---
    if State.db is not None:
        State.db.close()
        State.db = None


app = FastAPI(
    title="Stello desktop-context daemon",
    version="0.0.1",
    lifespan=_lifespan,
)


@app.get("/healthz")
def healthz() -> dict:
    """Liveness check. Step 3 nests MLX server status under `mlx`."""
    cfg = State.config
    db = State.db
    return {
        "ok": True,
        "stage": "config+store",
        "config": {
            "path": str(State.config_path) if State.config_path else None,
            "watched_folders": cfg.watched_folders if cfg else [],
            "blocklist_count": len(cfg.safari_blocklist) if cfg else 0,
            "dwell_window_s": cfg.dwell_window_s if cfg else None,
            "vlm_images_per_window": cfg.vlm_images_per_window if cfg else None,
        },
        "db": {
            "path": str(State.db_path) if State.db_path else None,
            "schema_version": store_mod.schema_version(db) if db else None,
            "items_by_status": store_mod.counts_by_status(db) if db else {},
        },
    }


def _install_signal_handlers(server: uvicorn.Server) -> None:
    def _shutdown(signum: int, _frame) -> None:
        logger.info("received signal %s, shutting down", signum)
        server.should_exit = True

    signal.signal(signal.SIGINT, _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)


def main() -> None:
    host = os.environ.get("STELLO_CTX_HOST", "127.0.0.1")
    port = int(os.environ.get("STELLO_CTX_PORT", "8766"))
    config = uvicorn.Config(
        app,
        host=host,
        port=port,
        log_level="info",
        access_log=False,
    )
    server = uvicorn.Server(config)
    _install_signal_handlers(server)
    logger.info("stello-context starting on http://%s:%d", host, port)
    server.run()


if __name__ == "__main__":
    main()
