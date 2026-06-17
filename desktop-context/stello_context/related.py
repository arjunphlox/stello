"""`/related` retrieval — activity classification, cosine search, rerank.

Pipeline (from the V1 plan):
  1. Snapshot → Activity (MLX text, cached ~10s by dedupe key)
  2. Embed activity string → query vector
  3. Cosine over ready items (mtime within 90d)
  4. Hard filters (project_hint, compatible type)
  5. Rerank top-20: 0.65·cosine + 0.25·recency + 0.10·source_app_match
"""
from __future__ import annotations

import base64
import json
import logging
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
from pydantic import BaseModel, Field, ValidationError

from . import context as context_mod
from . import enrich as enrich_mod
from . import mlx_client as mlx_mod
from . import sketch as sketch_mod
from .context import ContextSnapshot

logger = logging.getLogger("stello-context.related")

SKETCH_BUNDLE = sketch_mod.SKETCH_BUNDLE_ID
SAFARI_BUNDLE = context_mod.SAFARI_BUNDLE_ID

RECENCY_WINDOW_S = 90 * 86400
RERANK_POOL = 20
SNIPPET_MAX = 240

COMPATIBLE_TYPES: dict[str, frozenset[str]] = {
    "design": frozenset({"image", "sketch_artboard", "sketch", "pdf"}),
    "research": frozenset({"text", "pdf", "image", "sketch_artboard"}),
    "reference": frozenset({"text", "pdf", "image", "sketch_artboard", "sketch"}),
    "browsing": frozenset({"text", "pdf", "image"}),
    "admin": frozenset({"text", "pdf"}),
    "other": frozenset({"image", "pdf", "text", "sketch_artboard", "sketch", "other"}),
}


class ActivityClassification(BaseModel):
    """MLX text classifier output for the current Mac context."""

    activity_type: str = Field(
        description="One of: design, research, reference, browsing, admin, other"
    )
    topic: str = Field(description="Short phrase for the user's current focus")
    entities: list[str] = Field(default_factory=list)
    project_hint: str | None = None


@dataclass
class ActivityCache:
    key: str | None = None
    activity: ActivityClassification | None = None
    ts: float = 0.0


def compatible_types_for(activity_type: str) -> frozenset[str]:
    return COMPATIBLE_TYPES.get(activity_type.lower(), COMPATIBLE_TYPES["other"])


def activity_prompt(snap: ContextSnapshot) -> str:
    """Build the classifier prompt from a context snapshot."""
    lines = [
        "Classify what the user is doing on their Mac right now.",
        "",
    ]
    if snap.frontmost_app_name:
        lines.append(f"Frontmost app: {snap.frontmost_app_name}")
    if snap.frontmost_window_title:
        lines.append(f"Focused window: {snap.frontmost_window_title}")
    open_names = [a.get("name") for a in snap.open_apps if a.get("name")]
    if open_names:
        lines.append("Open apps: " + ", ".join(open_names[:16]))
    tabs = [t for t in snap.safari_tabs if not t.get("blocked") and t.get("url")]
    if tabs:
        lines.append("Safari tabs (non-private):")
        for t in tabs[:10]:
            lines.append(f"  - {t.get('title') or '(untitled)'} — {t.get('url')}")
    if snap.sketch_state:
        lines.append("Sketch open documents:")
        for doc in snap.sketch_state:
            lines.append(f"  - {Path(doc.get('path', '')).name}")
            for ab in (doc.get("visible_artboards") or [])[:6]:
                lines.append(f"      visible artboard: {ab.get('name')}")
    return "\n".join(lines)


def heuristic_activity(snap: ContextSnapshot) -> ActivityClassification:
    """Fallback when MLX classification fails."""
    front = snap.frontmost_app or ""
    topic = snap.frontmost_window_title or snap.frontmost_app_name or "general"
    entities: list[str] = []
    project_hint: str | None = None

    if front == SKETCH_BUNDLE:
        activity_type = "design"
        for doc in snap.sketch_state:
            project_hint = project_hint or Path(doc.get("path", "")).name
            for ab in doc.get("visible_artboards") or []:
                if ab.get("name"):
                    entities.append(str(ab["name"]))
    elif front == SAFARI_BUNDLE:
        activity_type = "browsing"
        for t in snap.safari_tabs:
            if not t.get("blocked") and t.get("title"):
                entities.append(str(t["title"]))
    else:
        activity_type = "other"

    return ActivityClassification(
        activity_type=activity_type,
        topic=topic[:120],
        entities=entities[:8],
        project_hint=project_hint,
    )


def classify_activity(
    mlx: mlx_mod.Client, snap: ContextSnapshot
) -> ActivityClassification:
    """MLX text classification with compact JSON parse (avoids schema-echo)."""
    prompt = activity_prompt(snap)
    instruction = (
        f"{prompt}\n\n"
        "Respond with ONLY valid JSON:\n"
        '{"activity_type":"design|research|reference|browsing|admin|other",'
        '"topic":"...", "entities":["..."], "project_hint": null or "..."}'
    )
    last_err: Exception | None = None
    for attempt in range(mlx.max_retries + 1):
        result = mlx.generate(instruction, max_tokens=256, json_mode=True)
        try:
            payload = mlx_mod._extract_json(result.text)
            return ActivityClassification.model_validate_json(payload)
        except (mlx_mod.MLXError, json.JSONDecodeError, ValidationError) as e:
            last_err = e
            logger.warning(
                "activity classify attempt %d/%d failed: %s",
                attempt + 1,
                mlx.max_retries + 1,
                e,
            )
    logger.warning("activity classify fallback: %s", last_err)
    return heuristic_activity(snap)


def get_cached_activity(
    cache: ActivityCache,
    snap: ContextSnapshot,
    ttl_s: float,
    now: float | None = None,
) -> ActivityClassification | None:
    ts = now if now is not None else time.time()
    key = context_mod.snapshot_dedupe_key(snap)
    if (
        cache.key == key
        and cache.activity is not None
        and ts - cache.ts <= ttl_s
    ):
        return cache.activity
    return None


def store_activity_cache(
    cache: ActivityCache,
    snap: ContextSnapshot,
    activity: ActivityClassification,
    now: float | None = None,
) -> None:
    cache.key = context_mod.snapshot_dedupe_key(snap)
    cache.activity = activity
    cache.ts = now if now is not None else time.time()


def activity_embed_input(activity: ActivityClassification) -> str:
    entities = ", ".join(activity.entities) if activity.entities else "none"
    return f"{activity.activity_type}: {activity.topic} ({entities})"


def recency_score(mtime: float, now: float) -> float:
    age = max(0.0, now - mtime)
    return max(0.0, 1.0 - age / RECENCY_WINDOW_S)


def source_app_match(item_type: str, snap: ContextSnapshot) -> float:
    front = snap.frontmost_app
    if not front:
        return 0.0
    if front == SKETCH_BUNDLE and item_type in ("sketch_artboard", "sketch"):
        return 1.0
    if front == SAFARI_BUNDLE and item_type in ("text", "pdf"):
        return 1.0
    if item_type == "image":
        return 0.5 if front == SKETCH_BUNDLE else 0.0
    return 0.0


def passes_hard_filters(
    row: sqlite3.Row,
    activity: ActivityClassification,
) -> bool:
    if activity.project_hint:
        hint = (row["project_hint"] or "").strip().lower()
        if hint and hint != activity.project_hint.strip().lower():
            return False
    if row["type"] not in compatible_types_for(activity.activity_type):
        return False
    return True


def _normalize(v: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    if n <= 0:
        return v
    return v / n


def _parse_tags(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    return data if isinstance(data, list) else []


def _snippet(row: sqlite3.Row) -> str | None:
    text = None
    for col in ("vlm_caption", "extracted_text", "embed_input"):
        val = row[col]
        if val:
            text = val
            break
    if not text:
        return None
    s = str(text).strip()
    return s[:SNIPPET_MAX] if len(s) > SNIPPET_MAX else s


def thumb_data_url(thumb_dir: Path | None, basename: str | None) -> str | None:
    if not thumb_dir or not basename:
        return None
    path = thumb_dir / basename
    if not path.is_file():
        return None
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:image/webp;base64,{encoded}"


def fetch_candidates(db: sqlite3.Connection, min_mtime: float) -> list[sqlite3.Row]:
    return db.execute(
        """
        SELECT id, kind, type, title, source_path, artboard_id, uniq_key,
               project_hint, extracted_text, vlm_caption, tags, thumb_path,
               mtime, embedding, embed_input
        FROM items
        WHERE status = 'ready'
          AND embedding IS NOT NULL
          AND mtime > ?
        """,
        (min_mtime,),
    ).fetchall()


def search_related(
    db: sqlite3.Connection,
    mlx: mlx_mod.Client,
    snap: ContextSnapshot,
    *,
    k: int = 10,
    activity_cache: ActivityCache,
    activity_ttl_s: float,
    thumb_dir: Path | None,
    debug: bool = False,
    now: float | None = None,
) -> dict[str, Any]:
    """Core /related handler logic (sync — caller runs MLX in a thread if needed)."""
    ts = now if now is not None else time.time()
    k = max(1, min(k, 50))

    activity = get_cached_activity(activity_cache, snap, activity_ttl_s, ts)
    if activity is None:
        activity = classify_activity(mlx, snap)
        store_activity_cache(activity_cache, snap, activity, ts)

    embed_result = mlx.embed([activity_embed_input(activity)])
    q = _normalize(np.array(embed_result.embeddings[0], dtype=np.float32))

    rows = fetch_candidates(db, ts - RECENCY_WINDOW_S)
    if not rows:
        return {
            "k": k,
            "count": 0,
            "activity": activity.model_dump(),
            "items": [],
        }

    scored: list[tuple[float, sqlite3.Row, float]] = []
    for row in rows:
        if not passes_hard_filters(row, activity):
            continue
        blob = row["embedding"]
        if not blob:
            continue
        vec = _normalize(np.frombuffer(blob, dtype=np.float32))
        cosine = float(np.dot(vec, q))
        scored.append((cosine, row, cosine))

    scored.sort(key=lambda t: t[0], reverse=True)
    pool = scored[:RERANK_POOL]

    reranked: list[dict[str, Any]] = []
    for cosine, row, _ in pool:
        rec = recency_score(float(row["mtime"] or ts), ts)
        src = source_app_match(str(row["type"]), snap)
        final = 0.65 * cosine + 0.25 * rec + 0.10 * src
        item: dict[str, Any] = {
            "uniq_key": row["uniq_key"],
            "kind": row["kind"],
            "type": row["type"],
            "title": row["title"],
            "source_path": row["source_path"],
            "vlm_caption": row["vlm_caption"],
            "tags": _parse_tags(row["tags"]),
            "extracted_snippet": _snippet(row),
            "thumb_data_url": thumb_data_url(thumb_dir, row["thumb_path"]),
            "score": round(final, 4),
        }
        if debug:
            item["debug"] = {
                "cosine": round(cosine, 4),
                "recency": round(rec, 4),
                "source_app_match": round(src, 4),
            }
        reranked.append(item)

    reranked.sort(key=lambda x: x["score"], reverse=True)
    top = reranked[:k]

    out: dict[str, Any] = {
        "k": k,
        "count": len(top),
        "activity": activity.model_dump(),
        "items": top,
    }
    if debug:
        out["debug"] = {
            "candidates_total": len(rows),
            "after_filter": len(scored),
            "embed_latency_s": embed_result.latency_s,
        }
    return out
