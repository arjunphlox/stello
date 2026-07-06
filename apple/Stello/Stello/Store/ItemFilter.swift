import Foundation

/// Stateless filter applied to a flat item array. Extracted for testability.
enum ItemFilter {
    static func apply(
        _ items: [Item],
        searchText: String,
        selectedTagNames: Set<String>,
        selectedWeekKey: String? = nil,
        needsReviewOnly: Bool = false
    ) -> [Item] {
        var result = items

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { ItemSearchBlob.build(for: $0).contains(q) }
        }

        if !selectedTagNames.isEmpty {
            result = result.filter { item in
                let names = Set(item.tags?.map(\.name) ?? [])
                return selectedTagNames.isSubset(of: names)
            }
        }

        if let selectedWeekKey {
            result = result.filter { WeekGroup.isoWeekKey(for: $0.addedAt) == selectedWeekKey }
        }

        if needsReviewOnly {
            result = result.filter { AwaitingReviewFilter.isEligible($0) }
        }

        return result
    }
}
