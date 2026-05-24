"""Sketch ZIP parsing tests — synthesises a minimal .sketch bundle and
verifies the cheap-path parser pulls out everything the embed input
needs."""
from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

from PIL import Image

from stello_context import sketch


def _build_test_sketch(
    path: Path,
    *,
    page_names: list[str] = ["Home Page"],
    artboards_per_page: dict[str, list[str]] | None = None,
    text_strings: list[str] = ["Welcome to HueGrid"],
    include_preview: bool = True,
) -> None:
    """Write a synthetic .sketch bundle matching the V103 schema we care about."""
    artboards_per_page = artboards_per_page or {"Home Page": ["Hero"]}
    pages_and_artboards: dict[str, dict] = {}
    page_files: dict[str, dict] = {}

    for i, pname in enumerate(page_names):
        page_uuid = f"{i:08d}-0000-0000-0000-000000000000"
        ab_meta = {}
        ab_layers: list[dict] = []
        for j, abname in enumerate(artboards_per_page.get(pname, [])):
            ab_uuid = f"{i:08d}-{j:04d}-0000-0000-000000000000"
            ab_meta[ab_uuid] = {"name": abname}
            ab_layers.append({
                "_class": "artboard",
                "do_objectID": ab_uuid,
                "name": abname,
                "layers": [
                    {
                        "_class": "text",
                        "do_objectID": f"text-{i}-{j}-{k}",
                        "name": f"text{k}",
                        "attributedString": {"string": s},
                    }
                    for k, s in enumerate(text_strings)
                ],
            })
        pages_and_artboards[page_uuid] = {"name": pname, "artboards": ab_meta}
        page_files[page_uuid] = {
            "_class": "page",
            "do_objectID": page_uuid,
            "name": pname,
            "layers": ab_layers,
        }

    meta = {
        "version": 103,
        "pagesAndArtboards": pages_and_artboards,
        "app": "test",
    }

    with zipfile.ZipFile(path, "w") as z:
        z.writestr("meta.json", json.dumps(meta))
        z.writestr("document.json", json.dumps({}))
        z.writestr("user.json", json.dumps({}))
        for uuid, page in page_files.items():
            z.writestr(f"pages/{uuid}.json", json.dumps(page))
        if include_preview:
            buf = io.BytesIO()
            Image.new("RGB", (120, 80), color="purple").save(buf, "PNG")
            z.writestr("previews/preview.png", buf.getvalue())


def test_parse_strings_minimal(tmp_path: Path) -> None:
    p = tmp_path / "design.sketch"
    _build_test_sketch(p)
    parsed = sketch.parse_sketch_strings(p)
    assert parsed["filename"] == "design.sketch"
    assert parsed["page_names"] == ["Home Page"]
    assert parsed["artboard_names"] == ["Hero"]
    assert parsed["text_strings"] == ["Welcome to HueGrid"]


def test_parse_strings_multipage(tmp_path: Path) -> None:
    p = tmp_path / "multi.sketch"
    _build_test_sketch(
        p,
        page_names=["Home", "About"],
        artboards_per_page={"Home": ["Hero", "CTA"], "About": ["Team"]},
        text_strings=["Welcome", "Sign up free"],
    )
    parsed = sketch.parse_sketch_strings(p)
    assert sorted(parsed["page_names"]) == ["About", "Home"]
    assert sorted(parsed["artboard_names"]) == ["CTA", "Hero", "Team"]
    # Each artboard has both text strings → 3 artboards × 2 = 6 entries
    assert parsed["text_strings"].count("Welcome") == 3
    assert parsed["text_strings"].count("Sign up free") == 3


def test_parse_strings_no_text_layers(tmp_path: Path) -> None:
    p = tmp_path / "empty.sketch"
    _build_test_sketch(p, text_strings=[])
    parsed = sketch.parse_sketch_strings(p)
    assert parsed["text_strings"] == []
    assert parsed["page_names"] == ["Home Page"]
    assert parsed["artboard_names"] == ["Hero"]


def test_parse_strings_ignores_empty_text(tmp_path: Path) -> None:
    p = tmp_path / "blanks.sketch"
    _build_test_sketch(p, text_strings=["", "   ", "Real text"])
    parsed = sketch.parse_sketch_strings(p)
    assert parsed["text_strings"] == ["Real text"]


def test_extract_preview_png_present(tmp_path: Path) -> None:
    p = tmp_path / "with-preview.sketch"
    _build_test_sketch(p, include_preview=True)
    png = sketch.extract_preview_png(p)
    assert png is not None
    assert png[:8] == b"\x89PNG\r\n\x1a\n"


def test_extract_preview_png_absent(tmp_path: Path) -> None:
    p = tmp_path / "no-preview.sketch"
    _build_test_sketch(p, include_preview=False)
    assert sketch.extract_preview_png(p) is None


def test_compose_embed_input_includes_all_parts(tmp_path: Path) -> None:
    parsed = {
        "filename": "foo.sketch",
        "page_names": ["Home", "About"],
        "artboard_names": ["Hero", "CTA"],
        "text_strings": ["Welcome", "Sign up"],
    }
    s = sketch.compose_embed_input(parsed)
    assert "foo.sketch" in s
    assert "Pages: Home, About" in s
    assert "Artboards: Hero, CTA" in s
    assert "Welcome" in s
    assert "Sign up" in s


def test_compose_embed_input_truncates(tmp_path: Path) -> None:
    parsed = {
        "filename": "x.sketch",
        "page_names": [],
        "artboard_names": [],
        "text_strings": ["a" * 10_000],
    }
    s = sketch.compose_embed_input(parsed, max_chars=100)
    assert len(s) <= 100


def test_real_sketch_file_smoke() -> None:
    """If a real .sketch sample is present on disk, the parser must
    not crash on it. Skipped otherwise."""
    import os

    sample = Path(
        "/Users/arjunphlox/Documents/Personal Docs/Arjun's Documents/Transport/Arjun_RC&DL_A4.sketch"
    )
    if not sample.exists() or not os.access(sample, os.R_OK):
        return
    parsed = sketch.parse_sketch_strings(sample)
    assert parsed["filename"] == "Arjun_RC&DL_A4.sketch"
    # Recon earlier confirmed 1 page with 3 artboards.
    assert len(parsed["page_names"]) >= 1
    assert len(parsed["artboard_names"]) >= 1
    # Embed input composes cleanly.
    s = sketch.compose_embed_input(parsed)
    assert parsed["filename"] in s
