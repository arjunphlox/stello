"""Unit tests for /related retrieval (no live MLX)."""
from __future__ import annotations

import sqlite3
import struct
import time

import numpy as np
import pytest

from stello_context import context, mlx_client, related, store


def _vec(first: float, second: float = 0.0) -> bytes:
    arr = np.zeros(1024, dtype=np.float32)
    arr[0] = first
    arr[1] = second
    arr = arr / np.linalg.norm(arr)
    return struct.pack(f"<{1024}f", *arr.tolist())


def _insert_item(
    db: sqlite3.Connection,
    *,
    uniq_key: str,
    type_: str,
    embedding: bytes,
    mtime: float,
    project_hint: str | None = None,
    title: str = "item",
) -> None:
    db.execute(
        """
        INSERT INTO items
            (kind, source_path, uniq_key, type, title, mtime, project_hint,
             embedding, status, enrich_version)
        VALUES ('file', ?, ?, ?, ?, ?, ?, ?, 'ready', 1)
        """,
        (uniq_key, uniq_key, type_, title, mtime, project_hint, embedding),
    )


class FakeMlx:
    max_retries = 2

    def __init__(self) -> None:
        self.generate_calls = 0
        self.embed_calls = 0

    def generate(self, prompt: str, **kwargs) -> mlx_client.GenerateResult:
        self.generate_calls += 1
        return mlx_client.GenerateResult(
            text=(
                '{"activity_type":"design","topic":"UI mockups",'
                '"entities":["hero"],"project_hint":"HueGrid"}'
            ),
            latency_s=0.01,
        )

    def embed(self, inputs: list[str]) -> mlx_client.EmbedResult:
        self.embed_calls += 1
        v = np.zeros(1024, dtype=np.float32)
        v[0] = 1.0
        return mlx_client.EmbedResult(
            embeddings=[v.tolist()],
            dim=1024,
            latency_s=0.01,
        )


def test_recency_score_fresh_is_one() -> None:
    now = 1_000_000.0
    assert related.recency_score(now - 3600, now) == pytest.approx(1.0 - 3600 / related.RECENCY_WINDOW_S)


def test_hard_filter_project_hint() -> None:
    row = {
        "project_hint": "OtherProject",
        "type": "image",
    }
    activity = related.ActivityClassification(
        activity_type="design",
        topic="x",
        project_hint="HueGrid",
    )
    assert related.passes_hard_filters(row, activity) is False  # type: ignore[arg-type]


def test_hard_filter_compatible_type() -> None:
    row = {"project_hint": None, "type": "text"}
    activity = related.ActivityClassification(
        activity_type="design", topic="x"
    )
    assert related.passes_hard_filters(row, activity) is False  # type: ignore[arg-type]


def test_search_related_ranks_by_cosine(tmp_path) -> None:
    db = store.open_db(tmp_path / "ctx.db")
    now = time.time()
    _insert_item(
        db,
        uniq_key="/a.png",
        type_="image",
        embedding=_vec(1.0, 0.0),
        mtime=now,
        project_hint="HueGrid",
        title="match",
    )
    _insert_item(
        db,
        uniq_key="/b.png",
        type_="image",
        embedding=_vec(0.0, 1.0),
        mtime=now,
        project_hint="HueGrid",
        title="orthogonal",
    )

    snap = context.ContextSnapshot(
        ts=now,
        frontmost_app=related.SKETCH_BUNDLE,
        open_apps=[],
    )
    mlx = FakeMlx()
    cache = related.ActivityCache()
    result = related.search_related(
        db,
        mlx,
        snap,
        k=2,
        activity_cache=cache,
        activity_ttl_s=10.0,
        thumb_dir=None,
        now=now,
    )
    assert result["count"] == 2
    assert result["items"][0]["title"] == "match"
    assert result["items"][0]["score"] >= result["items"][1]["score"]
    db.close()


def test_activity_cache_skips_reclassify(tmp_path) -> None:
    db = store.open_db(tmp_path / "ctx.db")
    now = time.time()
    _insert_item(
        db,
        uniq_key="/a.png",
        type_="image",
        embedding=_vec(1.0),
        mtime=now,
    )
    snap = context.ContextSnapshot(ts=now, open_apps=[])
    mlx = FakeMlx()
    cache = related.ActivityCache()
    related.search_related(
        db, mlx, snap, k=1, activity_cache=cache, activity_ttl_s=60, thumb_dir=None, now=now
    )
    related.search_related(
        db, mlx, snap, k=1, activity_cache=cache, activity_ttl_s=60, thumb_dir=None, now=now + 1
    )
    assert mlx.generate_calls == 1
    assert mlx.embed_calls == 2
    db.close()


def test_heuristic_activity_sketch() -> None:
    snap = context.ContextSnapshot(
        ts=1.0,
        frontmost_app=related.SKETCH_BUNDLE,
        frontmost_app_name="Sketch",
        sketch_state=[
            {
                "path": "/tmp/foo.sketch",
                "visible_artboards": [{"id": "1", "name": "Hero"}],
            }
        ],
    )
    act = related.heuristic_activity(snap)
    assert act.activity_type == "design"
    assert "Hero" in act.entities
