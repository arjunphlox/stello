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
