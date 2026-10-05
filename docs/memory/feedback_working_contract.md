---
name: Working contract and executor routing
description: Standing owner contract (ask before gaps bite, delegate execution by task shape, echo exact model ids) plus the Grok 4.7 lane summary
type: feedback
---

# Working contract (standing — never needs repeating in a prompt)

- **Ask before gaps bite.** If anything needed for the task to succeed is missing or ambiguous, ask (1–3 sharp questions, multiple-choice where possible) before acting. Never assume silently; state every assumption openly in the reply.
- **Delegate execution by task shape.** The parent session plans, orchestrates, and reviews. Execution goes to the right sub-agent: **Opus 5.5** for layout/cascade, multi-file, risky or judgement-heavy work · **Sonnet 5.5** for scoped components, copy application, measurement passes, docs · **Haiku 4.5** for mechanical reverts and lookups · **Grok 4.7 (Cursor)** only for closed-scope literal edits via a paste-ready brief, to free Claude usage. Routing detail + Grok brief rules: [execution-model-routing](https://github.com/huegrid-studio/huegrid-site/blob/main/docs/workflow/execution-model-routing.md).
- **Echo exact model ids** the owner names; never substitute.

## Grok 4.7 lane (summary)

Route executors by **task shape**, not one ranking. Predictive axis = how a model handles a gap in the brief: Opus argues with the brief using evidence (earns autonomy); Sonnet reports what it sees incl. uncomfortable margins (earns trust); Grok completes the form even when the form doesn't fit the world (earns a narrow lane).
Grok 4.7 brief rules: closed scope only (literal file / selector / old → new; any find / decide / if-then step is not Grok's); orchestrator pre-verifies every target renders; one STOP line per measurement → `NOT FOUND`, never substitute; raw stdout from an orchestrator-supplied script, no hand-typed tables; docs text is dictated; no fallbacks; fixed report (SHA · `git diff --stat origin/main` · check outputs · measurement stdout · `STOPS:` line); orchestrator re-measures one claim before trusting the rest.
Good Grok tasks: declared token/CSS value changes, owner-approved copy to named keys, listed doc sweeps with exact old→new, regenerating generated files, running a supplied script. Not Grok: discovery, conditionals, layout/cascade, writing measurement scripts, Decisions prose.
Canonical source: [execution-model-routing](https://github.com/huegrid-studio/huegrid-site/blob/main/docs/workflow/execution-model-routing.md) (HueGrid-Site `docs/workflow/execution-model-routing.md`, PR #117, 2026-10-04).
