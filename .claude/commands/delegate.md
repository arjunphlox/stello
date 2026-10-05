---
description: Turn a fuzzy task into a verifiable cloud-agent spec — walk the 5 delegatability gates, return a go/no-go verdict + launch-ready brief
---
<!-- Synced from arjunphlox/arjun-ai-gems harness/commands/delegate.md @ 2102bd4. Edit it there; this copy is overwritten. -->

Decide whether a task should run as a **cloud agent** (fire-and-forget, off-machine, branch → PR) or stay at the **desk** (interactive) — and if cloud, produce a launch-ready spec. Full method: [`workflows/cloud-agent-delegation.md`](https://github.com/arjunphlox/arjun-ai-gems/blob/main/knowledge/workflows/cloud-agent-delegation.md).

This command **never launches an agent and never writes code** — it only produces the spec + verdict. Launching stays a deliberate, human action.

## Steps

1. **Parse the task** from what I just said (or a BACKLOG row / GH issue I point at). State it back in one sentence.

2. **Pattern-match first** — compare against the pattern library in the delegation guide. If it matches a known shape (cross-repo propagation, dead-code removal, scaffolding, behavior-preserving refactor, bounded bug + repro, fix-from-diagnosis, document-existing-code), pre-fill the verifier + model from that row and tell me which pattern matched. If it matches a **desk-only anti-pattern** (local-Mac tooling, prod-ops/secrets, novel architecture, authoring/ideation), say so and stop at verdict **Desk** — don't run the questions.

3. **Walk the 5 gates as questions** — ask only the ones the task doesn't already answer. One batch, not one-at-a-time:
   - **Gate 1 (spec clarity):** One-sentence done state — what must be true that isn't now?
   - **Gate 2 (verifiable):** What command/check proves it? (test name, `wrangler deploy --dry-run`, `npm run build`, preview screenshot.) If the answer is "I'll look at it," flag it — propose writing a test/repro *first*, then delegating.
   - **Gate 3 (blast radius):** Which files/dirs are in scope? Any architectural decision still open?
   - **Gate 4 (interactivity):** Any decision you'd need to make mid-way?
   - **Gate 5 (env):** Needs local Mac state / prod secrets / live bindings? Are the secrets already in the Claude environment's secrets (Claude cloud session) — or, for a Cursor hand-off, in **Cursor → Cloud Agents → Secrets** — for this repo?

4. **Verdict** — one of:
   - **✅ Cloud** — all gates pass. Pick the executor by task shape: **Opus 5.5** (risky / layout / multi-file), **Sonnet 5.5** (scoped, measurement, docs), **Haiku 4.5** (mechanical) as a sub-agent / Claude cloud session (effort scaled to difficulty); **Grok 4.7 in Cursor** only for closed-scope literal edits via a paste-ready brief. Fable 5.1 reviews the result either way.
   - **⚠️ Split** — diagnosis/judgment is needed first (desk), but the resulting *fix* is delegatable. Name what to resolve at the desk, then what to hand off.
   - **❌ Desk** — name the failing gate(s) and the one thing that would flip it to cloud (e.g. "add a failing test", "load `SUPABASE_SERVICE_ROLE_KEY` into the Claude environment secrets").

5. **Emit the launch-ready brief** (only for ✅ Cloud, or the cloud half of ⚠️ Split) — exactly this shape, ready to paste into a cloud agent:

   ```markdown
   **Task:** <one-sentence done state>
   **Acceptance criteria:**
   - [ ] <observable outcome>
   **Verify with:** <exact command(s) that must pass>
   **Files in scope:** <paths>  ·  **Out of scope:** <do-not-touch>
   **Model:** Opus 5.5 (risky / layout / multi-file) | Sonnet 5.5 (scoped, measurement, docs) | Haiku 4.5 (mechanical) — as sub-agent / Claude cloud session (<effort>) | Grok 4.7 in Cursor (closed-scope literal edits only)
   **Env / secrets needed:** <list — confirm present in Claude environment secrets, or Cursor → Secrets for a Cursor hand-off>
   **Branch:** claude/<slug> (Claude cloud) | cursor-cloud/<slug> (Cursor)   ·   **Merge:** human-gated
   **Brief rules:** branch name ≤56 chars (preview hostname >63 breaks DNS) · env setup runs `apt-get update` before `apt-get install` · RERUN RULE: a gate may be re-run once if the failure is timing/infra and the reason is logged
   **Style:** write the brief in STE instruction style — imperative, one instruction per sentence, ≤20 words, only must/can/will, active voice (the `brief-style` skill)
   ```

6. **Report** — verdict, matched pattern (if any), the brief (if cloud), and a one-line "how to launch" reminder (Claude cloud session on `claude/<slug>` — or, for a Cursor hand-off, Cursor → Cloud Agent with Grok 4.7 on `cursor-cloud/<slug>`; or fan out across repos via a Dynamic Workflow for a propagation pattern).

## Rules

- Never create branches, commits, PRs, or launch an agent. Pure planning aid.
- Never write the implementation — output is the spec only.
- Max one batch of clarifying questions; if the task is already fully specified, skip straight to verdict + brief.
- Merge is always human-gated — say so in every cloud brief. Never suggest auto-merge.
- If Gate 5 fails on secrets, the fix is "add them to the Claude environment secrets (or Cursor → Cloud Agents → Secrets for a Cursor hand-off, repo-scoped)", not "share them in chat."
- Keep it honest: when in doubt on Gates 1–2, return **Desk** — an under-specified cloud agent wastes more time than it saves.
