# stello-context

Local-only Mac context indexer. Runs as a LaunchAgent (`com.stello.context`) on
`127.0.0.1:8766`. Watches `~/Downloads/Stello Watcher`, introspects Sketch and
Safari, and returns related items to the Stello frontend over a localhost HTTP
API. Uses the existing MLX server at `127.0.0.1:8765` for embed/vision/text.

**Nothing leaves the Mac.** No API calls, no telemetry, no cloud. The Anthropic
SDK is intentionally absent.

## Status

V1 build in progress. Track in `~/.claude/plans/firstly-the-data-capture-optimized-biscuit.md`.
This README is a stub; full setup + troubleshooting docs land in step 14.

## Quickstart (dev)

```bash
cd desktop-context
uv venv
source .venv/bin/activate
uv pip install -e ".[dev]"

# Foreground run (Ctrl+C to stop)
python -m stello_context.daemon

# Then in another shell:
curl http://127.0.0.1:8766/healthz
```

## Install as LaunchAgent

```bash
./install/install.sh   # creates folders; later steps wire up the agent
```

## Layout

```
stello_context/
  daemon.py          entrypoint — FastAPI app, signal-safe boot
  config.py          ~/.config/stello/desktop-context.json loader (step 2)
  store.py           SQLite schema + data layer (step 2)
  mlx_client.py      HTTP client for the MLX server (step 3)
  scanner.py         FSEvents watcher + initial walk (step 4)
  enrich.py          Per-type enrichment queue (steps 4–7, 11)
  thumbnails.py      Webp generation (step 5)
  pdf.py             pypdfium2 wrapper (step 6)
  sketch.py          .sketch ZIP + AppleScript glue + visible-rect math (steps 7, 10, 11)
  safari.py          AppleScript glue + blocklist (step 9)
  context.py         NSWorkspace + AX poll (step 8)
  api.py             /related, /index/status, /context/now, /healthz (step 12)
  log.py             Structured logging helpers

install/
  com.stello.context.plist.template   LaunchAgent template
  install.sh                          Bootstrap script
```

## Permissions needed (on first run of relevant steps)

- **Accessibility** for the AX poll (step 8) — System Settings → Privacy & Security → Accessibility → add Python.
- **Automation → Safari** for tab introspection (step 9) — prompted on first `osascript`.
- **Automation → Sketch** for open-document introspection + artboard export (step 10) — prompted on first `osascript`.
