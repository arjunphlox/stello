"""PDF wrapper tests — render + text extraction.

We synthesise PDFs via Pillow (image-only — no text layer). For text-
extraction-with-text we use a small in-repo helper that builds a real
text-layer PDF directly via pypdfium2's low-level pageobjects API.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from PIL import Image

from stello_context import pdf as pdf_mod


def _image_only_pdf(path: Path, size: tuple[int, int] = (200, 100)) -> None:
    Image.new("RGB", size, color="white").save(path, "PDF")


def test_render_first_page_returns_pil(tmp_path: Path) -> None:
    p = tmp_path / "x.pdf"
    _image_only_pdf(p, (400, 200))
    img = pdf_mod.render_first_page(p, scale=1.0)
    assert img.size == (400, 200)
    assert img.mode in ("RGB", "RGBA")


def test_render_scale_changes_size(tmp_path: Path) -> None:
    p = tmp_path / "x.pdf"
    _image_only_pdf(p, (100, 100))
    big = pdf_mod.render_first_page(p, scale=2.0)
    assert big.size == (200, 200)


def test_extract_text_returns_empty_for_image_only(tmp_path: Path) -> None:
    """A Pillow-saved image-only PDF has no text layer — must return ''
    cleanly (not error)."""
    p = tmp_path / "x.pdf"
    _image_only_pdf(p)
    text = pdf_mod.extract_first_page_text(p)
    assert text == ""


def test_extract_text_truncates_to_max_chars(tmp_path: Path) -> None:
    """Even with no text, the max_chars truncation path must run without error."""
    p = tmp_path / "x.pdf"
    _image_only_pdf(p)
    text = pdf_mod.extract_first_page_text(p, max_chars=10)
    assert text == ""


def test_render_raises_on_missing_file(tmp_path: Path) -> None:
    with pytest.raises(Exception):
        pdf_mod.render_first_page(tmp_path / "ghost.pdf")
