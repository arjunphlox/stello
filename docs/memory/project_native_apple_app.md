---
name: Native Apple app — SwiftUI multiplatform architecture
description: Stello native app under apple/Stello — local-first SwiftData+CloudKit, on-device Foundation Models enrichment, XcodeGen build harness, macOS inset-glass header pattern, CloudKit seed dedupe gotchas; coexists with web app
type: project
originSessionId: native-app-foundation-ship
---
Stello's native Apple app lives at `apple/Stello/` — a SwiftUI multiplatform target (iOS/iPadOS/macOS 27) that coexists with the web app. Web is NOT sunset until explicit OK.

## Architecture

- **Data:** local-first SwiftData + CloudKit sync (no backend dependency for native)
- **Enrichment:** on-device Apple Foundation Models (AFM 3) via `@Generable` for color/style/mood + snippets + why-saved; rule-based fallback when AFM unavailable
- **Capture:** paste/URL/text/image + Share Extension; on-device OG parse; rule tags ported from web
- **Read UX:** masonry Layout, ISO weeks, search, AND tag filters (incl. intent), detail view, light/dark + lime/amber/iris on Liquid Glass
- **macOS chrome:** web-faithful inset glass-amber header with native window controls, unified side panel, floating glass search

## Build harness

- **Source of truth:** `apple/Stello/project.yml` (XcodeGen) — agent-editable text project, not Xcode GUI target/capability/signing
- **CLI test:** `xcodebuild -project apple/Stello/Stello.xcodeproj -scheme Stello -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` (99 tests, unsigned iOS 27 sim)
- **Model routing:** Composer 2.5 executes building; Opus only orchestrates/reviews — Opus-as-builder caused UI drift
- **macOS screenshots:** use `open -g` (non-foreground) to avoid focus-stealing during visual verification

## macOS header pattern (Sketch reference)

Native window controls float on an inset glass-amber card — **never reposition the traffic lights**.

- Transparent `fullSizeContentView` titlebar
- Controls stay at native top-left; content card inset ~12pt on all edges
- Sketch.app is the reference: controls float native, card is inset — repositioning buttons drops/loses them

See `MacWindowConfigurator.swift`, `StelloHeaderView.swift`, `StelloLayout.swift`.

## SwiftData + CloudKit gotchas

- **Seed dedupe:** dedupe by slug + idempotent upsert in `SeedData`/`StelloStore.dedupe` — editing `SeedData.swift` alone never migrates persisted/CloudKit rows
- **Broken ItemImage shells:** rows with `isPrimary` set but `externalStorage` nil win cover selection → blank cards. Fix: purge shell rows + prefer renderable covers (`backfillSeedCovers`, `SampleCoverGenerator`)
- **CloudKit dupes:** if dupes recur after dedupe, consider a local-only seed container (non-synced)

## Status (2026-06-26)

Sprints 0–2 + refinement shipped. Pending: Sprint 3 (Supabase→native migration + cross-device sync verification), real-device AFM verification (sim uses mock only), Sprint 4 (full curation panel + App Intents/Spotlight/Visual Intelligence).

## UI overhaul lessons (2026-07-01, branch `cursor/native-visual-karst-zoom`)

Large web-parity + interaction pass (Karst font, single grid + timeline, panel, controls, zoom, drag-drop). Durable gotchas:

- **Side-panel width jumps per item** = `.fixedSize(horizontal: true)` on the panel: it overrides `.frame(width:)` and sizes to content. Use a fraction-based `.frame(width: viewport * clamp(0.25…0.5))` (persist the fraction in `@AppStorage`), no `fixedSize`.
- **Granular pinch zoom** beats whole-grid `.scaleEffect` (which scales everything + clips at the grid bounds mid-gesture). Live-step the column count: `target = clamp(round(baseCols / magnification), 1, 12)`, apply inside `withAnimation(.smooth)`, and add ~0.35 hysteresis (deadband) so it doesn't oscillate at a boundary. Capture `baseCols` on first `.onChanged`; persist on end.
- **Timeline = floating leading `.overlay`, no reserved gutter** (so cards use full width). Confine interaction to a narrow ~44pt left strip with ONE `.onContinuousHover` (pointer) + `DragGesture(minimumDistance:0)` (touch) that maps pointer-Y → nearest line via a `lineCenters` PreferenceKey. Per-line `.onHover` + `.frame(maxWidth:.infinity)` leaks hover to the right and blocks card taps.
- **iOS sticky header slid under the notch** because `.ignoresSafeArea(edges: .vertical)` zeroed the top safe-area inset. Use `.ignoresSafeArea(edges: .bottom)` only (respect top) while a separate `theme.background.ignoresSafeArea()` still bleeds behind the status bar.
- **`.fileExporter` / `NSSavePanel` on macOS wedges the app** (`REPORT_APP_ENTITLEMENTS_INSUFFICIENT` → `AppKitBreakInDebugger`, unkillable by `kill -9`) unless the sandbox grants `com.apple.security.files.user-selected.read-write` (`ENABLE_USER_SELECTED_FILES: readwrite`). `readonly` is the trap.
- **Zip a folder with zero SPM deps:** `NSFileCoordinator().coordinate(readingItemAt: folderURL, options: [.forUploading]) { zippedURL in … }` returns a `.zip` of the directory — read its `Data`, export via `.fileExporter(UTType.zip)`.
- **Video local-only (avoid CloudKit bloat):** write bytes to Application Support and store only a path `String` in a `LocalAttachment` @Model (NOT `@Attribute(.externalStorage)`), so CloudKit syncs a non-resolving path = effectively device-local. Register the model in the container schema.
- **Model name collision:** `Attachment` clashes with FoundationModels' `Attachment` → name it `LocalAttachment`.
- **Typography:** rem has no native equivalent and hardcoding it breaks Dynamic Type. Use points + Dynamic Type via `Font.custom(_, size:, relativeTo: style)`. Base body = 14pt with a derived monotonic scale centralized in `StelloFont.defaultSize(for:)`; keep deliberate fixed sizes (wordmark, card title/pill zoom curve, timeline label) explicit.
- **App-icon / Open-With capture:** declare `CFBundleDocumentTypes` (+ `UTImportedTypeDeclarations`) in `Info.plist` and handle `.onOpenURL` on the root scene; SwiftUI non-document apps still receive Dock-dropped files this way.
- **XcodeGen + iCloud path** spawns `Stello 2.xcodeproj` / `Stello 3.xcodeproj` duplicate siblings on `xcodegen generate`. Gitignore `apple/**/*[0-9].xcodeproj/` and delete strays; only `Stello.xcodeproj` is real.
- **Codesign "resource fork / detritus"** on `StelloShare.appex` blocks signed build/test under the iCloud/space workspace path. Clear with `xattr -cr <project>` and build/test into `-derivedDataPath /tmp/StelloDD`.
- **`.build-artifacts/` (Xcode DerivedData) is ~1.3 GB** — must be gitignored, never committed.

## Optacos CMS import + typed detail panel (2026-07-02, branch `cursor/native-visual-karst-zoom`)

- **Schema:** `Item.kind` (String) + `Item.metadataJSON` (Codable per-kind: `TypefaceMeta`, `WebsiteMeta`, …) + `ItemImage.role` (cover/specimen/gallery). Avoids SwiftData model explosion + keeps CloudKit syncable.
- **Seed:** `Stello/Resources/OptacosSeed.json` — 10 Framer CMS collections (162 entity rows + 197 tag rows). Export via `@framer/agent`; bundle as app resource.
- **Import:** `OptacosImporter.importIfNeeded` runs once after demo seed (UserDefaults guard + skip if typed items exist). Tag collections applied in a second pass; entity refs resolve by slug. Cross-collection slug collisions → `slug-kind` suffix.
- **Images:** async fetch w/ concurrency 5; Optacos SVGs skip the 500-byte OG floor. Offline test hook: `Options.offline` (no network, no guard).
- **Panel:** `CardSubcards` — outline-only sub-cards, render-if-data, 2 columns at ≥520pt panel width. Entity refs → tappable chips when target `Item` exists in store.
- **App icon:** Icon Composer `.icon` bundle in `Stello/Stello.icon/`; `ASSETCATALOG_COMPILER_APPICON_NAME = Stello`. Copy from Downloads when the design updates — do not hand-edit PNG layers inside the bundle.

## Native quick-wins sprint (2026-07-06, branch `cursor/native-quick-wins`)

Shipped A–E (117→138 macOS tests). Timeline nudge session same day **reverted** — deferred to a future session.

| Task | What shipped |
|---|---|
| A Revisit tracking | `Item.lastOpenedAt`, `Item.openCount`; `StelloStore.recordOpen(for:)` + session debounce; `DetailView.onAppear` |
| B Why-saved intent | Tappable chips → intent tag @0.9; dismiss; `TagFilterSheet` "Why saved" first |
| C Search blob | `ItemSearchBlob.swift`; extended `ItemFilter` full-text match |
| D Awaiting review strip | `AwaitingReviewFilter.swift`, `AwaitingReviewStripView.swift`, masonry integration + seed `-screenshotAwaitingReview` |
| E Page classification | `PageClassifier.swift` in capture path; `PageClassifierTests.swift`; Share target includes `PageClassifier.swift` + `CardMetadata.swift` via `project.yml` |

### PR #30 fix round lessons (2026-07-06, Sonnet 5 sub-agent round)

138 → 154 macOS tests. Durable gotchas from the review fixes:

- **Computed property → cached @State migration = staleness trap.** Replacing a computed filter (`awaitingReviewItems`) with a `cached*` @State silently loses the "body re-eval sees model mutations" behavior. Every mutation path that used to be picked up implicitly needs an explicit invalidation: refresh in the same handler for in-view mutations, plus a cheap signature `.onChange(of: allItems.map(\.someFlag))` (bool array) for mutations arriving from other views (panel/EnrichmentService).
- **`.onAppear` undercounts in persistent panel views.** SidePanel keeps one DetailView mounted across `selectedItem` changes (same view identity, no `.id()`), so `.onAppear` fires once per panel open, not per item. Use `.task(id: item.persistentModelID)` for per-item side effects — it re-runs on id change even with stable view identity, and covers sheet/push/panel/related-nav in one place.
- **Screenshot fixtures must never mutate persisted rows.** `ensureAwaitingReviewFixtures` was flipping flags + fabricating JSON on the 4 newest real items and CloudKit-synced the fake data. Guard fixture mutators with `context.container.configurations.allSatisfy(\.isStoredInMemoryOnly)`.
- **Classifier signals need structural context, not presence.** Any JSON-LD `Person` ⇒ individual mis-fired on every Yoast article (author Person in `@graph`); require top-level or `mainEntity`/`about` targeting. Host matching must be exact-host or dot-suffix (`host.contains("linkedin.com")` matched `linkedin.com.evil.net`); keyword signals whole-word/domain-label, never substring. When signals are weak/conflicting, stay `link`.

### Timeline + header — frozen until explicit OK (2026-07-06 failed session)

A timeline nudge pass (4px left, +1px bar, max corners) broke macOS chrome. Root causes:

- **`embedInPanelLayout: true` on macOS** — gating timeline tweaks on `!embedInPanelLayout` meant offsets never applied on macOS (the primary surface).
- **Negative `.offset(x:)`** — parent `.clipped()` cut the timeline off-screen.
- **`gridLeadingInset` on cards** — pushed masonry; timeline looked like it invaded the grid gutter.
- **Header/toolbar edits** — removing macOS top padding, square-top shape, solid-at-rest fill, scroll inset changes, and `MacWindowConfigurator` NSToolbar/`showsBaselineSeparator = false` caused clipped header + **duplicate "Stello" title** in the titlebar.

**Do not touch (future timeline session):** `StelloHeaderView.swift`, `MacWindowConfigurator.swift`, `ContentView.headerOverlay`, `StelloLayout` header constants, negative offsets, NSToolbar/titlebar separator.

**Safe scope for timeline nudges:** `TimelineOverlay.swift` only, plus at most one targeted padding tweak on the card/masonry stack in `MasonryGridView.swift` — trace macOS vs iPhone invariants first (`embedInPanelLayout`), one change at a time, screenshot gate before done, revert on first visual fail.

**Card↔header alignment + ring clip (2026-07-06):** cards sat 6pt inside the header edges because `selectionOutlineInset` padded the card stack uniformly. Aligning cards flush requires moving the 4pt selection ring's headroom into the clip boundary, not the content: `.scrollClipDisabled()` + a custom `HorizontalOutsetClip` shape (±6pt `gridRingClipOutset` horizontal, exact vertical) instead of tight `.clipped()`. General lesson: SwiftUI `.overlay`/outset strokes clip at the nearest `.clipped()` ancestor — "absolute positioning" doesn't escape parent clip bounds; widen the clip, never negative-offset out of it. Headless macOS screenshot recipe: `open -g <app> --args -screenshot*`, second `open -g` ping (background launch defers window creation), `screencapture -x -o -l <CGWindowList windowID>`; iPhone `simctl io screenshot`.

**Timeline-in-gutter (shipped 2026-07-06, second attempt):** the 12pt window gutter is `ContentView.regularLayout`'s HStack leading padding — OUTSIDE MasonryGridView's three `.clipped()` boundaries, so no TimelineOverlay/MasonryGridView edit can reach it (this is why negative offsets got clipped invisible last time). Working pattern: grid column absorbs the inset (`gridColumnWidth = gridWidth + windowInset`, HStack leading pad removed), then card stack / control bar / headerOverlay call-site frame compensate so only the timeline moves; bars centered via `(windowInset − barWidth)/2`. Gotcha caught at gate: blanket compensation pads flatten platform-conditional insets — iPhone's control bar uses `controlBarSideInsetCompact` (16pt) ≠ `windowInset` (12pt); keep compensations `embedInPanelLayout`-conditional.

**Process gate:** Composer executes; visual screenshot verification required before marking UI tasks done; never batch header + timeline in one pass.
