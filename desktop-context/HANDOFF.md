# desktop-context — Cursor handoff

You're continuing a multi-step desktop-context indexer for Stello. Steps 1–9 are
committed on branch `claude/pedantic-snyder-6b6cd4` (fully rebased onto current
`origin/main`). **Step 9 is committed but NOT YET VERIFIED — verify before moving on.**
Steps 10–14 remain.

## Project location

- Worktree: `~/Documents/Personal Projects/Stello/.claude/worktrees/pedantic-snyder-6b6cd4`
- Branch: `claude/pedantic-snyder-6b6cd4` (keep using this — same in-flight feature; only
  switch to `cursor/desktop-context` if you start a new sub-task)
- Daemon code: `desktop-context/` (FLAT layout, NOT `src/` — see "gotchas")
- Source-of-truth plan: `~/.claude/plans/firstly-the-data-capture-optimized-biscuit.md`

## What this is

A Python LaunchAgent daemon on `127.0.0.1:8766` that surfaces "related items" cards
based on what the user is doing on their Mac right now. Inputs: a watcher folder
(`~/Downloads/Stello Watcher`), open Sketch documents, Safari tabs (with a hostname-
suffix blocklist). It uses an **existing** local MLX server (separate LaunchAgent
`com.stello.mlx` on `127.0.0.1:8765`) for embed + vision + text inference.

**Nothing leaves the Mac.** No Anthropic SDK at runtime, no telemetry.

## Progress map

| # | Status | Step |
|---|---|---|
| 1 | ✓ | Skeleton + LaunchAgent stub |
| 2 | ✓ | Config + SQLite schema |
| 3 | ✓ | MLX client + venv build |
| 4 | ✓ | Watcher folder, text/markdown indexing |
| 5 | ✓ | Image enrichment + 256px webp thumbnails |
| 6 | ✓ | PDF enrichment via pypdfium2 |
| 7 | ✓ | Sketch ZIP cheap-path indexing |
| 8 | ✓ | Open-apps + AX poll (NSWorkspace + Accessibility) |
| 9 | **committed, unverified** | Safari tabs + blocklist (JXA) |
| 10 | pending | Sketch open-doc + visible-rect math |
| 11 | pending | Dwell-gated Sketch VLM (60s + per-window 5-image cap) |
| 12 | pending | `/related` endpoint (cosine + filters + rerank) |
| 13 | pending | Frontend stub: `desktop-context.js` |
| 14 | pending | `install.sh` polish + final README |

## First three things to do

1. **Bring MLX server back up** (it was unloaded to free memory at end of last session):

    ```bash
    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.stello.mlx.plist
    curl -s http://127.0.0.1:8765/healthz   # should return ok
    ```

2. **Verify step 9 cold** (mocked tests, no live Safari needed):

    ```bash
    cd desktop-context
    .venv/bin/pytest tests/   # expect 77 passed (10 of which are step 9's mocked Safari)
    ```

3. **Live-verify Safari tab capture** (will trigger the **Automation → Safari**
   permission dialog the first time `osascript` hits Safari — approve when it pops):

    ```bash
    .venv/bin/python -m stello_context.daemon &
    open -a Safari
    sleep 5
    curl -s http://127.0.0.1:8766/context/now | python3 -m json.tool | head -40
    # safari_tabs should be populated; blocked tabs have url=null + blocked=true
    pkill -f stello_context.daemon
    ```

Then proceed to step 10 per the plan doc.

## Critical gotchas (these all caused real bugs — preserve them)

- **macOS PyObjC frontmost is stale.** `NSWorkspace.frontmostApplication()`,
  `isActive()`, and `menuBarOwningApplication()` all rely on a notification cache that
  **never updates** without an NSRunLoop in the host process. Verified by 11h of real
  app-switching producing exactly 1 activity_log row. Use **Quartz `CGWindowList`**
  for live frontmost + `NSRunningApplication.runningApplicationWithProcessIdentifier_`
  for PID → bundle. See `stello_context/context.py::frontmost_app`. **Do not
  "simplify" this back to `NSWorkspace`.**

- **Hatchling editable `.pth` bug → use FLAT layout (`stello_context/`, no `src/`).**
  The src-layout editable install writes a `.pth` file with no trailing newline so
  `site.py` silently skips it and `python -m stello_context.daemon` can't find the
  package.

- **SQLite `check_same_thread=False`.** FastAPI runs sync handlers on a threadpool.
  The daemon owns the only DB connection across threads. WAL + the single-FIFO enrich
  worker keep it safe. See `stello_context/store.py::open_db`.

- **`Path.resolve()` everywhere.** macOS `/tmp` symlinks to `/private/tmp`. FSEvents
  emits resolved paths but `os.walk` doesn't — without `.resolve()` the same file
  gets two `uniq_key` rows on every restart. See
  `stello_context/scanner.py::initial_walk` for the regression test.

- **MLX calls go through a SINGLE asyncio queue.** Don't fan out parallel embed /
  vision calls — the server itself holds an `asyncio.Lock` so you'd just create
  head-of-line blocking. See `stello_context/enrich.py::worker_loop`.

- **VLM call constraints**: long-edge ≤ 1280 px (resize at ingest, don't rely on
  the server's safety net); use `generate_structured` / `vision_structured`
  (Pydantic + retry) — the 4B VLM occasionally echoes back the JSON schema.

- **Permissions**: Accessibility is already granted to
  `~/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13`.
  Automation → Safari triggers on step 9 verification. Automation → Sketch will
  trigger on step 10 (first `osascript` hit to Sketch).

## Key files

| Path | Purpose |
|---|---|
| `stello_context/daemon.py` | FastAPI lifespan: config + DB + MLX client + enrich worker + FSEvents + context poll |
| `stello_context/config.py` | Pydantic Config; loads `~/.config/stello/desktop-context.json` |
| `stello_context/store.py` | SQLite schema (`items`, `activity_log`, `caption_cache`, `schema_meta`) |
| `stello_context/mlx_client.py` | Vendored HTTP client for MLX (embed / generate / vision + structured) |
| `stello_context/scanner.py` | watchdog Observer + initial walk |
| `stello_context/enrich.py` | Per-type enrich dispatch + single-FIFO worker |
| `stello_context/thumbnails.py` | 256px webp via Pillow, sha1-keyed cache |
| `stello_context/pdf.py` | pypdfium2 page-1 render + text extraction |
| `stello_context/sketch.py` | ZIP parse: page+artboard names from `meta.json.pagesAndArtboards`, text-layer strings via tree walk; whole-file `previews/preview.png` as thumbnail |
| `stello_context/safari.py` | JXA `osascript` tab read + suffix-match blocklist (step 9) |
| `stello_context/context.py` | NSWorkspace + AX + Safari snapshot; `ContextSnapshot` dataclass; `poll_loop` |
| `tests/test_*.py` | 77 tests — 3 live MLX round-trips, 10 mocked-Safari tests, plus a real `.sketch` smoke against `Arjun_RC&DL_A4.sketch` when present |

## Run-the-daemon incantation

```bash
cd ~/Documents/Personal\ Projects/Stello/.claude/worktrees/pedantic-snyder-6b6cd4/desktop-context

# Foreground:
.venv/bin/python -m stello_context.daemon

# Verify endpoints:
curl -s http://127.0.0.1:8766/healthz | python3 -m json.tool
curl -s http://127.0.0.1:8766/context/now | python3 -m json.tool
```

Env overrides (use temp paths during smoke):

- `STELLO_CTX_CONFIG=/tmp/cfg.json`
- `STELLO_CTX_DB=/tmp/ctx.db`
- `STELLO_CTX_THUMB_DIR=/tmp/thumbs`
- `STELLO_CTX_PORT=8766`

## Working agreement (carried over)

- Small atomic commits — one logical change per commit.
- Surface concerns; do not silently fold in unrelated fixes.
- Visual / behavioral changes require live verification before claiming done.
- Same error twice → STOP and ask, do not try a third variation.

## Steps 10–14 in one paragraph (full spec is in the plan doc)

Step 10 reads each open `.sketch` via `osascript` (path + window pixel size from
System Events), reads `user.json` per-page for `scrollOrigin` + `zoomValue`,
intersects against artboard frames in `pages/<uuid>.json` to compute the visible
set, exposes it on `/context/now`. Step 11 layers the dwell state machine (60s
stable + ≤ 5 un-enriched artboards per window) and AppleScript-driven artboard
export → `/v1/vision_structured` for caption + tags. Step 12 implements
`/related?k=10`: snapshot → activity classification (cached 10s) → embed →
NumPy cosine over the items index → hard filters (project_hint, type) → rerank
(`0.65·cosine + 0.25·recency + 0.10·source_app_match`). Step 13 adds
`desktop-context.js` at the worktree root with a localhost-only fetcher exposed
on `window.stelloDesktop`. Step 14 polishes `install.sh` to build the venv,
install the package, template the LaunchAgent plist with the right paths, and
`launchctl bootstrap` it.
