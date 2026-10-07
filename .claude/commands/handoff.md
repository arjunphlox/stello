---
description: Fresh-session hand-off — emit ONE paste-ready prompt (≤6k chars) that lets a new session resume without re-briefing
---
<!-- Synced from arjunphlox/arjun-ai-gems harness/commands/handoff.md @ 77af9dc. Edit it there; this copy is overwritten. -->

Use when the session limit is near or I ask for "a prompt for a fresh session". Output is ONE markdown FILE I can paste as-is — delivered with `SendUserFile` (display `attach`) in cloud sessions, or written to the repo/outputs folder locally. NEVER inline in chat: nested code fences break the outer block and I get broken text (memory: `docs/memory/feedback_handoff_deliver_as_file.md`).

## Steps

1. **Check for a prior hand-off.** If a hand-off prompt was already given earlier in this session, say so and emit only a delta (or the updated full prompt if I ask) — never a silent duplicate.

2. **Gather facts, don't recall them.** Run: `git log origin/main -1 --format=%H` per repo, `gh pr list` or the GitHub MCP `list_pull_requests` (open PRs + check state), `git branch -a` for live branches, and list artefacts on disk with paths. Every SHA / PR state in the prompt comes from this run.

3. **Model roles.** Default (canonical stance):
   - **Fable 5.1** — planner, orchestrator, reviewer
   - **Opus 5.5** sub-agents — risky / layout / multi-file execution
   - **Sonnet 5.5** sub-agents — scoped components, measurement, docs
   - **Haiku 4.5** sub-agents — mechanical edits, lookups
   - **Grok 4.7 (Cursor)** — closed-scope literal edits via a paste-ready brief only

   If I named models for the next session, use exactly my ids, verbatim, and drop the defaults they replace.

4. **Write the prompt** with these sections, in order (omit a section only if empty):
   1. **Roles** — the list from step 3 + "Use these exact model ids; never substitute."
   2. **Read first** — files in reading order (repo CLAUDE.md, owning docs, plan in `docs/plans/`, the latest report).
   3. **Standing norms** — one line: "Follow the Working contract in each repo's CLAUDE.md." Don't re-paste rules that already live in CLAUDE.md / memory.
   4. **Where we are** — `main` SHA per repo, open PRs + state, branches, artefact contract (what's shipped, where, md5 if relevant).
   5. **Gates & commands** — exact commands that prove done.
   6. **Owner rules set this session** — verbatim quotes, each one line.
   7. **Open decisions / known gaps** — each with recommendation + runner-up.
   8. **Corrections** — empty slot: `Corrections from Arjun: _`
   9. **Then** — numbered next steps, first one actionable immediately.
   10. **Sources** — links to PRs, reports, plans.

5. **Size check.** `wc -c` the prompt; if over 6,000 chars, cut by linking (docs, PR bodies, reports) rather than inlining. Never drop sections 1, 4, 6 or 9 to fit.

6. **Emit** the file (`SendUserFile`, display `attach`; locally a `.md` in the repo or outputs folder). Commands inside the prompt are indented code (4 spaces), never fenced. Then one chat line: file name, char count, and anything I must save before archiving (or "run `/wrap` first"). Do not paste the prompt in chat.

## Rules

- Write the prompt in brief style (the `brief-style` skill): imperative steps, one instruction per sentence, ≤20 words, only must/can/will.
- Facts only from step 2 — no remembered SHAs or PR states.
- No "lessons from the last N sessions" sections; durable lessons belong in memory, linked from Read first.
- Scratchpad paths don't survive archive — never point the next session at one; move the file into a repo first (or flag it).
- Never emit the prompt inline in chat, and never nest fenced code inside it — see step 6.
