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
            var searchBlobCache: [UUID: String] = [:]
            result = result.filter { item in
                let blob = searchBlobCache[item.id] ?? {
                    let built = ItemSearchBlob.build(for: item)
                    searchBlobCache[item.id] = built
                    return built
                }()
                return blob.contains(q)
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
