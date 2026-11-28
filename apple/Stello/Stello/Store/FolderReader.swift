import Foundation

/// Reading Stello items back from the files in a folder (grid part 1, Nov 28 2026).
/// Web twin: `src/lib/folder-read.js`; both are checked against the same fixtures
/// (test/fixtures/folder-read.json → StelloTests/FolderReadFixtures.swift).
///
/// Stello shows only what's in the added folders, and an edit made to a file outside
/// Stello (a text editor, a script, an agent) shows up in Stello. Stello works out the
/// file it would write for the item it has (`FolderWriter.itemFile`, keeping the file's
/// own path and extras) and compares it with the file field by field. Only fields that
/// differ are taken, so a file Stello wrote itself changes nothing.
nonisolated enum FolderReader {
    typealias W = FolderWriter
    typealias JSON = FolderWriter.JSON
    typealias Obj = FolderWriter.Obj

    /// Header key → item field (sync API names), for the details a person may change in a file.
    static let map: [(String, String)] = [
        ("title", "title"), ("url", "source_url"), ("kind", "kind"), ("site", "domain"),
        ("summary", "summary"), ("status", "status"), ("added", "added_at"), ("review", "needs_review"),
        ("cover_aspect", "cover_aspect"), ("meta", "metadata"), ("snippets", "snippets"), ("images", "images"),
    ]
    /// Details Stello keeps up itself; read from a file only when the item is new.
    static let machine: [(String, String)] = [
        ("analyzed", "analyzed_at"), ("opened", "last_opened_at"), ("open_count", "open_count"), ("enrichment", "enrichment_status"),
    ]

    // MARK: - Comparing (folder-read.js `stable` / `same`)

    static func isEmpty(_ v: JSON?) -> Bool {
        guard let v else { return true }
        if case .bool(false) = v { return true }
        return v.isEmpty
    }

    /// JSON with sorted keys and empty values dropped, so equal data compares equal.
    static func stable(_ v: JSON?) -> String {
        guard let v, !isEmpty(v) else { return "null" }
        switch v {
        case .array(let a): return "[" + a.map { stable($0) }.joined(separator: ",") + "]"
        case .object(let o):
            return "{" + o.keys.sorted().filter { !isEmpty(o[$0]) }.map { W.quote($0) + ":" + stable(o[$0]) }.joined(separator: ",") + "}"
        default: return W.stringify(v)
        }
    }
    static func same(_ a: JSON?, _ b: JSON?) -> Bool { stable(a) == stable(b) }

    private static func trimEnd(_ s: String) -> String {
        var out = s
        while let last = out.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) { out.unicodeScalars.removeLast() }
        return out
    }

    /// Images as the item holds them: the folder's own copy (`file`) is the file's business.
    static func images(_ v: JSON?) -> JSON {
        .array((v?.array ?? []).map { img in
            guard var o = img.object else { return img }
            o["file"] = nil
            return .object(o)
        })
    }

    /// A header's title: people files keep it under `name`.
    private static func title(_ h: Obj) -> JSON? { h["title"] ?? h["name"] }

    /// Entity id → its name, from the folder's people/ and places/ files.
    static func name(of id: String, _ entities: [W.Entity]) -> String {
        if let e = entities.first(where: { $0.id == id }), !e.name.isEmpty { return e.name }
        var bare = id
        for p in ["person-", "place-"] where bare.hasPrefix(p) { bare = String(bare.dropFirst(p.count)); break }
        return W.titleFromTag(bare)
    }
    private static func placeTag(_ name: String) -> String { W.nameKey(name).replacingOccurrences(of: " ", with: "-") }

    /// Tags from a file: its grouped tags plus its places as location tags; `source` kept where known.
    static func tags(from h: Obj, _ entities: [W.Entity], known: [JSON] = []) -> JSON {
        var out: [Obj] = []
        func had(_ match: (Obj) -> Bool) -> Obj? { known.compactMap(\.object).first(where: match) }
        for (category, group) in h["tags"]?.object?.pairs ?? [] where category != "location" {
            for (tag, weight) in group.object?.pairs ?? [] {
                var t = Obj([("tag", .string(tag)), ("category", .string(category)), ("weight", .number(weight.number ?? 1))])
                if let prior = had({ $0["category"]?.string == category && $0["tag"]?.string == tag }),
                   let source = prior["source"], !isEmpty(source) { t["source"] = source }
                out.append(t)
            }
        }
        for id in (h["places"]?.array ?? []).compactMap(\.string) {
            let tag = placeTag(name(of: id, entities))
            if tag.isEmpty || out.contains(where: { $0["category"]?.string == "location" && $0["tag"]?.string == tag }) { continue }
            if let prior = had({ $0["category"]?.string == "location" && placeTag(W.titleFromTag($0["tag"]?.string ?? "")) == tag }) {
                out.append(prior)
            } else {
                out.append(Obj([("tag", .string(tag)), ("category", .string("location")), ("weight", .number(1))]))
            }
        }
        return .array(out.map { .object($0) })
    }

    /// The author's name from a file's people list (the entry marked author).
    static func author(from h: Obj, _ entities: [W.Entity]) -> JSON {
        guard let a = (h["people"]?.array ?? []).first(where: { $0["role"]?.string == "author" }),
              let id = a["id"]?.string else { return .null }
        return .string(name(of: id, entities))
    }

    /// Metadata after a file edit: some details live as people and places in the file, so
    /// only keys the file shows are taken from it; the rest stay.
    static func meta(had: JSON?, shown: JSON?, now: JSON?) -> JSON {
        var out = had?.object ?? Obj()
        for k in shown?.object?.keys ?? [] { out[k] = nil }
        for (k, v) in now?.object?.pairs ?? [] { out[k] = v }
        return out.isEmpty ? .null : .object(out)
    }

    // MARK: - Edits

    /// What a file changed about an item Stello already has (`item` in sync API shape, as
    /// `FolderSources.wire` gives it). Returns only the changed fields, or nil.
    static func fileEdits(_ item: Obj, text: String, path: String, entities: [W.Entity], paths: Set<String> = []) -> Obj? {
        guard let copy = W.readCopy(text), copy.header["id"]?.string?.lowercased() == item["id"]?.string?.lowercased() else { return nil }
        var used = paths
        let mine = W.itemFile(item, entities: entities, paths: &used, existing: (path, copy))
        let theirs = copy.header
        var fields = Obj()
        for (key, field) in map {
            let a = key == "title" ? title(mine.header) : mine.header[key]
            let b = key == "title" ? title(theirs) : theirs[key]
            if key == "images" ? same(images(a), images(b)) : same(a, b) { continue }
            switch key {
            case "review": fields[field] = .bool(b == .bool(true))
            case "images": fields[field] = images(b)
            case "snippets": fields[field] = .array(b?.array ?? [])
            case "meta": fields[field] = meta(had: item["metadata"], shown: a, now: b)
            case "title": fields[field] = isEmpty(b) ? .string("") : b!
            case "status", "added": if !isEmpty(b) { fields[field] = b! }
            default: fields[field] = isEmpty(b) ? .null : b!
            }
        }
        if !same(mine.header["tags"], theirs["tags"]) || !same(mine.header["places"], theirs["places"]) {
            fields["tags"] = tags(from: theirs, entities, known: item["tags"]?.array ?? [])
        }
        if !same(mine.header["people"], theirs["people"]) {
            let a = author(from: theirs, entities)
            if !same(a, item["author"]) { fields["author"] = a }
        }
        let mineBody = W.trim(trimEnd(mine.body)), theirBody = W.trim(trimEnd(copy.body))
        if mineBody != theirBody {
            let b = trimEnd(copy.body)
            fields["body_markdown"] = b.isEmpty ? .null : .string(b)
        }
        return fields.isEmpty ? nil : fields
    }

    // MARK: - New items

    /// A file whose item Stello doesn't have yet → its id and fields (sync API names), or nil
    /// when the file isn't a library item. `modified` (seconds) stands in for missing dates.
    static func itemFromFile(_ text: String, path: String, entities: [W.Entity], modified: Double) -> (id: String, fields: Obj)? {
        guard let copy = W.readCopy(text), let rawID = copy.header["id"]?.string, W.isLibraryID(rawID) else { return nil }
        let h = copy.header
        let id = rawID.lowercased()
        var fields = Obj()
        for (key, field) in map + machine {
            let v = key == "title" ? title(h) : h[key]
            fields[field] = isEmpty(v) ? .null : v!
        }
        let stamp = FolderIngest.iso(Date(timeIntervalSince1970: modified))
        var name = (path as NSString).lastPathComponent
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        fields["slug"] = .string(W.safeName(name, fallback: id))
        if isEmpty(fields["title"]) { fields["title"] = .string(name.isEmpty ? "Untitled" : name) }
        if isEmpty(fields["added_at"]) { fields["added_at"] = .string(stamp) }
        if isEmpty(fields["status"]) { fields["status"] = .string("active") }
        if isEmpty(fields["enrichment_status"]) {
            let linkWithoutKind = !isEmpty(fields["source_url"]) && isEmpty(fields["kind"])
            fields["enrichment_status"] = .string(linkWithoutKind ? "awaiting_classify" : "done")
        }
        fields["needs_review"] = .bool(h["review"] == .bool(true))
        fields["open_count"] = .number(h["open_count"]?.number ?? 0)
        fields["images"] = images(h["images"])
        fields["snippets"] = .array(h["snippets"]?.array ?? [])
        fields["tags"] = tags(from: h, entities)
        fields["author"] = author(from: h, entities)
        let body = trimEnd(copy.body)
        fields["body_markdown"] = body.isEmpty ? .null : .string(body)
        return (id, fields)
    }

    // MARK: - To SyncWire

    /// Ordered JSON → plain values (`NSNull` for null), the shape `SyncWire.Row` reads.
    static func plain(_ v: JSON) -> Any {
        switch v {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return NSNumber(value: n)  // reads as Double or Int, as JSONSerialization gives
        case .string(let s): return s
        case .array(let a): return a.map(plain)
        case .object(let o):
            var d: [String: Any] = [:]
            for (k, x) in o.pairs { d[k] = plain(x) }
            return d
        }
    }
}
