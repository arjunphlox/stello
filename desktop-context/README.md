# stello-context

Local-only Mac context indexer for [Stello](https://github.com/arjunphlox/Stello). Runs as a
LaunchAgent (`com.stello.context`) on `127.0.0.1:8766`. Watches
`~/Downloads/Stello Watcher`, introspects Sketch and Safari, indexes into local SQLite, and
returns related items to the Stello frontend over a localhost HTTP API. Uses the existing MLX
server at `127.0.0.1:8765` (`com.stello.mlx`) for embed, vision, and text inference.

**Nothing leaves the Mac.** No API calls, no telemetry, no cloud. The Anthropic SDK is
intentionally absent.

## Prerequisites

| Requirement | Notes |
|---|---|
| macOS | Accessibility + Automation APIs |
| Python 3.13+ | `uv` manages the venv |
| [uv](https://github.com/astral-sh/uv) | `brew install uv` |
| MLX server | Separate LaunchAgent `com.stello.mlx` on port 8765 (see **MLX Stack** repo) |
| Sketch (optional) | Open-document + artboard VLM enrichment |
| Safari (optional) | Tab introspection with hostname blocklist |

## Install (LaunchAgent)

From the repo checkout:

```bash
cd desktop-context
./install/install.sh
```

This is idempotent — safe to re-run after pulling updates (rebuilds the venv, reinstalls the
package, reloads the agent).

What it creates:

| Path | Purpose |
|---|---|
| `~/Downloads/Stello Watcher/` | Drop folder for PNG, PDF, `.sketch`, `.md`, … |
| `~/.config/stello/desktop-context.json` | Config (seeded once; never overwritten) |
| `~/Library/Application Support/Stello/desktop-context.db` | SQLite index + embeddings |
| `~/Library/Application Support/Stello/desktop-context/thumbs/` | 256px webp thumbnails |
| `~/Library/Application Support/Stello/logs/` | LaunchAgent stdout/stderr |
| `~/Library/LaunchAgents/com.stello.context.plist` | LaunchAgent definition |

Verify:

```bash
curl -s http://127.0.0.1:8766/healthz | python3 -m json.tool
curl -s 'http://127.0.0.1:8766/related?k=5' | python3 -m json.tool
```

### Permissions

macOS prompts on first use — approve each in **System Settings → Privacy & Security**:

- **Accessibility** — frontmost-app and window polling (`context.py`)
- **Automation → Safari** — open-tab introspection (`safari.py`)
- **Automation → Sketch** — open-document discovery + artboard export (`sketch.py`)

If Sketch visible-artboard dwell never fires, **activate Sketch** (bring it to the foreground).
Background Sketch windows report 0×0 size via System Events until the app is frontmost.

### Manage the agent

```bash
# Stop
launchctl bootout gui/$(id -u)/com.stello.context

# Start (after install or manual plist edit)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.stello.context.plist

# Logs
tail -f ~/Library/Application\ Support/Stello/logs/stello-context.err.log
```

## Dev quickstart (foreground)

Useful when iterating on the daemon without reloading the LaunchAgent:

```bash
cd desktop-context
uv venv
source .venv/bin/activate
uv pip install -e ".[dev]"

# Unset any stale test env from prior sessions
unset STELLO_CTX_PORT STELLO_CTX_CONFIG STELLO_CTX_DB STELLO_CTX_THUMB_DIR

python -m stello_context.daemon
# Ctrl+C to stop
```

In another shell:

```bash
curl http://127.0.0.1:8766/healthz
curl http://127.0.0.1:8766/context/now | python3 -m json.tool
curl 'http://127.0.0.1:8766/related?k=5' | python3 -m json.tool
```

Tests (mocked; no live Safari/Sketch/MLX required for most):

```bash
uv pip install -e ".[dev]"
pytest tests/ -q
```

## Frontend bridge

`desktop-context.js` at the repo root exposes:

```javascript
await stelloDesktop.fetchRelated(5)
```

- Returns JSON from `/related` when the page is loaded from `localhost` or `127.0.0.1`.
- Returns `null` in production (no daemon contact).
- Test with `npm run dev` + daemon running + browser DevTools console.

## HTTP API

All endpoints bind to loopback only (`127.0.0.1:8766`).

| Endpoint | Description |
|---|---|
| `GET /healthz` | Daemon + nested MLX health |
| `GET /context/now` | Live snapshot: frontmost app, Safari tabs, Sketch state |
| `GET /index/status` | Item counts by status/kind |
| `GET /config` | Effective config (blocklist redacted in response) |
| `GET /related?k=10&debug=0` | Activity-classified cosine retrieval + rerank |

`/related` response shape:

```json
{
  "k": 10,
  "count": 3,
  "activity": {
    "activity_type": "design",
    "topic": "…",
    "entities": ["…"],
    "project_hint": "…"
  },
  "items": [
    {
      "uniq_key": "…",
      "kind": "sketch_artboard",
      "type": "image",
      "title": "…",
      "score": 0.72,
      "vlm_caption": "…",
      "tags": ["…"],
      "thumb_data_url": "data:image/webp;base64,…"
    }
  ]
}
```

Rerank weights: `0.65·cosine + 0.25·recency + 0.10·source_app_match`.

## How indexing works

1. **Watcher folder** — FSEvents on `~/Downloads/Stello Watcher`. Text/markdown embed
   immediately; images/PDFs get cheap-path metadata + thumbnails; `.sketch` files parse page/
   artboard names from the ZIP bundle.
2. **Safari tabs** — All open tabs (both windows). Blocklisted hostnames (banking, Stello
   itself, localhost) are counted but never embedded, logged, or returned.
3. **Sketch open docs** — All open `.sketch` files. Visible artboards computed from
   `user.json` scroll/zoom intersected with artboard frames.
4. **Dwell-gated VLM** — When visible artboards stay stable for `dwell_window_s` (default 60s),
   up to `vlm_images_per_window` (default 5) un-captioned artboards per window are exported
   via `sketchtool` and captioned through the MLX vision endpoint.

Enrichment runs through a single FIFO asyncio queue so MLX inference never contends with itself.

## Config

`~/.config/stello/desktop-context.json` — edit and restart the daemon to pick up changes
(hot-reload not implemented in V1).

Key fields:

| Field | Default | Notes |
|---|---|---|
| `watched_folders` | `["~/Downloads/Stello Watcher"]` | One or more paths |
| `dwell_window_s` | `60` | Sketch VLM dwell threshold |
| `vlm_images_per_window` | `5` | Cap per Sketch window per dwell tick |
| `safari_blocklist` | banking + Stello hosts | Suffix match, case-insensitive |
| `poll_interval_s` | `2` | Context poll cadence |

Override paths via env (used by tests; LaunchAgent uses defaults):

- `STELLO_CTX_CONFIG` — config file path
- `STELLO_CTX_DB` — SQLite path
- `STELLO_CTX_THUMB_DIR` — thumbnail directory
- `STELLO_CTX_HOST` / `STELLO_CTX_PORT` — bind address

## Troubleshooting

### Daemon not responding on 8766

```bash
launchctl print gui/$(id -u)/com.stello.context
tail -20 ~/Library/Application\ Support/Stello/logs/stello-context.err.log
```

Common causes: stale `STELLO_CTX_PORT` in your shell (test sessions sometimes set 8768),
venv not built, or Python crash on import (check stderr log).

### MLX enrichment stalled

```bash
curl http://127.0.0.1:8765/healthz
launchctl print gui/$(id -u)/com.stello.mlx
```

The context daemon queues embed/vision work but cannot proceed without MLX. If the MLX venv
symlink is broken (`.venv` → `.venv.nosync`), fix it in the MLX Stack directory and reload
`com.stello.mlx`.

### `/related` returns empty items

Normal on a fresh install — drop files into the watcher folder and wait a few seconds for
cheap-path embed. For Sketch artboard captions, park on visible artboards for 60s with Sketch
in the foreground.

### Safari tabs empty

Approve **Automation → Safari** when prompted. Open Safari before curling `/context/now`.

### Sketch `visible_artboards` empty

Sketch must be running with at least one document open, and ideally frontmost so window
dimensions are non-zero.

## Layout

```
desktop-context/
  pyproject.toml
  README.md
  stello_context/          # flat package (NOT src/ — hatchling .pth quirk)
    daemon.py              # FastAPI entrypoint + lifespan
    config.py              # ~/.config/stello/desktop-context.json
    store.py               # SQLite schema + data layer
    mlx_client.py          # HTTP client for MLX server
    scanner.py             # FSEvents watcher + initial walk
    enrich.py              # FIFO enrich queue + per-type handlers
    thumbnails.py          # 256px webp + VLM resize
    pdf.py                 # pypdfium2 wrapper
    sketch.py              # .sketch ZIP + JXA + visible-rect + sketchtool export
    sketch_dwell.py        # Dwell state machine for artboard VLM
    safari.py              # JXA tab introspection + blocklist
    context.py             # CGWindowList + AX poll
    related.py             # /related pipeline
  install/
    com.stello.context.plist.template
    install.sh
  tests/
```

## End-to-end smoke

After install, with MLX running:

1. Drop 3 PNGs + one `.md` into `~/Downloads/Stello Watcher`. Wait ~10s.
2. Open Sketch, scroll to an area with 2 artboards, keep Sketch frontmost for 60s.
3. Open Safari: Tailwind docs, a GitHub repo, `chase.com`, `stello.arjunphlox.com`.
4. From `localhost` Stello DevTools: `await stelloDesktop.fetchRelated(10)`.

Expected: Sketch artboards with captions near the top; UI/typography PNGs ranked high; hike
photo lower (project mismatch); blocklisted tabs absent from debug payload.

## Related

- Stello frontend stub: `../desktop-context.js`
- MLX inference server: **MLX Stack** repo (`com.stello.mlx`, port 8765)
- Architecture note in repo root `CLAUDE.md` under **Desktop context**
