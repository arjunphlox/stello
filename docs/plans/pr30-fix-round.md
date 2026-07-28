# PR #30 fix round — Claude Code desktop, Sonnet 5 sub-agents

Paste-ready prompt for a **Claude Code desktop** session on the Mac (needs Xcode 27 toolchain).
Session model / orchestrator: **Opus 4.8**. Execution: **Sonnet 5 sub-agents** via the Task tool.
Haiku 4.5 was considered and rejected for the fix bundles — every finding here came from a
fast-but-shallow executor, and the fixes require SwiftUI identity / SwiftData store / classifier-
heuristic reasoning. Haiku is only appropriate for the final docs wrap-up.

Findings source: adversarially verified review of PR #30 (2026-07-06), 9 confirmed findings.

---

## Prompt

You are orchestrating a fix round for PR #30 (`cursor/native-quick-wins`) on the native Stello app (`apple/Stello`, SwiftUI multiplatform iOS/iPadOS/macOS 27, SwiftData + CloudKit). Check out `cursor/native-quick-wins` and push fixes there so PR #30 updates.

**First, read `docs/memory/MEMORY.md` and `docs/memory/project_native_apple_app.md`** (on this branch) — they carry the build harness, SwiftData/CloudKit gotchas, and hard guardrails below.

### Build harness — zero Xcode GUI (hard rule)
All building/testing is CLI-only; never open or ask the user to open Xcode. The toolchain is already configured (`xcode-select` → Xcode-beta / Xcode 27; xcodegen installed).
- `apple/Stello/project.yml` (XcodeGen) is the project source of truth. If (and only if) a bundle needs target-membership changes, edit `project.yml` and run `xcodegen generate` from `apple/Stello/` — then check for and delete stray `Stello 2.xcodeproj`-style duplicates (an iCloud-path XcodeGen artifact; only `Stello.xcodeproj` is real). None of the bundles below should need this.
- Tests (gate): `xcodebuild -project apple/Stello/Stello.xcodeproj -scheme Stello -destination 'platform=macOS' -derivedDataPath /tmp/StelloDD test`
- iOS build (gate): same with `-destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` (unsigned sim — no signing setup ever).
- If codesign fails with "resource fork / detritus" on `StelloShare.appex`: `xattr -cr apple/Stello` and keep `-derivedDataPath /tmp/StelloDD`.
- Screenshots: the existing launch-arg pattern (`-screenshotCleanStore` + feature args) into `apple/Stello/.artifacts/`; launch macOS builds with `open -g` (non-foreground, no focus-stealing).

### Frozen files — do not touch (from the failed 2026-07-06 timeline/header session)
`StelloHeaderView.swift`, `MacWindowConfigurator.swift`, `ContentView`'s `headerOverlay`, `StelloLayout` header constants, `TimelineOverlay.swift`, anything NSToolbar/titlebar. Bundle 4 edits ContentView's selection path (`handleCardTap`) ONLY — if a fix seems to require a frozen file, stop and report instead of editing.

### Session discipline (repo contract)
Trace structural invariants before changing shared code; one bundle = one concern, surface unrelated issues instead of folding them in; verify visually (screenshot) before calling UI work done; append durable new lessons to `docs/memory/MEMORY.md` (+ index) at the end.

**Your role (orchestrator): plan, dispatch, review, gate. Write no code yourself.** Dispatch each bundle below as a **Sonnet 5 sub-agent** (Task tool, `model: sonnet`). Bundles 1–5 touch disjoint files and may run in parallel; the file ownership listed per bundle is a hard boundary — a sub-agent must not edit files outside its list (this is how the last round broke things). Instruct every sub-agent to think through the failure mechanism before editing, keep diffs minimal, and extend the existing test files rather than restructuring them.

**Acceptance gate, applied by you per bundle:** read the returned diff against the finding; reject and re-dispatch with feedback if the fix is shallow (e.g. patches the symptom in the view instead of the named mechanism). Sprint-wide gate: `xcodebuild -project apple/Stello/Stello.xcodeproj -scheme Stello -destination 'platform=macOS' test` green, iOS Simulator build green, all pre-existing 138 tests still passing plus new regression tests per bundle.

### Bundle 1 — PageClassifier correctness + hygiene (Sonnet 5, extended thinking)
Files: `Capture/PageClassifier.swift`, `Capture/CaptureService.swift`, `StelloTests/PageClassifierTests.swift`.
1. **Over-eager classification (CONFIRMED).** `hasIndividualSignals` (PageClassifier.swift:48) fires on ANY JSON-LD `Person`, and `collectTypedNodes` recurses into `@graph` — so Yoast-style publisher articles (author `Person` in `@graph` on every page) become `kind=individual` with the *author's* jobTitle/address/socials written into `IndividualMeta` and the article og:description as "bio". `hasFoundrySignals` (lines 53–57) fires on any `Organization` + bare `"fonts"` substring in title/domain — "The 10 Best Free Fonts of 2026" becomes a foundry. Fix: for `individual`, require the Person to be a top-level node or the page's `mainEntity`/`about` (an author/publisher-nested Person inside an Article/@graph context must NOT count), or require og:type=profile as a co-signal; for `foundry`, require the keyword as a word/domain-label match (not bare substring) and treat keyword-only weak matches as `link`. The spec rule is: when signals conflict or are weak, stay `link`. Add negative fixtures: Yoast `@graph` article with author Person; publisher article titled with "fonts" + Organization node.
2. **Social-link mis-assignment (CONFIRMED).** `applySocialLinks` (lines 185–198) harvests every `<a>` first-match-wins with host-only matching: `twitter.com/intent/tweet` share widgets and links to other people's profiles become `xURL`; `host.contains("linkedin.com")` matches `business.linkedin.com` and `linkedin.com.evil.net`; any unrecognized https `rel=me` link is blindly stored as `mastodon` (lines 195, 236). Fix: exact-host or dot-suffix matching only; skip known share/intent paths (`/intent/`, `/share`); prefer `rel=me` links over body anchors when both exist; drop the mastodon fallback for unrecognized hosts (leave unset). Add fixtures: intent link, foreign profile in body, `rel=me` GitHub link.
3. **Parser hygiene (CONFIRMED).** PageClassifier duplicates CaptureService.parseOG's meta/attribute regexes character-for-character (PageClassifier.swift:289,302 vs CaptureService.swift:189,195), re-scans metas for og:type that parseOG already walked, calls `jsonLDTypedNodes(from:)` up to 3× per classify, and constructs every `NSRegularExpression` per call (parseAttributes runs once per tag). Fix: hoist patterns to `static let` compiled regexes; parse JSON-LD once at the top of `classify` and pass nodes down; add an `ogType` field to `OGResult` populated in parseOG and delete PageClassifier's meta re-scan; share one attribute-parsing helper between the two files.

### Bundle 2 — Review-strip lifecycle + fixture safety (Sonnet 5)
Files: `Store/AwaitingReviewFilter.swift`, `Views/AwaitingReviewStripView.swift`, `Capture/EnrichmentService.swift`, `Store/SeedData.swift`, `StelloTests/AwaitingReviewStripTests.swift`.
1. **`needsReview` never cleared (CONFIRMED).** Only the strip's ✕ ever sets it false (AwaitingReviewFilter.swift:31). `addIntentTag` and `dismissWhySavedSuggestion` (EnrichmentService.swift:105–141) don't clear it even when the last suggestion is consumed, and `isEligible` (line 10) doesn't require non-empty suggestions — so fully-reviewed items sit in the strip as "0 suggestions" forever and legacy items (default `true`) fill it on upgrade. Fix: clear `needsReview` in both EnrichmentService mutations when the remaining suggestion list becomes empty, AND add a non-empty-suggestions requirement to `isEligible`. Tests: accept-last-suggestion removes item from strip; zero-suggestion item ineligible.
2. **Fixture corrupts real store (CONFIRMED — data integrity).** `ensureAwaitingReviewFixtures` (SeedData.swift:270–289) flips `needsReview=true` and fabricates `whySavedSuggestionsJSON` on the 4 newest REAL items + inserts a permanent fixture row, then saves — and `-screenshotAwaitingReview` is wired independently of `-screenshotCleanStore` (ContentView.swift:111 vs StelloApp.swift:14), so a screenshot run against a dev store syncs fake data via CloudKit with no cleanup. Fix inside SeedData (do NOT touch ContentView/StelloApp — Bundle 4 owns them): make `ensureAwaitingReviewFixtures` a no-op unless the ModelContext's container is in-memory (`isStoredInMemoryOnly`). Never mutate persisted rows for screenshots.
3. While here: `suggestionsLabel` JSON-decodes per row render (AwaitingReviewFilter.swift:25–28 called from AwaitingReviewStripView.swift:42) — compute counts once when the strip's items change, not in row body.

### Bundle 3 — Search performance + coverage (Sonnet 5, extended thinking)
Files: `Store/ItemFilter.swift`, `Store/ItemSearchBlob.swift`, `Views/MasonryGridView.swift`, `StelloTests/SearchBlobTests.swift`.
1. **Dead cache + per-keystroke JSON decoding (CONFIRMED).** `searchBlobCache` (ItemFilter.swift:15) is a local dict per `apply()` call where each item is looked up exactly once — zero hits ever — while `ItemSearchBlob.build` JSON-decodes `metadataJSON` + `whySavedSuggestionsJSON` per item, on the main thread, per keystroke. Fix: a real persistent cache — e.g. a static/actor-scoped `[UUID: (stamp: Date, blob: String)]` inside `ItemSearchBlob` keyed by `(item.id, item.updatedAt)` (do NOT put it in StelloStore — Bundle 4 owns store/view wiring). Keep `ItemFilter.apply` stateless in signature.
2. **Double filter pass (CONFIRMED).** `refreshFilterCaches` (MasonryGridView.swift:148–156) calls `ItemFilter.apply` twice per change even when `selectedWeekKey` is nil. Fix: derive the week-filtered array from the already-filtered result (`tagFiltered.filter { WeekGroup.isoWeekKey... }`), one `apply` call total.
3. **Strip filter runs per body eval (CONFIRMED).** `awaitingReviewItems` (MasonryGridView.swift:143) filters+sorts `allItems` on every body evaluation — and body re-evaluates every ~10pt of scroll. Fix: fold it into the existing `cached*` @State pattern refreshed in `refreshFilterCaches`.
4. **`bodyMarkdown` unsearchable (CONFIRMED).** ItemSearchBlob omits it, so dropped text/markdown files (DropImportService stores full content there) can't be found by body text. Fix: append to the blob; add a test with a body-only match.

### Bundle 4 — Revisit tracking placement (Sonnet 5, extended thinking)
Files: `Views/DetailView.swift`, `Views/SidePanelView.swift`, `ContentView.swift`, `Store/StelloStore.swift`, `StelloTests/RevisitTrackingTests.swift`.
**Opens undercounted on the primary surface (CONFIRMED).** `recordOpen` hangs on `DetailView.onAppear` (DetailView.swift:16), but the macOS/iPad side panel keeps one DetailView mounted while `selectedItem` changes (SidePanelView.swift:111, no `.id()` in the path), so browsing N items through an open panel records exactly 1 open. Only the iPhone sheet/push paths count correctly. Fix at the right altitude: either `.task(id: item.persistentModelID)` in DetailView (fires per identity change) or record in the shared selection path (`ContentView.handleCardTap` / the `selectedItem` setter) — pick one place through which ALL open paths flow, and make sure related-item navigation inside the panel (`detailOpenItem`) also counts. Keep the per-session debounce semantics. Add a test that simulates consecutive different-item opens recording each, and same-item re-open still debounced.

### Bundle 5 — Why-saved chip interaction (Sonnet 5)
Files: `Views/CardSubcards.swift` only.
**Accept target shrank to bare text; destructive ✕ 4pt away, no undo (CONFIRMED).** On main the whole capsule was the accept Button; now padding/background sit on a non-interactive HStack, both buttons are glyph-bounds only (far under 44pt), and dismiss permanently deletes with no confirmation (CardSubcards.swift:275–299). Fix: restore the full-capsule accept hit area (`.contentShape` on a padded label), give the ✕ its own comfortably padded target with clear visual separation (or move dismiss behind a long-press/context menu), and ensure both meet platform hit-target guidance. Do not change EnrichmentService semantics (Bundle 2 owns that file). Screenshot the chip row on macOS + iOS after.

### Wrap-up (you, the orchestrator; optionally a Haiku 4.5 sub-agent for the docs)
- Re-run the full gate (macOS tests + iOS build, commands above). Report per-bundle: accepted/rejected rounds, final diff summary, test count before/after.
- Update `apple/README.md` handoff log (newest at top) noting this was a Sonnet 5 fix round against the PR #30 review findings, and append any durable new lessons to `docs/memory/project_native_apple_app.md` (+ MEMORY.md index).
- Push to `cursor/native-quick-wins` (updates PR #30). Do not merge.

## Deferred (not in this round)
- Generic reflection-based `searchTerms()` to replace the six hand-enumerated per-kind extensions (design choice — parallel field lists remain a drift risk).
- `slugify` vs `makeSlug` divergence (latent; matters when location becomes a navigable chip).
- TagFilterSheet default expansion fallback for zero-intent libraries (one-line UX call).
