"""Stello desktop-context daemon — entrypoint.

Stage 1 (skeleton): boots a FastAPI app on STELLO_CTX_PORT (default 8766),
serves /healthz, exits cleanly on SIGINT/SIGTERM.

Later steps wire in:
  - Config + SQLite (step 2)
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

import uvicorn
from fastapi import FastAPI

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("stello-context")

app = FastAPI(title="Stello desktop-context daemon", version="0.0.1")


@app.get("/healthz")
def healthz() -> dict:
    """Liveness check. Step 3 adds nested MLX server status."""
    return {"ok": True, "stage": "skeleton"}


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
