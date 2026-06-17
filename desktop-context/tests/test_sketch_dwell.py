"""Dwell tracker + sketchtool export unit tests."""
from __future__ import annotations

import asyncio
import json
import zipfile
from pathlib import Path

import pytest

from stello_context import enrich, mlx_client, sketch, sketch_dwell, store


def test_window_key() -> None:
    doc = {"path": "/a.sketch", "window_width": 1200, "window_height": 800}
    assert sketch_dwell.window_key(doc) == "/a.sketch:1200x800"


def test_dwell_resets_on_visible_set_change(tmp_path: Path) -> None:
    tracker = sketch_dwell.DwellTracker(dwell_window_s=60, vlm_cap=5)
    doc_a = {
        "path": "/a.sketch",
        "window_width": 100,
        "window_height": 100,
        "visible_artboards": [{"id": "1", "name": "One"}],
    }
    queue: asyncio.Queue = asyncio.Queue()
    db = store.open_db(tmp_path / "ctx.db")

    assert tracker.tick([doc_a], db, queue, now=0.0) == 0
    assert tracker.tick([doc_a], db, queue, now=30.0) == 0

    doc_b = {
        **doc_a,
        "visible_artboards": [{"id": "2", "name": "Two"}],
    }
    assert tracker.tick([doc_b], db, queue, now=90.0) == 0
    db.close()


def test_dwell_fires_after_threshold(tmp_path: Path) -> None:
    page_uuid = "page-uuid"
    ab_uuid = "ab-uuid"
    sketch_path = tmp_path / "demo.sketch"
    with zipfile.ZipFile(sketch_path, "w") as z:
        z.writestr("meta.json", json.dumps({"pagesAndArtboards": {}}))
        z.writestr(
            "user.json",
            json.dumps({page_uuid: {"scrollOrigin": "{0, 0}", "zoomValue": 1}}),
        )
        z.writestr(
            f"pages/{page_uuid}.json",
            json.dumps(
                {
                    "layers": [
                        {
                            "_class": "artboard",
                            "do_objectID": ab_uuid,
                            "name": "Hero",
                            "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
                        }
                    ]
                }
            ),
        )

    tracker = sketch_dwell.DwellTracker(dwell_window_s=10, vlm_cap=2)
    doc = {
        "path": str(sketch_path.resolve()),
        "window_width": 200,
        "window_height": 200,
        "visible_artboards": [{"id": ab_uuid, "name": "Hero"}],
    }
    queue: asyncio.Queue = asyncio.Queue()
    db = store.open_db(tmp_path / "ctx.db")

    tracker.tick([doc], db, queue, now=0.0)
    assert queue.qsize() == 0
    enqueued = tracker.tick([doc], db, queue, now=11.0)
    assert enqueued == 1
    job = queue.get_nowait()
    assert job.artboard_id == ab_uuid
    assert job.reason == "sketch_dwell"
    db.close()


def test_export_artboard_png_mocked(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    sketch_path = tmp_path / "demo.sketch"
    sketch_path.write_bytes(b"PK")  # existence check only
    fake_tool = tmp_path / "sketchtool"
    fake_tool.write_text("#!/bin/sh\n", encoding="utf-8")

    def fake_run(cmd, **kwargs):
        out_dir = Path(cmd[-1].split("=", 1)[1])
        out_dir.mkdir(parents=True, exist_ok=True)
        target = out_dir / "Hero.png"
        target.write_bytes(b"\x89PNG\r\n\x1a\n")

        class R:
            returncode = 0
            stdout = "Exported Hero.png"
            stderr = ""

        return R()

    monkeypatch.setattr(sketch, "SKETCHTOOL_PATH", fake_tool)
    monkeypatch.setattr(sketch.subprocess, "run", fake_run)

    result = sketch.export_artboard_png(sketch_path, "ab-uuid")
    assert result is not None
    assert result.name == "Hero.png"


def test_enrich_sketch_artboard_fallback(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    page_uuid = "page-uuid"
    ab_uuid = "ab-uuid"
    sketch_path = tmp_path / "demo.sketch"
    with zipfile.ZipFile(sketch_path, "w") as z:
        z.writestr(
            "meta.json",
            json.dumps(
                {
                    "pagesAndArtboards": {
                        page_uuid: {
                            "name": "Home",
                            "artboards": {ab_uuid: {"name": "Hero"}},
                        }
                    }
                }
            ),
        )
        z.writestr("user.json", json.dumps({}))
        z.writestr(
            f"pages/{page_uuid}.json",
            json.dumps(
                {
                    "layers": [
                        {
                            "_class": "artboard",
                            "do_objectID": ab_uuid,
                            "name": "Hero",
                            "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
                        }
                    ]
                }
            ),
        )

    db = store.open_db(tmp_path / "ctx.db")
    monkeypatch.setattr(sketch, "export_artboard_png", lambda *a, **k: None)

    class FakeMlx:
        def embed(self, inputs):
            return mlx_client.EmbedResult(
                embeddings=[[0.1] * 1024], dim=1024, latency_s=0.01
            )

    job = enrich.EnrichJob(
        source_path=str(sketch_path),
        reason="test",
        artboard_id=ab_uuid,
        artboard_name="Hero",
    )

    async def run() -> None:
        await enrich.enrich_sketch_artboard(
            db, FakeMlx(), job, tmp_path / "thumbs"
        )

    asyncio.run(run())
    row = db.execute(
        "SELECT status, error, vlm_caption FROM items WHERE artboard_id = ?",
        (ab_uuid,),
    ).fetchone()
    assert row["status"] == "ready"
    assert row["vlm_caption"] is None
    assert "export-failed" in (row["error"] or "")
    db.close()
