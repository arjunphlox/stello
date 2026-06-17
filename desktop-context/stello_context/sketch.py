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

Stage 10 (current):
  - discover_sketch_state(): open-document discovery via JXA + visible-rect
    math from user.json scroll/zoom intersected against page artboard frames.
  - Pure helpers (parse_scroll_origin, compute_visible_canvas_rect, …) are
    unit-tested against a real .sketch sample when present.

Stage 11 will add AppleScript-driven artboard export + dwell-gated VLM.
"""
from __future__ import annotations

import json
import logging
import re
import subprocess
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

logger = logging.getLogger("stello-context.sketch")

SKETCH_BUNDLE_ID = "com.bohemiancoding.sketch3"

# JXA: enumerate open Sketch documents + window pixel sizes (System Events).
JXA_OPEN_DOCS = """
function run() {
  try {
    const Sketch = Application('Sketch');
    if (!Sketch.running()) return JSON.stringify([]);
    const windowByTitle = {};
    try {
      const se = Application('System Events');
      const proc = se.processes.byName('Sketch');
      if (proc.exists()) {
        proc.windows().forEach(function(w) {
          try {
            const title = String(w.name() || '');
            const sz = w.size();
            windowByTitle[title] = {width: sz[0], height: sz[1]};
          } catch (e) {}
        });
      }
    } catch (e) {}
    const titles = Object.keys(windowByTitle);
    const out = [];
    Sketch.documents().forEach(function(doc, idx) {
      try {
        const path = String(doc.path() || '');
        if (!path) return;
        let pageId = '', pageName = '';
        try {
          const cp = doc.currentPage();
          pageId = String(cp.id() || '');
          pageName = String(cp.name() || '');
        } catch (e) {}
        let winW = 0, winH = 0;
        try {
          const docName = String(doc.name() || '');
          if (windowByTitle[docName]) {
            winW = windowByTitle[docName].width;
            winH = windowByTitle[docName].height;
          } else if (titles.length === 1) {
            winW = windowByTitle[titles[0]].width;
            winH = windowByTitle[titles[0]].height;
          } else if (titles.length > idx) {
            winW = windowByTitle[titles[idx]].width;
            winH = windowByTitle[titles[idx]].height;
          }
        } catch (e) {}
        out.push({
          path: path,
          page_id: pageId,
          page_name: pageName,
          window_width: winW,
          window_height: winH,
        });
      } catch (e) {}
    });
    return JSON.stringify(out);
  } catch (e) {
    return JSON.stringify({error: String(e)});
  }
}
"""


@dataclass(frozen=True)
class CanvasRect:
    """Axis-aligned rectangle in Sketch canvas space."""

    x: float
    y: float
    width: float
    height: float

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


# -- visible-rect math (stage 10) --------------------------------------------


_SCROLL_ORIGIN_RE = re.compile(
    r"^\s*\{\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\}\s*$"
)


def parse_scroll_origin(raw: str) -> tuple[float, float]:
    """Parse Sketch user.json scrollOrigin strings like ``{-1363, 183}``."""
    m = _SCROLL_ORIGIN_RE.match(raw.strip())
    if not m:
        raise ValueError(f"bad scrollOrigin: {raw!r}")
    return float(m.group(1)), float(m.group(2))


def compute_visible_canvas_rect(
    scroll_origin: tuple[float, float],
    zoom: float,
    window_width: float,
    window_height: float,
) -> CanvasRect:
    """Map viewport scroll/zoom + window pixels → canvas-space visible rect."""
    if zoom <= 0:
        zoom = 1.0
    sx, sy = scroll_origin
    return CanvasRect(
        x=-sx / zoom,
        y=-sy / zoom,
        width=window_width / zoom,
        height=window_height / zoom,
    )


def intersection_area(a: CanvasRect, b: CanvasRect) -> float:
    """Intersection area of two canvas rects; 0 when disjoint."""
    x1 = max(a.x, b.x)
    y1 = max(a.y, b.y)
    x2 = min(a.x + a.width, b.x + b.width)
    y2 = min(a.y + a.height, b.y + b.height)
    if x2 <= x1 or y2 <= y1:
        return 0.0
    return (x2 - x1) * (y2 - y1)


def frame_to_rect(frame: dict | None) -> CanvasRect | None:
    if not isinstance(frame, dict):
        return None
    try:
        return CanvasRect(
            x=float(frame["x"]),
            y=float(frame["y"]),
            width=float(frame["width"]),
            height=float(frame["height"]),
        )
    except (KeyError, TypeError, ValueError):
        return None


def read_user_json(sketch_path: Path) -> dict:
    with zipfile.ZipFile(sketch_path) as z:
        try:
            return json.loads(z.read("user.json"))
        except KeyError:
            return {}


def infer_page_uuid_from_user_json(user_json: dict) -> str | None:
    """Fallback when AppleScript can't return current page — the page UUID
    key in user.json that carries scroll/zoom state is usually the one
    the user last viewed."""
    found: str | None = None
    for key, val in user_json.items():
        if key == "document" or not isinstance(val, dict):
            continue
        if "scrollOrigin" in val:
            found = key
    return found


def page_viewport(
    user_json: dict, page_uuid: str
) -> tuple[tuple[float, float], float] | None:
    page_state = user_json.get(page_uuid)
    if not isinstance(page_state, dict):
        return None
    raw = page_state.get("scrollOrigin")
    if not isinstance(raw, str):
        return None
    try:
        origin = parse_scroll_origin(raw)
    except ValueError:
        return None
    zoom = float(page_state.get("zoomValue", 1) or 1)
    return origin, zoom


def extract_page_artboards(sketch_path: Path, page_uuid: str) -> list[dict]:
    """Top-level artboard layers on a page with canvas frames."""
    member = f"pages/{page_uuid}.json"
    with zipfile.ZipFile(sketch_path) as z:
        try:
            page = json.loads(z.read(member))
        except KeyError:
            return []
    out: list[dict] = []
    for layer in page.get("layers", []):
        if layer.get("_class") != "artboard":
            continue
        ab_id = layer.get("do_objectID")
        frame = frame_to_rect(layer.get("frame"))
        if ab_id and frame is not None:
            out.append(
                {
                    "id": str(ab_id),
                    "name": str(layer.get("name") or ""),
                    "frame": frame,
                }
            )
    return out


def compute_visible_artboards(
    sketch_path: Path,
    page_uuid: str,
    window_width: int,
    window_height: int,
    scroll_origin: tuple[float, float],
    zoom: float,
) -> list[dict]:
    """Artboards intersecting the visible canvas rect, largest first."""
    visible = compute_visible_canvas_rect(
        scroll_origin, zoom, window_width, window_height
    )
    results: list[dict] = []
    for ab in extract_page_artboards(sketch_path, page_uuid):
        area = intersection_area(visible, ab["frame"])
        if area > 0:
            results.append(
                {
                    "id": ab["id"],
                    "name": ab["name"],
                    "intersection_area": area,
                }
            )
    results.sort(key=lambda row: row["intersection_area"], reverse=True)
    return results


def _run_jxa(script: str, timeout_s: float = 8.0) -> str:
    proc = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        capture_output=True,
        text=True,
        timeout=timeout_s,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"osascript exit {proc.returncode}: {proc.stderr.strip()!r}"
        )
    return proc.stdout.strip()


def get_open_documents(timeout_s: float = 8.0) -> list[dict]:
    """Live open Sketch documents via JXA.

    Returns [{path, page_id, page_name, window_width, window_height}, …].
    Empty when Sketch isn't running or Automation permission is denied.
    """
    try:
        raw = _run_jxa(JXA_OPEN_DOCS, timeout_s=timeout_s)
    except subprocess.TimeoutExpired:
        logger.warning("sketch: osascript timed out after %.1fs", timeout_s)
        return []
    except FileNotFoundError:
        logger.warning("sketch: osascript not on PATH")
        return []
    except RuntimeError as e:
        logger.warning("sketch: %s", e)
        return []

    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        logger.warning("sketch: non-JSON osascript output: %r", raw[:200])
        return []
    if isinstance(data, dict) and "error" in data:
        logger.warning("sketch: JXA error: %s", data["error"])
        return []
    if not isinstance(data, list):
        return []
    return data


def build_document_state(doc: dict) -> dict | None:
    """Merge a JXA document row with on-disk user.json + page artboards."""
    path = str(doc.get("path") or "")
    if not path:
        return None
    sketch_path = Path(path).resolve()
    if not sketch_path.is_file():
        logger.debug("sketch: open doc path missing on disk: %s", path)
        return None

    page_uuid = str(doc.get("page_id") or "") or None
    user_json = read_user_json(sketch_path)
    if not page_uuid:
        page_uuid = infer_page_uuid_from_user_json(user_json)

    window_w = int(doc.get("window_width") or 0)
    window_h = int(doc.get("window_height") or 0)

    state: dict[str, Any] = {
        "path": str(sketch_path),
        "page_id": page_uuid,
        "page_name": doc.get("page_name") or None,
        "window_width": window_w,
        "window_height": window_h,
        "zoom": None,
        "scroll_origin": None,
        "visible_artboards": [],
    }

    if not page_uuid or window_w <= 0 or window_h <= 0:
        return state

    viewport = page_viewport(user_json, page_uuid)
    if viewport is None:
        return state

    origin, zoom = viewport
    state["zoom"] = zoom
    state["scroll_origin"] = [origin[0], origin[1]]
    state["visible_artboards"] = compute_visible_artboards(
        sketch_path, page_uuid, window_w, window_h, origin, zoom
    )
    return state


def discover_sketch_state() -> list[dict]:
    """Full Sketch snapshot for /context/now — one entry per open document."""
    return [
        s
        for doc in get_open_documents()
        if (s := build_document_state(doc)) is not None
    ]
