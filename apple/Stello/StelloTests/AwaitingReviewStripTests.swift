import Testing
import Foundation
import SwiftData
@testable import Stello

@Suite("AwaitingReviewStrip")
struct AwaitingReviewStripTests {

    @Test("strip includes needsReview items past pending enrichment only")
    func stripPredicate() {
        let now = Date.now
        let eligible = Item(
            title: "Ready",
            needsReview: true,
            addedAt: now,
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions(["layout-reference"])
        )
        let pending = Item(
            title: "Still enriching",
            needsReview: true,
            addedAt: now.addingTimeInterval(60),
            enrichmentStatus: "pending"
        )
        let dismissed = Item(
            title: "Reviewed",
            needsReview: false,
            addedAt: now.addingTimeInterval(120),
            enrichmentStatus: "candidates_done"
        )
        let textDone = Item(
            title: "Text done",
            needsReview: true,
            addedAt: now.addingTimeInterval(30),
            enrichmentStatus: "text_done"
        )

        let result = AwaitingReviewFilter.items(from: [pending, dismissed, eligible, textDone])

        #expect(result.map(\.title) == ["Text done", "Ready"])
        #expect(!result.contains(where: { $0.title == "Still enriching" }))
        #expect(!result.contains(where: { $0.title == "Reviewed" }))
    }

    @Test("strip caps at eight items newest first")
    func stripLimitAndSort() {
        let base = Date.now
        let items = (0..<10).map { index in
            Item(
                title: "Item \(index)",
                needsReview: true,
                addedAt: base.addingTimeInterval(TimeInterval(index)),
                enrichmentStatus: "candidates_done",
                whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions(["suggestion"])
            )
        }
        let result = AwaitingReviewFilter.items(from: items)
        #expect(result.count == 8)
        #expect(result.first?.title == "Item 9")
        #expect(result.last?.title == "Item 2")
    }

    @Test("suggestion count reads whySavedSuggestionsJSON")
    func suggestionCount() {
        let item = Item(
            title: "Tagged",
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions([
                "layout-reference",
                "inspiration",
            ])
        )
        #expect(AwaitingReviewFilter.suggestionCount(for: item) == 2)
        #expect(AwaitingReviewFilter.suggestionsLabel(for: item) == "2 suggestions")
    }

    @Test("dismiss sets needsReview false")
    func dismissReview() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Review me", needsReview: true, enrichmentStatus: "candidates_done")
        context.insert(item)
        try context.save()

        try AwaitingReviewFilter.dismissReview(for: item, context: context)

        #expect(item.needsReview == false)
        #expect(AwaitingReviewFilter.items(from: [item]).isEmpty)
    }

    @Test("accepting the last suggestion clears needsReview and removes item from strip")
    func acceptingLastSuggestionClearsReview() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(
            title: "One suggestion left",
            needsReview: true,
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions(["layout-reference"])
        )
        context.insert(item)
        try context.save()

        try EnrichmentService.addIntentTag(name: "layout-reference", to: item, context: context)

        #expect(item.needsReview == false)
        #expect(AwaitingReviewFilter.items(from: [item]).isEmpty)
    }

    @Test("dismissing the last suggestion clears needsReview and removes item from strip")
    func dismissingLastSuggestionClearsReview() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(
            title: "One suggestion left",
            needsReview: true,
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions(["inspiration"])
        )
        context.insert(item)
        try context.save()

        try EnrichmentService.dismissWhySavedSuggestion(name: "inspiration", from: item, context: context)

        #expect(item.needsReview == false)
        #expect(AwaitingReviewFilter.items(from: [item]).isEmpty)
    }

    @Test("zero-suggestion candidates_done item is ineligible even if needsReview wasn't cleared")
    func zeroSuggestionItemIneligible() {
        let item = Item(
            title: "Legacy leftover",
            needsReview: true,
            enrichmentStatus: "candidates_done"
        )
        #expect(!AwaitingReviewFilter.isEligible(item))
        #expect(AwaitingReviewFilter.items(from: [item]).isEmpty)
    }

    @Test("text_done item with zero suggestions is still eligible (suggestions not produced yet)")
    func textDoneZeroSuggestionsStillEligible() {
        let item = Item(
            title: "Still enriching",
            needsReview: true,
            enrichmentStatus: "text_done"
        )
        #expect(AwaitingReviewFilter.isEligible(item))
    }
}
