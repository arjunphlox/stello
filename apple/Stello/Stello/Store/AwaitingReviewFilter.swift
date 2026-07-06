import Foundation
import SwiftData

/// Items eligible for the horizontal "Awaiting review" strip above the grid.
enum AwaitingReviewFilter {
    static let maxVisibleCount = 8

    /// Enrichment has started (`enrichmentStatus` is not `pending`) and the item still needs review.
    static func isEligible(_ item: Item) -> Bool {
        item.needsReview && item.enrichmentStatus != "pending"
    }

    /// Newest first, capped at `maxVisibleCount`.
    static func items(from all: [Item]) -> [Item] {
        all.filter(isEligible)
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
