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
        ctx.insert(item1)
        item1.tags = [
            ItemTag(name: "swift", category: "tool", weight: 0.9),
            ItemTag(name: "ui", category: "subject", weight: 0.8),
        ]

        let item2 = Item(title: "Swift Only")
        ctx.insert(item2)
        item2.tags = [ItemTag(name: "swift", category: "tool", weight: 0.9)]

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
        ctx.insert(item1); ctx.insert(item2); ctx.insert(item3)
        item1.tags = [ItemTag(name: "swift", category: "tool", weight: 0.9)]
        item2.tags = [ItemTag(name: "swift", category: "tool", weight: 0.9)]
        item3.tags = [ItemTag(name: "css", category: "tool", weight: 0.9)]

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

    @Test("AccentColor resolves to mode-appropriate default when stored accent is out-of-set")
    func accentColorModeResolution() {
        #expect(AccentColor.resolved(storedRawValue: "iris", for: .dark) == .amber)
        #expect(AccentColor.resolved(storedRawValue: "lime", for: .light) == .iris)
        #expect(AccentColor.resolved(storedRawValue: "cyan", for: .dark) == .cyan)
        #expect(AccentColor.resolved(storedRawValue: "teal", for: .light) == .teal)
    }

    @Test("Accent picker sets differ by color mode")
    func accentChoicesByMode() {
        #expect(AccentColor.choices(for: .dark) == AccentColor.brightChoices)
        #expect(AccentColor.choices(for: .light) == AccentColor.mutedChoices)
        #expect(AccentColor.choices(for: .dark).count == 6)
        #expect(AccentColor.choices(for: .light).count == 6)
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

    @Test("header layout constants use uniform 12pt inset everywhere")
    func headerLayoutConstants() {
        #expect(StelloLayout.macTitleBarLeadingInset == 78)
        #expect(StelloLayout.windowInset == 12)
        #expect(StelloLayout.sectionGap == 12)
        #expect(StelloLayout.columnGap == 12)
        #expect(StelloLayout.headerCornerRadius == 12)
        #expect(StelloLayout.iconButtonFootprint == 32)
        #expect(StelloLayout.iconButtonCornerRadius == 8)
        #expect(StelloLayout.headerScrollFadeDistance > 0)
    }

    @Test("headerOverlayScrollInset clears header + gap + top inset")
    func headerOverlayScrollInset() {
        let expected = StelloLayout.headerHeight
            + StelloLayout.sectionGap
            + StelloLayout.windowInset
        #expect(StelloLayout.headerOverlayScrollInset == expected)
    }

    @Test("dedupe collapses duplicate slugs and preserves unique slugs")
    func dedupeDuplicateSlugs() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let stale = Item(
            slug: "figma-auto-layout-guide",
            title: "Stale Auto Layout",
            sourceURL: "https://figma.com/blog/auto-layout",
            domain: "figma.com"
        )
        let fresh = Item(
            slug: "figma-auto-layout-guide",
            title: "Auto Layout Demystified",
            sourceURL: "https://www.figma.com/blog/design-systems-101-what-is-a-design-system/",
            domain: "figma.com",
            enrichmentStatus: "candidates_done"
        )
        let user = Item(slug: "my-captured-article-2", title: "User Item")
        ctx.insert(stale)
        ctx.insert(fresh)
        ctx.insert(user)
        try ctx.save()

        let result = SeedData.deduplicateAndCleanSeedStore(in: ctx)
        #expect(result.countBefore == 3)
        #expect(result.countAfter == 2)
        #expect(result.removedCount == 1)

        let remaining = try ctx.fetch(FetchDescriptor<Item>())
        #expect(remaining.count == 2)
        let slugs = Set(remaining.map(\.slug))
        #expect(slugs == ["figma-auto-layout-guide", "my-captured-article-2"])

        let figma = remaining.first { $0.slug == "figma-auto-layout-guide" }
        #expect(figma?.sourceURL?.contains("design-systems-101") == true)
    }

    @Test("seedIfNeeded upserts by slug without creating duplicates")
    func seedIfNeededIdempotent() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let existing = Item(
            slug: "figma-auto-layout-guide",
            title: "Old Title",
            domain: "figma.com"
        )
        ctx.insert(existing)
        try ctx.save()

        await SeedData.seedIfNeeded(in: ctx)
        let items = try ctx.fetch(FetchDescriptor<Item>())
        let figmaRows = items.filter { $0.slug == "figma-auto-layout-guide" }
        #expect(figmaRows.count == 1)
        #expect(figmaRows.first?.title == "Auto Layout Demystified")
        #expect(items.count == SeedData.catalogManagedSlugs().count)
    }

    @Test("dedupe removes ephemeral screenshot seed rows")
    func dedupeRemovesEphemeralSeeds() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Item(slug: "enrichment-demo", title: "Auto Layout Demystified"))
        ctx.insert(Item(slug: "figma-auto-layout-guide", title: "Auto Layout Demystified", domain: "figma.com"))
        try ctx.save()

        let result = SeedData.deduplicateAndCleanSeedStore(in: ctx)
        #expect(result.removedCount == 1)
        let slugs = Set(try ctx.fetch(FetchDescriptor<Item>()).map(\.slug))
        #expect(!slugs.contains("enrichment-demo"))
        #expect(slugs.contains("figma-auto-layout-guide"))
    }

    @Test("dedupe collapses catalog URL duplicates under different slugs")
    func dedupeCatalogURLDuplicates() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let url = "https://www.figma.com/blog/design-systems-101-what-is-a-design-system/"
        ctx.insert(Item(slug: "legacy-figma-auto-layout", title: "Old", sourceURL: url, domain: "figma.com"))
        ctx.insert(Item(slug: "figma-auto-layout-guide", title: "Fresh", sourceURL: url, domain: "figma.com"))
        try ctx.save()

        let result = SeedData.deduplicateAndCleanSeedStore(in: ctx)
        #expect(result.removedCount == 1)
        let remaining = try ctx.fetch(FetchDescriptor<Item>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.slug == "figma-auto-layout-guide")
    }

    @Test("refreshSeedCatalogIfNeeded bumps catalog version")
    func seedCatalogRefresh() async throws {
        UserDefaults.standard.removeObject(forKey: "stello.seedCatalogVersion")
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let item = Item(
            slug: "figma-auto-layout-guide",
            title: "Auto Layout",
            sourceURL: "https://figma.com/blog/auto-layout",
            domain: "figma.com"
        )
        ctx.insert(item)
        try ctx.save()

        await SeedData.refreshSeedCatalogIfNeeded(in: ctx)
        #expect(UserDefaults.standard.integer(forKey: "stello.seedCatalogVersion") == 3)
        #expect(item.sourceURL?.contains("design-systems-101") == true)
    }

    // MARK: - Optacos seed

    @Test("OptacosSeed.json collection counts")
    func optacosSeedCollectionCounts() {
        guard let counts = OptacosImporter.seedCollectionCounts(from: stelloAppBundle()) else {
            Issue.record("OptacosSeed.json missing from Stello.app bundle")
            return
        }
        #expect(counts.typefaces == 36)
        #expect(counts.websites == 38)
        #expect(counts.creatives == 47)
    }

    @Test("TypefaceMeta decodes after Optacos import (offline)")
    func typefaceMetaDecodesAfterImport() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        // Offline, guard-free run so it's deterministic and doesn't touch the network.
        await OptacosImporter.importIfNeeded(in: ctx, options: .offline)

        let typefaces = try ctx.fetch(
            FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.kind == "typeface" })
        )
        #expect(typefaces.count == 36)

        let websites = try ctx.fetch(
            FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.kind == "website" })
        )
        #expect(websites.count == 38)

        let creatives = try ctx.fetch(
            FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.kind == "individual" })
        )
        #expect(creatives.count == 47)

        let places = try ctx.fetch(
            FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.kind == "place" })
        )
        #expect(places.isEmpty)

        // A known typeface decodes with real, non-empty facets.
        let dmMono = try #require(typefaces.first { $0.slug == "dm-mono" })
        let meta = try #require(dmMono.typefaceMeta())
        #expect(meta.classification.isEmpty == false)
        #expect(meta.weightTypes.isEmpty == false)
    }

    // MARK: - Helpers

    private func stelloAppBundle() -> Bundle {
        Bundle.allBundles.first { $0.bundlePath.hasSuffix("Stello.app") } ?? .main
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

@Suite("Web import background classify")
@MainActor
struct WebImportClassifyTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try StelloStore.makeInMemoryContainer())
    }

    private func pendingCount(_ context: ModelContext) throws -> Int {
        let status = WebLibraryImporter.awaitingAIStatus
        return try context.fetchCount(FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.enrichmentStatus == status }))
    }

    @Test("Import writes rows and queues covers without touching the network")
    func importQueuesItems() async throws {
        let context = try makeContext()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let json = """
        {"image_base_url":"https://images.example.com/img/","items":[
          {"id":"\(UUID().uuidString)","slug":"has-image","title":"Has image","source_url":"https://example.com/a",
           "images":[{"path":"/img/u/a/og.png","source":"og","is_primary":true,"width":2400,"height":1260}]},
          {"id":"\(UUID().uuidString)","slug":"no-image","title":"No image","source_url":"https://x.com/someone/status/1"},
          {"id":"\(UUID().uuidString)","slug":"no-url","title":"No URL"}
        ]}
        """
        try Data(json.utf8).write(to: file)

        let importer = WebLibraryImporter()
        await importer.run(fileURL: file, context: context, limit: 3)

        #expect(importer.imported == 3)
        let items = try context.fetch(FetchDescriptor<Item>())
        let hasImage = try #require(items.first { $0.slug == "has-image" })
        let row = try #require(hasImage.images?.first)
        #expect(hasImage.enrichmentStatus == WebLibraryImporter.awaitingClassifyStatus)
        #expect(row.coverPending)
        #expect(row.data == nil)
        #expect(row.sourceURL == "https://images.example.com/img/u/a/og.png")

        // The Worker sorts even URL-only cases later (readPages); an empty row asks the page
        // pass for a cover.
        let noImage = try #require(items.first { $0.slug == "no-image" })
        #expect(noImage.kind == ItemKind.link.rawValue)
        #expect(noImage.enrichmentStatus == WebLibraryImporter.awaitingClassifyStatus)
        #expect(noImage.images?.first?.coverPending == true)
        #expect(noImage.images?.first?.sourceURL == nil)

        let noURL = try #require(items.first { $0.slug == "no-url" })
        #expect(noURL.enrichmentStatus == "candidates_done")
        #expect(noURL.images?.isEmpty != false)
    }

    @Test("Thumbnails fit the size limit and reject non-images")
    func thumbnails() throws {
        let cover = try #require(SampleCoverGenerator.cover(seed: 7))
        let thumbnail = try #require(ImportThumbnail(imageData: cover.data, maxPixels: 64))
        #expect(max(thumbnail.width, thumbnail.height) <= 64)
        #expect(ImportThumbnail(imageData: Data("<svg/>".utf8)) == nil)
    }

    @Test("Known covers store a thumbnail, and a failed download stops retrying but keeps its URL")
    func knownCovers() async throws {
        let context = try makeContext()
        func row(_ slug: String) -> ItemImage {
            let item = queued(slug, url: "https://example.com/\(slug)", in: context)
            let image = ItemImage(source: "og", isPrimary: true)
            image.sourceURL = "https://images.example.com/\(slug).png"
            image.coverPending = true
            context.insert(image)
            image.item = item
            return image
        }
        let good = row("good")
        let bad = row("bad")
        try context.save()

        let network = ImportNetwork(page: { _ in nil }, thumbnail: { url in
            url.lastPathComponent == "good.png" ? ImportThumbnail(data: Data([1, 2, 3]), width: 600, height: 300) : nil
        })
        await WebLibraryImporter.downloadKnownCovers(context: context, network: network)

        #expect(good.data == Data([1, 2, 3]))
        #expect(good.width == 600)
        #expect(!good.coverPending)
        #expect(bad.data == nil)
        #expect(!bad.coverPending)
        #expect(bad.sourceURL != nil)
    }

    private func queued(_ slug: String, url: String?, label: String? = nil, in context: ModelContext) -> Item {
        let item = Item(slug: slug, title: slug, sourceURL: url, enrichmentStatus: WebLibraryImporter.awaitingClassifyStatus)
        context.insert(item)
        if let label {
            item.tags = [ItemTag(name: label, category: "collection", weight: 0.5, source: "import")]
        }
        return item
    }

    @Test("Page pass reads kinds and covers, flags gone pages, and moves failures on as links")
    func pagesPass() async throws {
        let context = try makeContext()
        let article = queued("article", url: "https://example.com/blog/how-kerning-works", in: context)
        let gone = queued("gone", url: "https://example.com/gone", in: context)
        let failed = queued("failed", url: "https://example.com/fail", in: context)
        let noURL = queued("no-url", url: nil, in: context)
        let row = ItemImage(source: "og", isPrimary: true)
        row.coverPending = true
        context.insert(row)
        row.item = article
        let failedRow = ItemImage(source: "og", isPrimary: true)
        failedRow.coverPending = true
        context.insert(failedRow)
        failedRow.item = failed
        try context.save()

        let network = ImportNetwork(page: { url in
            switch url.lastPathComponent {
            case "how-kerning-works":
                let html = #"<html><head><meta property="og:type" content="article"><meta property="og:image" content="https://example.com/og.png"></head></html>"#
                return PageFetchResult(html: html, og: CaptureService.parseOG(html: html, baseURL: url), statusCode: 200)
            case "gone":
                return PageFetchResult(html: "", og: OGResult(), statusCode: 404)
            default:
                return nil
            }
        }, thumbnail: { _ in ImportThumbnail(data: Data([9]), width: 10, height: 10) },
        canSort: { true },
        classify: { url, _, _, _ in
            // The Worker's answer: an article for the readable page, a plain link otherwise
            // (an unreadable page is decided from its URL alone).
            WorkerRead(json: ["kind": url.lastPathComponent == "how-kerning-works" ? "article" : "link"])
        })

        await WebLibraryImporter.readPages(context: context, network: network, concurrency: 2)

        #expect(article.kind == ItemKind.article.rawValue)
        #expect(row.data == Data([9]))
        #expect(row.sourceURL == "https://example.com/og.png")
        #expect(!row.coverPending)
        #expect(gone.status == "gone")
        #expect(failed.kind == ItemKind.link.rawValue)
        #expect(failed.images?.isEmpty != false)
        for item in [article, gone, failed, noURL] {
            #expect(item.enrichmentStatus == WebLibraryImporter.awaitingAIStatus)
        }
    }

    @Test("Page pass never runs more fetches at once than asked")
    func pagesPassConcurrency() async throws {
        actor Gauge {
            var now = 0, peak = 0
            func enter() { now += 1; peak = max(peak, now) }
            func leave() { now -= 1 }
        }
        let context = try makeContext()
        for index in 0..<12 { _ = queued("q\(index)", url: "https://example.com/\(index)", in: context) }
        try context.save()

        let gauge = Gauge()
        let network = ImportNetwork(page: { _ in
            await gauge.enter()
            try? await Task.sleep(for: .milliseconds(20))
            await gauge.leave()
            return nil
        }, thumbnail: { _ in nil }, canSort: { true }, classify: { _, _, _, _ in WorkerRead(json: ["kind": "link"]) })
        await WebLibraryImporter.readPages(context: context, network: network, concurrency: 3)
        let peak = await gauge.peak
        #expect(peak > 1)
        #expect(peak <= 3)
    }

    @Test("Page pass: an unreachable Worker leaves items queued; signed out, nothing is fetched")
    func pagesPassUnsorted() async throws {
        let context = try makeContext()
        let item = queued("offline", url: "https://example.com/offline", in: context)
        try context.save()

        let fetches = Counter()
        let unreachable = ImportNetwork(
            page: { _ in await fetches.bump(); return nil },
            thumbnail: { _ in nil },
            canSort: { true },
            classify: { _, _, _, _ in nil }
        )
        await WebLibraryImporter.readPages(context: context, network: unreachable, concurrency: 1)
        #expect(await fetches.value == 1)
        #expect(item.kind == ItemKind.link.rawValue)
        #expect(item.enrichmentStatus == WebLibraryImporter.awaitingClassifyStatus)

        let signedOut = ImportNetwork(
            page: { _ in await fetches.bump(); return nil },
            thumbnail: { _ in nil },
            canSort: { false },
            classify: { _, _, _, _ in Issue.record("classify called while signed out"); return nil }
        )
        await WebLibraryImporter.readPages(context: context, network: signedOut, concurrency: 1)
        #expect(await fetches.value == 1)
        #expect(item.enrichmentStatus == WebLibraryImporter.awaitingClassifyStatus)
    }

    @Test("Page pass: a small queue gets the Worker's fields; kind only is not asked")
    func pagesPassFields() async throws {
        let context = try makeContext()
        let item = queued("tool", url: "https://example.com/app", label: "digital-tools", in: context)
        try context.save()

        let asked = Counter()
        let network = ImportNetwork(
            page: { _ in PageFetchResult(html: "<html></html>", og: OGResult(), statusCode: 200) },
            thumbnail: { _ in nil },
            canSort: { true },
            classify: { _, _, labels, kindOnly in
                #expect(labels == ["digital-tools"])
                #expect(!kindOnly)
                await asked.bump()
                return WorkerRead(json: ["kind": "tool", "metadata": ["name": "Acme", "platforms": [String](), "platformsAreGuess": false, "pricingIsGuess": false, "topics": [String]()]])
            }
        )
        await WebLibraryImporter.readPages(context: context, network: network, concurrency: 1)
        #expect(await asked.value == 1)
        #expect(item.kind == ItemKind.tool.rawValue)
        #expect(item.metadataJSON?.contains("Acme") == true)
        #expect(item.enrichmentStatus == WebLibraryImporter.awaitingAIStatus)
    }

    @Test("Items with a summary skip the background pass but stay queued for opening")
    func triage() async throws {
        let context = try makeContext()
        let summarized = Item(
            slug: "summarized", title: "Has summary",
            summary: "A real summary that is comfortably longer than thirty characters.",
            enrichmentStatus: WebLibraryImporter.awaitingAIStatus
        )
        let bare = Item(slug: "bare", title: "No summary", enrichmentStatus: WebLibraryImporter.awaitingAIStatus)
        context.insert(summarized)
        context.insert(bare)
        try context.save()

        await WebLibraryImporter.triageAwaitingAI(context: context)

        #expect(summarized.enrichmentStatus == WebLibraryImporter.awaitingOpenStatus)
        #expect(WebLibraryImporter.isQueued(summarized))
        #expect(bare.enrichmentStatus == WebLibraryImporter.awaitingAIStatus)
    }

    @Test("Enrich pass finishes queued items only, even when Enrich changes nothing")
    func passFinishesQueuedItems() async throws {
        let context = try makeContext()
        for index in 0..<3 {
            context.insert(Item(slug: "queued-\(index)", title: "Queued", enrichmentStatus: WebLibraryImporter.awaitingAIStatus))
        }
        context.insert(Item(slug: "other", title: "Other", enrichmentStatus: "text_done"))
        try context.save()

        var seen: [String] = []
        await WebLibraryImporter.enrichAwaitingAI(context: context, pause: { .zero }) { seen.append($0.slug) }

        #expect(seen.count == 3)
        #expect(!seen.contains("other"))
        #expect(try pendingCount(context) == 0)
    }

    @Test("A stopped Enrich pass keeps the unfinished items and the next run resumes them")
    func stoppedPassResumes() async throws {
        let context = try makeContext()
        for index in 0..<3 {
            context.insert(Item(slug: "queued-\(index)", title: "Queued", enrichmentStatus: WebLibraryImporter.awaitingAIStatus))
        }
        try context.save()

        let first = Task { @MainActor in
            await WebLibraryImporter.enrichAwaitingAI(context: context, pause: { .zero }) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await first.value
        #expect(try pendingCount(context) == 3)

        await WebLibraryImporter.enrichAwaitingAI(context: context, pause: { .zero }) { _ in }
        #expect(try pendingCount(context) == 0)
    }
}

/// Counts calls from `@Sendable` fakes.
private actor Counter {
    var value = 0
    func bump() { value += 1 }
}
