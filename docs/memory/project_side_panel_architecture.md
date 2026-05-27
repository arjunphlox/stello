---
name: Stello home layout architecture (single-panel + flex masonry)
description: How PanelManager, the flex-column masonry, the JS-driven --grid-cols, and the panel transitions fit together as of PR #11 (May 2026). Read before touching index.html / app.js / style.css.
type: project
originSessionId: 451a3397-2449-463c-ae88-fa3c66dd07bd
---
Updated for the masonry + single-panel rewrite (branch `claude/youthful-noether-73aa2c`, PR #11, May 2026). Supersedes the dual-panel + column-count description from PR #2.

**Layout hierarchy**
- `.main-layout` (`display: flex; height: 100vh; overflow: hidden`) contains
  `.main-content` (flex: 1 1 auto) on the left and `.panels-container` on
  the right.
- `.main-content` is a flex column with `align-items: center`; its only
  child is `.content-inner` (no max-width — fills available width — padding 24px sides, flex-column gap 16px).
- `.content-inner` children top-to-bottom: accent-coloured `.header`,
  `.search-input`, `.active-filters`, `<main class="grid-container">`.

**PanelManager** (app.js IIFE)
- **Single panel at a time** — item panel OR tool panel, never both.
  Opening either implicitly closes the other.
- State: `slug` (open item slug or null), `tool` ('filters'|'settings'|'import'|null), `originSlug`.
  No `width`, no `userResized`, no `slugs[]`.
- Panel width is computed: `clamp(MIN=360, round(viewport*0.25), MAX=480)`.
  Published as `--panel-width` on `document.documentElement` so both
  `.panel` and `.panels-container` can read it. Updated on viewport resize via `window.resize` listener (debounced 120ms).
- Persistence: URL `?panel=slug` + localStorage `{ slug }`. Legacy keys
  (`panel1`/`panel2`/`slugs[]`/`width`/`toolWidth`) tolerated on read.
- No resize handle. localStorage stores only `slug` now.
- Public API: `init`, `open`, `close`, `focus`, `shuffle`, `openTool`,
  `closeTool`, `getOpenSlug`, `refreshAfterGridRender`, `refreshItem`,
  `state`.

**Masonry layout (FLEX, not column-count)**
- `.masonry-section { display: flex; gap: 24px }` containing N
  `.masonry-col { flex: 1 1 0; display: flex; flex-direction: column; gap: 24px }` divs.
- JS distributes cards into columns via `distributeIntoColumns(entries, colCount)`
  (greedy shortest-column-wins using `estimateCardHeight` from stored image
  dims). Same visual as column-count masonry but no WebKit flicker.
- Column count is driven by JS — `updateGridCols` watches `.main-content` width
  via ResizeObserver and sets `--grid-cols` (5/4/3/2 at >1200/≤1200/≤768/≤500).
  No `@container` queries.
- Re-distribute is debounced 650ms (after panel-slide animations) so the
  masonry-section.innerHTML rewrite doesn't visibly happen mid-transition.

**Why flex over column-count:** WebKit's column engine briefly flickered
to single-column on every panel-open / week-toggle / hover. Defensive CSS
(`will-change`, `contain: layout`, `break-inside`) helped but couldn't
eliminate the engine recompute. Flex has no such recompute.

**Card hover dim** — `filter: brightness(0.175)` directly on
`.card-thumb` / `.card-text-content` / `.card-placeholder`. No overlay
div anymore (it had a 1px sub-pixel gap at fractional column widths).
Filter applies to rendered pixels — nothing to align.

**Related-items rule**
- Triggered only on panel open (no hover-delay).
- Rule: `(same format OR same domain) AND ≥3 shared tags with weight ≥0.5`.
  See `buildRelatedIndex` in app.js.
- Updates are diff-based — only toggles `.card-focused` on cards whose
  state actually changes.

**Image dimensions pipeline**
- Every server-side image write captures `{ width, height }` from sharp
  metadata and stores them in `items.images[]` entries. Touches `webp.js`,
  `screenshots.js`, `capture.js`, `capture-bulk.js`, `enrich.js`,
  `reenrich.js`, `reprocess.js`, `item-update.js`, `upload-image.js`.
- `renderCard()` emits `<img width=W height=H>` when known.
- `scripts/backfill-image-dimensions.js` retrofits dims onto legacy rows
  (requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY env vars).
- Lazy in-app backfill runs at idle priority — `backfillImageDimensions()`
  in app.js, idempotent, handles legacy `og_image_path`-only rows by
  synthesising an `images[]` entry.

**Things that no longer exist (don't reintroduce blindly)**
- `:has(.panel) .content-inner { padding-right: 12px }` — gone.
- `column-count: var(--grid-cols)` — gone (CSS is flex now).
- `@container grid (max-width: ...)` rules — gone.
- `body.resizing`, `.resize-handle`, `.panel-entering` / `.panel-leaving` — gone.
- `card-overlay` div — gone (filter handles dim now).

**Pending follow-up:** item-detail-page comparison (the dual-panel feature
removed from the home grid). BACKLOG entry tracks this.
