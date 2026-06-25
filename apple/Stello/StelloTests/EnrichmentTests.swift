import Testing
import Foundation
import SwiftData
@testable import Stello

@Suite("EnrichmentService")
struct EnrichmentServiceTests {

    @Test("Vision-tag merge skips duplicate names")
    func visionTagMergeNoDuplicates() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)

        let item = Item(title: "Test", enrichmentStatus: "text_done")
        let existing = Stello.Tag(name: "minimalist", category: "style", weight: 0.65, source: "rule")
        context.insert(item)
        context.insert(existing)
        existing.item = item

        let result = EnrichmentResult(
            visionTags: [
                VisionTagSpec(name: "minimalist", category: "style", weight: 0.8),
                VisionTagSpec(name: "teal", category: "color", weight: 0.85),
            ],
            snippets: [],
            whySavedSuggestions: []
        )

        try EnrichmentService.apply(result, to: item, context: context)

        let tags = try context.fetch(FetchDescriptor<Stello.Tag>())
        let minimalistTags = tags.filter { $0.name.lowercased() == "minimalist" }
        #expect(minimalistTags.count == 1)
        #expect(minimalistTags.first?.source == "rule")
        #expect(tags.contains { $0.name == "teal" && $0.source == "ai" })
        #expect(item.enrichmentStatus == "candidates_done")
    }

    @Test("Snippets become Snippet(source: ai)")
    func snippetsSourceAI() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Test", enrichmentStatus: "text_done")
        context.insert(item)

        let result = EnrichmentResult(
            visionTags: [],
            snippets: ["A notable quote from the page."],
            whySavedSuggestions: []
        )
        try EnrichmentService.apply(result, to: item, context: context)

        let snippets = try context.fetch(FetchDescriptor<Snippet>())
        #expect(snippets.count == 1)
        #expect(snippets[0].source == "ai")
        #expect(snippets[0].text == "A notable quote from the page.")
    }

    @Test("whySaved suggestion adds intent tag at weight 0.9")
    func whySavedAddsIntentTag() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(
            title: "Test",
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions(["layout-reference"])
        )
        context.insert(item)

        try EnrichmentService.addIntentTag(name: "layout-reference", to: item, context: context)

        let tags = try context.fetch(FetchDescriptor<Stello.Tag>())
        let intent = tags.first { $0.category == "intent" }
        #expect(intent?.name == "layout-reference")
        #expect(intent?.weight == 0.9)
        #expect(EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON).isEmpty)
    }

    @Test("enrichmentStatus transitions text_done → vision_done → candidates_done")
    func statusTransitions() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Test", enrichmentStatus: "text_done")
        context.insert(item)

        let result = MockEnricher.defaultResult
        try EnrichmentService.apply(result, to: item, context: context)
        #expect(item.enrichmentStatus == "candidates_done")
        #expect(item.analyzedAt != nil)
    }

    @Test("Unavailable enricher marks candidates_done without AI output")
    func unavailableEnricherNoOp() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Offline", enrichmentStatus: "text_done")
        context.insert(item)
        try context.save()

        let enricher = MockEnricher(isAvailable: false)
        await EnrichmentService.enrich(item: item, context: context, enricher: enricher)

        #expect(item.enrichmentStatus == "candidates_done")
        #expect((item.tags ?? []).isEmpty)
        #expect((item.snippets ?? []).isEmpty)
    }

    @Test("MockEnricher full pipeline via coordinator")
    func mockEnricherPipeline() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Swift UI patterns", summary: "Layout notes", enrichmentStatus: "text_done")
        context.insert(item)
        try context.save()

        let coordinator = await EnrichmentCoordinator(
            primary: MockEnricher(),
            fallback: RuleBasedFallbackEnricher()
        )
        await coordinator.enrichItem(item, context: context)

        #expect(item.enrichmentStatus == "candidates_done")
        #expect((item.tags ?? []).contains { $0.source == "ai" })
        #expect((item.snippets ?? []).contains { $0.source == "ai" })
        #expect(!EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON).isEmpty)
    }
}

@Suite("RuleBasedFallbackEnricher")
struct FallbackEnricherTests {

    @Test("Returns empty enrichment result")
    func emptyResult() async throws {
        let enricher = RuleBasedFallbackEnricher()
        #expect(enricher.isAvailable)
        let result = try await enricher.enrich(
            title: "Test",
            summary: "Summary",
            domain: "example.com",
            coverImageData: nil
        )
        #expect(result.visionTags.isEmpty)
        #expect(result.snippets.isEmpty)
        #expect(result.whySavedSuggestions.isEmpty)
    }
}
