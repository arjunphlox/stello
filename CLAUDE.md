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

- `npm run dev` — builds `dist/` (asset allowlist) then runs `wrangler dev` (local Worker + static assets + a local D1). Optional secrets in `.dev.vars` (copy `.env.example`).
- `npm run dev:remote` — `wrangler dev --remote` against the real R2 + Images bindings; needed to exercise image conversion/serving locally.
- Deploys are automatic: Cloudflare Workers Builds deploys every push to `main` (build `npm run build`, deploy `npx wrangler deploy`) to `stello.arjunphlox.workers.dev`. `npm run deploy` still works for a manual deploy. Secrets set via `wrangler secret put` (not in the repo).
- `python3 -m http.server 8080` — static preview only (no auth, no API — useful for CSS tweaks)

## Architecture

Vanilla HTML/CSS/JS frontend, a single Cloudflare Worker (Hono) for accounts, data API, capture/enrichment + image serving, Cloudflare D1 for data + accounts, and R2 for image bytes. Supabase was removed on 2026-11-07; the Apple apps keep their own SwiftData + CloudKit copy, synced with D1. Minimal build step (asset allowlist copy only, no framework).

- **Frontend**: `index.html` (masonry grid), `detail.html` (item detail view), `app.js` (client logic), `style.css`, `auth-client.js` (auth + session helpers).
- **Worker**: one Hono Worker (`src/index.js`) serves the static frontend (`dist/`) + all `/api/*` routes (`src/routes/*`) + `/img/*` R2 image serving + a daily Cron Trigger. Endpoints ported from the old Vercel fns via `src/lib/adapter.js`. Image bytes live in R2 (`src/lib/storage.js`), served back at `/img/<key>` (zero egress); WebP conversion via the CF Images binding (`src/lib/images.js`). All auth-gated via `src/lib/common.js` → `src/lib/auth.js`.
- **Data**: Items in D1 `items` table (`env.DB`), per-user; `src/lib/db.js` scopes every query to the signed-in user, soft-deletes, and bumps the sync counters. Schema in `migrations/0001_init.sql`, applied by the Worker itself. Accounts: `src/lib/auth.js` (email + password, Sign in with Apple, cookie sessions, device tokens). Backups: D1 Time Travel (30 days) plus the daily R2 snapshots from the sync code.
- **Config**: Per-user Anthropic keys in `user_settings`. `config.json` is legacy and gitignored.
- **Desktop context (local Mac only)**: `desktop-context/` is a Python LaunchAgent (`com.stello.context`) on `127.0.0.1:8766` — watches `~/Downloads/Stello Watcher`, introspects Sketch + Safari, indexes into local SQLite, and serves `/related`. The frontend stub `desktop-context.js` calls it only when the page is loaded from `localhost` or `127.0.0.1` (`window.stelloDesktop.fetchRelated(k)`); production deploys never contact the daemon.

## Key Files

| File | Purpose |
|---|---|
| `index.html` | Main grid view with search, tag filtering, import modal |
| `detail.html` | Item detail page |
| `app.js` | All frontend logic — filtering, masonry layout, tag system, related items index |
| `panel-layout.js` | Item detail panel layout: web port of the Mac `CardSubcards.swift` + `PanelDedupe.swift` (all kinds); `app.js` renders its cards. Keep in step with the Mac panel |
| `desktop-context.js` | Localhost-only bridge to the desktop-context daemon (`window.stelloDesktop.fetchRelated`) |
| `style.css` | All styles |
| `auth-client.js` | Client-side auth + session helpers (`window.Stello`) |
| `src/index.js` | Hono Worker entry — `/api/*` routes, `/img/*` R2 serving, daily cron |
| `src/routes/*.js` | Ported endpoint handlers (capture, enrich, upload-image, …) |
| `src/lib/*.js` | Shared: `common` (auth gate + OG/tag helpers), `db` (D1 query builder), `auth` (accounts, sessions, Apple), `schema` (self-applied D1 schema), `images` (CF Images→WebP), `storage` (R2), `adapter` (req/res shim) |
| `wrangler.jsonc` | Worker config — assets, D1 + R2 + Images bindings, cron trigger |
| `migrations/0001_init.sql` | D1 schema (applied by the Worker on first request) |
| `config.json` | Legacy API key config (gitignored) — per-user keys now live in `user_settings` |
| `figma-plugin/` | Stello for Figma + FigJam (dev plugin, no build): library panel, context cards, related saves, Save to Stello, FigJam Board sync. See its README |
| `src/lib/projects.js` + `src/routes/projects.js` | Canvas docs on D1 (`projects` table, migration 0002): the library canvas (id `library`) and named projects; whole-doc saves with a rev check; `mergeBoard` for FigJam sync |
| `src/lib/library.js` + `src/routes/library.js` | Slim library reads, search and Layer 1 "related" rules (same colour/style/idea/place/kind/source) for the plugin and MCP |
| `src/routes/mcp.js` | Stello MCP server at `POST /api/mcp` (bearer device token): search, related, projects, add/link/note |
| `src/routes/pair.js` + `pair.html` | Pair a plugin or MCP client: code → approve in Stello → device token |

## Tag System

Items have weighted tags across categories: `format`, `domain`, `style`, `subject`, `tool`, `location`, `mood`, `color`. The app builds a `relatedIndex` mapping each item to related items by shared tags.

## Content Structure

Items live in D1 (web) and SwiftData + CloudKit (Apple). Moving to a user-owned folder of Markdown files: `docs/plans/folder-engine.md`, format in `src/lib/folder-format.js`, export via `scripts/export-folder.mjs`. The old `cosmos/` topic notes moved out of the repo into iCloud Drive/Stello on 2026-11-27.

## Maintenance Scripts

- `node scripts/export-folder.mjs --out <folder>` — read-only export of the library into the folder format (pairs through /pair.html)
- `node scripts/convert-folder-v2.mjs --dir <folder> [--apply]` — one-time v1 → v2 folder conversion (trial by default; `--apply` keeps v1 in `.stello-v1/`)

## Active Work
- [ ] **Desktop-context follow-ups** — e2e smoke (BACKLOG), cards UI scoping (BACKLOG). V1 pipeline shipped 2026-06-17.
- [~] **Native Apple app** (`apple/Stello`) — foundations shipped (Sprints 0-2 + refinement): local-first SwiftData+CloudKit, on-device Foundation Models enrichment, capture + Share Extension, masonry/weeks/search/filters/detail/themes, web-faithful macOS chrome. Refinement ongoing; data migration (Sprint 3) + real-device AI verification pending.
- [x] **Native quick-wins sprint** — SHIPPED (PR #30, 2026-07-06): revisit tracking, why-saved→intent facet, awaiting-review strip, search-over-everything, deterministic PageClassifier at capture. Built by Cursor/Composer, review-fixed by Claude Code — 8/9 review findings closed, 1 acceptable partial; residual minors in BACKLOG. Next: kind-dispatched AI enrichment + typed Highlights (BACKLOG, gated on real-device AFM verification).

## Decisions Log

Dated decisions live in [`docs/decisions-log.md`](docs/decisions-log.md) (newest first). Add new lines there, not here.
