# AGENTS.md

Agent context for this repo lives in **[CLAUDE.md](CLAUDE.md)** — read it first. It's the single source of truth for both Cursor and Claude Code.

**Durable project memory** (the contract any agent reads at session start and appends to as it learns) is in **[docs/memory/MEMORY.md](docs/memory/MEMORY.md)** — project-scoped lessons only; account-level/personal memory stays in `~/.claude` and is never committed.

**Workflow:** Cursor primary, Claude Code for deep / MCP / subagent work, Codex for async-mechanical. Branch prefixes `cursor/*`, `claude/*`, `codex/*`. See [arjun-ai-gems/ai-workflow-orchestration.md](https://github.com/arjunphlox/arjun-ai-gems/blob/main/workflows/ai-workflow-orchestration.md).
