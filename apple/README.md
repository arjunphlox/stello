# Stello Native — build workspace

The native SwiftUI multiplatform app (iOS / iPadOS / macOS 27) lives here.
Source of truth for scope and decisions: the PRD at `.cursor/plans/stello_native_rewrite_b8103fbf.plan.md`.

## Repo layout decision
- The Xcode project lives at **`apple/Stello/`** (created via Xcode's New Project wizard, location = this `apple/` folder).
- It co-locates with the web repo during the build so the PRD, project memory, and the one-time migration script stay together. The web stack is sunset later (see PRD Sprint 5).

## Who builds what (orchestration)
- **Cursor (Opus 4.8)** — planner / reviewer / integrator (this session). Writes specs, reviews diffs, integrates. Does not hand-write app code.
- **Xcode 27 agent (Claude inside Xcode)** — primary builder for SwiftUI + on-device features. Visual previews, Device Hub, writes/runs its own tests.
- **Claude Code Desktop (Dynamic Workflows)** — fan-out: parallel design variations, enrichment prompt bake-offs.

## Workstream board
Status legend: ⬜ not started · 🟡 in progress · ✅ done · 🔬 in review

- ⬜ **Sprint 0** — Walking skeleton (Xcode agent). Project + SwiftData/CloudKit models + 20 seed items + masonry renders on all 3 platforms.
- ⬜ **Sprint 1** — Core read UX (Xcode agent). Masonry, week grouping, search, filters (+intent), detail, theming.
- ⬜ **Sprint 2** — Capture + on-device enrichment (Xcode agent + Claude Code bake-off).
- ⬜ **Sprint 3** — Migration (Cursor runs export once; in-app Import).
- ⬜ **Sprint 4** — System integration + delight (mixed).
- ⬜ **Sprint 5** — Polish + ship.

## Handoff log
Each handoff: surface, prompt given, what came back, review notes. Append newest at top.

### (pending) Sprint 0 → Xcode 27 agent
Prompt issued from the orchestration session. Build Spec Sheet (exact constants) attached separately. Awaiting first build for review.

## Review / integration protocol
1. Build happens in Xcode (agent) or Claude Code, on this `feature/native-rewrite` branch (or a `cursor/native-*` sub-branch).
2. When a sprint is "done" in Xcode, the orchestrator (Cursor/Opus) reviews the diff for: PRD fit, HIG/accessibility, SwiftData+CloudKit correctness, test coverage, and parity with the Build Spec Sheet.
3. Orchestrator integrates, updates this board, and issues the next handoff prompt.
4. Per-sprint gate: Xcode build green + relevant tests pass.
