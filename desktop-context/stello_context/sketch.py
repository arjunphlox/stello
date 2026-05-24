"""Sketch introspection — ZIP parsing, AppleScript glue, visible-rect math.

Stage 7 (current — cheap path only):
  - parse_sketch_strings(): pulls page names + artboard names from
    meta.json (avoiding a full per-page walk just for that), plus
    text-layer strings by walking each page tree once.
  - extract_preview_png(): returns the whole-file preview PNG bytes
    (Sketch ships one at previews/preview.png; per-page previews don't
    exist in the bundle).
  - compose_embed_input(): builds the canonical string we feed to
    /v1/embed.

Stage 10 will add open-document discovery + visible-rect math, and
stage 11 the AppleScript-driven artboard export + dwell-gated VLM.
"""
from __future__ import annotations

import json
import logging
import zipfile
from pathlib import Path
from typing import Any

logger = logging.getLogger("stello-context.sketch")

# Cap on the assembled embed-input string. BGE-M3 handles more, but
# we want the headline strings to dominate over a long text dump.
EMBED_MAX_CHARS = 4000


def _collect_text_strings(node: Any, out: list[str]) -> None:
    """Recursively pull every text-layer string out of a Sketch JSON tree.

    Looks for `_class == "text"` nodes and grabs their
    attributedString.string. Handles nested artboards, symbols, groups.
    """
    if isinstance(node, dict):
        if node.get("_class") == "text":
            attr = node.get("attributedString", {})
            if isinstance(attr, dict):
                s = attr.get("string")
                if isinstance(s, str) and s.strip():
                    out.append(s.strip())
        for v in node.values():
            _collect_text_strings(v, out)
    elif isinstance(node, list):
        for v in node:
            _collect_text_strings(v, out)


def parse_sketch_strings(p: Path) -> dict:
    """Pull names + text out of a .sketch bundle.

    Returns {filename, page_names, artboard_names, text_strings}.
    Page and artboard names come from meta.json — fast, no per-page walk.
    Text strings require walking each pages/<uuid>.json once.
    """
    with zipfile.ZipFile(p) as z:
        try:
            meta = json.loads(z.read("meta.json"))
        except KeyError:
            meta = {}

        page_names: list[str] = []
        artboard_names: list[str] = []
        for _page_id, page_meta in meta.get("pagesAndArtboards", {}).items():
            if isinstance(page_meta, dict):
                name = page_meta.get("name")
                if isinstance(name, str):
                    page_names.append(name)
                for _ab_id, ab_meta in page_meta.get("artboards", {}).items():
                    if isinstance(ab_meta, dict):
                        ab_name = ab_meta.get("name")
                        if isinstance(ab_name, str):
                            artboard_names.append(ab_name)

        text_strings: list[str] = []
        for member in z.namelist():
            if member.startswith("pages/") and member.endswith(".json"):
                try:
                    data = json.loads(z.read(member))
                except (json.JSONDecodeError, KeyError):
                    continue
                _collect_text_strings(data, text_strings)

    return {
        "filename": p.name,
        "page_names": page_names,
        "artboard_names": artboard_names,
        "text_strings": text_strings,
    }


def extract_preview_png(p: Path) -> bytes | None:
    """Return raw PNG bytes of the .sketch's whole-file preview, or None.

    Sketch ships previews/preview.png inside the bundle. Per-page
    previews don't exist in the bundle — for those we need step 11's
    AppleScript-driven export.
    """
    with zipfile.ZipFile(p) as z:
        try:
            return z.read("previews/preview.png")
        except KeyError:
            return None


def compose_embed_input(parsed: dict, max_chars: int = EMBED_MAX_CHARS) -> str:
    """Build the canonical embed input from parse_sketch_strings's output."""
    parts: list[str] = [parsed.get("filename", "")]
    if parsed.get("page_names"):
        parts.append("Pages: " + ", ".join(parsed["page_names"]))
    if parsed.get("artboard_names"):
        parts.append("Artboards: " + ", ".join(parsed["artboard_names"]))
    if parsed.get("text_strings"):
        parts.append("Text: " + " | ".join(parsed["text_strings"]))
    return "\n".join(p for p in parts if p).strip()[:max_chars]
