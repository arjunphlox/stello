"""Per-type enrichment dispatch + single FIFO MLX call queue.

The queue is filled by the FSEvents watcher (step 4) and by the dwell-
gated Sketch path (step 11). One asyncio worker drains it — so MLX
calls go out one-at-a-time and never contend the server's own asyncio
lock.

MLX HTTP calls run via asyncio.to_thread() so the event loop stays
responsive (the underlying httpx.Client is sync).

Currently handles:
  - text   (.md, .txt)         step 4
  - image  (.png/.jpg/.jpeg/.webp)  step 5 — embeds filename + writes
                                   thumbnail; status='pending_vlm'
                                   until step 11's dwell-gated VLM call
  - pdf    (.pdf)              step 6 — renders + thumbnails page 1,
                                   extracts page-1 text (if any), embeds
                                   filename + text; status='ready'.
                                   (V1 doesn't VLM-caption PDFs.)
  - sketch (.sketch)           step 7 — unzips the bundle, embeds
                                   filename + page names + artboard
                                   names + text-layer strings; uses the
                                   whole-file preview as the thumbnail;
                                   status='ready'. Artboard-level rows
                                   land later via step 11.

Step 11 adds sketch_artboard (dwell-gated VLM).
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
from . import pdf as pdf_mod
from . import sketch as sketch_mod
from . import thumbnails as thumbnails_mod

logger = logging.getLogger("stello-context.enrich")

# How many raw bytes we peek at for the embed call. ~4000 utf-8 chars
# worst-case (4-byte chars) → comfortably within BGE-M3's context.
TEXT_PEEK_BYTES = 16_000

IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")
TEXT_EXTS = (".md", ".txt")
PDF_EXTS = (".pdf",)
SKETCH_EXTS = (".sketch",)


@dataclass(frozen=True)
class EnrichJob:
    """A request to (re-)enrich a single source path."""

    source_path: str
    reason: str  # "initial_walk" | "fs_event:created" | "fs_event:modified" | etc.


# -- helpers ------------------------------------------------------------------


def classify_path(p: Path) -> str:
    """Map a path's extension to one of the enrich types we support.

    Returns "other" only for genuinely unsupported extensions.
    """
    ext = p.suffix.lower()
    if ext in TEXT_EXTS:
        return "text"
    if ext in IMAGE_EXTS:
        return "image"
    if ext in PDF_EXTS:
        return "pdf"
    if ext in SKETCH_EXTS:
        return "sketch"
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


def _record_failure(
    db: sqlite3.Connection, source_path: str, type_: str, error: str
) -> None:
    """Write status='failed' + error message into the items row."""
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
        ("file", source_path, source_path, type_, error, now),
    )


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
             thumb_path, enriched_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(uniq_key) DO UPDATE SET
            title = excluded.title,
            size = excluded.size,
            mtime = excluded.mtime,
            ctime = excluded.ctime,
            project_hint = excluded.project_hint,
            extracted_text = excluded.extracted_text,
            embedding = excluded.embedding,
            embed_input = excluded.embed_input,
            thumb_path = excluded.thumb_path,
            enriched_at = excluded.enriched_at,
            status = excluded.status,
            error = NULL
        """,
        (
            "file", str(p), str(p), "text", p.name,
            stat.st_size, stat.st_mtime, stat.st_ctime,
            hint, body, blob, embed_input,
            None,  # text rows have no thumbnail
            now, "ready",
        ),
    )
    logger.info(
        "text enriched: %s (%d bytes, hint=%s, embed_latency=%.2fs)",
        p.name, len(body), hint, result.latency_s,
    )


async def enrich_image(
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    job: EnrichJob,
    watched_folders: list[str],
    thumb_dir_path: Path,
) -> None:
    """Enrich one PNG/JPG/WEBP. Idempotent on mtime.

    Cheap path only: writes a 256px webp thumbnail + embeds the filename.
    The row is marked status='pending_vlm' so step 11's dwell-gated VLM
    can find it and add the caption + tags + re-embed.
    """
    p = Path(job.source_path)
    if not p.exists():
        logger.info("image skipped (file gone): %s", job.source_path)
        return
    stat = p.stat()

    existing = db.execute(
        "SELECT mtime, status FROM items WHERE uniq_key = ?",
        (str(p),),
    ).fetchone()
    if (
        existing is not None
        and existing["mtime"] == stat.st_mtime
        and existing["status"] in ("pending_vlm", "ready")
    ):
        logger.debug("image skip (mtime match, status=%s): %s", existing["status"], p.name)
        return

    # Thumbnail (sync — Pillow decode/encode happens in a thread).
    thumb_path, orig_size = await asyncio.to_thread(
        thumbnails_mod.make_thumbnail_from_image, p, thumb_dir_path
    )

    # Embed by filename only — VLM caption comes in step 11.
    embed_input = p.name
    result = await asyncio.to_thread(mlx.embed, [embed_input])
    blob = embedding_to_blob(result.embeddings[0])

    hint = project_hint_for(p, watched_folders)
    now = time.time()

    db.execute(
        """
        INSERT INTO items
            (kind, source_path, uniq_key, type, title, size, mtime, ctime,
             project_hint, extracted_text, embedding, embed_input,
             thumb_path, enriched_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(uniq_key) DO UPDATE SET
            title = excluded.title,
            size = excluded.size,
            mtime = excluded.mtime,
            ctime = excluded.ctime,
            project_hint = excluded.project_hint,
            embedding = excluded.embedding,
            embed_input = excluded.embed_input,
            thumb_path = excluded.thumb_path,
            enriched_at = excluded.enriched_at,
            status = excluded.status,
            error = NULL
        """,
        (
            "file", str(p), str(p), "image", p.name,
            stat.st_size, stat.st_mtime, stat.st_ctime,
            hint, None, blob, embed_input,
            thumb_path.name,  # basename only — thumb_dir is resolved at read
            now, "pending_vlm",
        ),
    )
    logger.info(
        "image queued (pending_vlm): %s (orig=%dx%d, thumb=%s, embed_latency=%.2fs)",
        p.name, orig_size[0], orig_size[1], thumb_path.name, result.latency_s,
    )


async def enrich_pdf(
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    job: EnrichJob,
    watched_folders: list[str],
    thumb_dir_path: Path,
) -> None:
    """Enrich one PDF. Idempotent on mtime.

    Page-1 rendered → 256px webp thumbnail. Page-1 text (if any) extracted
    and concatenated with the filename for the embed input. Status = 'ready'
    immediately — V1 doesn't push PDFs through the VLM path.
    """
    p = Path(job.source_path)
    if not p.exists():
        logger.info("pdf skipped (file gone): %s", job.source_path)
        return
    stat = p.stat()

    existing = db.execute(
        "SELECT mtime, status FROM items WHERE uniq_key = ?",
        (str(p),),
    ).fetchone()
    if (
        existing is not None
        and existing["mtime"] == stat.st_mtime
        and existing["status"] == "ready"
    ):
        logger.debug("pdf skip (mtime match): %s", p.name)
        return

    # Page-1 text + render (both touch native pypdfium2 — keep on a thread).
    text = await asyncio.to_thread(pdf_mod.extract_first_page_text, p)
    image = await asyncio.to_thread(pdf_mod.render_first_page, p)
    thumb_path = await asyncio.to_thread(
        thumbnails_mod.make_thumbnail_from_pillow, image, p, thumb_dir_path
    )

    embed_input = f"{p.name}\n\n{text}".strip() if text else p.name
    result = await asyncio.to_thread(mlx.embed, [embed_input])
    blob = embedding_to_blob(result.embeddings[0])

    hint = project_hint_for(p, watched_folders)
    now = time.time()

    db.execute(
        """
        INSERT INTO items
            (kind, source_path, uniq_key, type, title, size, mtime, ctime,
             project_hint, extracted_text, embedding, embed_input,
             thumb_path, enriched_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(uniq_key) DO UPDATE SET
            title = excluded.title,
            size = excluded.size,
            mtime = excluded.mtime,
            ctime = excluded.ctime,
            project_hint = excluded.project_hint,
            extracted_text = excluded.extracted_text,
            embedding = excluded.embedding,
            embed_input = excluded.embed_input,
            thumb_path = excluded.thumb_path,
            enriched_at = excluded.enriched_at,
            status = excluded.status,
            error = NULL
        """,
        (
            "file", str(p), str(p), "pdf", p.name,
            stat.st_size, stat.st_mtime, stat.st_ctime,
            hint, text or None, blob, embed_input,
            thumb_path.name,
            now, "ready",
        ),
    )
    logger.info(
        "pdf enriched: %s (text=%d chars, thumb=%s, embed_latency=%.2fs)",
        p.name, len(text), thumb_path.name, result.latency_s,
    )


async def enrich_sketch(
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    job: EnrichJob,
    watched_folders: list[str],
    thumb_dir_path: Path,
) -> None:
    """Enrich one .sketch bundle (cheap path — no AppleScript, no VLM).

    Idempotent on mtime. Embed input = filename + page names + artboard
    names + text-layer strings (composed by sketch.compose_embed_input).
    The bundle's own previews/preview.png becomes the row's thumbnail
    if present; otherwise thumb_path stays NULL.
    """
    import io

    from PIL import Image as PILImage

    p = Path(job.source_path)
    if not p.exists():
        logger.info("sketch skipped (file gone): %s", job.source_path)
        return
    stat = p.stat()

    existing = db.execute(
        "SELECT mtime, status FROM items WHERE uniq_key = ?",
        (str(p),),
    ).fetchone()
    if (
        existing is not None
        and existing["mtime"] == stat.st_mtime
        and existing["status"] == "ready"
    ):
        logger.debug("sketch skip (mtime match): %s", p.name)
        return

    parsed = await asyncio.to_thread(sketch_mod.parse_sketch_strings, p)
    embed_input = sketch_mod.compose_embed_input(parsed)

    # Whole-file preview (if shipped inside the bundle) → thumbnail.
    png_bytes = await asyncio.to_thread(sketch_mod.extract_preview_png, p)
    thumb_basename: str | None = None
    if png_bytes:
        def _save_thumb() -> Path:
            with PILImage.open(io.BytesIO(png_bytes)) as im:
                im.load()
                return thumbnails_mod.make_thumbnail_from_pillow(
                    im, p, thumb_dir_path
                )
        thumb_path = await asyncio.to_thread(_save_thumb)
        thumb_basename = thumb_path.name

    result = await asyncio.to_thread(mlx.embed, [embed_input])
    blob = embedding_to_blob(result.embeddings[0])

    hint = project_hint_for(p, watched_folders)
    now = time.time()

    db.execute(
        """
        INSERT INTO items
            (kind, source_path, uniq_key, type, title, size, mtime, ctime,
             project_hint, extracted_text, embedding, embed_input,
             thumb_path, enriched_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(uniq_key) DO UPDATE SET
            title = excluded.title,
            size = excluded.size,
            mtime = excluded.mtime,
            ctime = excluded.ctime,
            project_hint = excluded.project_hint,
            extracted_text = excluded.extracted_text,
            embedding = excluded.embedding,
            embed_input = excluded.embed_input,
            thumb_path = excluded.thumb_path,
            enriched_at = excluded.enriched_at,
            status = excluded.status,
            error = NULL
        """,
        (
            "file", str(p), str(p), "sketch", p.name,
            stat.st_size, stat.st_mtime, stat.st_ctime,
            hint, embed_input, blob, embed_input,
            thumb_basename,
            now, "ready",
        ),
    )
    logger.info(
        "sketch enriched: %s (pages=%d, artboards=%d, texts=%d, thumb=%s, embed_latency=%.2fs)",
        p.name,
        len(parsed["page_names"]),
        len(parsed["artboard_names"]),
        len(parsed["text_strings"]),
        thumb_basename or "(none)",
        result.latency_s,
    )


# -- dispatch + worker -------------------------------------------------------


async def enrich(
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    job: EnrichJob,
    watched_folders: list[str],
    thumb_dir_path: Path,
) -> None:
    """Route a job by file type. Records failures into the items row."""
    p = Path(job.source_path)
    kind = classify_path(p)
    try:
        if kind == "text":
            await enrich_text(db, mlx, job, watched_folders)
        elif kind == "image":
            await enrich_image(db, mlx, job, watched_folders, thumb_dir_path)
        elif kind == "pdf":
            await enrich_pdf(db, mlx, job, watched_folders, thumb_dir_path)
        elif kind == "sketch":
            await enrich_sketch(db, mlx, job, watched_folders, thumb_dir_path)
        # else: unknown extensions silently skipped.
    except Exception as e:  # noqa: BLE001
        logger.exception("%s enrich failed: %s", kind, job.source_path)
        _record_failure(db, str(p), kind, str(e))


async def worker_loop(
    queue: asyncio.Queue,
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    watched_folders: list[str],
    thumb_dir_path: Path,
) -> None:
    """Single-consumer queue worker. Survives per-job exceptions."""
    logger.info("enrich worker started")
    while True:
        job = await queue.get()
        try:
            await enrich(db, mlx, job, watched_folders, thumb_dir_path)
        except Exception:  # noqa: BLE001
            logger.exception("enrich worker: unhandled exception (job=%s)", job)
        finally:
            queue.task_done()
