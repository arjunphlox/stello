# AGENTS.md

Agent context for this repo lives in **[CLAUDE.md](CLAUDE.md)** — read it first. It's the single source of truth for both Cursor and Claude Code.

**Durable project memory** (the contract any agent reads at session start and appends to as it learns) is in **[docs/memory/MEMORY.md](docs/memory/MEMORY.md)** — project-scoped lessons only; account-level/personal memory stays in `~/.claude` and is never committed.

**Workflow:** Cursor Agentic Desktop is the primary harness — Opus 4.8 *in Cursor* is the planning/thinking/orchestration brain, Composer 2.5 *in Cursor* executes (single / multi-session / sub-agents). Claude Code is occasional (fan-out Dynamic Workflows + mobile capture only). Branch prefixes are app-based: `cursor/*`, `claude/*`. See [arjun-ai-gems/ai-workflow-orchestration.md](https://github.com/arjunphlox/arjun-ai-gems/blob/main/workflows/ai-workflow-orchestration.md).
