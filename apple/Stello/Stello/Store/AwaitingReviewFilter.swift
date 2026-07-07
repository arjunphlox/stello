import Foundation
import SwiftData

/// Items eligible for review: drives the on-card review badge (`ItemCardView.reviewBadge`).
enum AwaitingReviewFilter {
    /// Enrichment has started (`enrichmentStatus` is not `pending`) and the item still needs review.
    /// Once enrichment has reached a suggestion-producing state, an empty suggestion list means
    /// there's nothing left to review, so the item is excluded even if `needsReview` wasn't cleared.
    static func isEligible(_ item: Item) -> Bool {
        guard item.needsReview, item.enrichmentStatus != "pending" else { return false }
        if item.enrichmentStatus == "text_done" { return true }
        return suggestionCount(for: item) > 0
    }

    static func suggestionCount(for item: Item) -> Int {
        EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON).count
    }

    static func dismissReview(for item: Item, context: ModelContext) throws {
        item.needsReview = false
        item.updatedAt = .now
        try context.save()
    }

    /// Alias for `dismissReview` used at "user stopped viewing this item" call sites — panel
    /// close, selection switch, sheet/push dismissal. Same mutation; named for readability at
    /// those sites, which are clearing the nag state because viewing counts as reviewing, not
    /// because the user explicitly dismissed a suggestion. Callers should guard on
    /// `item.needsReview` first so already-reviewed items don't take a gratuitous `updatedAt`
    /// bump (which would also invalidate the search-blob cache) on every panel close.
    static func markReviewed(for item: Item, context: ModelContext) throws {
        try dismissReview(for: item, context: context)
    }
}
