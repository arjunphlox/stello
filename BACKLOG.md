# Backlog — Stello

## Ready to Execute

| Task | Tool | Platform | Model | Status |
|---|---|---|---|---|
| **Visual card variants** — visually distinguish cards by content type (typefaces, products, articles, tools) using `domain` tag; subtle border/accent/icon differences per type | Claude Code | Desktop | Opus | Open |
| **Add new item from app** — URL input in UI, local Python server to fetch metadata + analyze + save to `_items/`; needs `scripts/serve.py` with Flask | Claude Code | Desktop | Opus | Open |
| **Tag-based "more like this"** — dedicated panel showing related items for a selected item; relatedness index already exists, just needs UI | Claude Code | Desktop | Opus | Open |
| **User notes on items** — editable text field on detail page, saved back to item.md; needs local server | Claude Code | Desktop | Opus | Open |

## Needs Planning

| Task | Tool | Platform | Model | Status |
|---|---|---|---|---|
| **Personal authentication/login** — auth system for Stello; needs architecture decision: local-only vs cloud, session management, credential storage | Claude Code | Either | Opus | Open |
| **New user account and onboarding** — first-run experience, account creation flow, initial content setup; depends on auth system | Claude Code | Either | Opus | Open |
| **Integrating Tessor configuration panel** — bring Tessor design tokens/config UI into Stello; depends on Tessor project state | Claude Code | Desktop | Opus | Open |
| **Semantic search** — embeddings + vector search for fuzzy retrieval; needs architecture decision: client-side vs server-side, which embedding model | Claude Code | Either | Opus | Open |
| **Smart ranking** — boost items by tag weight + retrieval frequency; needs click tracking, storage, ranking algorithm | Claude Code | Either | Opus | Open |
| **Progressive automation** — paste URL to fully analyzed item with zero manual steps; end-to-end pipeline | Claude Code | Either | Opus | Open |
| **Item-to-item comparison on the detail page** — bring back dual-panel side-by-side comparison (removed from home grid May 2026); needs a layout that doesn't crowd the masonry, shared-tag highlighting (`.tag-shared`, `sharedTagSet`), and a way to enter compare from a card or related-items list | Claude Code | Desktop | Opus | Open |
| **Cloudflare Browser Rendering screenshot fallback** — the richer fallback for pages with genuinely no og:image (the puppeteer path dropped in the CF migration; PR #17 added a harvested-page-image cover as the cheap interim). Needs the Browser Rendering binding + cost/latency assessment + where to trigger (enrich vs reenrich) | Claude Code | Desktop | Opus | Open |
| **Server-side enrichment drain** — enrichment healing is frontend-driven (`backfillEnrichment`, concurrency 2), so a deep `text_done` queue re-fetches OG for every item on every app load until it drains. Move the drain to the daily Cron Trigger (or a dedicated queued worker) so it self-heals server-side without per-load churn or a babysat tab. Surfaced 2026-06-14 while draining the ~970 post-recovery `text_done` backlog | Claude Code | Desktop | Opus | Open |

## Quick Wins

| Task | Tool | Platform | Model | Status |
|---|---|---|---|---|
| **Review item cards without images** — audit and fix cards with no OG image; improve fallback display or re-fetch images | Claude Code | Web | Sonnet | PR #17 — root cause fixed (brittle OG-meta regex) + cover fallback + diagnostics. Remaining: deploy & run `recover-errored-items.js` to clear the existing no-image / 379-error backlog |
| **Better tag navigation and management** — improve tag browsing, filtering, bulk editing, and tag cleanup tools | Claude Code | Desktop | Opus | Open |
| **UI bugs & refinements** — collect and fix visual glitches, layout issues, and polish rough edges | Claude Code | Desktop | Sonnet | Open |
| **Finish Supabase legacy-key rotation** — Step 1 DONE (PR #21): frontend + Worker var swapped to `sb_publishable_*`. Remaining (manual, post-deploy): `wrangler secret put SUPABASE_SERVICE_ROLE_KEY`=`sb_secret_*`, verify app, then disable legacy JWT keys in the dashboard to kill the previously exposed service_role JWT | Claude Code | Web | Sonnet | In progress |
| **Port `link_check.py` + `refetch.py` to Supabase** — they currently read the local `_items/` mirror, so results lag real data; should query Supabase directly or at least note "run backup first" | Claude Code | Either | Sonnet | Open |
| ~~**Update `.claude/launch.json`**~~ — DONE (PR #17 session): repointed from the deleted `scripts/local-dev.js` to `npm run dev` (build-assets + `wrangler dev`, pinned port 8787). `.claude/` is gitignored so it's local-only, no commit. Note: `vercel dev` no longer applies — repo is Cloudflare Workers now | Claude Code | Desktop | Sonnet | Done |
| **Fix auth login + reset URL config** — Supabase Site URL was the dead `stello.arjunphlox.com` (never resolved), so password-reset / confirmation email links are broken (pre-existing — also broke reset on `mystello.vercel.app`). Set Site URL to the live prod URL and allowlist `https://stello.phloxpage.workers.dev/**` (the `/**` also covers `/api/auth-callback` for Apple OAuth). Verify email/password reset + Apple sign-in end-to-end on the deployed Worker. Interim workaround used: hand-edit the email link's host to the workers.dev URL | Claude Code | Web | Sonnet | Open |
| **Grid reflow when a freshly-captured OG image loads** — on first capture the OG image renders before its aspect-ratio slot is reserved, widening/narrowing the other columns until a reload or right-panel close fixes it. Capture already persists width/height from the Images binding, so likely the panel-open `--grid-cols` squeeze + masonry redistribution rather than missing dims — reserve the slot on the optimistic insert so the column doesn't jump | Claude Code | Desktop | Sonnet | Open |
| ~~**Run `recover-errored-items.js` after PR #17 deploys**~~ — DONE (2026-06-14, PR #21): reset all 379 errored-with-image items `error`→`text_done`, error count → 0. Real root cause found mid-run: prod vision was dead because the `ANTHROPIC_API_KEY` Worker secret was never set post-CF-migration — set it, vision resumed. ~970 `text_done` now drain to `vision_done` over subsequent app loads | Claude Code | Desktop | Sonnet | Done |
| **Update CLAUDE.md to the Cloudflare Workers architecture** — Architecture / Key Files / Dev Commands sections still describe the retired Vercel `api/*` + `npm run dev`→`local-dev.js` + puppeteer setup. Repo is now `src/routes/*` + `src/lib/*`, `wrangler dev`, CF Images/R2 bindings. Stale docs misled this session's first pass | Claude Code | Desktop | Sonnet | Open |
| **Verify single-URL capture hits the Worker** — 7d of Worker logs show only `/api/capture-bulk`, never `/api/capture`. Likely just no single saves in the window, but confirm the import-modal / bookmarklet single-capture path actually reaches `stello.phloxpage.workers.dev` (the shared Supabase DB hides a wrong origin) | Claude Code | Web | Sonnet | Open |

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
