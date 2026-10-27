# AGENTS.md

Agent context for this repo lives in **[CLAUDE.md](CLAUDE.md)** — read it first. It's the single source of truth for both Cursor and Claude Code.

**Durable project memory** (the contract any agent reads at session start and appends to as it learns) is in **[docs/memory/MEMORY.md](docs/memory/MEMORY.md)** — project-scoped lessons only; account-level/personal memory stays in `~/.claude` and is never committed.

**Workflow:** **Claude Code is the primary harness** (since 2026-09-23). Work runs in Claude project threads, one thread per task, done inline in that thread: **no sub-agents** (since 2026-10-27; each one reloads all standing context). Medium effort by default; higher only for layout, multi-file or risky work. **Grok 4.7 in Cursor** takes closed-scope literal edits through a paste-ready brief. Branch prefixes: `claude/*`, `cursor/*`, `feature/*` / `fix/*`. Full spec: arjun-ai-gems [`knowledge/workflows/ai-workflow-orchestration.md`](https://github.com/arjunphlox/arjun-ai-gems/blob/main/knowledge/workflows/ai-workflow-orchestration.md).

The standing **Working contract** (ask before gaps bite · delegate by task shape · echo exact model ids) is in [CLAUDE.md](CLAUDE.md).
