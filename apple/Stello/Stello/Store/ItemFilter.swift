import Foundation

/// Stateless filter applied to a flat item array. Extracted for testability.
enum ItemFilter {
    static func apply(
        _ items: [Item],
        searchText: String,
        selectedTagNames: Set<String>,
        selectedWeekKey: String? = nil
    ) -> [Item] {
        var result = items

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { item in
                item.title.lowercased().contains(q)
                    || (item.summary?.lowercased().contains(q) ?? false)
                    || (item.tags?.contains { $0.name.lowercased().contains(q) } ?? false)
            }
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

        return result
    }
}
