# AGENTS.md

Agent context for this repo lives in **[CLAUDE.md](CLAUDE.md)** — read it first. It's the single source of truth for both Cursor and Claude Code.

**Durable project memory** (the contract any agent reads at session start and appends to as it learns) is in **[docs/memory/MEMORY.md](docs/memory/MEMORY.md)** — project-scoped lessons only; account-level/personal memory stays in `~/.claude` and is never committed.

**Workflow:** Cursor Agentic Desktop is the primary harness — Opus 4.8 *in Cursor* is the planning/thinking/orchestration brain, Composer 2.5 *in Cursor* executes (single / multi-session / sub-agents). Claude Code is occasional (fan-out Dynamic Workflows + mobile capture only). Branch prefixes are app-based: `cursor/*`, `claude/*`. See [arjun-ai-gems/ai-workflow-orchestration.md](https://github.com/arjunphlox/arjun-ai-gems/blob/main/workflows/ai-workflow-orchestration.md).

## Cursor Cloud specific instructions

Runs on a **headless Linux** VM. Only the **Stello Web** product (Cloudflare Worker + static frontend) can run here. The **Apple native app** (`apple/`) and the **desktop-context daemon** (`desktop-context/`) are **macOS/Xcode-only** and cannot be built or run on Linux — skip them.

- **Run the web app:** `npm run dev` (build-assets → `wrangler dev`, serves on `http://localhost:8787`). Dev commands and architecture are documented in [CLAUDE.md](CLAUDE.md). Start it as a long-lived process (e.g. under tmux), not with a fixed foreground timeout.
- **Env file is required before `dev`:** copy `.env.example` → `.env.local` (gitignored). `wrangler dev` auto-loads `.env.local` as local vars/secrets. `SUPABASE_URL`/`SUPABASE_ANON_KEY` are public and already committed in `wrangler.jsonc`, so the Worker boots even with the two secret slots blank.
- **`SUPABASE_SERVICE_ROLE_KEY` is empty by default** — read/auth flows work without it, but capture/enrich **write** paths and the cron drain need it (secret, from the Supabase dashboard). `ANTHROPIC_API_KEY` is optional (only for enriching users who lack their own key).
- **R2 + Images bindings run in local simulation** under plain `npm run dev`. Real WebP conversion/serving (`/img/*`) needs `npm run dev:remote`, which requires a real Cloudflare account + network egress.
- **Auth gate + email confirmation:** every page except `/login` redirects to login until there's a Supabase session. Signup goes against the **shared cloud Supabase project** and **requires email confirmation** (no session is returned on signup), so reaching the item grid / capturing an item needs a **pre-confirmed test account** — a fresh signup alone cannot log in. The signup UI flow itself (account creation → "Check your email to confirm your account.") is fully exercisable without credentials.
- **No lint or automated test suite** exists for the web product (no eslint/tsconfig/`test` script in `package.json`). `npm run build` (asset allowlist copy) is the only build check.
- **`npm run dev:up` / `dev:down`** call external `dev-up`/`dev-down` binaries that are **not in the repo** — they will fail on a fresh VM; use `npm run dev` instead.
