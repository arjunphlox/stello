# Backlog — Stello

## Ready to Execute

| Task | Tool | Platform | Model | Status |
|---|---|---|---|---|
| **Desktop-context e2e smoke** — run the plan's end-to-end checklist: drop 3 PNGs + `.md` into `~/Downloads/Stello Watcher`, Sketch dwell 60s, Safari tabs (incl. blocklisted), then `await stelloDesktop.fetchRelated(10)` from localhost DevTools; verify ranking + blocklist. See `desktop-context/README.md` | Cursor | Desktop | Sonnet | Open |
| **Visual card variants** — visually distinguish cards by content type (typefaces, products, articles, tools) using `domain` tag; subtle border/accent/icon differences per type | Claude Code | Desktop | Opus | Open |
| **Add new item from app** — URL input in UI, local Python server to fetch metadata + analyze + save to `_items/`; needs `scripts/serve.py` with Flask | Claude Code | Desktop | Opus | Open |
| **Tag-based "more like this"** — dedicated panel showing related items for a selected item; relatedness index already exists, just needs UI | Claude Code | Desktop | Opus | Open |
| **User notes on items** — editable text field on detail page, saved back to item.md; needs local server | Claude Code | Desktop | Opus | Open |

## Needs Planning

| Task | Tool | Platform | Model | Status |
|---|---|---|---|---|
| **Desktop-context cards UI** — render `/related` results in Stello (placement: panel vs strip TBD), wire `stelloDesktop.fetchRelated(k)`, refresh cadence, empty/offline when daemon down; localhost-only gate already in `desktop-context.js`. Pipeline shipped 2026-06-17; needs UX scoping before build | Claude Code | Desktop | Opus | Open |
| **Personal authentication/login** — auth system for Stello; needs architecture decision: local-only vs cloud, session management, credential storage | Claude Code | Either | Opus | Open |
| **New user account and onboarding** — first-run experience, account creation flow, initial content setup; depends on auth system | Claude Code | Either | Opus | Open |
| **Integrating Tessor configuration panel** — bring Tessor design tokens/config UI into Stello; depends on Tessor project state | Claude Code | Desktop | Opus | Open |
| **Semantic search** — embeddings + vector search for fuzzy retrieval; needs architecture decision: client-side vs server-side, which embedding model | Claude Code | Either | Opus | Open |
| **Smart ranking** — boost items by tag weight + retrieval frequency; needs click tracking, storage, ranking algorithm | Claude Code | Either | Opus | Open |
| **Progressive automation** — paste URL to fully analyzed item with zero manual steps; end-to-end pipeline | Claude Code | Either | Opus | Open |
| **Item-to-item comparison on the detail page** — bring back dual-panel side-by-side comparison (removed from home grid May 2026); needs a layout that doesn't crowd the masonry, shared-tag highlighting (`.tag-shared`, `sharedTagSet`), and a way to enter compare from a card or related-items list | Claude Code | Desktop | Opus | Open |
| **Cloudflare Browser Rendering screenshot fallback** — the richer fallback for pages with genuinely no og:image (the puppeteer path dropped in the CF migration; PR #17 added a harvested-page-image cover as the cheap interim). Needs the Browser Rendering binding + cost/latency assessment + where to trigger (enrich vs reenrich) | Claude Code | Desktop | Opus | Open |
| ~~**Server-side enrichment drain**~~ — DONE (2026-06-15, PR #22): `drainEnrichment` runs from the daily cron (`limit:20` backstop, `waitUntil`) + a guarded `POST /api/cron/drain-enrichment` trigger; reuses extracted `reprocessItem`/`enrichItem` cores. Pilot-verified. Backlog drains passively (cron + app-load backfill); the old tail is mostly link-rotted (→`candidates_done`/`error`). Possible follow-up: pre-resize oversized images before vision to cut the `400 invalid_request` errors | Claude Code | Desktop | Opus | Done |

## Quick Wins

| Task | Tool | Platform | Model | Status |
|---|---|---|---|---|
| ~~**Review item cards without images**~~ — DONE (PR #17 root-cause fix + PR #21 recovery): brittle OG-meta regex fixed, cover fallback + diagnostics added, and the 379-error backlog cleared (`error` → 0; true blocker was the unset `ANTHROPIC_API_KEY` secret, now set). Residual ~970 `text_done` drain to `vision_done` over normal app use | Claude Code | Web | Sonnet | Done |
| **Better tag navigation and management** — improve tag browsing, filtering, bulk editing, and tag cleanup tools | Claude Code | Desktop | Opus | Open |
| **UI bugs & refinements** — collect and fix visual glitches, layout issues, and polish rough edges | Claude Code | Desktop | Sonnet | Open |
| ~~**Finish Supabase legacy-key rotation**~~ — DONE (2026-06-14, PR #21 + manual): frontend + Worker var → `sb_publishable_*`, `SUPABASE_SERVICE_ROLE_KEY` secret → `sb_secret_*`, legacy JWT keys disabled in the dashboard. Verified end-to-end: the previously-exposed legacy `service_role` + `anon` JWTs now return `401`; publishable + sb_secret work | Claude Code | Web | Sonnet | Done |
| **Port `link_check.py` + `refetch.py` to Supabase** — they currently read the local `_items/` mirror, so results lag real data; should query Supabase directly or at least note "run backup first" | Claude Code | Either | Sonnet | Open |
| ~~**Update `.claude/launch.json`**~~ — DONE (PR #17 session): repointed from the deleted `scripts/local-dev.js` to `npm run dev` (build-assets + `wrangler dev`, pinned port 8787). `.claude/` is gitignored so it's local-only, no commit. Note: `vercel dev` no longer applies — repo is Cloudflare Workers now | Claude Code | Desktop | Sonnet | Done |
| **Fix auth login + reset URL config** — Supabase Site URL was the dead `stello.arjunphlox.com` (never resolved), so password-reset / confirmation email links are broken (pre-existing — also broke reset on `mystello.vercel.app`). Set Site URL to the live prod URL and allowlist `https://stello.phloxpage.workers.dev/**` (the `/**` also covers `/api/auth-callback` for Apple OAuth). Verify email/password reset + Apple sign-in end-to-end on the deployed Worker. Interim workaround used: hand-edit the email link's host to the workers.dev URL | Claude Code | Web | Sonnet | Open |
| **Grid reflow when a freshly-captured OG image loads** — on first capture the OG image renders before its aspect-ratio slot is reserved, widening/narrowing the other columns until a reload or right-panel close fixes it. Capture already persists width/height from the Images binding, so likely the panel-open `--grid-cols` squeeze + masonry redistribution rather than missing dims — reserve the slot on the optimistic insert so the column doesn't jump | Claude Code | Desktop | Sonnet | Open |
| ~~**Run `recover-errored-items.js` after PR #17 deploys**~~ — DONE (2026-06-14, PR #21): reset all 379 errored-with-image items `error`→`text_done`, error count → 0. Real root cause found mid-run: prod vision was dead because the `ANTHROPIC_API_KEY` Worker secret was never set post-CF-migration — set it, vision resumed. ~970 `text_done` now drain to `vision_done` over subsequent app loads | Claude Code | Desktop | Sonnet | Done |
| ~~**Update CLAUDE.md to the Cloudflare Workers architecture**~~ — DONE (verified 2026-07-06): CLAUDE.md Architecture / Key Files / Dev Commands now describe the Hono Worker (`src/routes/*` + `src/lib/*`), `wrangler dev`, CF Images/R2 bindings | Claude Code | Desktop | Sonnet | Done |
| **Verify single-URL capture hits the Worker** — 7d of Worker logs show only `/api/capture-bulk`, never `/api/capture`. Likely just no single saves in the window, but confirm the import-modal / bookmarklet single-capture path actually reaches `stello.phloxpage.workers.dev` (the shared Supabase DB hides a wrong origin) | Claude Code | Web | Sonnet | Open |
| **Pre-resize oversized images before vision** — some items hit Anthropic `400 invalid_request` in `enrich.js` Phase A (image too large / bad dimensions) → terminal `error`, never healed (backfill + drain both skip `error`). Resize/re-encode via the CF Images binding before the vision call so these recover. Surfaced 2026-06-15 during the drain pilot (~6 items already stuck this way) | Claude Code | Desktop | Sonnet | Open |
| **Fix desktop-context hanging pytest** — `test_poll_loop_logs_only_on_change` blocks full `pytest tests/` run; skip, timeout, or rewrite | Cursor | Desktop | Sonnet | Open |

## Native app

| Task | Tool | Platform | Model | Status |
|---|---|---|---|---|
| ~~**Native quick-wins A–E**~~ — revisit tracking, why-saved intent chips, full-text search blob, awaiting-review strip, deterministic PageClassifier at capture (`cursor/native-quick-wins`, 117→138 tests) | Cursor | iOS/macOS | Composer | Done |
| **Verify live on-device AFM** — text jobs (snippets/why-saved) VERIFIED on macOS 2026-07-11 (real device, Apple Intelligence on). Vision job BLOCKED by OS: macOS 27.0 26A5378j's FoundationModels lacks the image `Attachment` API the Xcode 27 SDK declares (weak-symbol call → SIGSEGV); hard-disabled via `FoundationModelsEnricher.imageAttachmentSupported`. Remaining: iOS-device verification (signing) | Cursor | iOS/macOS | Composer | Open |
| ~~**Re-enable vision enrichment after macOS beta update**~~ — DONE (2026-07-11): root cause was Xcode beta 2 SDK vs macOS beta 3 skew, not a missing OS feature; rebuilt with Xcode beta 3, vision live on fresh captures with covers | Cursor | macOS | Composer | Done |
| **Richer page text for enrichment** — enrichment's text jobs only see `title + summary` (og:description, ~200 chars), so snippets/why-saved are thin; capture and store readable page text (readability-extracted body) at fetch time and feed it to `pageText` (also strengthens the search blob + future vibe-search corpus) | Cursor | iOS/macOS | Sonnet | Open |
| **Verify CloudKit cross-device sync + Supabase→native migration** — Sprint 3: prove sync across devices, build one-way import from Supabase web data | Cursor | iOS/macOS | Opus | Open |
| ~~**Domain-pill tint + subtle visual polish**~~ — DONE (2026-07-01, branch `cursor/native-visual-karst-zoom`): shipped as part of a large native UI overhaul — Karst default font (System/Light/Dark, off-white light, 14pt Apple-native type scale), web-faithful cards (flat 6px, 12px gaps, hover/long-press title, domain pill), single continuous grid + left-edge timeline overlay (scroll-spy/hover/scrub), granular pinch zoom, bottom control bar (add/filter/search/avatar) w/ Liquid Glass, web-parity detail panel (adjustable 25–50%, top-bleed image, multi-column, image strip), drag & drop capture (window/card/panel/app-icon; video local-only; "local" link), Download Full Item (zip). 111→113 tests green | Cursor | iOS/macOS | Composer | Done |
| ~~**Rich typed detail panel + Optacos CMS import (#6)**~~ — DONE (2026-07-02, branch `cursor/native-visual-karst-zoom`): `Item.kind` + `metadataJSON` per-kind Codable metas; `OptacosSeed.json` (10 collections, 359 CMS rows); `OptacosImporter` (162 entity items + tag pass, async image fetch, slug disambiguation); `CardSubcards` outlined sub-cards w/ 1→2 column reflow; Icon Composer `Stello.icon` wired. Plan: `docs/plans/rich-typed-detail-panel.md` | Cursor | iOS/macOS | Composer | Done |
| **Kind-dispatched AI enrichment + typed Highlights** — per-kind @Generable jobs (`WebsiteHighlights`, `IndividualProfile`) + `Highlight` model (color-scheme/typography/copywriting/animation/graphic/structure); gated on real-device AFM verification + highlight-taxonomy design pass. Analysis: `BOOKMARK_POSSIBILITIES.md` status header | Cursor | iOS/macOS | Opus | Open |
| **Quick-wins residual minors** (from PR #30 fix-round verification, 2026-07-06) — (1) `ItemSearchBlob` cache never evicts deleted items (unbounded growth across delete/re-import); (2) accepting a non-last why-saved suggestion leaves the strip's "N suggestions" label stale until next refresh; (3) `markTerminalWithoutAI` items linger in the strip until an unrelated refresh; (4) why-saved chip hit targets ~31–33pt (under 44pt ideal), dismiss has no undo; (5) `-screenshotAwaitingReview` silently no-ops without `-screenshotCleanStore` (safe direction, but pairing unenforced) | Claude Code | iOS/macOS | Sonnet | Open |
| **Full curation panel + App Intents/Spotlight/Visual Intelligence** — Sprint 4, deferred | Cursor | iOS/macOS | Opus | Open |
| **Consider local-only seed container** — if CloudKit dupes recur, isolate seed catalog in a non-synced container | Cursor | iOS/macOS | Composer | Open |

## Maintenance (run periodically via Claude Code)

| Task | Tool | Platform | Model | Status |
|---|---|---|---|---|
| **Link check** — `python3 scripts/link_check.py run` (every 7 days; reads local `_items/` backup mirror) | Claude Code | Either | Sonnet | Open |
| **Refetch images** — `python3 scripts/refetch.py run` for items without images (reads local `_items/` backup mirror) | Claude Code | Either | Sonnet | Open |
| **Verify Supabase setup** — `node scripts/verify-supabase.js` after any schema change or key rotation | Claude Code | Either | Sonnet | Open |
| **Backfill image dimensions (one-time)** — `node scripts/backfill-image-dimensions.js` sniffs each stored image's width/height and writes them into items.images[]. Eliminates the column-count reflow on legacy items so card thumbnails never appear cut off across columns. Run once with env vars set | Claude Code | Either | Sonnet | Open |

---

## Worktree Guide

Use a worktree session when the work is **experimental, risky, or parallel-safe**. Use main when it's **sequential, small, or maintenance**.

| Task | Worktree? | Why |
|---|---|---|
| Visual card variants | No | Sequential UI feature, builds on main |
| Desktop-context e2e smoke | No | Manual checklist on main machine; daemon already installable |
| Desktop-context cards UI | **Yes** | New UI surface + placement decisions; prototype in isolation |
| Tag-based "more like this" | No | Builds on existing relatedIndex in app.js |
| User notes on items | No | Small, contained server + UI change |
| Reviewing cards without images | No | Audit + fixes, low risk |
| Better tag navigation | No | Incremental UI improvement |
| UI bugs & refinements | No | Small targeted fixes |
| Personal auth/login | **Yes** | Adds auth layer across server + frontend, may need iteration, easy to discard if approach changes |
| New user account & onboarding | **Yes** | Depends on auth, large scope, experimental UX flows |
| Tessor config panel integration | **Yes** | Sweeping CSS/component changes, may conflict with UI work on main |
| Semantic search | **Yes** | High uncertainty — embeddings, vector store, new search UI. Prototype in isolation |
| Smart ranking | **Yes** | Needs click tracking infra, algorithm tuning. Experimental |
| Progressive automation | No | Pipeline work, extends existing scripts on main |
| Dark mode / theme system | **Yes** | Broad CSS changes, develop in isolation |
| Performance overhaul | **Yes** | Virtual scrolling, lazy loading — experimental, needs benchmarking |
