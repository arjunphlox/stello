---
name: Capture pipeline — capture → curation panel → 3-phase enrichment
description: Stello's capture flow as of PR #8 (Apr 2026) — capture opens the Item Panel immediately, enrichment streams candidates + screenshots into the same panel, user curates which images/snippets/reasons to keep
type: project
originSessionId: 74a39846-74af-48ec-bd9d-770db4733db6
---
The capture pipeline landed a big shape change in PR #8: the inline "why did you save this?" question card is gone. Adding a URL now opens the side Item Panel immediately and enrichment streams suggested images, text snippets, reasons, and page screenshots into that same panel. Data model grew three JSONB columns plus a new enrichment status.

## Pipeline phases (`enrichment_status` column drives client polling)

- `pending` — back-compat default for very old rows
- `text_done` — OG fetched, rule tags applied; capture returns to the client here
- `vision_done` — vision tags (color/style/mood) merged
- `candidates_done` — image candidates + snippet candidates + suggested reasons written to `enrichment_candidates`; terminal
- `error` — permanent failure, stops retry loops

The CHECK constraint on this column lives at the bottom of `scripts/schema.sql` as an idempotent ALTER block — safe to re-run.

## Data columns added in PR #8

- `items.images JSONB DEFAULT '[]'` — `[{path, label?, source: 'og'|'extracted'|'manual'|'screenshot', is_primary}]`. Legacy `og_image_path` is kept as a mirror of whichever entry has `is_primary: true`.
- `items.snippets JSONB DEFAULT '[]'` — `[{text, source: 'extracted'|'manual', added_at}]`. These are user-*selected* snippets. `body_markdown`'s `## Key Snippets` section is rebuilt from this array on every `/api/item-update` call.
- `items.enrichment_candidates JSONB DEFAULT '{}'` — `{images: [{path, label?}], snippets: [text], reasons: [kebab-case]}`. Transient bag the user picks from; entries get removed as they're promoted.

## Rule-based enrichment still in `api/_lib/enrich-rules.js`

Unchanged from PR #6: `generateTagsFromMetadata()` in `api/_lib/supabase.js` is the single entry point. Emits up to 12 tags sorted by weight desc. Runs synchronously at capture time.

## `/api/enrich` now has two phases in one invocation

1. **Vision**: reads `og_image_path` → Claude Sonnet 4.6 vision → merges color/style/mood tags. Sets `enrichment_status = 'vision_done'`.
2. **Candidates**: fetches full page HTML via `fetchPageHtml` (up to 500KB), harvests up to 5 `<img>` candidates through `extractImageUrls` + `harvestImageCandidates` (filters: dimensions ≥ 100px, path heuristics against icons/pixels), and asks Claude for 3–5 snippet quotes + 2–3 why-saved reason suggestions with `CANDIDATES_PROMPT`. Writes `enrichment_candidates` + sets status to `candidates_done`.

Candidate images are stored at `{user_id}/{slug}/candidate-{n}.webp`. See the WebP normalization note below.

## `/api/reenrich` is the user-triggered full redo

Three-dot footer menu → Enrich. Body: `{slug}`. Does:

1. Re-fetch OG metadata via `fetchOGMetadata`, backfill missing title/summary/og_image_path. Non-vision, non-intent tags are regenerated fresh; intent + vision tags are preserved.
2. Capture full-page screenshots at widths `[1440, 640, 360]` via `captureScreenshots` (puppeteer-core + @sparticuz/chromium). Upload as `{user_id}/{slug}/screenshot-{w}w.webp`. Push entries onto `images[]` with `source: 'screenshot'` and `label: 'Screenshot — {w}w'`. Re-enriching replaces entries of the same width instead of stacking duplicates, preserving `is_primary`.
3. Reset `enrichment_status='text_done'` + clear `enrichment_candidates`, then fire `/api/enrich` fire-and-forget.

**Screenshots require a Chromium binary.** On Vercel the @sparticuz/chromium package provides one; on macOS dev without Chrome installed, `launchBrowser` returns null and `captureScreenshots` returns `[]` — reenrich succeeds with zero screenshots. See `reference_vercel_puppeteer_limits.md`.

## WebP normalization at ingest (PR #8)

Every image write funnels through `api/_lib/webp.js` (`toWebp` / `ensureWebp`, sharp-backed). Paths:
- `downloadImage` in `api/_lib/supabase.js` — now always returns `{buffer, ext: '.webp', mime: 'image/webp'}`. Lazy-requires `./webp` to keep modules that only need OG fetch lighter.
- `/api/item-update` manual_image_upload — calls `ensureWebp` (fast path when input is already WebP).
- Screenshots — puppeteer emits WebP directly via `{type: 'webp', quality: 78}`.

All new paths end in `.webp`. Existing legacy `og-image.png` / `og-image.jpg` files are left alone — new captures go `og-image.webp`.

## `/api/item-update` is the single curation mutation endpoint

Replaces the narrower `/api/review`. Accepts deltas:
- `primary_image_path` — set cover
- `add_image_paths[]` — promote candidate / screenshot into `images[]` (silent on cover)
- `remove_image_paths[]` — drop from `images[]` AND delete from storage (best-effort; non-blocking on failure)
- `new_snippets[]`, `removed_snippet_ids[]` — mutate `snippets[]`, rebuild `## Key Snippets` section of `body_markdown`
- `why_saved[]`, `what_works` — commit intent tags + `## What Makes It Work` section. Any presence of `why_saved` (even `[]`) flips `needs_review` to false so the capture form stops appearing.
- `manual_image_upload: {base64, mime}` — WebP-convert + upload + push onto `images[]` with `is_primary: images.length === 0`

Response echoes the updated shape so the client can merge into `itemsBySlug` without a round-trip refetch.

## `/api/item-delete` — destructive path

POST with `{slug}`. Lists the item's storage folder (`{user_id}/{slug}/`), batch-removes all files, then deletes the row. Storage errors logged but non-blocking. Frontend surfaces via the footer three-dot menu with a two-step `data-step="0" → "1"` confirm on the Delete button (resets on menu close / Escape).

## Client flow (`app.js`)

- `captureURL` / `captureImage` / `captureText` / `processResults` all call `enqueueForCuration(slug)` instead of inserting a question card. The queue opens panels sequentially — close one, next slides in.
- `PanelManager.open(slug, {fromCapture:true})` + `pollForEnrichment(slug)` drives live updates.
- `pollForEnrichment` terminates on `candidates_done` / `error` (not `vision_done` anymore). `maxAttempts` bumped to 14 (~42s) to cover the extra Claude call + screenshot latency.
- `PanelManager.refreshItem(slug)` is **diff-aware** — slider rebuilds always, capture form only renders/removes based on `needs_review`, snippet list rebuilds but preserves the in-progress "add snippet" textarea, markdown body lazy-loaded.

## Cover / preview decoupling

Slider state = two independent things:
- `is-cover` — server truth (`images[*].is_primary`)
- `is-active` — client-only (which thumb is in the main area)

Single thumb click swaps preview only. "Set as cover" pill (crosshair icon) is the *only* way to change cover. Re-clicking an already-active thumb does nothing. Cover-dot color flips black/white by image luminance (Rec. 601 luma from a 16×16 canvas sample, cached by URL).

## How to apply

- "Why doesn't my panel show the question form?" → `needs_review=false`. Either the item was already curated (Save/Skip clicked) or was captured before PR #8.
- "Screenshots missing in dev" → no local Chrome. Set `PUPPETEER_EXECUTABLE_PATH` or install Chrome; otherwise enrich silently skips them.
- "Storage orphans after image removal" → `item-update`'s storage cleanup is best-effort; a storage error doesn't block the row update. Clean up periodically if it matters.
- Every insert path sets `enrichment_status='text_done'` — if you add a new insert site, do the same or the poller will never terminate.
- DO NOT fire `/api/review` from new code — it's legacy; `/api/item-update` is the replacement.
