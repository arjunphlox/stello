# Stello

Personal knowledge base — a rich item analysis and discovery tool with weighted tags, masonry grid UI, and content organization. Data lives in the user's iCloud; native apps + a web app read the same library.

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

- `npm run dev` — builds `dist/` (asset allowlist) then runs `wrangler dev` (static web app + `/img/*`) on `http://localhost:8787`, an allowed CloudKit origin.
- Deploys are automatic: Cloudflare Workers Builds deploys every push to `main` (build `npm run build`, deploy `npx wrangler deploy`) to `stello.arjunphlox.workers.dev`. `npm run deploy` still works for a manual deploy. No secrets needed.
- `python3 -m http.server 8080` — static preview only (no iCloud sign-in — useful for CSS tweaks)

## Architecture

**iCloud is the only data home** (since 2026-11-05; Supabase removed). Vanilla HTML/CSS/JS web app, native SwiftUI apps, and a tiny Cloudflare Worker that only serves files. See `docs/memory/project_icloud_data.md`.

- **Apps**: `apple/Stello` — SwiftData + CloudKit (container `iCloud.com.arjunphlox.Stello`), on-device capture + enrichment. `Sync/WebInboxProcessor.swift` applies web saves/edits from the `StelloInbox` zone (silent push).
- **Web**: `index.html` (masonry grid), `detail.html`, `login.html` (Apple ID sign-in), `app.js` (client logic), `style.css`, `icloud-client.js` (CloudKit JS: Apple ID auth, reads the apps' SwiftData mirror zone into IndexedDB, lazy images, inbox writes). The web never writes SwiftData's `CD_` records directly.
- **Worker**: `src/index.js` (Hono) serves `dist/` + legacy `/img/*` from R2. `/img` + R2 stay only until the Supabase export is imported into iCloud.
- **Desktop context (local Mac only)**: `desktop-context/` is a Python LaunchAgent (`com.stello.context`) on `127.0.0.1:8766` — watches `~/Downloads/Stello Watcher`, introspects Sketch + Safari, indexes into local SQLite, and serves `/related`. The frontend stub `desktop-context.js` calls it only when the page is loaded from `localhost` or `127.0.0.1` (`window.stelloDesktop.fetchRelated(k)`); production deploys never contact the daemon.

## Key Files

| File | Purpose |
|---|---|
| `index.html` | Main grid view with search, tag filtering, import modal |
| `detail.html` | Item detail page |
| `login.html` | Sign in with Apple ID (CloudKit JS) |
| `app.js` | All frontend logic — filtering, masonry layout, tag system, related items index |
| `icloud-client.js` | CloudKit JS client — auth, library sync + cache, lazy images, `StelloInbox` writes. Holds the CloudKit API token + environment |
| `desktop-context.js` | Localhost-only bridge to the desktop-context daemon (`window.stelloDesktop.fetchRelated`) |
| `style.css` | All styles |
| `src/index.js` | Worker entry — static assets + `/img/*` R2 serving |
| `wrangler.jsonc` | Worker config — assets + R2 binding |
| `apple/Stello/Stello/Sync/WebInboxProcessor.swift` | Native side of the web inbox |
| `index.json` | Old local backup mirror (Supabase era) |

## Tag System

Items have weighted tags across categories: `format`, `domain`, `style`, `subject`, `tool`, `location`, `mood`, `color`. The app builds a `relatedIndex` mapping each item to related items by shared tags.

## Content Structure

Items stored as markdown files in `_items/` directory with YAML frontmatter metadata. Indexed in `index.json`. Topic collections live under `cosmos/` as `.md` files and themed sub-directories (e.g., `cosmos/Figma.md`, `cosmos/Typography/`) — content only, not consumed by the app.

## Maintenance Scripts

- `python3 scripts/link_check.py run` — check for dead links (reads the local `_items/` backup mirror; every 7 days)
- `python3 scripts/refetch.py run` — retry image fetching for items without images (reads the local `_items/` backup mirror)
- Archived: `scripts/archive/analyze.py`, `scripts/archive/vision_enrich.py` — superseded; enrichment now happens on-device in the native apps

## Active Work
- [~] **iCloud as the only data home** (2026-11-05) — Supabase + Worker API removed; web reads iCloud via CloudKit JS with Apple ID sign-in; web writes via the `StelloInbox` zone. Pending: CloudKit API token in `icloud-client.js`, on-device inbox test, importing the 3,605-item Supabase export into iCloud, then dropping R2 + `/img`.
- [ ] **Desktop-context follow-ups** — e2e smoke (BACKLOG), cards UI scoping (BACKLOG). V1 pipeline shipped 2026-06-17.
- [~] **Native Apple app** (`apple/Stello`) — foundations shipped (Sprints 0-2 + refinement): local-first SwiftData+CloudKit, on-device Foundation Models enrichment, capture + Share Extension, masonry/weeks/search/filters/detail/themes, web-faithful macOS chrome. Refinement ongoing; data migration (Sprint 3) + real-device AI verification pending.
- [x] **Native quick-wins sprint** — SHIPPED (PR #30, 2026-07-06): revisit tracking, why-saved→intent facet, awaiting-review strip, search-over-everything, deterministic PageClassifier at capture. Built by Cursor/Composer, review-fixed by Claude Code (Opus orchestrator + Sonnet 5 sub-agents, `docs/plans/pr30-fix-round.md`) — 8/9 review findings closed, 1 acceptable partial; residual minors in BACKLOG. Next from the possibilities analysis: kind-dispatched AI enrichment + typed Highlights (BACKLOG, gated on real-device AFM verification).

## Decisions Log

Dated decisions live in [`docs/decisions-log.md`](docs/decisions-log.md) (newest first). Add new lines there, not here.
