"""Thumbnail generation tests."""
from __future__ import annotations

from pathlib import Path

import pytest
from PIL import Image

from stello_context import thumbnails


def _make_png(path: Path, size: tuple[int, int], mode: str = "RGB", color: str = "red") -> None:
    img = Image.new(mode, size, color=color)
    img.save(path, "PNG")


def test_thumb_key_stable() -> None:
    a = thumbnails.thumb_key("/tmp/foo.png")
    b = thumbnails.thumb_key("/tmp/foo.png")
    c = thumbnails.thumb_key("/tmp/bar.png")
    assert a == b
    assert a != c
    assert len(a) == 40  # sha1 hex


def test_thumb_basename_format() -> None:
    name = thumbnails.thumb_basename("/tmp/x.jpg")
    assert name.endswith(".webp")
    assert len(name) == 45  # 40 hex + ".webp"


def test_make_thumbnail_downscales(tmp_path: Path) -> None:
    src = tmp_path / "big.png"
    _make_png(src, (1024, 512))
    out_dir = tmp_path / "thumbs"

    out_path, orig = thumbnails.make_thumbnail_from_image(src, out_dir)
    assert out_path.exists()
    assert orig == (1024, 512)

    with Image.open(out_path) as im:
        # Long edge clamped to MAX_EDGE; aspect ratio preserved.
        assert max(im.size) == thumbnails.MAX_EDGE
        assert im.format == "WEBP"


def test_make_thumbnail_overwrites_same_key(tmp_path: Path) -> None:
    """Re-thumbnailing the same source must overwrite, not duplicate."""
    src = tmp_path / "x.png"
    _make_png(src, (100, 100))
    out_dir = tmp_path / "thumbs"
    p1, _ = thumbnails.make_thumbnail_from_image(src, out_dir)
    p2, _ = thumbnails.make_thumbnail_from_image(src, out_dir)
    assert p1 == p2
    assert len(list(out_dir.iterdir())) == 1


def test_make_thumbnail_converts_palette(tmp_path: Path) -> None:
    """A palette ('P') mode PNG must be converted to RGB for webp."""
    src = tmp_path / "pal.png"
    img = Image.new("P", (50, 50))
    img.putpalette([0, 0, 0] * 256)
    img.save(src, "PNG")
    out_dir = tmp_path / "thumbs"
    out_path, _ = thumbnails.make_thumbnail_from_image(src, out_dir)
    assert out_path.exists()
    with Image.open(out_path) as im:
        assert im.mode in ("RGB", "RGBA")


def test_make_thumbnail_preserves_alpha(tmp_path: Path) -> None:
    """RGBA PNGs round-trip as RGBA webp (alpha not lost)."""
    src = tmp_path / "alpha.png"
    _make_png(src, (300, 300), mode="RGBA", color=(255, 0, 0, 128))
    out_dir = tmp_path / "thumbs"
    out_path, _ = thumbnails.make_thumbnail_from_image(src, out_dir)
    with Image.open(out_path) as im:
        assert im.mode == "RGBA"


def test_thumb_dir_env_override(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("STELLO_CTX_THUMB_DIR", str(tmp_path / "alt"))
    d = thumbnails.thumb_dir()
    assert d == tmp_path / "alt"
    assert d.exists()
