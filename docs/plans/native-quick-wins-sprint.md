# Native Quick-Wins Sprint — revisit signal, intent facet, review strip, full search, kind capture

Paste-ready Cursor prompt (Composer 2.5 sub-agents). Source analysis: `BOOKMARK_POSSIBILITIES.md` (Tier-1 items) + session brainstorm 2026-07-06.

---

## Prompt

You are coordinating a quick-wins sprint on the **native Stello app** (`apple/Stello`, SwiftUI multiplatform iOS/iPadOS/macOS 27, local-first SwiftData + CloudKit). Cite `apple/BUILD_SPEC.md` for constants. Work on a `cursor/native-quick-wins` branch.

Dispatch **Tasks A–D as parallel Composer sub-agents** (they touch disjoint files), then run **Task E sequentially** after A–D merge (it touches capture, which D's reviewer may also read). Every task ships with Swift Testing coverage; the gate for the whole sprint is `xcodebuild` green on iOS Simulator + macOS for all targets, all tests passing, plus screenshots in `apple/Stello/.artifacts/`.

**SwiftData + CloudKit rules (all tasks):** every new stored property needs a default value or optional type (CloudKit requirement); never rename/remove existing properties; new entities need inverse relationships. Match the existing code style (see `Item.swift`, `Tag.swift`).

### Task A — Revisit tracking (schema + touch points)
The schema has no revisit signal; every future recommendation/decay/timeline feature depends on it (see `BOOKMARK_POSSIBILITIES.md` §1.3).
1. Add to `Stello/Models/Item.swift`: `var lastOpenedAt: Date?` and `var openCount: Int = 0`.
2. Record an "open" when an item's detail surface appears: the side panel (`Views/SidePanelView.swift` / `SidePanelContent.swift`) and `Views/DetailView.swift`. Debounce per item per app session (an in-memory `Set<UUID>` on the store is fine) so re-opening the same panel while browsing doesn't inflate counts. Do NOT count grid hover or search-result rendering.
3. Bump `openCount`, set `lastOpenedAt = .now`; do not touch `updatedAt` (it means content edits).
4. Tests: opening sets both fields; second open same session doesn't double-count; different session (new debounce set) does.

### Task B — "Why saved" as a first-class intent facet
Why-saved suggestions are generated on-device and stored in `Item.whySavedSuggestionsJSON`, rendered as a sub-card in `Views/CardSubcards.swift` (`whySavedSubCard`), but they are display-only dead ends.
1. Make each why-saved chip tappable: accepting converts it to a `Tag(name: reason, category: "intent", weight: 0.9, source: "manual")` on the item and removes it from the suggestions JSON. Add a subtle dismiss affordance (removes from suggestions without creating a tag). This restores/finishes the Sprint-2b "chips → intent tag @0.9" flow after the UI overhaul.
2. In `Views/TagFilterSheet.swift`, ensure `intent` renders as its own category section with counts, labeled "Why saved", ordered first among categories.
3. Tests: accept creates the intent tag and shrinks suggestions; dismiss shrinks suggestions only; filter by an intent tag returns the item.

### Task C — Search over everything
`Store/ItemFilter.swift` searches only title/summary/tag names. Extend the text match to: `author`, `domain`, snippet text (`item.snippets`), why-saved suggestions, intent tag names (comes free via tags), and the string values inside `metadataJSON` (decode per `kind` via the helpers in `Models/CardMetadata.swift` — e.g. a person's professions, location, social handles; a website's typography/agency/founders `EntityRef` names).
1. Implement as a lazily-built lowercase `searchBlob` per item (compute once per filter pass, not per keystroke per field). Keep `ItemFilter` stateless and testable.
2. Tests: search hits an item by snippet text, by why-saved reason, by a metadata field (e.g. an `IndividualMeta.professions` entry), and still by title/tag; miss returns empty.

### Task D — "Awaiting review" strip
Enrichment suggestions currently surface only if the user happens to open the item (`BOOKMARK_POSSIBILITIES.md` §1.5).
1. Add a horizontally scrolling strip above the grid in `Views/MasonryGridView.swift`/`ContentView.swift` showing up to 8 items where `needsReview == true` and enrichment has completed (`enrichmentStatus` past `pending`), newest first. Compact cards: cover thumb + title + "N suggestions" count.
2. Tapping opens the item's panel (existing navigation). A per-item ✕ sets `needsReview = false`. Strip hides entirely when empty — zero chrome cost.
3. Match the existing design language exactly (12pt gaps, card radius, Karst type — see `apple/Stello/DESIGN_TOKENS.md`). Screenshot both platforms.
4. Tests: strip predicate (needsReview + status) filtering and the dismiss state change.

### Task E — Kind classification + deterministic metadata at capture (sequential, after A–D)
`Item.kind` + per-kind `metadataJSON` (`Models/CardMetadata.swift`) exist but nothing populates them at capture — everything lands as `link`; only the Optacos import fills them.
1. In `Capture/CaptureService.swift`, after the OG parse, classify `kind` deterministically from the fetched HTML — no AI: `og:type == "profile"` or JSON-LD `Person` → `individual`; JSON-LD `Organization` + foundry/type-shop signals (domain or title contains foundry/typefoundry/fonts) → `foundry`; otherwise keep `link` (a generic saved page is NOT a `website` entity — that kind means a site saved *as a reference object*, leave promotion to the user for now). Be conservative: when signals conflict, stay `link`.
2. For `individual` pages, extract deterministically and store in `IndividualMeta`: social URLs (known hosts: x.com/twitter.com, instagram, linkedin, behance, dribbble, bsky.app, mastodon `rel="me"`, threads.net) from `<a href>` + `rel="me"` links; location and job title from JSON-LD `Person` (`address`, `jobTitle`); bio from `og:description`. Only set fields you actually found — never fabricate.
3. Follow the `RuleTagger` porting style: pure functions, exhaustive tests with HTML fixtures (a `Person` JSON-LD page, a `rel=me` indie site, a plain article that must stay `link`).
4. Do NOT add new AI enrichment jobs in this sprint (kind-dispatched prompts are gated on real-device Apple Intelligence verification).

### Wrap-up (coordinator)
- Update `apple/README.md` handoff log (newest at top) and the BACKLOG.md Native app rows for these tasks.
- Report: file-level diff summary, test count before/after, screenshots list.

---

## Deferred follow-ups (explicitly out of scope here)
- Kind-dispatched AI enrichment (`WebsiteHighlights`, `IndividualProfile` @Generable jobs) — gated on real-device AFM verification.
- Typed `Highlight` model (color-scheme / typography / copywriting / animation / graphic / structure) — needs a taxonomy design pass from Arjun first.
- Taste timeline, calendar resurfacing, palette view — next sprint candidates once revisit data accrues.
