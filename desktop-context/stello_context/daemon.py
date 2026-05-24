"""Stello desktop-context daemon — entrypoint.

Stage 3: lifespan startup also instantiates the MLX HTTP client and
surfaces its health under /healthz. The MLX server is allowed to be
unreachable at startup (logged as a warning); /related will report it
in step 12.

Later steps wire in:
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
from . import mlx_client as mlx_mod
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
    mlx: mlx_mod.Client | None = None
    mlx_url: str | None = None


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
    State.mlx_url = mlx_mod.DEFAULT_URL
    State.mlx = mlx_mod.Client(base_url=State.mlx_url)
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
    try:
        h = State.mlx.healthz()
        logger.info("mlx:    %s (loaded=%s)", State.mlx_url, h.get("loaded"))
    except Exception as e:
        logger.warning("mlx:    %s — unreachable at startup (%s)", State.mlx_url, e)
    yield
    # --- shutdown ---
    if State.mlx is not None:
        State.mlx.close()
        State.mlx = None
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
    """Liveness check with nested config / db / mlx state."""
    cfg = State.config
    db = State.db
    mlx_status: dict | None = None
    if State.mlx is not None:
        try:
            mlx_status = State.mlx.healthz()
        except Exception as e:
            mlx_status = {"ok": False, "error": str(e)}
    return {
        "ok": True,
        "stage": "mlx-client",
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
        "mlx": {"url": State.mlx_url, "status": mlx_status},
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
