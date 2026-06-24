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

- ✅ **Sprint 0** — Walking skeleton. Models + masonry + 20 seed items render (2-col iPhone confirmed); CloudKit private sync enabled (container `iCloud.com.phloxpage.Stello`); test target green (9 tests/12 runs). Commits e4f9cbf, 789ab6f.
- ✅ **Sprint 1** — Core read UX. Real theme (exact Radix, {dark,amber} default, @AppStorage + Settings picker), ISO-week sections, search, AND tag filters (+intent, counts, pills), DetailView (split on iPad/Mac), 25/25 tests. Commit f0ec677. Minor non-blocking notes below.
- 🟡 **Sprint 2** — Capture + on-device enrichment (planning; will split 2a capture / 2b Foundation Models).
- ⬜ **Sprint 3** — Migration (Cursor runs export once; in-app Import).
- ⬜ **Sprint 4** — System integration + delight (mixed).
- ⬜ **Sprint 5** — Polish + ship.

## Source of truth for constants
`BUILD_SPEC.md` holds the exact web-app constants (tag rules, related-items thresholds, masonry breakpoints, theme hex, capture heuristics, enrichment caps). Building agents must cite it so the Swift port matches behavior.

## Handoff log
Each handoff: surface, prompt given, what came back, review notes. Append newest at top.

### Sprint 1 → reviewed, committed f0ec677
PASS. Theme palettes verbatim-correct; ISO-week via Calendar(.iso8601); AND filter via subset; navigation wired (Item: Hashable); theme persisted + injected; seed status normalized. Minor non-blocking follow-ups: (1) tag filter matches by NAME only — web uses (name, category) pairs; revisit if same name appears across categories. (2) macOS filter sheet doesn't set preferredColorScheme (iOS does). (3) detail tag chips encode weight only via opacity. Carry to a later polish pass.

### Sprint 1 → Xcode 27 agent (issued)
Core read UX: real theme system from `DESIGN_TOKENS.md` (default {dark, amber}, exact Radix hex, accent semantics, settings picker, @AppStorage persistence), ISO-week sections (header `Week N — Month`, newest first, recent expanded / older collapsed), instant search (title/summary/tags), AND-combined tag filters incl. `intent` with active pills, detail view (NavigationSplitView on iPad/Mac), and Swift Testing for week-key/search/filter/theme-persistence. Carry-forwards from Sprint 0 folded in. Open items: (1) signing profile must include the iCloud container before real-device sync (App ID provisioning); (2) graceful no-iCloud-account handling — app already degrades to local store, but add explicit `CKAccountStatus` detection for a clean "sync off" state with zero console noise (CKAccountStatusNoAccount / Code 134400 currently logs on signed-out simulators).

### Sprint 0 → Xcode 27 agent (reviewed, committed e4f9cbf)
Delivered: 4 SwiftData models (CloudKit-ready), local-only container with documented CloudKit-deferral, 20 seed items across domains + 3 ISO weeks (incl. `intent` tags), custom `MasonryLayout` with exact breakpoints + shortest-column packing using real measured heights, `ItemCardView` (SF Symbol covers), multiplatform previews, Swift Testing suite.
Review verdict: PASS for scope. Carry into Sprint 1: (1) theme default should be `{dark, amber}` not `{light, lime}`; (2) accent colors are RGB approximations — replace with exact Radix hex from BUILD_SPEC; (3) Theme defined but not yet injected/applied; (4) seed `enrichmentStatus` uses "done" which isn't in the enum (`pending|text_done|vision_done|candidates_done|error`) — normalize.

## Review / integration protocol
1. Build happens in Xcode (agent) or Claude Code, on this `feature/native-rewrite` branch (or a `cursor/native-*` sub-branch).
2. When a sprint is "done" in Xcode, the orchestrator (Cursor/Opus) reviews the diff for: PRD fit, HIG/accessibility, SwiftData+CloudKit correctness, test coverage, and parity with the Build Spec Sheet.
3. Orchestrator integrates, updates this board, and issues the next handoff prompt.
4. Per-sprint gate: Xcode build green + relevant tests pass.
