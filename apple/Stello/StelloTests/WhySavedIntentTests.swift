import Testing
import Foundation
import SwiftData
@testable import Stello

@Suite("Why saved intent")
struct WhySavedIntentTests {

    @Test("Accept creates intent tag and shrinks suggestions")
    func acceptCreatesIntentTagAndShrinksSuggestions() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(
            title: "Layout study",
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions([
                "layout-reference",
                "typography-pairing",
            ])
        )
        context.insert(item)

        try EnrichmentService.addIntentTag(name: "layout-reference", to: item, context: context)

        let tags = try context.fetch(FetchDescriptor<Stello.Tag>())
        let intent = tags.first { $0.category == "intent" && $0.name == "layout-reference" }
        #expect(intent != nil)
        #expect(intent?.weight == 0.9)
        #expect(intent?.source == "manual")

        let remaining = EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON)
        #expect(remaining == ["typography-pairing"])
    }

    @Test("Dismiss shrinks suggestions only")
    func dismissShrinksSuggestionsOnly() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(
            title: "Color study",
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions([
                "palette-reference",
                "mood-board",
            ])
        )
        context.insert(item)

        try EnrichmentService.dismissWhySavedSuggestion(name: "palette-reference", from: item, context: context)

        let tags = try context.fetch(FetchDescriptor<Stello.Tag>())
        #expect(tags.isEmpty)

        let remaining = EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON)
        #expect(remaining == ["mood-board"])
    }

    @Test("Filtering by intent tag returns the item")
    func filteringByIntentTagReturnsItem() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let matching = Item(
            title: "Matched",
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions(["layout-reference"])
        )
        let other = Item(title: "Other", enrichmentStatus: "candidates_done")
        context.insert(matching)
        context.insert(other)

        try EnrichmentService.addIntentTag(name: "layout-reference", to: matching, context: context)

        let result = ItemFilter.apply(
            [matching, other],
            searchText: "",
            selectedTagNames: ["layout-reference"]
        )
        #expect(result.count == 1)
        #expect(result.first?.title == "Matched")
    }
}
