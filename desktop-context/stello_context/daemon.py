"""Stello desktop-context daemon — entrypoint.

Stage 8: the daemon now polls NSWorkspace + Accessibility every
poll_interval_s and keeps the latest ContextSnapshot in memory.
/context/now exposes it; activity_log records distinct snapshots only.
Accessibility permission for the host Python is required for the
focused-window title — without it the daemon still runs and logs a
warning, but title comes back None.

Later steps wire in:
  - Safari + Sketch introspection (steps 9–11)
  - /related endpoint (step 12)
"""
from __future__ import annotations

import asyncio
import logging
import os
import signal
import sqlite3
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import uvicorn
from fastapi import FastAPI

from . import config as config_mod
from . import context as context_mod
from . import enrich as enrich_mod
from . import mlx_client as mlx_mod
from . import scanner as scanner_mod
from . import store as store_mod
from . import thumbnails as thumbnails_mod

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
    queue: asyncio.Queue | None = None
    worker_task: asyncio.Task | None = None
    observer: Any = None
    initial_walk_count: int = 0
    thumb_dir: Path | None = None
    context_poll_task: asyncio.Task | None = None
    context_snapshot: context_mod.ContextSnapshot | None = None


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
    except Exception as e:  # noqa: BLE001
        logger.warning("mlx:    %s — unreachable at startup (%s)", State.mlx_url, e)

    # Queue + initial walk + worker + watcher.
    State.thumb_dir = thumbnails_mod.thumb_dir()
    State.queue = asyncio.Queue()
    max_bytes = State.config.max_file_size_mb * 1024 * 1024
    State.initial_walk_count = scanner_mod.initial_walk(
        State.config.watched_folders,
        State.config.include_extensions,
        State.config.ignore_globs,
        max_bytes,
        State.queue,
    )
    logger.info("initial walk: enqueued %d file(s)", State.initial_walk_count)
    logger.info("thumbs:   %s", State.thumb_dir)

    State.worker_task = asyncio.create_task(
        enrich_mod.worker_loop(
            State.queue,
            State.db,
            State.mlx,
            State.config.watched_folders,
            State.thumb_dir,
        )
    )
    State.observer = scanner_mod.start_observer(
        asyncio.get_running_loop(),
        State.queue,
        State.config.watched_folders,
        State.config.include_extensions,
        State.config.ignore_globs,
        max_bytes,
    )

    # Context poll (NSWorkspace + AX). Logs a warning at startup if AX
    # isn't trusted; the loop keeps running regardless.
    if not context_mod.ax_is_trusted():
        logger.warning(
            "AX not trusted — focused-window titles will be None. Grant the "
            "venv Python binary in System Settings → Privacy & Security → "
            "Accessibility. realpath(sys.executable) is what TCC checks."
        )
    State.context_poll_task = asyncio.create_task(
        context_mod.poll_loop(
            State,
            State.db,
            State.config.poll_interval_s,
            safari_blocklist=State.config.safari_blocklist,
        )
    )

    yield

    # --- shutdown ---
    if State.context_poll_task is not None:
        State.context_poll_task.cancel()
        try:
            await State.context_poll_task
        except asyncio.CancelledError:
            pass
        State.context_poll_task = None
    if State.observer is not None:
        State.observer.stop()
        State.observer.join(timeout=2.0)
        State.observer = None
    if State.worker_task is not None:
        State.worker_task.cancel()
        try:
            await State.worker_task
        except asyncio.CancelledError:
            pass
        State.worker_task = None
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
    """Liveness check with nested config / db / mlx / queue state."""
    cfg = State.config
    db = State.db
    mlx_status: dict | None = None
    if State.mlx is not None:
        try:
            mlx_status = State.mlx.healthz()
        except Exception as e:  # noqa: BLE001
            mlx_status = {"ok": False, "error": str(e)}
    queue_depth = State.queue.qsize() if State.queue is not None else None
    observer_alive = bool(State.observer is not None and State.observer.is_alive())
    snap = State.context_snapshot
    return {
        "ok": True,
        "stage": "context-poll",
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
        "indexer": {
            "queue_depth": queue_depth,
            "initial_walk_count": State.initial_walk_count,
            "observer_alive": observer_alive,
            "thumb_dir": str(State.thumb_dir) if State.thumb_dir else None,
        },
        "context": {
            "ax_trusted": snap.ax_trusted if snap else None,
            "frontmost_app": snap.frontmost_app if snap else None,
            "frontmost_window_title": snap.frontmost_window_title if snap else None,
            "open_apps_count": len(snap.open_apps) if snap else None,
            "safari_tabs_total": len(snap.safari_tabs) if snap else None,
            "safari_tabs_blocked": (
                sum(1 for t in snap.safari_tabs if t.get("blocked"))
                if snap
                else None
            ),
        },
    }


@app.get("/context/now")
def context_now() -> dict:
    """Return the most recent ContextSnapshot. Useful for debugging and as
    the data source for /related (step 12)."""
    snap = State.context_snapshot
    if snap is None:
        return {"available": False, "reason": "no snapshot yet"}
    return {"available": True, **context_mod.snapshot_to_dict(snap)}


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
