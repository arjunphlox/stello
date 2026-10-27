# Stello

Personal knowledge base — a rich item analysis and discovery tool with weighted tags, masonry grid UI, and content organization.

## AI Coding Workflow

**Claude Code is the primary harness** (since 2026-09-23). Work runs in Claude project threads, one thread per task, done inline in that thread: **no sub-agents** (since 2026-10-27; each one reloads all standing context). Medium effort by default; higher only for layout, multi-file or risky work. **Grok 4.7 in Cursor** takes closed-scope literal edits through a paste-ready brief. Branch prefixes: `claude/*`, `cursor/*`, `feature/*` / `fix/*`. Full spec: arjun-ai-gems [`knowledge/workflows/ai-workflow-orchestration.md`](https://github.com/arjunphlox/arjun-ai-gems/blob/main/knowledge/workflows/ai-workflow-orchestration.md).

### Working contract (standing — never needs repeating in a prompt)

- **Ask before gaps bite.** If anything needed for the task to succeed is missing or ambiguous, ask (1–3 sharp questions, multiple-choice where possible) before acting. Never assume silently; state every assumption openly in the reply.
- **Work inline, one thread per task.** No sub-agents: the thread that owns a task does the work itself. **Grok 4.7 (Cursor)** only for closed-scope literal edits via a paste-ready brief, to free Claude usage. Routing detail + Grok brief rules: [execution-model-routing](https://github.com/huegrid-studio/huegrid-site/blob/main/docs/workflow/execution-model-routing.md).
- **Echo exact model ids** the owner names; never substitute.

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

Dated decisions live in [`docs/decisions-log.md`](docs/decisions-log.md) (newest first). Add new lines there, not here.
