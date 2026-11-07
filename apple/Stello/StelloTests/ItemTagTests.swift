import Testing
import Foundation
import SwiftData
@testable import Stello

@Suite("Tags stored on the item")
@MainActor
struct ItemTagTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try StelloStore.makeInMemoryContainer())
    }

    private let sample = [
        ItemTag(name: "Café / Bar", category: "subject", weight: 0.85, source: "import"),
        ItemTag(name: "teal", category: "color", weight: 0.5, source: "ai"),
    ]

    private func importLibrary(_ json: String, into context: ModelContext) async throws -> WebLibraryImporter {
        let file = FileManager.default.temporaryDirectory.appending(path: "tags-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(json.utf8).write(to: file)
        let importer = WebLibraryImporter()
        await importer.run(fileURL: file, context: context, limit: 10)
        return importer
    }

    private let library = """
    {"image_base_url":"https://example.com/img/","items":[
      {"id":"6F1C2E5A-0000-4000-8000-000000000001","slug":"tool","title":"A tool",
       "source_url":"https://example.com/app",
       "tags":[{"tag":"Typography","category":"subject","weight":0.8},
               {"tag":"typography","category":"subject","weight":0.2},
               {"tag":"typography","category":"style"},
               {"tag":"","category":"subject"},
               {"tag":"no-category"},
               {"tag":"digital-tools","category":"collection","weight":0.5}]},
      {"id":"6F1C2E5A-0000-4000-8000-000000000002","slug":"plain","title":"Plain"}
    ]}
    """

    // MARK: Encoding

    @Test("Encode and decode round trip every field")
    func roundTrip() {
        let json = ItemTag.encode(sample)
        #expect(ItemTag.decode(json) == sample)
    }

    @Test("Encoding is the exact shape the web reads, with stable key order")
    func encodedShape() {
        let one = [ItemTag(name: "a/b", category: "subject", weight: 0.75, source: "rule")]
        #expect(ItemTag.encode(one) == #"[{"category":"subject","name":"a/b","source":"rule","weight":0.75}]"#)
    }

    @Test("No tags encode to nil; nil and bad JSON decode to no tags")
    func emptyAndBad() {
        #expect(ItemTag.encode([]) == nil)
        #expect(ItemTag.decode(nil).isEmpty)
        #expect(ItemTag.decode("not json").isEmpty)
    }

    // MARK: Item accessor

    @Test("Tags survive a save and a fresh context")
    func persists() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Stored")
        context.insert(item)
        item.tags = sample
        try context.save()

        let fetched = try #require(ModelContext(container).fetch(FetchDescriptor<Item>()).first)
        #expect(fetched.tags == sample)
        #expect(fetched.tagsJSON == ItemTag.encode(sample))
    }

    @Test("A new tagsJSON, as from sync, replaces the cached tags")
    func cacheFollowsField() {
        let item = Item(title: "Synced")
        item.tags = sample
        #expect(item.tags == sample)

        let incoming = [ItemTag(name: "new", category: "subject")]
        item.tagsJSON = ItemTag.encode(incoming)
        #expect(item.tags == incoming)

        item.tagsJSON = nil
        #expect(item.tags.isEmpty)
    }

    @Test("Clearing the last tag empties the field")
    func clearing() {
        let item = Item(title: "Cleared")
        item.tags = sample
        item.tags.removeAll()
        #expect(item.tagsJSON == nil)
    }

    @Test("The store has no Tag entity")
    func noTagEntity() throws {
        let container = try StelloStore.makeInMemoryContainer()
        #expect(!container.schema.entities.map(\.name).contains("Tag"))
    }

    // MARK: Editing and de-duplication

    @Test("Vision tags skip names already on the item, ignoring case, and each other")
    func visionDedupe() throws {
        let context = try makeContext()
        let item = Item(title: "Vision")
        context.insert(item)
        item.tags = [ItemTag(name: "Minimalist", category: "style", weight: 0.65, source: "rule")]

        let result = EnrichmentResult(
            visionTags: [
                VisionTagSpec(name: "minimalist", category: "style", weight: 0.9),
                VisionTagSpec(name: "teal", category: "color", weight: 0.8),
                VisionTagSpec(name: "TEAL", category: "color", weight: 0.7),
            ],
            snippets: [],
            whySavedSuggestions: []
        )
        try EnrichmentService.apply(result, to: item, context: context)

        #expect(item.tags == [
            ItemTag(name: "Minimalist", category: "style", weight: 0.65, source: "rule"),
            ItemTag(name: "teal", category: "color", weight: 0.8, source: "ai"),
        ])
    }

    @Test("Intent tag is added once, ignoring case")
    func intentDedupe() throws {
        let context = try makeContext()
        let item = Item(title: "Intent")
        context.insert(item)

        try EnrichmentService.addIntentTag(name: "Reference", to: item, context: context)
        try EnrichmentService.addIntentTag(name: "reference", to: item, context: context)

        #expect(item.tags == [ItemTag(name: "Reference", category: "intent", weight: 0.9, source: "manual")])
    }

    @Test("Removing a tag keeps the others")
    func removing() {
        let item = Item(title: "Remove")
        item.tags = sample
        let removed = sample[1]
        item.tags.removeAll { $0 == removed }
        #expect(item.tags == [sample[0]])
    }

    @Test("Capture writes rule tags onto the item")
    func captureWritesTags() throws {
        let context = try makeContext()
        let item = try CaptureService.captureImage(Data(), context: context)
        #expect(item.tags == [ItemTag(name: "image-upload", category: "format", weight: 0.4, source: "rule")])
    }

    // MARK: Import, filtering, search

    @Test("Import writes tags on the item, keeping its de-duplication rules")
    func importWritesTags() async throws {
        let context = try makeContext()
        let importer = try await importLibrary(library, into: context)
        #expect(importer.imported == 2)

        let items = try context.fetch(FetchDescriptor<Item>())
        let tool = try #require(items.first { $0.slug == "tool" })
        #expect(tool.tags == [
            ItemTag(name: "Typography", category: "subject", weight: 0.8, source: "import"),
            ItemTag(name: "typography", category: "style", weight: 0.5, source: "import"),
            ItemTag(name: "digital-tools", category: "collection", weight: 0.5, source: "import"),
        ])
        let plain = try #require(items.first { $0.slug == "plain" })
        #expect(plain.tagsJSON == nil)
    }

    @Test("Collection labels come from the item's tags and drive classification")
    func collectionLabels() async throws {
        let context = try makeContext()
        _ = try await importLibrary(library, into: context)

        let items = try context.fetch(FetchDescriptor<Item>())
        let tool = try #require(items.first { $0.slug == "tool" })
        #expect(EnrichmentService.collectionLabels(for: tool) == ["digital-tools"])
        #expect(tool.kind == ItemKind.tool.rawValue)
    }

    @Test("Filter and search find imported tags")
    func filterAndSearch() async throws {
        let context = try makeContext()
        _ = try await importLibrary(library, into: context)
        let items = try context.fetch(FetchDescriptor<Item>())

        let both = ItemFilter.apply(items, searchText: "", selectedTagNames: ["Typography", "digital-tools"])
        #expect(both.map(\.slug) == ["tool"])
        #expect(ItemFilter.apply(items, searchText: "", selectedTagNames: ["Typography", "absent"]).isEmpty)
        #expect(ItemFilter.apply(items, searchText: "digital-tools", selectedTagNames: []).map(\.slug) == ["tool"])
    }
}
