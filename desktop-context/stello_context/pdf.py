"""PDF page-1 render + text extraction via pypdfium2.

V1 only touches page 1 — the page-1 thumbnail goes through the same
sha1-keyed thumbnail store as images, and the page-1 text (if the PDF
has a text layer) is concatenated with the filename for the embedding
input.

Scanned/image-only PDFs (no text layer) gracefully return "" — the
filename embedding still gets a row.
"""
from __future__ import annotations

import logging
from pathlib import Path

import pypdfium2 as pdfium
from PIL import Image

logger = logging.getLogger("stello-context.pdf")

# Render scale: 1.5x at 72dpi = 108dpi. Good enough for a 256px thumbnail
# regardless of original page size.
RENDER_SCALE = 1.5

# Cap how much page-1 text we feed into the embed call. BGE-M3 handles
# more, but we want the filename + page-1 to fit comfortably.
MAX_TEXT_CHARS = 4000


def extract_first_page_text(p: Path, max_chars: int = MAX_TEXT_CHARS) -> str:
    """Return page-1 text, truncated to max_chars. Empty string for
    image-only PDFs (no embedded text layer).

    Resource handles (textpage, page, document) are explicitly closed
    to avoid pypdfium2's destructor warnings.
    """
    pdf = pdfium.PdfDocument(str(p))
    try:
        if len(pdf) == 0:
            return ""
        page = pdf[0]
        try:
            tp = page.get_textpage()
            try:
                # 0 to -1 = entire page.
                text = tp.get_text_range(0, -1) or ""
            finally:
                tp.close()
        finally:
            page.close()
    finally:
        pdf.close()
    return text[:max_chars]


def render_first_page(p: Path, scale: float = RENDER_SCALE) -> Image.Image:
    """Render page 1 as a PIL.Image (RGB). Caller is responsible for
    thumbnailing + saving."""
    pdf = pdfium.PdfDocument(str(p))
    try:
        if len(pdf) == 0:
            raise ValueError(f"PDF has no pages: {p}")
        page = pdf[0]
        try:
            bitmap = page.render(scale=scale)
            img = bitmap.to_pil()
        finally:
            page.close()
    finally:
        pdf.close()
    return img
