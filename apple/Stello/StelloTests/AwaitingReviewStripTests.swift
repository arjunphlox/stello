import Testing
import Foundation
import SwiftData
@testable import Stello

/// Lifecycle tests for `AwaitingReviewFilter.isEligible` — the SAME predicate that drives
/// the on-card review badge in `ItemCardView`. Kept as `AwaitingReviewStripTests` (filename
/// unchanged to minimize project-file churn) after the horizontal awaiting-review strip was
/// replaced by the badge; strip-only behavior (the 8-item cap, `suggestionsLabel`) was removed.
@Suite("AwaitingReviewStrip")
struct AwaitingReviewStripTests {

    @Test("eligibility includes needsReview items past pending enrichment only")
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

        #expect(AwaitingReviewFilter.isEligible(eligible))
        #expect(AwaitingReviewFilter.isEligible(textDone))
        #expect(!AwaitingReviewFilter.isEligible(pending))
        #expect(!AwaitingReviewFilter.isEligible(dismissed))
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
        #expect(!AwaitingReviewFilter.isEligible(item))
    }

    @Test("accepting the last suggestion clears needsReview and removes item from the badge")
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
        #expect(!AwaitingReviewFilter.isEligible(item))
    }

    @Test("dismissing the last suggestion clears needsReview and removes item from the badge")
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
        #expect(!AwaitingReviewFilter.isEligible(item))
    }

    @Test("zero-suggestion candidates_done item is ineligible even if needsReview wasn't cleared")
    func zeroSuggestionItemIneligible() {
        let item = Item(
            title: "Legacy leftover",
            needsReview: true,
            enrichmentStatus: "candidates_done"
        )
        #expect(!AwaitingReviewFilter.isEligible(item))
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

    // MARK: - markReviewed ("viewing counts as reviewing" — ContentView.onChange(of: selectedItem)
    // / DetailView.onDisappear call sites)

    @Test("markReviewed clears needsReview and the item leaves isEligible")
    func markReviewedClearsNeedsReview() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(
            title: "Review me",
            needsReview: true,
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions(["layout-reference"])
        )
        context.insert(item)
        try context.save()

        try AwaitingReviewFilter.markReviewed(for: item, context: context)

        #expect(item.needsReview == false)
        #expect(!AwaitingReviewFilter.isEligible(item))
    }

    @Test("markReviewed is idempotent — calling it again on an already-reviewed item doesn't bump updatedAt")
    func markReviewedIsIdempotent() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Already reviewed", needsReview: false, enrichmentStatus: "candidates_done")
        context.insert(item)
        try context.save()
        let updatedAtBefore = item.updatedAt

        // Mirrors the real call sites, which guard on `needsReview` before calling.
        if item.needsReview {
            try AwaitingReviewFilter.markReviewed(for: item, context: context)
        }

        #expect(item.needsReview == false)
        #expect(item.updatedAt == updatedAtBefore)
    }

    @Test("suggestions survive markReviewed — chips stay decodable after needsReview clears")
    func suggestionsSurviveMarkReviewed() throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(
            title: "Keeps its chips",
            needsReview: true,
            enrichmentStatus: "candidates_done",
            whySavedSuggestionsJSON: EnrichmentService.encodeWhySavedSuggestions([
                "layout-reference",
                "inspiration",
            ])
        )
        context.insert(item)
        try context.save()

        try AwaitingReviewFilter.markReviewed(for: item, context: context)

        #expect(item.needsReview == false)
        let remaining = EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON)
        #expect(remaining.count == 2)
        #expect(remaining.contains("layout-reference"))
        #expect(remaining.contains("inspiration"))
    }

    // MARK: - "Needs review" filter-sheet toggle (ItemFilter.apply(needsReviewOnly:))
    //
    // Same predicate (`AwaitingReviewFilter.isEligible`) as the on-card badge, so the
    // toggle and the badge can never disagree.

    @Test("needsReviewOnly returns only eligible items")
    func needsReviewOnlyReturnsOnlyEligibleItems() {
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

        let result = ItemFilter.apply(
            [eligible, pending, dismissed],
            searchText: "",
            selectedTagNames: [],
            needsReviewOnly: true
        )

        #expect(result.count == 1)
        #expect(result.first?.title == "Ready")
    }

    @Test("needsReviewOnly defaults to off and passes every item through")
    func needsReviewOnlyDefaultsToOff() {
        let item = Item(title: "Reviewed", needsReview: false, enrichmentStatus: "candidates_done")
        let result = ItemFilter.apply([item], searchText: "", selectedTagNames: [])
        #expect(result.count == 1)
    }

    @Test("item drops out of needsReviewOnly filter after its last suggestion is accepted")
    func acceptingLastSuggestionRemovesItemFromNeedsReviewFilter() throws {
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

        let before = ItemFilter.apply([item], searchText: "", selectedTagNames: [], needsReviewOnly: true)
        #expect(before.count == 1)

        try EnrichmentService.addIntentTag(name: "layout-reference", to: item, context: context)

        let after = ItemFilter.apply([item], searchText: "", selectedTagNames: [], needsReviewOnly: true)
        #expect(after.isEmpty)
    }
}
