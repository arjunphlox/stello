"""Visible-rect math + document-state builder — pure tests, no live Sketch."""
from __future__ import annotations

import json
import os
import zipfile
from pathlib import Path

import pytest

from stello_context import context, sketch


def test_parse_scroll_origin() -> None:
    assert sketch.parse_scroll_origin("{-1363, 183}") == (-1363.0, 183.0)
    assert sketch.parse_scroll_origin("{0, 0}") == (0.0, 0.0)


def test_parse_scroll_origin_rejects_garbage() -> None:
    with pytest.raises(ValueError):
        sketch.parse_scroll_origin("not-a-rect")


def test_compute_visible_canvas_rect() -> None:
    rect = sketch.compute_visible_canvas_rect((-1363, 183), 1.0, 1440, 900)
    assert rect.x == pytest.approx(1363.0)
    assert rect.y == pytest.approx(-183.0)
    assert rect.width == pytest.approx(1440.0)
    assert rect.height == pytest.approx(900.0)


def test_intersection_area_disjoint() -> None:
    a = sketch.CanvasRect(0, 0, 100, 100)
    b = sketch.CanvasRect(200, 200, 50, 50)
    assert sketch.intersection_area(a, b) == 0.0


def test_intersection_area_overlap() -> None:
    a = sketch.CanvasRect(0, 0, 100, 100)
    b = sketch.CanvasRect(50, 50, 100, 100)
    assert sketch.intersection_area(a, b) == 2500.0


def test_build_document_state_from_fixture(tmp_path: Path) -> None:
    page_uuid = "0A26ECF5-1064-4494-BF6D-9DA8EA1E14B5"
    ab_uuid = "316C09BC-EE72-42A7-AD58-FC9041E46320"
    page = {
        "_class": "page",
        "do_objectID": page_uuid,
        "name": "Page 1",
        "layers": [
            {
                "_class": "artboard",
                "do_objectID": ab_uuid,
                "name": "Hero",
                "frame": {"x": 880, "y": -44, "width": 595, "height": 842},
            }
        ],
    }
    user = {
        "document": {},
        page_uuid: {"scrollOrigin": "{-880, 44}", "zoomValue": 1},
    }
    meta = {
        "pagesAndArtboards": {
            page_uuid: {"name": "Page 1", "artboards": {ab_uuid: {"name": "Hero"}}}
        }
    }
    p = tmp_path / "demo.sketch"
    with zipfile.ZipFile(p, "w") as z:
        z.writestr("meta.json", json.dumps(meta))
        z.writestr("user.json", json.dumps(user))
        z.writestr(f"pages/{page_uuid}.json", json.dumps(page))

    state = sketch.build_document_state(
        {
            "path": str(p),
            "page_id": page_uuid,
            "page_name": "Page 1",
            "window_width": 1440,
            "window_height": 900,
        }
    )
    assert state is not None
    assert state["path"] == str(p.resolve())
    assert state["zoom"] == 1.0
    assert state["scroll_origin"] == [-880.0, 44.0]
    assert len(state["visible_artboards"]) == 1
    assert state["visible_artboards"][0]["id"] == ab_uuid
    assert state["visible_artboards"][0]["name"] == "Hero"
    assert state["visible_artboards"][0]["intersection_area"] > 0


def test_discover_sketch_state_mocked(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        sketch,
        "get_open_documents",
        lambda: [
            {
                "path": "/tmp/missing.sketch",
                "page_id": "",
                "page_name": "",
                "window_width": 0,
                "window_height": 0,
            }
        ],
    )
    assert sketch.discover_sketch_state() == []


def test_snapshot_dedupe_key_includes_sketch_visible_set() -> None:
    a = context.ContextSnapshot(
        ts=1.0,
        sketch_state=[
            {
                "path": "/a.sketch",
                "visible_artboards": [{"id": "x", "name": "X"}],
            }
        ],
    )
    b = context.ContextSnapshot(
        ts=2.0,
        sketch_state=[
            {
                "path": "/a.sketch",
                "visible_artboards": [{"id": "y", "name": "Y"}],
            }
        ],
    )
    assert context.snapshot_dedupe_key(a) != context.snapshot_dedupe_key(b)


def test_real_sketch_visible_rect_smoke() -> None:
    """When the transport sample is on disk, visible-rect math must run."""
    sample = Path(
        "/Users/arjunphlox/Documents/Personal Docs/Arjun's Documents/Transport/Arjun_RC&DL_A4.sketch"
    )
    if not sample.exists() or not os.access(sample, os.R_OK):
        return
    user = sketch.read_user_json(sample)
    page_uuid = sketch.infer_page_uuid_from_user_json(user)
    assert page_uuid is not None
    viewport = sketch.page_viewport(user, page_uuid)
    assert viewport is not None
    origin, zoom = viewport
    visible = sketch.compute_visible_artboards(
        sample, page_uuid, 1440, 900, origin, zoom
    )
    assert isinstance(visible, list)
    # Sample scroll position shows at least one of the three A4 artboards.
    assert len(visible) >= 1
