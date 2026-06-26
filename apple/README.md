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
- ✅ **Sprint 2a** — In-app capture. RuleTagger (faithful port), CaptureService (classify + on-device OG parse + image download/downsize + slug/dedupe), CaptureSheet (+ button, paste, PhotosPicker), 48 tests. Committed 05bb311. Follow-up: platformNoise in title mining (fold into 2b).
- ✅ **Sprint 2a-share** — Share Extension + App Group shared store. StelloStore factory (App Group + CloudKit / extension / fallbacks), StelloShare extension (NSItemProvider routing -> CaptureService), entitlements on both targets. Built in Xcode, committed 3efdf93.

## Build workflow (switched 2026-06-25)
Xcode GUI proved too painful (targets/capabilities/signing). Now **Cursor-driven**: Opus orchestrates/reviews/commits; **Composer 2.5** sub-agents/sessions edit Swift + a text **XcodeGen `project.yml`**, build/test via `xcodebuild` (iOS Simulator, unsigned), and post screenshots. Toolchain: xcode-select -> /Applications/Xcode-beta.app (Xcode 27); xcodegen 2.45.4. In progress: migrate the hand-managed .xcodeproj to project.yml (all 3 targets).
- ✅ **Sprint 2b** — On-device Foundation Models enrichment. Swappable Enricher (FoundationModels / fallback / mock), @Generable color/style/mood + snippets + why-saved, auto-enrich after capture + launch backfill, DetailView light review (AI tags/snippets/why-saved chips -> intent tag @0.9). 83 tests green. Committed 5ff38bc7.
  - Pending: (1) LIVE on-device AI unverified — simulator lacks Apple Intelligence; verify on a real Apple-Intelligence device (needs signing). (2) Swap in the bake-off-winning prompt into EnrichmentPrompts.swift when ready.

## Sprint 2 complete (capture + intelligence)
2a in-app capture · 2a-share Share Extension · 2b on-device enrichment + bake-off prompts (e454a096, 88 tests).

## Branch + scope (2026-06-25)
- Native + web now COEXIST on `main` (feature/native-rewrite fast-forwarded in). No more branch-switching (it was gutting the working tree). Recovery note: switching the folder to `main` before the merge removed untracked native source; FF restore fixed it.
- Web stack stays until explicit user confirmation (no sunset).
- Next = REFINEMENT (sample data + UI/interactions per user's tweak list), not new features. Sprint 3 (migration) / full curation panel / Sprint 4 deferred.
- Bake-off enrichment prompts (3-job VisionTags/SnippetSet/WhySavedSet design) integrated; live AI still pending real-device verification (simulator lacks Apple Intelligence).
- ⬜ **Sprint 3** — Migration (Cursor runs export once; in-app Import).
- ⬜ **Sprint 4** — System integration + delight (mixed).
- ⬜ **Sprint 5** — Polish + ship.

## Source of truth for constants
`BUILD_SPEC.md` holds the exact web-app constants (tag rules, related-items thresholds, masonry breakpoints, theme hex, capture heuristics, enrichment caps). Building agents must cite it so the Swift port matches behavior.

## Handoff log
Each handoff: surface, prompt given, what came back, review notes. Append newest at top.

### 2026-06-26 — macOS traffic-light inset + bottom-left title with symmetric header padding (Cursor/Composer)
Two changes: (1) `WindowChromeController.repositionTrafficLights` inset = **`windowInset + headerPadding` (24pt from window origin → ~12pt inside the amber header card on x and y)**, re-applied on layout/resize/fullscreen/key; (2) removed the **78pt `macTitleBarLeadingInset` gutter** from `StelloHeaderView` leading padding — title "Stello" + count now sit **bottom-left at the uniform 12pt header padding**, so **title left-gap == icons right-gap == bottom-gap == 12pt** (traffic lights live top-left, title bottom-left — no collision). iOS + macOS build; **99 tests green**. Screenshots: `apple/Stello/.artifacts/macos-controls-inset-12.png`, `macos-header-title-controls.png`.

### 2026-06-25 — Uniform 12pt gaps + glass header + panel parity + card composition (Cursor/Composer)
Single **12pt** inset everywhere (`windowInset`, `sectionGap`, `columnGap`, header top/sides, content-to-panel gap, panel top/right/bottom). Header confined to **content column** (no overlap on side panel); **liquid-glass amber** base via `.glassEffect` tint; wordmark + buttons **bottom-aligned**; `.header-btn` **32×32 rounded squares** (8pt radius, border + fill states). macOS traffic lights **repositioned** via `WindowChromeController` (re-applied on layout/resize/fullscreen/key). Filters panel: search + collapsible category **chips**; Import panel: URL textarea + Import button + or-divider + CSV/Markdown drop zone. Cards: text notes show **title + summary**; fetched OG images render title **below** image (overlay only on generated covers); domain pills **color-tag tinted**. iOS + macOS build; **99 tests green**. Screenshots: `apple/Stello/.artifacts/macos-grid-uniform-gaps.png`, `macos-panel-equal-gaps.png`, `macos-filters-chips.png`, `macos-import-panel.png`, `macos-card-composition.png`.

### 2026-06-25 — Inset header card all-gaps + no button rings + uniform panel inset (Cursor/Composer)
macOS header restructured: **transparent full-width overlay** flush to window top (`.ignoresSafeArea(.top)`), inner padding insets the accent card — **top 8pt**, **sides 12pt** (8pt top keeps native traffic lights ~14pt from window top on the card body without straddling the top edge; sides match content column). Removed `windowInsetPanelOpenTrailing` (6pt); panel now **12pt top/right/bottom** + column gap. Header icon buttons: **fill-only** states (removed capsule stroke + `.focusEffectDisabled()`), active = 16–20% accent-contrast fill, no ring. iOS + macOS build; **99 tests green**. Screenshots: `apple/Stello/.artifacts/macos-header-allgaps.png`, `macos-no-ring-active.png`, `macos-panel-equal-gaps.png`.

### 2026-06-25 — Native traffic lights float on inset header card (Sketch-style, no repositioning)
Removed all custom traffic-light repositioning (`TrafficLightLayout`, `TrafficLightPositioner`, `TrafficLightAnchorView`, `setFrameOrigin` hacks). `MacWindowConfigurator` now only sets transparent title bar chrome (`titlebarAppearsTransparent`, `.fullSizeContentView`, hidden title); dropped `.windowStyle(.hiddenTitleBar)` from `StelloApp` so native buttons render. Content positioned via insets: **top 0pt**, **sides 12pt**, **header corner radius 12pt**, **wordmark gutter 78pt** + `.ignoresSafeArea(.top)` so system traffic lights (~14pt) land on the amber card body. iOS + macOS build; **99 tests green**. Screenshots: `apple/Stello/.artifacts/macos-controls-on-card.png`, `macos-panel-inset.png`.

### 2026-06-25 — macOS inset header card + robust traffic lights + panel/hover/filter fixes (Cursor/Composer)
macOS header is now a **12pt-inset rounded card on all four corners** (removed `.ignoresSafeArea(.top)` full-bleed + square-top `UnevenRoundedRectangle`). **Native traffic lights** repositioned inside the card via `TrafficLightLayout` + `TrafficLightPositioner` — re-applied on `NSView.layout()`, `resizeSubviews`, and `NSWindow` resize/live-resize/fullscreen/key/update notifications (native path, no fallback cluster). Side panel gets **12pt top/right/bottom inset** + existing column gap. Header/panel icon buttons: **16–22% accent-contrast capsule fill** on hover/pressed/active (removed `.glassEffect` tint + `.circle.fill` filter icon that caused glow/dark-block artifact). Screenshot args moved to synchronous `onAppear`. iOS + macOS build; **115 tests green**. Screenshots: `apple/Stello/.artifacts/macos-header-inset-card.png`, `macos-panel-inset.png`, `macos-header-hover.png`, `macos-filters-active.png`, `iphone-17-pro-grid.png`.

### 2026-06-25 — Real-store seed dedupe + idempotent seeding (Cursor/Composer)
Launch-time `SeedData.prepareStore` dedupes the persisted App Group / CloudKit store: collapse duplicate slugs, collapse catalog-URL duplicates under legacy slugs, remove ephemeral screenshot rows (`enrichment-demo`) and retired catalog slugs; then upsert seeds by slug (update-in-place, never insert a second row). CloudKit local-only seed deferred — SwiftData has no per-record sync opt-out without a second container. iOS + macOS build; **99 tests green**. Real-store verification: **21 → 20 items** (removed stale `enrichment-demo` duplicate); relaunch **20 → 20** (idempotent). Screenshot: `apple/Stello/.artifacts/macos-deduped-real-store.png`.

### 2026-06-25 — Native macOS title bar + scroll-reactive header + richer OG seed (Cursor/Opus)
Re-architected the macOS header onto the **native transparent title bar**: removed `MacTrafficLightCluster` + all `standardWindowButton` frame hacks + the negative `macTopContentPadding` (−16) hack. `MacWindowConfigurator` now keeps the real traffic lights visible (`titlebarAppearsTransparent` + `.fullSizeContentView` + hidden title) and the sticky accent banner extends to the window top so the native controls sit on the accent color, top-left (78pt leading inset, square top corners, rounded bottom). Header is **fully opaque at rest, transitioning to accent-tinted `.glassEffect` glass only on scroll** (offset tracked via a `PreferenceKey` probe in `MasonryGridView` → `scrollProgress` binding in `ContentView`). Icon buttons gained **clear macOS hover/pressed fills** (`.onHover` capsule highlight + pressed overlay, full-capsule hit target). Seed catalog bumped to **v3** with 6 swapped URLs verified live for og:image (figma config-2024, Apple HIG, Tailwind v4, Typewolf, Notion, Vercel AI SDK) → ~17/18 URL cards now show real covers, the lone miss using the real `LinearGradient` fallback. Screenshot-only launch args added (`-screenshotCleanStore` in-memory store to dodge CloudKit-synced legacy rows; `-screenshotExpandAll`). iOS + macOS build; 95 tests green. Screenshots: `apple/Stello/.artifacts/macos-header-rest.png` (opaque, native controls, full cover grid), `macos-header-scrolled.png` (translucent, content under header), `iphone-17-pro-grid.png`. (macOS live hover not captured — would require moving the cursor onto a background window, which violates the no-foreground-theft rule.)

### 2026-06-25 — Five UI fixes: equal top inset, OG covers, panel wiring, glass buttons, floating header (Cursor/Composer)
Fixed macOS top gap (neutralize ~28pt title-bar safe area via negative padding), replaced fake seed URLs + catalog migration v2 for real OG covers, restored filters/import/settings panel toggles (traffic-light overlay was stealing hits), 36×36 capsule hit targets with hover/press on `StelloGlassIconButton`, floating accent-tinted glass header with grid scrolling underneath. 94 tests green; screenshots at `apple/Stello/.artifacts/macos-*.png` + `iphone-17-pro-og-grid.png`.

### 2026-06-25 — Session end: 12pt inset, floating glass search, uniform SF icons (Cursor/Composer)
Halved window inset (24→12pt) on top/leading/trailing with bottom content bleed (no outer bottom gap; scroll inset clears floating search). Uniform 36×36 Liquid Glass icon buttons via `StelloGlassIconButton` (filters `line.3.horizontal.decrease`, import `plus`, settings `gearshape`). Centered floating `.glassEffect` search bar on iOS/iPadOS/macOS. 92 tests green; screenshots at `apple/Stello/.artifacts/macos-12pt-floating-search.png` + `iphone-17-pro-floating-search.png`.

### 2026-06-25 — Session end: compact header + iPhone title fixes (Cursor/Composer)
Fixed macOS header balloon regression (fixed 120pt ZStack layout: traffic lights top-left, wordmark+pills bottom) and iPhone "St…" truncation (compact tighter pill buttons, wordmark `fixedSize` + layout priority). Kept pill glass buttons, real OG covers, equal 24pt window insets, SwiftUI traffic lights. Stronger OG card bottom scrim. 92 tests green; screenshots at `apple/Stello/.artifacts/macos-compact-header.png` + `iphone-17-pro-header.png`.

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
