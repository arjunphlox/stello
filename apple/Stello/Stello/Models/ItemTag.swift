import Foundation

/// One weighted tag on an item. A plain value stored inside `Item.tagsJSON`, so an item's
/// tags sync as one field of its CloudKit record rather than as a record each.
nonisolated struct ItemTag: Codable, Hashable, Sendable {
    var name: String
    var category: String
    var weight: Double
    /// `rule` (capture), `ai` (enrichment), `manual` (user edits), `import` (web library).
    var source: String

    init(name: String = "", category: String = "", weight: Double = 0.5, source: String = "rule") {
        self.name = name
        self.category = category
        self.weight = weight
        self.source = source
    }

    /// JSON for `Item.tagsJSON`; nil when there are no tags. Keys are sorted so equal tags
    /// encode to equal strings, and an unchanged list never dirties the CloudKit record.
    static func encode(_ tags: [ItemTag]) -> String? {
        guard !tags.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(tags) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ json: String?) -> [ItemTag] {
        guard let json else { return [] }
        return (try? JSONDecoder().decode([ItemTag].self, from: Data(json.utf8))) ?? []
    }
}

/// The last decode of `Item.tagsJSON`. A reference type so a read can refresh it without
/// writing to the observed model while a view is rendering.
nonisolated final class ItemTagCache {
    var json: String?
    var tags: [ItemTag] = []
}

extension Item {
    /// The item's tags. Cards and filters read this constantly, so a read only decodes when
    /// `tagsJSON` differs from the cached string, which also catches changes synced in.
    var tags: [ItemTag] {
        get {
            let json = tagsJSON
            if json == tagCache.json { return tagCache.tags }
            let decoded = ItemTag.decode(json)
            tagCache.json = json
            tagCache.tags = decoded
            return decoded
        }
        set {
            let json = ItemTag.encode(newValue)
            if json != tagsJSON { tagsJSON = json }
            tagCache.json = json
            tagCache.tags = newValue
        }
    }
}
