"""SQLite data layer at ~/Library/Application Support/Stello/desktop-context.db.

Schema created on open (CREATE TABLE IF NOT EXISTS — idempotent). WAL mode
so concurrent reads from /related don't block the enrich-queue writer.

Embeddings are stored as raw float32 little-endian bytes (4 bytes/dim ×
1024 dims = 4096 bytes per row). The cosine path in step 12 wraps the
blob into a numpy array with `np.frombuffer(blob, dtype=np.float32)`.

`status` is a free-text column (no CHECK constraint) so new states can be
introduced without a migration. Current values used by the pipeline:
  pending, pending_vlm, enriching, ready, failed, skipped
"""
from __future__ import annotations

import os
import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

DEFAULT_DB_PATH = Path(
    "~/Library/Application Support/Stello/desktop-context.db"
).expanduser()

SCHEMA_VERSION = 1

SCHEMA = """
PRAGMA journal_mode = WAL;
PRAGMA synchronous  = NORMAL;
PRAGMA foreign_keys = ON;

-- Items the index can return as related cards.
-- Sources: watcher folder + Sketch artboards from any open .sketch file.
CREATE TABLE IF NOT EXISTS items (
    id              INTEGER PRIMARY KEY,
    kind            TEXT    NOT NULL,         -- file | sketch_artboard
    source_path     TEXT    NOT NULL,         -- absolute path on disk
    artboard_id     TEXT,                     -- non-null when kind=sketch_artboard
    uniq_key        TEXT    UNIQUE NOT NULL,  -- source_path or source_path#artboard_id
    type            TEXT    NOT NULL,         -- image | pdf | text | sketch_artboard | other
    title           TEXT,                     -- filename or artboard name
    size            INTEGER,
    mtime           REAL,
    ctime           REAL,
    project_hint    TEXT,
    extracted_text  TEXT,
    vlm_caption     TEXT,
    tags            TEXT,                     -- JSON array
    thumb_path      TEXT,                     -- relative to thumbs/
    embedding       BLOB,                     -- float32[1024]
    embed_input     TEXT,                     -- exact string embedded (debug)
    enriched_at     REAL,
    enrich_version  INTEGER NOT NULL DEFAULT 1,
    status          TEXT    NOT NULL,
    error           TEXT
);
CREATE INDEX IF NOT EXISTS items_status ON items(status);
CREATE INDEX IF NOT EXISTS items_mtime  ON items(mtime DESC);

-- Ephemeral context snapshots (ring buffer; pruning lands in step 8).
CREATE TABLE IF NOT EXISTS activity_log (
    id              INTEGER PRIMARY KEY,
    ts              REAL    NOT NULL,
    open_apps       TEXT,                     -- JSON
    safari_tabs     TEXT,                     -- JSON [{url,title,hostname,blocked}]
    sketch_state    TEXT,                     -- JSON [{path,page,visible_artboards}]
    classified      TEXT                      -- JSON {activity_type,topic,entities,project_hint}
);
CREATE INDEX IF NOT EXISTS activity_ts ON activity_log(ts DESC);

-- Cache keyed by SHA1 of the VLM-input PNG bytes. Lets us re-embed
-- (cheap) without re-VLM (expensive) when the embed prompt changes.
CREATE TABLE IF NOT EXISTS caption_cache (
    content_hash    TEXT    PRIMARY KEY,
    caption         TEXT,
    tags            TEXT,
    created_at      REAL
);

CREATE TABLE IF NOT EXISTS schema_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


def open_db(path: Path | None = None) -> sqlite3.Connection:
    """Open the SQLite database, creating parent dirs and schema as needed.

    Path resolution: explicit `path` arg → $STELLO_CTX_DB → DEFAULT_DB_PATH.
    Returns a connection in autocommit mode with sqlite3.Row factory.

    `check_same_thread=False` because FastAPI dispatches sync handlers on
    its threadpool. WAL mode + the single-writer enrich queue (added in
    step 4) keep concurrent reads safe; writes are always queued through
    one worker, so we never get write-vs-write contention either.
    """
    p = path if path is not None else Path(
        os.environ.get("STELLO_CTX_DB", str(DEFAULT_DB_PATH))
    )
    p.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(p), isolation_level=None, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    conn.execute(
        "INSERT OR IGNORE INTO schema_meta(key, value) VALUES('version', ?)",
        (str(SCHEMA_VERSION),),
    )
    return conn


@contextmanager
def transaction(conn: sqlite3.Connection) -> Iterator[sqlite3.Connection]:
    """Wrap writes in a single BEGIN/COMMIT (needed because we're in autocommit)."""
    conn.execute("BEGIN")
    try:
        yield conn
    except Exception:
        conn.execute("ROLLBACK")
        raise
    else:
        conn.execute("COMMIT")


def schema_version(conn: sqlite3.Connection) -> int:
    row = conn.execute(
        "SELECT value FROM schema_meta WHERE key = 'version'"
    ).fetchone()
    return int(row["value"]) if row else 0


def counts_by_status(conn: sqlite3.Connection) -> dict[str, int]:
    """Used by /healthz and /index/status to show pipeline state at a glance."""
    rows = conn.execute(
        "SELECT status, COUNT(*) AS n FROM items GROUP BY status"
    ).fetchall()
    return {r["status"]: r["n"] for r in rows}
