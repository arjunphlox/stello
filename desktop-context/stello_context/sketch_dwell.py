"""Dwell-gated Sketch artboard VLM enqueue (step 11).

Every context-poll tick feeds the latest sketch_state into a per-window
dwell tracker. When the visible artboard set stays stable for
``dwell_window_s`` seconds, up to ``vlm_images_per_window`` un-enriched
artboards are enqueued on the single FIFO enrich queue.
"""
from __future__ import annotations

import logging
import sqlite3
import time
from dataclasses import dataclass

from .enrich import EnrichJob

logger = logging.getLogger("stello-context.sketch-dwell")


@dataclass
class _WindowDwell:
    artboard_ids: frozenset[str]
    since_ts: float


def window_key(doc: dict) -> str:
    """Stable key for one Sketch document window."""
    return f"{doc['path']}:{doc.get('window_width')}x{doc.get('window_height')}"


def is_artboard_enriched(
    db: sqlite3.Connection,
    sketch_path: str,
    artboard_id: str,
    sketch_mtime: float,
) -> bool:
    """True when a ready row exists with caption and matching sketch mtime."""
    uniq = f"{sketch_path}#{artboard_id}"
    row = db.execute(
        "SELECT status, mtime, vlm_caption FROM items WHERE uniq_key = ?",
        (uniq,),
    ).fetchone()
    if row is None:
        return False
    if row["mtime"] != sketch_mtime:
        return False
    # Terminal for this mtime: captioned ready row, or a failed attempt (don't
    # spin the dwell queue forever when VLM/export keeps erroring).
    if row["status"] == "failed":
        return True
    return row["status"] == "ready" and bool(row["vlm_caption"])


def unenriched_visible(
    doc: dict,
    db: sqlite3.Connection,
    cap: int,
) -> list[dict]:
    """Visible artboards not yet VLM-captioned at the current sketch mtime."""
    from pathlib import Path

    sketch_path = doc["path"]
    try:
        sketch_mtime = Path(sketch_path).stat().st_mtime
    except OSError:
        return []
    out: list[dict] = []
    for ab in doc.get("visible_artboards") or []:
        ab_id = ab.get("id")
        if not ab_id:
            continue
        if is_artboard_enriched(db, sketch_path, ab_id, sketch_mtime):
            continue
        out.append(ab)
        if len(out) >= cap:
            break
    return out


class DwellTracker:
    """Per-window visible-set dwell state machine."""

    def __init__(self, dwell_window_s: int, vlm_cap: int) -> None:
        self.dwell_window_s = dwell_window_s
        self.vlm_cap = vlm_cap
        self._windows: dict[str, _WindowDwell] = {}

    def tick(
        self,
        sketch_state: list[dict],
        db: sqlite3.Connection,
        queue,
        *,
        now: float | None = None,
    ) -> int:
        """Advance dwell timers; enqueue EnrichJobs when thresholds fire."""
        ts = now if now is not None else time.time()
        seen: set[str] = set()
        enqueued = 0

        for doc in sketch_state:
            key = window_key(doc)
            visible = doc.get("visible_artboards") or []
            visible_ids = frozenset(a["id"] for a in visible if a.get("id"))
            if not visible_ids:
                self._windows.pop(key, None)
                continue
            seen.add(key)

            dwell = self._windows.get(key)
            if dwell is None or dwell.artboard_ids != visible_ids:
                self._windows[key] = _WindowDwell(visible_ids, ts)
                continue

            if ts - dwell.since_ts < self.dwell_window_s:
                continue

            targets = unenriched_visible(doc, db, self.vlm_cap)
            dwell.since_ts = ts
            if not targets:
                continue

            sketch_path = doc["path"]
            for ab in targets:
                job = EnrichJob(
                    source_path=sketch_path,
                    reason="sketch_dwell",
                    artboard_id=ab["id"],
                    artboard_name=ab.get("name") or "",
                )
                queue.put_nowait(job)
                enqueued += 1
            logger.info(
                "sketch dwell fired: %s (%d artboard(s) enqueued)",
                sketch_path,
                len(targets),
            )

        for key in list(self._windows):
            if key not in seen:
                del self._windows[key]

        return enqueued
