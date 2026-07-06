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
}
