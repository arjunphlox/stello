# Stello

Personal knowledge base — a rich item analysis and discovery tool with weighted tags, masonry grid UI, and content organization.

## AI Coding Workflow

This repo follows Arjun's AI coding workflow. See the full spec: https://github.com/arjunphlox/arjun-ai-gems/blob/main/workflows/ai-workflow-orchestration.md

**Cursor Agentic Desktop is the primary harness.** Opus 4.8 *in Cursor* is the planning/thinking/orchestration brain; Composer 2.5 *in Cursor* executes (single sessions, multi-sessions, sub-agents). For small-to-medium, high-clarity tasks, Composer plans *and* executes directly (no Opus hop).

**Claude Code is occasional** — only for primitives that live only there: fan-out Dynamic Workflows (Agent Spawns) and mobile capture (iOS / Remote Control). It is not the default tool or brain.

**Model routing (delegate by task type — parent plans/orchestrates, sub-agents execute):**
- **Composer 2.5** — default coding: well-specified edits, boilerplate, mechanical refactors, codemods, fast iterative builds. Cheapest + most token-efficient.
- **Sonnet 5** — mid-complexity: multi-file features, non-trivial refactors, code review, test authoring, moderate debugging, agentic tool-use where Composer is too shallow. Balanced quality/cost.
- **Opus 4.8** — hard/risky: architecture, ambiguous or high-blast-radius changes, deep debugging, planning + orchestration, and all non-coding latent work. Highest accuracy/thinking; reserve.
- **GPT-5.5** — gated: 1M-token single-doc reasoning or native Codex/ChatGPT computer-use.
- **Fan-out/swarm** — parallel-safe, many-independent-unit work → hand off a paste-ready **Claude Code Dynamic Workflow** prompt; parent only plans + coordinates.

For any non-trivial task, delegate execution to the right-tier sub-agent (Task tool) rather than doing everything inline; escalate a tier on stalls/growing blast radius, de-escalate when it turns mechanical. See gems memory [`subagent-model-routing`](https://github.com/arjunphlox/arjun-ai-gems/blob/main/docs/memory/subagent-model-routing.md).

**Branch prefixes** (app-based, keeps parallel work from colliding):
- `cursor/*` — Cursor sessions
- `claude/*` — Claude sessions
- `feature/*`, `fix/*` — user-driven or mixed

**BACKLOG schema:** `| Task | Tool | Platform | Model | Status |` — every task gets tool / platform / reasoning-tier classified at capture time. Use `/to-do` to add tasks; it auto-classifies.

## Memory

Two layers:

- **Project-scoped, committed:** [`docs/memory/MEMORY.md`](docs/memory/MEMORY.md) — the portable, version-controlled contract any agent (Claude Code or Cursor) reads at session start and appends to. Project-scoped lessons only (`type: project`). `AGENTS.md` points here.
- **Account-level, not committed:** `~/.claude/projects/-Users-arjunphlox-Documents-Personal-Projects-Stello/memory/` — cross-project / personal / workflow prefs (`type: feedback | user | reference`). Auto-loaded by Claude Code; stays out of the repo. Backfill project-scoped entries with `arjun-ai-gems/scripts/sync-project-memory.sh`.

## Dev Commands

- `npm run dev` — builds `dist/` (asset allowlist) then runs `wrangler dev` (local Worker + static assets). Loads env from `.env.local` (copy `.env.example`).
- `npm run dev:remote` — `wrangler dev --remote` against the real R2 + Images bindings; needed to exercise image conversion/serving locally.
- `npm run deploy` — `wrangler deploy` to `stello.arjunphlox.workers.dev`. Secrets set via `wrangler secret put` (not in the repo).
- `python3 -m http.server 8080` — static preview only (no auth, no API — useful for CSS tweaks)
- `node scripts/verify-supabase.js` — check schema + RLS + storage bucket
- `node scripts/sync-local.js` — back up Supabase items to a local `_items/` mirror

## Architecture

Vanilla HTML/CSS/JS frontend, Supabase for auth + data (Postgres + RLS), a single Cloudflare Worker (Hono) for item capture/enrichment + image serving, and R2 for image bytes. Minimal build step (asset allowlist copy only, no framework).

- **Frontend**: `index.html` (masonry grid), `detail.html` (item detail view), `app.js` (client logic), `style.css`, `supabase-client.js` (auth + session helpers).
- **Worker**: one Hono Worker (`src/index.js`) serves the static frontend (`dist/`) + all `/api/*` routes (`src/routes/*`) + `/img/*` R2 image serving + a daily Cron Trigger. Endpoints ported from the old Vercel fns via `src/lib/adapter.js`. Image bytes live in R2 (`src/lib/storage.js`), served back at `/img/<key>` (zero egress); WebP conversion via the CF Images binding (`src/lib/images.js`). All auth-gated via `src/lib/supabase.js`.
- **Data**: Items in Supabase `items` table, per-user, RLS-scoped. Schema in `scripts/schema.sql`. Local `_items/` + `index.json` are backup mirrors written by `scripts/sync-local.js`.
- **Config**: Per-user Anthropic keys in `user_settings`. `config.json` is legacy and gitignored.
- **Desktop context (local Mac only)**: `desktop-context/` is a Python LaunchAgent (`com.stello.context`) on `127.0.0.1:8766` — watches `~/Downloads/Stello Watcher`, introspects Sketch + Safari, indexes into local SQLite, and serves `/related`. The frontend stub `desktop-context.js` calls it only when the page is loaded from `localhost` or `127.0.0.1` (`window.stelloDesktop.fetchRelated(k)`); production deploys never contact the daemon.

## Key Files

| File | Purpose |
|---|---|
| `index.html` | Main grid view with search, tag filtering, import modal |
| `detail.html` | Item detail page |
| `app.js` | All frontend logic — filtering, masonry layout, tag system, related items index |
| `desktop-context.js` | Localhost-only bridge to the desktop-context daemon (`window.stelloDesktop.fetchRelated`) |
| `style.css` | All styles |
| `supabase-client.js` | Client-side auth + session helpers |
| `src/index.js` | Hono Worker entry — `/api/*` routes, `/img/*` R2 serving, daily cron |
| `src/routes/*.js` | Ported endpoint handlers (capture, enrich, upload-image, …) |
| `src/lib/*.js` | Shared: `supabase` (auth + OG/tag helpers), `images` (CF Images→WebP), `storage` (R2), `adapter` (req/res shim) |
| `wrangler.jsonc` | Worker config — assets, R2 + Images bindings, cron trigger |
| `scripts/schema.sql` | Supabase schema + RLS policies |
| `index.json` | Local backup mirror (regenerated by sync-local.js) |
| `config.json` | Legacy API key config (gitignored) — per-user keys now live in `user_settings` |

## Tag System

Items have weighted tags across categories: `format`, `domain`, `style`, `subject`, `tool`, `location`, `mood`, `color`. The app builds a `relatedIndex` mapping each item to related items by shared tags.

## Content Structure

Items stored as markdown files in `_items/` directory with YAML frontmatter metadata. Indexed in `index.json`. Topic collections live under `cosmos/` as `.md` files and themed sub-directories (e.g., `cosmos/Figma.md`, `cosmos/Typography/`) — content only, not consumed by the app.

## Maintenance Scripts

- `python3 scripts/link_check.py run` — check for dead links (reads the local `_items/` backup mirror; every 7 days)
- `python3 scripts/refetch.py run` — retry image fetching for items without images (reads the local `_items/` backup mirror)
- Archived: `scripts/archive/analyze.py`, `scripts/archive/enrich.py`, `scripts/archive/vision_enrich.py` — superseded by `src/routes/capture.js` + `src/routes/enrich.js`; enrichment now happens at capture time in the Worker flow

## Active Work
- [ ] **Desktop-context follow-ups** — e2e smoke (BACKLOG), cards UI scoping (BACKLOG). V1 pipeline shipped 2026-06-17.
- [~] **Native Apple app** (`apple/Stello`) — foundations shipped (Sprints 0-2 + refinement): local-first SwiftData+CloudKit, on-device Foundation Models enrichment, capture + Share Extension, masonry/weeks/search/filters/detail/themes, web-faithful macOS chrome. Refinement ongoing; data migration (Sprint 3) + real-device AI verification pending.
- [x] **Native quick-wins sprint** — SHIPPED (PR #30, 2026-07-06): revisit tracking, why-saved→intent facet, awaiting-review strip, search-over-everything, deterministic PageClassifier at capture. Built by Cursor/Composer, review-fixed by Claude Code (Opus orchestrator + Sonnet 5 sub-agents, `docs/plans/pr30-fix-round.md`) — 8/9 review findings closed, 1 acceptable partial; residual minors in BACKLOG. Next from the possibilities analysis: kind-dispatched AI enrichment + typed Highlights (BACKLOG, gated on real-device AFM verification).

## Decisions Log
- 2026-06-26 · Native Apple app under `apple/` (SwiftUI multiplatform iOS/iPadOS/macOS 27, local-first SwiftData+CloudKit, on-device AFM 3, no backend) · matures Stello to local-first/privacy/Apple-native per PRD; coexists with web (web NOT sunset until explicit OK)
- 2026-06-26 · Native build harness = XcodeGen (`apple/Stello/project.yml` source of truth) + xcodebuild on iOS 27 sim (unsigned) · Xcode GUI target/capability/signing too painful; text project is agent-editable
- 2026-06-26 · Native build model routing: Composer 2.5 executes building; Opus only orchestrates/reviews · Opus-built passes caused UI drift
- 2026-06-26 · macOS header: native window controls via transparent fullSizeContentView titlebar, robustly repositioned ~12pt inset on a glass-amber inset card (Sketch pattern — float native, never reposition-and-lose) · fragile button-moving kept dropping them
- 2026-06-26 · SwiftData+CloudKit: dedupe seeds by slug + idempotent upsert; broken ItemImage shell rows (isPrimary, externalStorage nil) win cover selection → purge + prefer renderable covers · editing SeedData alone never migrates persisted/CloudKit rows
- 2026-06-17 · Desktop-context V1 pipeline shipped · Python LaunchAgent `com.stello.context` on `127.0.0.1:8766` watches `~/Downloads/Stello Watcher`, introspects Sketch + Safari, indexes to local SQLite, serves `/related` via MLX on `8765`; frontend stub `desktop-context.js` is localhost-only. Cards UI deferred. Sketch export via sketchtool; VLM uses compact vision prompt (not structured — Qwen3-VL-4B schema-echo); CGWindowList for frontmost app
- 2026-06-15 · Server-side enrichment drain · enrichment healing was frontend-only (`backfillEnrichment`, concurrency 2), so a deep `text_done` queue re-fetched OG every app load. Extracted pure cores `enrichItem(env,client,item,apiKey,userId)` from `enrich.js` + `reprocessItem(env,client,item,userId)` from `reprocess.js` (handlers now just auth+fetch+delegate; signatures unchanged), and added `drainEnrichment(env,{limit})` run from the daily cron (`limit:20` backstop) + a guarded `POST /api/cron/drain-enrichment` (Bearer = `SUPABASE_SERVICE_ROLE_KEY`, no new secret). Pilot finding: the old tail is mostly link-rotted images (→`candidates_done`/`error`, ~5% reach `vision_done`) and slow (OG-fetch timeouts); the synchronous manual trigger must stay ≤~25/call (cron uses `waitUntil`, not time-bound) (PR #22)
- 2026-06-14 · Production vision enrichment had been silently dead since the CF migration · the `ANTHROPIC_API_KEY` Worker secret was never set (and `user_settings` is empty), so `getApiKey()` returned null → `enrich.js` skipped the `if (og_image_path && anthropic)` vision block, stranding items at `text_done`/`error`. Set the secret via `wrangler secret put`; vision resumed (vision_done climbing). This — not the recovery script — was the true root cause behind the 379 errored + 676 stuck-`text_done` items (PR #21)
- 2026-06-14 · Ran `recover-errored-items.js --apply` to reset all 379 errored-with-image items `error`→`text_done` so the frontend backfill drip re-arms them (backfill explicitly gives up on `error`) · error count → 0. Healing is frontend-driven at concurrency 2, so the ~970 `text_done` drain to `vision_done`/`candidates_done` over subsequent app loads, not instantly. Follow-up candidate: a cron/server-side drain to avoid the per-load OG re-fetch churn while the queue is deep (PR #21)
- 2026-06-14 · Legacy-key rotation step 1 · swapped the exposed-era legacy anon JWT for the new-scheme `sb_publishable_*` key in the 3 places it shipped (frontend `supabase-client.js` fallback, Worker `SUPABASE_ANON_KEY` var in `wrangler.jsonc`, `.env.example`). Var name kept as `SUPABASE_ANON_KEY` to avoid churning every `src/lib/supabase.js` call site — value-only change. Remaining manual steps post-deploy: `wrangler secret put SUPABASE_SERVICE_ROLE_KEY`=`sb_secret_*`, then disable legacy JWT keys in the Supabase dashboard to kill the previously-exposed `service_role` JWT (PR #21)
- 2026-06-13 · Grid "blinking" during enrichment was `pollForEnrichment` replacing each polled card's `outerHTML` every ~3s (re-creating its `<img>` + flipping `idx=0` placeholder hues) · added a content signature `cardRenderSig` → `data-render-sig`; the poll + backfill drip only replace the card DOM when the sig changes (`refreshItem` stays unconditional, already diff-aware) (PR #19)
- 2026-06-13 · `reprocess` caps dead-og:image retries · a present-but-undownloadable og:image (e.g. a `todo.png` placeholder) stayed `text_done` = retryable → re-fetched every backfill load; now terminal `candidates_done` after the 2nd consecutive `image-download-failed` (PR #19)
- 2026-06-13 · Password-recovery links silently auto-logged-in instead of showing the set-password form · Supabase recovery emails land on the Site URL (`/`) when the reset redirect isn't allow-listed → supabase-js (`detectSessionInUrl`) consumed the token on the home page; `<head>` safety-net on `index.html`+`login.html` redirects `type=recovery` → `/reset-password` before any Supabase script loads. Site URL must be the Worker URL (`stello.arjunphlox.com` is dead) (PR #18)
- 2026-06-13 · "No image despite og:image" root cause was `fetchOGMetadata`'s fixed-position regex, NOT the Images binding · it skipped any `<meta>` with an attribute before `property` (e.g. `slot="seo_meta"` → sonsanddaughters); replaced with an order-independent per-`<meta>` parser + `twitter:image` fallback. Worker observability confirmed zero image-failure warns + the binding works (PR #17)
- 2026-06-13 · `reprocess` no longer marks imageless items `vision_done` · that terminal mask blocked retry (the frontend backfill gives up on `vision_done`); now `text_done` when the page advertises an og:image we couldn't store (retryable) or `candidates_done` when genuinely imageless (PR #17)
- 2026-06-13 · No-og:image pages promote the first harvested page image to the cover · the CF migration dropped the puppeteer screenshot fallback; keeps cards from rendering blank. Browser Rendering screenshots still deferred (PR #17)
- 2026-06-13 · Added nullable `items.enrichment_error`; capture/enrich/reprocess record a reason and clear it on success, panel empty-state surfaces it · silent `console.warn`+`return null` had made no-image items undiagnosable, needing a DB+logs forensics pass to find (PR #17)
- 2026-06-13 · `downloadImage` stores original bytes when the WebP transform fails, instead of returning null · defensive insurance (not the root cause); breaks the single-format-bucket ideal but a stored image beats a dropped one (PR #17)
- 2026-06-11 · Migrated off Vercel to a single Cloudflare Worker (L5 migration) · sharp→**CF Images binding**, Supabase Storage→**R2** (paths `/img/<key>`, served by the Worker — zero egress), Vercel fns→Hono routes via `src/lib/adapter.js`, cron→Cron Trigger, background enrich via `ctx.waitUntil`. Supabase stays DB+auth. Live at `stello.arjunphlox.workers.dev` (no custom domain). The ~1,982 existing images were copied Supabase→R2 + DB paths rewritten in a one-time migration (via a temp guarded Worker endpoint, since the standalone script capped at Supabase's 1000-row default + was too slow at 3.4k items). Vercel project decommissioned. Puppeteer screenshots in `reenrich` deferred to Phase 2 (Browser Rendering). Follow-up: Supabase auth Site URL was the dead `stello.arjunphlox.com` — fixed to the Worker URL.
- 2026-04-16 · Side-panel comparison UI replaces inline card expansion · supports A/B discovery without blocking grid, persists via URL + localStorage
- 2026-04-16 · Masonry uses CSS `column-count` (not grid/flex) · keeps natural aspect ratios; documented downside: no row gap, cards use margin-bottom
- 2026-04-16 · 3-panel layout defaults to equal viewport/4 split, `state.userResized` flags preserve manual drags · so auto-rebalancing doesn't fight the user
- 2026-04-16 · Header alignment via `text-box-trim: trim-both cap alphabetic` · lets `align-items: flex-end` line the h1 baseline up with the icon buttons
- 2026-04-16 · Container query on `.header` (not viewport media) · header stacks based on its own width, correctly responds to 3-panel squeeze
- 2026-04-16 · Layout margins replaced with padding/flex-gap as a broad rule · exceptions flagged: CSS column-count row spacing, markdown prose, `* { margin: 0 }` reset, sr-only `-1px`
- 2026-04-16 · Phosphor icons inlined as JS string constants (not font/CDN) · zero runtime deps, fully color-controllable via currentColor
- 2026-04-16 · Whole week-title bar is the click target (caret decorative) · lower-precision tap, ARIA role=button + keyboard support
- 2026-04-16 · Radix Colors via copied CSS values (not CDN/npm) · zero deps, works without build step, self-contained
- 2026-04-16 · `--accent-contrast` hardcoded per accent (not `var(--{color}-12)`) · step-12 flips in dark mode, but accent-9 is always bright for Lime/Amber — needs fixed dark text
- 2026-04-16 · Header + expanded week bar use `--accent` as background · accent color drives the app identity, not just buttons/links
- 2026-04-16 · Card highlights use `outline` with 4px offset (not opacity dimming) · accent border is visible without reducing card readability
- 2026-04-16 · Theme stored as `stello.theme` in localStorage (`{mode, accent}`) · trivially syncable to server when auth lands
- 2026-04-16 · Aribau Grotesk self-hosted via `fonts/*.otf` kebab-case paths · `server.js` doesn't decode URL-encoded pathnames, so spaces/%20 404; renamed files to avoid encoding entirely
- 2026-04-16 · Login page reuses `.header` + `.login-header` with shared `view-transition-name: app-header` · cross-document `@view-transition { navigation: auto }` auto-morphs the header between `/login.html` ↔ `/` with no JS orchestration
- 2026-04-16 · Post-login stagger triggered by `?welcome=1` URL flag (stripped via history.replaceState) · works for both email sign-in (client) and Apple OAuth (server callback); avoids needing sessionStorage
- 2026-04-16 · Login error floats above form via `position: absolute; bottom: calc(100% + 6px)` on a child of the form · form stays pinned to the same bottom Y as the login-options row regardless of mode or error visibility
- 2026-04-16 · Settings logout pinned to bottom via `margin: auto -16px -16px` inside flex-column `.panel-body` · same shape as item panel tags footer; negative side margins cancel panel-body padding for edge-to-edge divider
- 2026-04-16 · Canonical bitten-apple logo (Simple Icons path) on Sign in with Apple button · Phosphor's apple-logo-fill stylizes differently (two stem notches, no bite/leaf) and read as a bean at 16px
- 2026-04-16 · Filesystem fallbacks removed from `detail.html` + `app.js` (Supabase is now the only data source) · in a multi-tenant deploy the fallback code paths would have leaked the owner's `_items/*.md` + `index.json` to any visitor; surface the Supabase error instead
- 2026-04-16 · `server.js` + `serve.sh` deleted; Vercel functions are the only API surface · `server.js` had zero auth and duplicated every endpoint; local dev is now `vercel dev` (auth-gated, hits live Supabase), `python3 -m http.server` for pure static preview
- 2026-04-16 · `_items/` + `index.json` stopped being tracked in git · they're a local backup mirror regenerated by `npm run backup`, not source; tracking one user's data post multi-tenant is the wrong shape, and every sync churned a 300k-line diff
- 2026-04-16 · Supabase setup moved to the new `sb_secret_*` / `sb_publishable_*` key scheme · the legacy JWT `service_role` was accidentally exposed; migrating also future-proofs against the upcoming legacy-key deprecation (follow-up: confirm frontend ships the publishable key in prod, then flip off legacy JWT keys)
- 2026-04-16 · GSAP (jsDelivr CDN) drives the login→home header morph when cross-document view-transitions aren't supported · Firefox has no cross-doc VT; the morph is critical to the sign-in experience. Synchronous `<head>` gate on `?welcome=1` flips `html.arriving-from-login` before first paint so CSS paints the hero footprint, then `runLoginArrivalFallback()` in app.js tweens back to compact with the same 275ms/225ms durations as the native `::view-transition-*` rules
- 2026-04-17 · Capture opens curation Item Panel; inline question card removed · enrichment streams image candidates + snippet candidates + suggested reasons into the same panel the user is reviewing, instead of a second card below the first
- 2026-04-17 · Preview vs cover are decoupled in the panel slider · clicking a thumb only swaps the main preview; cover change goes through the "Set as cover" icon button. The cover-dot stays on one thumb and only moves on an explicit action
- 2026-04-17 · Cover-dot color flips black/white based on image luminance (Rec. 601 luma, cached by URL) · so the dot stays visible whether the cover is a sunny landscape or a dark hero
- 2026-04-17 · All image writes normalize to WebP at ingest via sharp · OG, extracted candidates, manual uploads, page screenshots — one format in the bucket, simpler frontend, smaller transfer
- 2026-04-17 · Enrich captures full-page screenshots at 1440/640/360 via puppeteer-core + @sparticuz/chromium · serverless-friendly pairing; local dev falls back to a configurable Chrome executable path and degrades to zero screenshots if none is available
- 2026-04-17 · `/api/item-update` is the single mutation endpoint for panel curation (images, snippets, why-saved, manual uploads) · replaced the narrower `/api/review`; deltas-only payloads keep debouncing cheap
- 2026-04-17 · Image removal deletes from Supabase storage and from images[] together · storage orphans are cheap to clean up later, but a broken DB row isn't, so storage errors are logged but non-blocking
- 2026-04-17 · Page body doesn't scroll; `.main-layout` is 100vh with `.main-content` as the scroll container · panels stay viewport-tall without sticky hacks, scroll position is independent from panel state
- 2026-04-17 · Grid column right-padding collapses 24 → 12 when any panel is open (`:has(.panel)`) · the panels-container already adds 24px padding; stacking both gave a perceptual 48px gap
- 2026-04-25 · Password reset is fully client-side via `auth.resetPasswordForEmail` + `auth.updateUser` · no new serverless function (Hobby cap is 12, we were at 12); `/reset-password.html` is the recovery-link landing
- 2026-04-25 · `reset-password.html` enables submit on the `PASSWORD_RECOVERY` auth event with a 600ms session-check fallback · users who land directly (no hash, stale tab) see "invalid or expired" instead of a silently-disabled form
- 2026-04-27 · Auth emails route through Resend custom SMTP from `noreply@stello.arjunphlox.com` (verified domain) · Supabase's default SMTP is capped at ~4/hr project-wide, which silently 429'd every public signup with `over_email_send_rate_limit`; SMTP creds + URL allowlist (`https://stello.arjunphlox.com/**`, `http://localhost:8080/**`) live in the Supabase dashboard, not the repo
- 2026-04-27 · Login form surfaces in-flight state via button label swap (`Creating account…` / `Signing in…`) and shakes the floating error · the prior 0.8rem right-aligned error was easy to miss when Supabase silently rejected a signup, leading to "button disabled, nothing happened" reports
- 2026-05-16 · `items.images[]` entries carry `{ width, height }` from sharp metadata; `renderCard()` emits `<img width=W height=H>` · prevents column-count masonry from reflowing when the image lands at a natural aspect-ratio different from the OG-default fallback, which is what caused card thumbnails to visibly fragment across columns. CSS `aspect-ratio: auto 1200/630` stays as the legacy-row fallback; `node scripts/backfill-image-dimensions.js` retrofits dims onto existing rows
- 2026-05-17 · Masonry is flex-column stacks distributed by JS, not CSS column-count · WebKit's column engine briefly flickers to single-column state on every panel-open / week-toggle / hover. Flex layout has no such recompute. `distributeIntoColumns` packs cards greedily into the shortest column at render time.
- 2026-05-17 · Card hover dim is `filter: brightness(0.175)` on the image itself, not an overlay div · overlay had a sub-pixel alignment gap (CSS background vs raster img rounded differently at fractional column widths); filter applies to rendered pixels so there's nothing to align.
- 2026-05-17 · Single-panel mode on the home grid (item OR tool, mutually exclusive); dual-panel removed pending detail-page reimplementation · prevents the two-panels-eat-the-grid layout collapse, simplifies PanelManager state.
- 2026-05-17 · Related-items lights up on panel open only (no 2s hover delay); rule is `(format OR domain) AND ≥3 shared high-weight tags` · hover trigger was mass-class-toggling which Safari column-count engine misinterpreted as relayout signal; diff-based updates keep DOM mutations minimal.
- 2026-05-17 · `--grid-cols` is driven by JS (ResizeObserver on `.main-content`), not CSS container queries · Safari has unreliable container-query support on flex children; JS path is the canonical source, container queries removed entirely.
- 2026-05-17 · Panel width is `clamp(360px, round(viewport*0.25), 480px)` — no resize handle · single-panel UX doesn't need user-controlled width; localStorage just stores the open slug, not panel dimensions.
- 2026-05-18 · Topic content (~80 `.md` + ~30 dirs) moved out of repo root into `cosmos/`; added to `.vercelignore` · root is now app code + meta only, deploys no longer ship ~100MB of unused user notes. App was already Supabase-only post-PR #5, so no code changes needed.
- 2026-05-20 · Enrich now captures one 1440×900 viewport screenshot per item, not three full-page widths (1440/640/360) · supersedes the 2026-04-17 entry. Three widths produced three `source: 'screenshot'` entries per item with wildly varying aspect ratios, and the panel slider had to render each separately. Fixed viewport = predictable slider thumbnail. Re-enrichment drops legacy multi-width entries from `images[]` and `storage.remove`s the orphan `screenshot-1440w.webp` / `-640w.webp` / `-360w.webp` files in-band so the bucket self-cleans.
