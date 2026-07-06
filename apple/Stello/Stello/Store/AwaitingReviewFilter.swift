import Foundation
import SwiftData

/// Items eligible for the horizontal "Awaiting review" strip above the grid.
enum AwaitingReviewFilter {
    static let maxVisibleCount = 8

    /// Enrichment has started (`enrichmentStatus` is not `pending`) and the item still needs review.
    /// Once enrichment has reached a suggestion-producing state, an empty suggestion list means
    /// there's nothing left to review, so the item is excluded even if `needsReview` wasn't cleared.
    static func isEligible(_ item: Item) -> Bool {
        guard item.needsReview, item.enrichmentStatus != "pending" else { return false }
        if item.enrichmentStatus == "text_done" { return true }
        return suggestionCount(for: item) > 0
    }

    /// Newest first, capped at `maxVisibleCount`.
    static func items(from all: [Item]) -> [Item] {
        all.filter { isEligible($0) }
            .sorted { $0.addedAt > $1.addedAt }
            .prefix(maxVisibleCount)
            .map { $0 }
    }

    static func suggestionCount(for item: Item) -> Int {
        EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON).count
    }

    static func suggestionsLabel(for item: Item) -> String {
        let count = suggestionCount(for: item)
        return count == 1 ? "1 suggestion" : "\(count) suggestions"
    }

    static func dismissReview(for item: Item, context: ModelContext) throws {
        item.needsReview = false
        item.updatedAt = .now
        try context.save()
    }
}
