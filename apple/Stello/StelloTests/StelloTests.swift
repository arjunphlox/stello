import Testing
import Foundation
import SwiftData
@testable import Stello

@Suite("Stello Sprint 1")
struct StelloTests {

    // MARK: - ISO week key

    @Test("June 24 2026 → 2026-W26")
    func isoWeekKeyJune24() throws {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 24
        let date = try #require(Calendar(identifier: .iso8601).date(from: comps))
        #expect(WeekGroup.isoWeekKey(for: date) == "2026-W26")
    }

    @Test("Jan 1 2026 is Thursday → 2026-W01")
    func isoWeekKeyJan1() throws {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 1
        let date = try #require(Calendar(identifier: .iso8601).date(from: comps))
        #expect(WeekGroup.isoWeekKey(for: date) == "2026-W01")
    }

    @Test("Key format is YYYY-Wnn with zero-padded week")
    func isoWeekKeyFormat() throws {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 8 // week 2
        let date = try #require(Calendar(identifier: .iso8601).date(from: comps))
        let key = WeekGroup.isoWeekKey(for: date)
        #expect(key == "2026-W02")
    }

    // MARK: - Search filtering

    @Test("Search matches title case-insensitively")
    func searchByTitle() {
        let items = [
            Item(title: "Hello World"),
            Item(title: "Goodbye"),
        ]
        let result = ItemFilter.apply(items, searchText: "hello", selectedTagNames: [])
        #expect(result.count == 1)
        #expect(result.first?.title == "Hello World")
    }

    @Test("Search matches summary")
    func searchBySummary() {
        let items = [
            Item(title: "A", summary: "A guide to typography in UI"),
            Item(title: "B", summary: "Swift programming basics"),
        ]
        let result = ItemFilter.apply(items, searchText: "typography", selectedTagNames: [])
        #expect(result.count == 1)
        #expect(result.first?.title == "A")
    }

    @Test("Empty search returns all items")
    func emptySearchReturnsAll() {
        let items = [Item(title: "A"), Item(title: "B"), Item(title: "C")]
        let result = ItemFilter.apply(items, searchText: "", selectedTagNames: [])
        #expect(result.count == 3)
    }

    @Test("Search with no matches returns empty")
    func searchNoMatch() {
        let items = [Item(title: "Swift"), Item(title: "Figma")]
        let result = ItemFilter.apply(items, searchText: "kotlin", selectedTagNames: [])
        #expect(result.isEmpty)
    }

    // MARK: - AND tag filter

    @Test("AND filter: both tags required")
    func andTagFilterBothRequired() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let item1 = Item(title: "Swift UI")
        let tag1a = Tag(name: "swift", category: "tool", weight: 0.9)
        let tag1b = Tag(name: "ui", category: "subject", weight: 0.8)
        ctx.insert(item1); ctx.insert(tag1a); ctx.insert(tag1b)
        tag1a.item = item1; tag1b.item = item1

        let item2 = Item(title: "Swift Only")
        let tag2 = Tag(name: "swift", category: "tool", weight: 0.9)
        ctx.insert(item2); ctx.insert(tag2)
        tag2.item = item2

        try ctx.save()

        let result = ItemFilter.apply([item1, item2], searchText: "", selectedTagNames: ["swift", "ui"])
        #expect(result.count == 1)
        #expect(result.first?.title == "Swift UI")
    }

    @Test("AND filter: single tag matches multiple items")
    func singleTagMatchesMultiple() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let item1 = Item(title: "A")
        let item2 = Item(title: "B")
        let item3 = Item(title: "C")
        let t1 = Tag(name: "swift", category: "tool", weight: 0.9)
        let t2 = Tag(name: "swift", category: "tool", weight: 0.9)
        let t3 = Tag(name: "css", category: "tool", weight: 0.9)
        ctx.insert(item1); ctx.insert(item2); ctx.insert(item3)
        ctx.insert(t1); ctx.insert(t2); ctx.insert(t3)
        t1.item = item1; t2.item = item2; t3.item = item3

        try ctx.save()

        let result = ItemFilter.apply([item1, item2, item3], searchText: "", selectedTagNames: ["swift"])
        #expect(result.count == 2)
    }

    @Test("Empty tag selection returns all items")
    func emptyTagSelectionReturnsAll() {
        let items = [Item(title: "A"), Item(title: "B")]
        let result = ItemFilter.apply(items, searchText: "", selectedTagNames: [])
        #expect(result.count == 2)
    }

    // MARK: - Theme persistence round-trip

    @Test("ColorMode raw value round-trips for all cases")
    func colorModeRoundTrip() {
        for mode in ColorMode.allCases {
            #expect(ColorMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test("AccentColor raw value round-trips for all cases")
    func accentColorRoundTrip() {
        for accent in AccentColor.allCases {
            #expect(AccentColor(rawValue: accent.rawValue) == accent)
        }
    }

    @Test("Default theme is dark / amber per BUILD_SPEC")
    func defaultThemeIsAmbigua() {
        let t = AppTheme()
        #expect(t.mode == .dark)
        #expect(t.accent == .amber)
    }

    @Test("AppTheme reconstructed from raw strings matches original")
    func themeRoundTrip() {
        let original = AppTheme(mode: .light, accent: .iris)
        let restored = AppTheme(
            mode:   ColorMode(rawValue: original.mode.rawValue)   ?? .dark,
            accent: AccentColor(rawValue: original.accent.rawValue) ?? .amber
        )
        #expect(restored == original)
    }

    // MARK: - Seed cover backfill

    @Test("backfillSeedCovers attaches generated covers to URL items missing images")
    func backfillSeedCovers() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let withDomain = Item(
            slug: "figma-auto-layout-guide",
            title: "Auto Layout",
            sourceURL: "https://figma.com/blog/auto-layout",
            domain: "figma.com",
            summary: "A walkthrough of auto layout."
        )
        let note = Item(
            slug: "note-stello-sprint-1",
            title: "Sprint notes",
            summary: "Detail view redesign, tag editor, search with embeddings."
        )
        ctx.insert(withDomain)
        ctx.insert(note)
        try ctx.save()

        let patched = await SeedData.backfillSeedCovers(in: ctx)
        #expect(patched == 1)
        #expect(withDomain.hasRenderableCover)
        #expect(withDomain.coverImage?.hasRenderableCoverData == true)
        #expect(note.images?.isEmpty != false || note.images == nil)
    }

    @Test("backfillSeedCovers replaces broken generated shell rows")
    func backfillReplacesBrokenShells() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let item = Item(slug: "figma-auto-layout-guide", title: "Auto Layout", domain: "figma.com")
        let shell = ItemImage(source: "generated", isPrimary: true)
        ctx.insert(item)
        ctx.insert(shell)
        shell.item = item
        item.images = [shell]
        try ctx.save()

        #expect(await SeedData.backfillSeedCovers(in: ctx) == 1)
        #expect(item.hasRenderableCover)
    }

    @Test("seedIfNeeded persists renderable covers across relaunch context")
    func seedCoverPersistence() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        await SeedData.seedIfNeeded(in: ctx)
        await SeedData.backfillSeedCovers(in: ctx)

        let relaunch = ModelContext(container)
        let items = try relaunch.fetch(FetchDescriptor<Item>(
            predicate: #Predicate { $0.slug == "figma-auto-layout-guide" }
        ))
        #expect(items.first?.hasRenderableCover == true)
    }

    @Test("backfillSeedCovers is idempotent")
    func backfillSeedCoversIdempotent() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let item = Item(slug: "css-tricks-grid", title: "CSS Grid", domain: "css-tricks.com")
        ctx.insert(item)
        try ctx.save()

        #expect(await SeedData.backfillSeedCovers(in: ctx) == 1)
        #expect(await SeedData.backfillSeedCovers(in: ctx) == 0)
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
