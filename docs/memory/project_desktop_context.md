---
name: project_desktop_context
description: Stello desktop-context daemon (com.stello.context) — local Mac indexer on 127.0.0.1:8766, MLX on 8765, flat stello_context/ package, sketchtool export, CGWindowList frontmost, localhost-only frontend stub
type: project
---

# Desktop-context daemon

Shipped 2026-06-17. Full plan: `~/.claude/plans/firstly-the-data-capture-optimized-biscuit.md`.

## What it is

Second related-items source for Stello — driven by Mac context (watcher folder, Sketch artboards, Safari tabs), not Supabase tag overlap. Local SQLite + thumbnails; no cloud egress except loopback MLX.

## Key paths

- Code: `desktop-context/stello_context/` (flat layout — **not** `src/`)
- Install: `desktop-context/install/install.sh` → `com.stello.context` LaunchAgent
- Config: `~/.config/stello/desktop-context.json`
- DB: `~/Library/Application Support/Stello/desktop-context.db`
- Frontend stub: `desktop-context.js` → `window.stelloDesktop.fetchRelated(k)` (localhost only)

## Gotchas that caused real bugs

1. **NSWorkspace frontmost is stale** without NSRunLoop — use `CGWindowList` in `context.py`.
2. **Sketch background windows report 0×0** — activate Sketch for visible-rect + dwell.
3. **VLM schema echo** — Qwen3-VL-4B echoes JSON schema if using `vision_structured`; use compact `/v1/vision` + manual JSON parse in `enrich.py`.
4. **Sketch export** — `sketchtool` CLI, not AppleScript (`sketch.py`).
5. **Stale test env** — `STELLO_CTX_PORT=8768` from prior sessions makes curl to 8766 fail silently.
6. **SQLite** — `check_same_thread=False`; use `Path.resolve()` for `/tmp` symlinks on macOS.
7. **pytest** — `test_poll_loop_logs_only_on_change` hangs; run targeted tests or fix separately.

## Deferred (BACKLOG)

- E2e smoke checklist (manual)
- Cards UI (needs scoping)
- Optional `scripts/smoke-desktop-context.sh`
