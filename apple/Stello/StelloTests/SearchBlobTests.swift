import Testing
import SwiftData
@testable import Stello

@Suite("Search blob")
struct SearchBlobTests {

    @Test("Search hits by snippet text")
    func searchBySnippet() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let item = Item(title: "Grid Article")
        let snippet = Snippet(text: "CSS grid auto-placement patterns")
        ctx.insert(item)
        ctx.insert(snippet)
        snippet.item = item
        item.snippets = [snippet]
        try ctx.save()

        let result = ItemFilter.apply([item], searchText: "auto-placement", selectedTagNames: [])
        #expect(result.count == 1)
        #expect(result.first?.title == "Grid Article")
    }

    @Test("Search hits by why-saved reason")
    func searchByWhySavedReason() {
        let item = Item(
            title: "Design Systems 101",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions([
                "layout-reference",
                "typography-inspiration",
            ])
        )

        let result = ItemFilter.apply([item], searchText: "layout-reference", selectedTagNames: [])
        #expect(result.count == 1)
        #expect(result.first?.title == "Design Systems 101")
    }

    @Test("Search hits by metadata field")
    func searchByMetadataField() {
        var meta = IndividualMeta()
        meta.professions = ["Lettering Artist", "Type Designer"]
        meta.location = EntityRef(name: "Portland", slug: "portland", kind: "place")

        let item = Item(title: "Creative Profile", kind: ItemKind.individual.rawValue)
        item.setMetadata(meta)

        let result = ItemFilter.apply([item], searchText: "lettering artist", selectedTagNames: [])
        #expect(result.count == 1)
        #expect(result.first?.title == "Creative Profile")
    }

    @Test("Search still hits by title and tag")
    func searchByTitleAndTag() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let byTitle = Item(title: "SwiftUI Layout Guide")
        let byTag = Item(title: "Unrelated")
        let tag = Tag(name: "typography", category: "subject", weight: 0.9)
        ctx.insert(byTitle)
        ctx.insert(byTag)
        ctx.insert(tag)
        tag.item = byTag
        byTag.tags = [tag]
        try ctx.save()

        let titleResult = ItemFilter.apply([byTitle, byTag], searchText: "swiftui", selectedTagNames: [])
        #expect(titleResult.map(\.title) == ["SwiftUI Layout Guide"])

        let tagResult = ItemFilter.apply([byTitle, byTag], searchText: "typography", selectedTagNames: [])
        #expect(tagResult.map(\.title) == ["Unrelated"])
    }

    @Test("Search hits by body markdown text")
    func searchByBodyMarkdown() {
        let item = Item(
            title: "Dropped Note",
            bodyMarkdown: "A paragraph about kerning pairs and optical alignment."
        )

        let result = ItemFilter.apply([item], searchText: "optical alignment", selectedTagNames: [])
        #expect(result.count == 1)
        #expect(result.first?.title == "Dropped Note")
    }

    @Test("Search miss returns empty")
    func searchMissReturnsEmpty() {
        let items = [
            Item(title: "Swift Patterns", domain: "apple.com"),
            Item(title: "Figma Tips", author: "Jane Doe"),
        ]

        let result = ItemFilter.apply(items, searchText: "kotlin", selectedTagNames: [])
        #expect(result.isEmpty)
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
