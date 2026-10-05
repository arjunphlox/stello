# AGENTS.md

Agent context for this repo lives in **[CLAUDE.md](CLAUDE.md)** — read it first. It's the single source of truth for both Cursor and Claude Code.

**Durable project memory** (the contract any agent reads at session start and appends to as it learns) is in **[docs/memory/MEMORY.md](docs/memory/MEMORY.md)** — project-scoped lessons only; account-level/personal memory stays in `~/.claude` and is never committed.

**Workflow:** **Claude Code is the primary harness** (since 2026-09-23). **Fable 5.1** plans, orchestrates, and reviews; execution goes to sub-agents routed by task shape — **Opus 5.5** (risky / layout / multi-file), **Sonnet 5.5** (scoped, measurement, docs), **Haiku 4.5** (mechanical) — and to **Grok 4.7 in Cursor** only through a closed-scope paste-ready brief. Fan-out of many independent units → a Dynamic Workflow. Branch prefixes: `claude/*`, `cursor/*`, `feature/*` / `fix/*`. Full spec: arjun-ai-gems [`knowledge/workflows/ai-workflow-orchestration.md`](https://github.com/arjunphlox/arjun-ai-gems/blob/main/knowledge/workflows/ai-workflow-orchestration.md).

The standing **Working contract** (ask before gaps bite · delegate by task shape · echo exact model ids) is in [CLAUDE.md](CLAUDE.md).
