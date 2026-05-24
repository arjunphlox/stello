"""256px webp thumbnail generation for images, PDF page-1 (step 6), and
Sketch artboards (step 11).

Files live under ~/Library/Application Support/Stello/desktop-context/thumbs/
keyed by SHA1 of the source's canonical absolute path — so re-enriching
the same source deterministically overwrites its existing thumbnail.

`thumb_path` is stored in items.thumb_path as the basename (e.g.
`<sha1>.webp`), relative to thumb_dir(); the absolute path is
reconstructed on read so the install location can move without a DB
migration.
"""
from __future__ import annotations

import hashlib
import logging
import os
from pathlib import Path

from PIL import Image

logger = logging.getLogger("stello-context.thumbnails")

DEFAULT_THUMB_DIR = Path(
    "~/Library/Application Support/Stello/desktop-context/thumbs"
).expanduser()

MAX_EDGE = 256
WEBP_QUALITY = 80


def thumb_dir() -> Path:
    """Resolve the thumb dir from env or default; mkdir parents on access."""
    d = Path(os.environ.get("STELLO_CTX_THUMB_DIR", str(DEFAULT_THUMB_DIR)))
    d.mkdir(parents=True, exist_ok=True)
    return d


def thumb_key(source_path: str) -> str:
    """SHA1 hex of the absolute source path — stable cache key."""
    return hashlib.sha1(source_path.encode("utf-8")).hexdigest()


def thumb_basename(source_path: str) -> str:
    """The basename we store in items.thumb_path."""
    return f"{thumb_key(source_path)}.webp"


def _prepare_for_webp(im: Image.Image) -> Image.Image:
    """webp supports RGB and RGBA natively. Convert anything else to RGB
    (palette, grayscale, CMYK, etc.) so encoding doesn't fail."""
    if im.mode in ("RGB", "RGBA"):
        return im
    return im.convert("RGB")


def make_thumbnail_from_image(
    src_path: Path,
    out_dir: Path | None = None,
    max_edge: int = MAX_EDGE,
) -> tuple[Path, tuple[int, int]]:
    """Resize one on-disk image and save as webp.

    Returns (out_path, original_size). The thumb is keyed on the SHA1
    of str(src_path) so it overwrites itself across re-enrichments.
    """
    out_dir = out_dir or thumb_dir()
    out_dir.mkdir(parents=True, exist_ok=True)
    with Image.open(src_path) as im:
        im.load()  # force decode under the open context
        orig = im.size
        im.thumbnail((max_edge, max_edge), Image.Resampling.LANCZOS)
        im = _prepare_for_webp(im)
        out_path = out_dir / thumb_basename(str(src_path))
        im.save(out_path, "WEBP", quality=WEBP_QUALITY)
    return out_path, orig


def make_thumbnail_from_pillow(
    image: Image.Image,
    source_path: Path,
    out_dir: Path | None = None,
    max_edge: int = MAX_EDGE,
) -> Path:
    """Resize an already-open PIL image and save as webp.

    Used by PDF (step 6) and Sketch artboard export (step 11), where
    we already have decoded pixels and don't need to re-open from disk.
    `source_path` is the logical key (the PDF / .sketch / artboard ID),
    NOT necessarily an existing on-disk image.
    """
    out_dir = out_dir or thumb_dir()
    out_dir.mkdir(parents=True, exist_ok=True)
    im = image.copy()
    im.thumbnail((max_edge, max_edge), Image.Resampling.LANCZOS)
    im = _prepare_for_webp(im)
    out_path = out_dir / thumb_basename(str(source_path))
    im.save(out_path, "WEBP", quality=WEBP_QUALITY)
    return out_path
