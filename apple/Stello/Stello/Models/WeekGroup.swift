import Foundation

struct WeekGroup: Identifiable {
    let key: String     // "YYYY-Wnn" or "undated"
    let label: String   // "Week N — Month" or "Undated"
    let items: [Item]

    var id: String { key }

    // MARK: - Public helpers (also used in tests)

    /// ISO 8601 week key (Thursday-anchored). Returns "undated" if date is invalid.
    static func isoWeekKey(for date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let week = cal.component(.weekOfYear, from: date)
        let year = cal.component(.yearForWeekOfYear, from: date)
        guard week > 0, year > 0 else { return "undated" }
        return String(format: "%04d-W%02d", year, week)
    }

    /// "Week N — Month" header label (e.g. "Week 26 — June").
    static func headerLabel(key: String, representativeDate: Date) -> String {
        guard key != "undated" else { return "Undated" }
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let weekNum = cal.component(.weekOfYear, from: representativeDate)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMMM"
        return "Week \(weekNum) — \(fmt.string(from: representativeDate))"
    }

    /// Groups items (assumed newest-first) into ordered WeekGroup array.
    static func makeGroups(from items: [Item]) -> [WeekGroup] {
        var orderedKeys: [String] = []
        var buckets: [String: [Item]] = [:]

        for item in items {
            let key = isoWeekKey(for: item.addedAt)
            if buckets[key] == nil { orderedKeys.append(key) }
            buckets[key, default: []].append(item)
        }

        return orderedKeys.compactMap { key in
            guard let groupItems = buckets[key], let rep = groupItems.first else { return nil }
            return WeekGroup(key: key, label: headerLabel(key: key, representativeDate: rep.addedAt), items: groupItems)
        }
    }
}
