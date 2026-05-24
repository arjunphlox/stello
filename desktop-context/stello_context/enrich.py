"""Per-type enrichment dispatch + single FIFO MLX call queue.

The queue is filled by the FSEvents watcher (step 4) and by the dwell-
gated Sketch path (step 11). One asyncio worker drains it — so MLX
calls go out one-at-a-time and never contend the server's own asyncio
lock.

MLX HTTP calls run via asyncio.to_thread() so the event loop stays
responsive (the underlying httpx.Client is sync).

Currently handles:
  - text (.md, .txt)          step 4

Step 5 adds image, step 6 adds pdf, step 7 adds sketch (cheap path),
step 11 adds sketch_artboard (dwell-gated VLM).
"""
from __future__ import annotations

import asyncio
import logging
import sqlite3
import struct
import time
from dataclasses import dataclass
from pathlib import Path

from . import mlx_client as mlx_mod

logger = logging.getLogger("stello-context.enrich")

# How many raw bytes we peek at for the embed call. ~4000 utf-8 chars
# worst-case (4-byte chars) → comfortably within BGE-M3's context.
TEXT_PEEK_BYTES = 16_000


@dataclass(frozen=True)
class EnrichJob:
    """A request to (re-)enrich a single source path."""

    source_path: str
    reason: str  # "initial_walk" | "fs_event:created" | "fs_event:modified" | etc.


# -- helpers ------------------------------------------------------------------


def classify_path(p: Path) -> str:
    """Map a path's extension to one of the enrich types we support.

    Returns "other" for anything outside the current step's coverage —
    the worker will silently skip those (steps 5–7 add image/pdf/sketch).
    """
    ext = p.suffix.lower()
    if ext in (".md", ".txt"):
        return "text"
    return "other"


def project_hint_for(path: Path, watched_folders: list[str]) -> str | None:
    """Use the watched-folder basename as the project hint.

    For Sketch artboards (step 11) we override to the .sketch filename
    so a single Sketch file groups all its artboards under one hint.
    """
    for wf in watched_folders:
        wfp = Path(wf).resolve()
        try:
            path.resolve().relative_to(wfp)
            return wfp.name
        except ValueError:
            continue
    return None


def read_text_excerpt(p: Path, max_bytes: int = TEXT_PEEK_BYTES) -> str:
    """Read up to max_bytes of UTF-8 text, ignoring decode errors."""
    with open(p, "rb") as f:
        raw = f.read(max_bytes)
    return raw.decode("utf-8", errors="ignore")


def embedding_to_blob(vec: list[float]) -> bytes:
    """1024 float32 little-endian bytes. Matches store.py's BLOB column."""
    return struct.pack(f"<{len(vec)}f", *vec)


def blob_to_embedding(blob: bytes) -> list[float]:
    """Inverse of embedding_to_blob. Used by /related in step 12."""
    return list(struct.unpack(f"<{len(blob) // 4}f", blob))


# -- per-type enrich functions -----------------------------------------------


async def enrich_text(
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    job: EnrichJob,
    watched_folders: list[str],
) -> None:
    """Enrich one .md / .txt file. Idempotent: skips if mtime unchanged.

    Embed input = filename + body (filename first so it always carries
    weight even when the body is empty).
    """
    p = Path(job.source_path)
    if not p.exists():
        logger.info("text skipped (file gone): %s", job.source_path)
        return
    stat = p.stat()

    # Skip if already enriched at this exact mtime.
    existing = db.execute(
        "SELECT mtime, status FROM items WHERE uniq_key = ?",
        (str(p),),
    ).fetchone()
    if (
        existing is not None
        and existing["mtime"] == stat.st_mtime
        and existing["status"] == "ready"
    ):
        logger.debug("text skip (mtime match): %s", p.name)
        return

    body = read_text_excerpt(p)
    embed_input = f"{p.name}\n\n{body}".strip()

    result = await asyncio.to_thread(mlx.embed, [embed_input])
    vec = result.embeddings[0]
    blob = embedding_to_blob(vec)

    hint = project_hint_for(p, watched_folders)
    now = time.time()

    db.execute(
        """
        INSERT INTO items
            (kind, source_path, uniq_key, type, title, size, mtime, ctime,
             project_hint, extracted_text, embedding, embed_input,
             enriched_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(uniq_key) DO UPDATE SET
            title = excluded.title,
            size = excluded.size,
            mtime = excluded.mtime,
            ctime = excluded.ctime,
            project_hint = excluded.project_hint,
            extracted_text = excluded.extracted_text,
            embedding = excluded.embedding,
            embed_input = excluded.embed_input,
            enriched_at = excluded.enriched_at,
            status = excluded.status,
            error = NULL
        """,
        (
            "file",
            str(p),
            str(p),
            "text",
            p.name,
            stat.st_size,
            stat.st_mtime,
            stat.st_ctime,
            hint,
            body,
            blob,
            embed_input,
            now,
            "ready",
        ),
    )
    logger.info(
        "text enriched: %s (%d bytes, hint=%s, embed_latency=%.2fs)",
        p.name,
        len(body),
        hint,
        result.latency_s,
    )


# -- dispatch + worker -------------------------------------------------------


async def enrich(
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    job: EnrichJob,
    watched_folders: list[str],
) -> None:
    """Route a job by file type. Records failures into the items row."""
    p = Path(job.source_path)
    kind = classify_path(p)
    if kind == "text":
        try:
            await enrich_text(db, mlx, job, watched_folders)
        except Exception as e:  # noqa: BLE001
            logger.exception("text enrich failed: %s", job.source_path)
            now = time.time()
            db.execute(
                """
                INSERT INTO items
                    (kind, source_path, uniq_key, type, status, error, enriched_at)
                VALUES (?, ?, ?, ?, 'failed', ?, ?)
                ON CONFLICT(uniq_key) DO UPDATE SET
                    status = 'failed',
                    error = excluded.error,
                    enriched_at = excluded.enriched_at
                """,
                ("file", str(p), str(p), "text", str(e), now),
            )
    # else: unknown extensions silently skipped — steps 5–7 add image/pdf/sketch.


async def worker_loop(
    queue: asyncio.Queue,
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    watched_folders: list[str],
) -> None:
    """Single-consumer queue worker. Survives per-job exceptions."""
    logger.info("enrich worker started")
    while True:
        job = await queue.get()
        try:
            await enrich(db, mlx, job, watched_folders)
        except Exception:  # noqa: BLE001
            logger.exception("enrich worker: unhandled exception (job=%s)", job)
        finally:
            queue.task_done()
