import Foundation
import SwiftData

/// Item ↔ the web copy's row shape (`src/lib/sync.js` FIELDS). Field names are the
/// web's snake_case; tags/images/snippets keep the web's JSON shapes so the web app
/// reads them unchanged.
enum SyncWire {
    /// Every synced field, in wire names.
    static let allFields: [String] = [
        "slug", "title", "source_url", "domain", "author", "summary", "body_markdown", "status",
        "needs_review", "kind", "enrichment_status", "added_at", "analyzed_at", "cover_aspect",
        "metadata", "tags", "images", "snippets",
    ]

    /// Item attribute → wire field, for reading SwiftData change history.
    static let fieldForKeyPath: [PartialKeyPath<Item>: String] = [
        \Item.slug: "slug", \Item.title: "title", \Item.sourceURL: "source_url", \Item.domain: "domain",
        \Item.author: "author", \Item.summary: "summary", \Item.bodyMarkdown: "body_markdown",
        \Item.status: "status", \Item.needsReview: "needs_review", \Item.kind: "kind",
        \Item.enrichmentStatus: "enrichment_status", \Item.addedAt: "added_at",
        \Item.analyzedAt: "analyzed_at", \Item.coverAspect: "cover_aspect",
        \Item.metadataJSON: "metadata", \Item.tagsJSON: "tags",
        \Item.imagesChangedAt: "images", \Item.snippetsChangedAt: "snippets",
    ]

    /// One row from `/api/sync/pull`. Values stay as parsed JSON (`NSNull` for null).
    struct Row: @unchecked Sendable {
        let id: UUID
        let seq: Int
        let values: [String: Any]
        let deletedAt: Int?
        let purged: Bool

        init?(_ json: [String: Any]) {
            guard let raw = json["id"] as? String, let id = UUID(uuidString: raw) else { return nil }
            self.id = id
            seq = json["seq"] as? Int ?? 0
            values = json
            deletedAt = json["deleted_at"] as? Int
            purged = json["purged"] as? Bool ?? false
        }
    }

    /// One change for `/api/sync/push`.
    struct Change: @unchecked Sendable {
        let id: UUID
        var fields: [String: Any]
        var clock: [String: Int]
        var full: Bool

        var json: [String: Any] {
            ["id": id.uuidString.lowercased(), "fields": fields, "clock": clock, "full": full]
        }
    }

    static func ms(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1000).rounded()) }

    // MARK: Item → wire

    /// The named fields of `item` (all of them when `only` is nil). Images that have no
    /// web path yet are left out; `SyncBridge` uploads them first.
    static func values(of item: Item, only: Set<String>? = nil) -> [String: Any] {
        var out: [String: Any] = [:]
        func want(_ f: String) -> Bool { only?.contains(f) ?? true }
        func opt(_ v: Any?) -> Any { v ?? NSNull() }
        if want("slug") { out["slug"] = item.slug }
        if want("title") { out["title"] = item.title }
        if want("source_url") { out["source_url"] = opt(item.sourceURL) }
        if want("domain") { out["domain"] = opt(item.domain) }
        if want("author") { out["author"] = opt(item.author) }
        if want("summary") { out["summary"] = opt(item.summary) }
        if want("body_markdown") { out["body_markdown"] = opt(item.bodyMarkdown) }
        if want("status") { out["status"] = item.status == "gone" ? "broken" : item.status }
        if want("needs_review") { out["needs_review"] = item.needsReview }
        if want("kind") { out["kind"] = item.kind }
        if want("enrichment_status") { out["enrichment_status"] = item.enrichmentStatus }
        if want("added_at") { out["added_at"] = iso(item.addedAt) }
        if want("analyzed_at") { out["analyzed_at"] = opt(item.analyzedAt.map(iso)) }
        if want("cover_aspect") { out["cover_aspect"] = item.coverAspect }
        if want("metadata") { out["metadata"] = item.metadataJSON.flatMap(parseJSON) ?? NSNull() }
        if want("tags") {
            out["tags"] = item.tags.map {
                ["tag": $0.name, "category": $0.category, "weight": $0.weight, "source": $0.source] as [String: Any]
            }
        }
        if want("images") {
            out["images"] = (item.images ?? []).compactMap { image -> [String: Any]? in
                guard let path = webPath(of: image) else { return nil }
                var row: [String: Any] = ["path": path, "source": image.source, "is_primary": image.isPrimary, "role": image.role]
                if let w = image.width { row["width"] = w }
                if let h = image.height { row["height"] = h }
                if let l = image.label { row["label"] = l }
                return row
            }
        }
        if want("snippets") {
            out["snippets"] = (item.snippets ?? []).sorted { $0.addedAt < $1.addedAt }.map {
                ["text": $0.text, "source": $0.source, "added_at": iso($0.addedAt)] as [String: Any]
            }
        }
        return out
    }

    /// `/img/<key>` for an image the web copy already has: uploaded by the bridge, or
    /// imported from the old web library (its `sourceURL` points at the Worker).
    static func webPath(of image: ItemImage) -> String? {
        if let p = image.remotePath { return p }
        guard let url = image.sourceURL.flatMap(URL.init(string:)) else { return nil }
        if url.host == SyncAPI.baseURL.host, url.path.hasPrefix("/img/") { return url.path }
        // An external cover we never stored (og:image URL): the web can show it as is.
        if image.data == nil, url.scheme?.hasPrefix("http") == true { return url.absoluteString }
        return nil
    }

    // MARK: Wire → item

    /// Writes the row's scalar fields into `item`, touching only values that differ so
    /// an unchanged pull never dirties the item (or its CloudKit record).
    static func apply(_ row: Row, to item: Item, skipping skip: Set<String>) {
        let v = row.values
        func str(_ k: String) -> String?? { v[k].map { $0 as? String } }
        func set<T: Equatable>(_ k: String, _ kp: ReferenceWritableKeyPath<Item, T>, _ value: T) {
            if !skip.contains(k), item[keyPath: kp] != value { item[keyPath: kp] = value }
        }
        if let s = str("slug"), let s, !s.isEmpty { set("slug", \.slug, s) }
        if let s = str("title") { set("title", \.title, s ?? "") }
        if let s = str("source_url") { set("source_url", \.sourceURL, s) }
        if let s = str("domain") { set("domain", \.domain, s) }
        if let s = str("author") { set("author", \.author, s) }
        if let s = str("summary") { set("summary", \.summary, s) }
        if let s = str("body_markdown") { set("body_markdown", \.bodyMarkdown, s) }
        if let s = str("status"), let s { set("status", \.status, s == "broken" ? "gone" : s) }
        if let b = v["needs_review"] as? Bool { set("needs_review", \.needsReview, b) }
        if let s = str("kind"), let s { set("kind", \.kind, s) }
        if let s = str("enrichment_status"), let s { set("enrichment_status", \.enrichmentStatus, s) }
        if let s = str("added_at"), let d = s.flatMap(date) { set("added_at", \.addedAt, d) }
        if let s = str("analyzed_at") { set("analyzed_at", \.analyzedAt, s.flatMap(date)) }
        if let d = v["cover_aspect"] as? Double { set("cover_aspect", \.coverAspect, d) }
        if !skip.contains("metadata"), let m = v["metadata"] {
            let json = m is NSNull ? nil : encodeJSON(m)
            // Compare parsed, so key order from the server never counts as a change.
            if json.flatMap(parseJSON).map(canonical) != item.metadataJSON.flatMap(parseJSON).map(canonical) {
                item.metadataJSON = json
            }
        }
        if !skip.contains("tags"), let list = v["tags"] as? [[String: Any]] {
            let tags = list.compactMap { t -> ItemTag? in
                guard let name = (t["tag"] ?? t["name"]) as? String, let category = t["category"] as? String else { return nil }
                return ItemTag(name: name, category: category, weight: t["weight"] as? Double ?? 0.5, source: t["source"] as? String ?? "web")
            }
            if tags != item.tags { item.tags = tags }
        }
        if !skip.contains("snippets"), let list = v["snippets"] as? [[String: Any]], let context = item.modelContext {
            let incoming = list.compactMap { s -> (String, String, Date)? in
                guard let text = s["text"] as? String, !text.isEmpty else { return nil }
                return (text, s["source"] as? String ?? "web", (s["added_at"] as? String).flatMap(date) ?? item.addedAt)
            }
            let current = (item.snippets ?? []).sorted { $0.addedAt < $1.addedAt }
            if current.map(\.text) != incoming.map(\.0) {
                for old in current { context.delete(old) }
                for (text, source, added) in incoming {
                    let snippet = Snippet(text: text, source: source, addedAt: added)
                    context.insert(snippet)
                    snippet.item = item
                }
            }
        }
    }

    /// Image rows the item should gain or lose to match the row. New images come back
    /// as paths for the bridge to download; nothing here touches the network.
    static func applyImages(_ row: Row, to item: Item) -> [(ItemImage, String)] {
        guard let list = row.values["images"] as? [[String: Any]], let context = item.modelContext else { return [] }
        var byPath: [String: ItemImage] = [:]
        for image in item.images ?? [] { if let p = webPath(of: image) { byPath[p] = image } }
        var keep = Set<String>()
        var downloads: [(ItemImage, String)] = []
        for entry in list {
            guard let path = entry["path"] as? String else { continue }
            keep.insert(path)
            let isPrimary = entry["is_primary"] as? Bool ?? false
            if let existing = byPath[path] {
                if existing.isPrimary != isPrimary { existing.isPrimary = isPrimary }
                continue
            }
            let image = ItemImage(
                source: entry["source"] as? String ?? "web", isPrimary: isPrimary,
                width: entry["width"] as? Int, height: entry["height"] as? Int,
                label: entry["label"] as? String, role: entry["role"] as? String ?? "cover"
            )
            image.remotePath = path.hasPrefix("/img/") ? path : nil
            image.sourceURL = path.hasPrefix("http") ? path : SyncAPI.baseURL.appending(path: String(path.dropFirst())).absoluteString
            context.insert(image)
            image.item = item
            downloads.append((image, path))
        }
        // Only drop images the web copy knew about. A local image still waiting to upload
        // (no web path yet) stays.
        for (path, image) in byPath where !keep.contains(path) { context.delete(image) }
        return downloads
    }

    /// A new item for a row the device doesn't have (made or restored on the web).
    static func makeItem(from row: Row, in context: ModelContext) -> (Item, [(ItemImage, String)]) {
        let item = Item(id: row.id, enrichmentStatus: "candidates_done")
        context.insert(item)
        apply(row, to: item, skipping: [])
        let downloads = applyImages(row, to: item)
        return (item, downloads)
    }

    // MARK: Helpers

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
    static func date(_ s: String) -> Date? { isoFormatter.date(from: s) ?? isoPlain.date(from: s) }

    private static func parseJSON(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }
    private static func encodeJSON(_ v: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(v),
              let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
    private static func canonical(_ v: Any) -> String { encodeJSON(v) ?? "" }
}
