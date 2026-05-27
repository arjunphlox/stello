---
name: Radix Color theme system
description: How theme.css, ThemeManager, and accent/mode switching work. Read before touching colors, header, or theme UI.
type: project
---

**Architecture** (added PR #2, Apr 2026)
- `theme.css` — all Radix Colors values (Sand neutral + Lime/Amber/Iris accents) for light & dark modes, semantic mapping to Stello tokens, tag category colors per mode.
- `ThemeManager` in app.js — `load()`, `save()`, `apply()`, `setMode()`, `setAccent()`. Uses `stello.theme` localStorage key (`{mode, accent}`).
- Flash-prevention `<script>` in `<head>` of both index.html and detail.html reads localStorage and sets `data-theme`/`data-accent` before CSS paints.

**Key design decisions**
- Radix values are copied inline (no CDN, no npm) — works without build step.
- `--accent-contrast` is hardcoded per accent, NOT `var(--{color}-12)`. Reason: step-12 flips light↔dark with mode, but Lime-9 and Amber-9 are always bright — they always need dark text.
  - Lime: `#37401c`, Amber: `#4f3422`, Iris: `#fff`
- Header and expanded week bar use `--accent` as background, not `--text`.
- Header buttons use `color-mix(in srgb, var(--accent-contrast) N%, transparent)` for semi-transparent states on the accent bg.

**Selectors**
- `[data-theme="dark"]` / `[data-theme="light"]` — on `<html>`, controls neutral + utility vars
- `[data-accent="lime"]` / `[data-accent="amber"]` / `[data-accent="iris"]` — on `<html>`, controls accent vars
- These are orthogonal — any accent works with either mode.

**Card highlights**
- Related cards get `outline: 1px solid var(--accent)` with `outline-offset: 4px` on `.card-visual-area`.
- `syncHighlightsToOpenPanels(slugs)` is called at the end of PanelManager's `render()`.
- Hover highlights (2s delay) fall back to panel-based highlights on mouse leave.

**Future sync**: when Vercel+passkey auth lands, sync `stello.theme` JSON to/from server on login/change. Two string fields, trivially portable.
