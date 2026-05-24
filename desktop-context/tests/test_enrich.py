"""Enrich unit tests — classification, project hint, embed blob round-trip,
text + image enrich with a fake MLX client (idempotent + failure paths)."""
from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest
from PIL import Image

from stello_context import enrich, mlx_client, store


class FakeMLX:
    """Minimal stand-in for mlx_client.Client.

    embed() returns a deterministic 1024-dim vector and bumps a call counter,
    so tests can assert on cache behavior.
    """

    def __init__(self) -> None:
        self.embed_calls = 0

    def embed(self, inputs: list[str]) -> mlx_client.EmbedResult:
        self.embed_calls += 1
        vec = [0.001 * i for i in range(1024)]
        return mlx_client.EmbedResult(
            embeddings=[vec for _ in inputs],
            dim=1024,
            latency_s=0.01,
        )


def test_classify_path() -> None:
    assert enrich.classify_path(Path("a.md")) == "text"
    assert enrich.classify_path(Path("a.TXT")) == "text"
    assert enrich.classify_path(Path("a.png")) == "image"
    assert enrich.classify_path(Path("a.JPG")) == "image"
    assert enrich.classify_path(Path("a.webp")) == "image"
    assert enrich.classify_path(Path("a.sketch")) == "other"


def test_project_hint_for(tmp_path: Path) -> None:
    wf = tmp_path / "Stello Watcher"
    wf.mkdir()
    inside = wf / "sub" / "note.md"
    inside.parent.mkdir()
    inside.write_text("x")
    assert enrich.project_hint_for(inside, [str(wf)]) == "Stello Watcher"
    outside = tmp_path / "elsewhere.md"
    outside.write_text("x")
    assert enrich.project_hint_for(outside, [str(wf)]) is None


def test_embedding_blob_round_trip() -> None:
    vec = [float(i) / 7.0 for i in range(1024)]
    blob = enrich.embedding_to_blob(vec)
    assert len(blob) == 4 * 1024
    back = enrich.blob_to_embedding(blob)
    assert len(back) == 1024
    for a, b in zip(vec, back):
        assert abs(a - b) < 1e-5


def test_enrich_text_inserts_and_is_idempotent(tmp_path: Path) -> None:
    """One MLX call on first enrich; a second enrich with unchanged mtime skips."""
    md = tmp_path / "note.md"
    md.write_text("Hello world.\n\nA second paragraph.")

    db = store.open_db(tmp_path / "ctx.db")
    fake = FakeMLX()
    job = enrich.EnrichJob(source_path=str(md), reason="initial_walk")

    asyncio.run(enrich.enrich_text(db, fake, job, [str(tmp_path)]))
    row = db.execute("SELECT * FROM items WHERE uniq_key = ?", (str(md),)).fetchone()
    assert row is not None
    assert row["status"] == "ready"
    assert row["type"] == "text"
    assert row["title"] == "note.md"
    assert row["project_hint"] == tmp_path.name
    assert row["embedding"] is not None
    assert len(row["embedding"]) == 4 * 1024
    assert fake.embed_calls == 1

    # Re-enrich without modifying the file → cached, no extra MLX call.
    asyncio.run(enrich.enrich_text(db, fake, job, [str(tmp_path)]))
    assert fake.embed_calls == 1

    # Touch the file (new mtime) → re-enriched.
    md.write_text("Different content now.")
    asyncio.run(enrich.enrich_text(db, fake, job, [str(tmp_path)]))
    assert fake.embed_calls == 2

    db.close()


def test_enrich_text_handles_missing_file(tmp_path: Path) -> None:
    db = store.open_db(tmp_path / "ctx.db")
    fake = FakeMLX()
    job = enrich.EnrichJob(
        source_path=str(tmp_path / "ghost.md"), reason="initial_walk"
    )
    # Should not raise.
    asyncio.run(enrich.enrich_text(db, fake, job, [str(tmp_path)]))
    n = db.execute("SELECT COUNT(*) AS n FROM items").fetchone()["n"]
    assert n == 0
    assert fake.embed_calls == 0
    db.close()


def test_enrich_records_failure(tmp_path: Path) -> None:
    """If the MLX call raises, dispatch() should write a status='failed' row."""
    md = tmp_path / "boom.md"
    md.write_text("content")

    class BrokenMLX:
        def embed(self, _inputs: list[str]) -> Any:
            raise RuntimeError("mlx down")

    db = store.open_db(tmp_path / "ctx.db")
    job = enrich.EnrichJob(source_path=str(md), reason="initial_walk")
    asyncio.run(enrich.enrich(db, BrokenMLX(), job, [str(tmp_path)], tmp_path / "thumbs"))
    row = db.execute("SELECT status, error FROM items WHERE uniq_key = ?", (str(md),)).fetchone()
    assert row is not None
    assert row["status"] == "failed"
    assert "mlx down" in row["error"]
    db.close()


def test_enrich_skips_unknown_extension(tmp_path: Path) -> None:
    """Unsupported types should be silently skipped (no row, no error)."""
    weird = tmp_path / "thing.xyz"
    weird.write_text("x")
    db = store.open_db(tmp_path / "ctx.db")
    fake = FakeMLX()
    job = enrich.EnrichJob(source_path=str(weird), reason="initial_walk")
    asyncio.run(enrich.enrich(db, fake, job, [str(tmp_path)], tmp_path / "thumbs"))
    n = db.execute("SELECT COUNT(*) AS n FROM items").fetchone()["n"]
    assert n == 0
    assert fake.embed_calls == 0
    db.close()


def _make_png(path: Path, size: tuple[int, int] = (200, 100)) -> None:
    Image.new("RGB", size, color="blue").save(path, "PNG")


def test_enrich_image_pending_vlm_with_thumb(tmp_path: Path) -> None:
    """Drop a PNG → row inserted with status=pending_vlm, thumb on disk,
    embedding from filename only (1024 floats), one MLX call."""
    src = tmp_path / "hero.png"
    _make_png(src, (800, 400))
    thumbs = tmp_path / "thumbs"

    db = store.open_db(tmp_path / "ctx.db")
    fake = FakeMLX()
    job = enrich.EnrichJob(source_path=str(src), reason="initial_walk")
    asyncio.run(enrich.enrich_image(db, fake, job, [str(tmp_path)], thumbs))

    row = db.execute(
        "SELECT type, status, title, thumb_path, length(embedding) AS emb FROM items WHERE uniq_key = ?",
        (str(src),),
    ).fetchone()
    assert row is not None
    assert row["type"] == "image"
    assert row["status"] == "pending_vlm"
    assert row["title"] == "hero.png"
    assert row["thumb_path"].endswith(".webp")
    assert row["emb"] == 4 * 1024
    assert fake.embed_calls == 1

    # Thumbnail file exists in the configured thumb_dir.
    assert (thumbs / row["thumb_path"]).exists()
    db.close()


def test_enrich_image_idempotent_on_mtime(tmp_path: Path) -> None:
    src = tmp_path / "p.png"
    _make_png(src)
    thumbs = tmp_path / "thumbs"

    db = store.open_db(tmp_path / "ctx.db")
    fake = FakeMLX()
    job = enrich.EnrichJob(source_path=str(src), reason="initial_walk")
    asyncio.run(enrich.enrich_image(db, fake, job, [str(tmp_path)], thumbs))
    asyncio.run(enrich.enrich_image(db, fake, job, [str(tmp_path)], thumbs))
    assert fake.embed_calls == 1  # second call is a cache hit
    db.close()


def test_enrich_dispatch_routes_image(tmp_path: Path) -> None:
    src = tmp_path / "x.jpg"
    Image.new("RGB", (64, 64), color="green").save(src, "JPEG")
    thumbs = tmp_path / "thumbs"
    db = store.open_db(tmp_path / "ctx.db")
    fake = FakeMLX()
    job = enrich.EnrichJob(source_path=str(src), reason="initial_walk")
    asyncio.run(enrich.enrich(db, fake, job, [str(tmp_path)], thumbs))
    row = db.execute(
        "SELECT type, status FROM items WHERE uniq_key = ?", (str(src),)
    ).fetchone()
    assert row is not None
    assert row["type"] == "image"
    assert row["status"] == "pending_vlm"
    db.close()
