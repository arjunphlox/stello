import Foundation
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

/// "Package" export (web `canvas-export.js`, format `package`): a zip folder with
/// README.md (groups, links, notes), one Markdown file per item, the covers, and
/// canvas.json (the doc plus item data), so a canvas leaves Stello whole.
enum CanvasPackageExporter {
    struct Card {
        let slug: String
        let item: Item
        let rect: CGRect
        let state: String?
        let reason: String?
        var groups: [String] = []
        var file = ""
        var imageFile: String?
    }

    static func slugName(_ s: String) -> String {
        let lower = s.lowercased()
        var out = ""
        var dash = false
        for ch in lower {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch)
                dash = false
            } else if !dash && !out.isEmpty {
                out.append("-")
                dash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        let cut = String(out.prefix(60))
        return cut.isEmpty ? "canvas" : cut
    }

    private static func title(_ item: Item) -> String {
        !item.title.isEmpty ? item.title : (item.domain ?? item.slug)
    }

    private static func quoted(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data()
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }

    /// Builds the package and returns the zip's bytes.
    static func makeZip(doc: CanvasDoc, items: [String: Item], rects: [String: CGRect],
                        families: [CanvasFamily]) throws -> Data {
        let base = slugName(doc.name.isEmpty ? "canvas" : doc.name)
        var cards: [Card] = doc.cards.compactMap { c in
            guard let item = items[c.slug], let r = rects[c.slug] else { return nil }
            return Card(slug: c.slug, item: item, rect: r, state: c.state, reason: c.note)
        }
        let index = Dictionary(uniqueKeysWithValues: cards.enumerated().map { ($1.slug, $0) })
        let groups = families.filter { $0.slugs.count >= 2 }
        for g in groups {
            for s in g.slugs { if let i = index[s] { cards[i].groups.append(g.pills.first ?? "Group") } }
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("stello-canvas-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(base, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let itemsDir = folder.appendingPathComponent("items", isDirectory: true)
        let imagesDir = folder.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: itemsDir, withIntermediateDirectories: true)

        for i in cards.indices {
            let n = String(format: "%03d", i + 1)
            let name = slugName(title(cards[i].item))
            cards[i].file = "\(n)-\(name.prefix(50)).md"
            if let data = cards[i].item.coverImage?.data, !data.isEmpty {
                let ext = ItemBundleExporter.imageExtension(for: data)
                let file = "\(n)-\(name.prefix(40)).\(ext == "bin" ? "jpg" : ext)"
                if !fm.fileExists(atPath: imagesDir.path) {
                    try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
                }
                try data.write(to: imagesDir.appendingPathComponent(file))
                cards[i].imageFile = file
            }
        }
        for c in cards {
            try itemMarkdown(c).write(to: itemsDir.appendingPathComponent(c.file), atomically: true, encoding: .utf8)
        }
        try readme(doc: doc, cards: cards, groups: groups)
            .write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try canvasJSON(doc: doc, cards: cards).write(to: folder.appendingPathComponent("canvas.json"))
        return try ItemBundleExporter.zipDirectory(at: folder)
    }

    // MARK: - Markdown

    static func itemMarkdown(_ c: Card) -> String {
        let it = c.item
        var fm = ["---", "title: \(quoted(title(it)))"]
        if let url = it.sourceURL, !url.isEmpty { fm.append("url: \(url)") }
        if let d = it.domain, !d.isEmpty { fm.append("domain: \(d)") }
        if !it.kind.isEmpty { fm.append("kind: \(it.kind)") }
        fm.append("saved: \(String(ISO8601DateFormatter().string(from: it.addedAt).prefix(10)))")
        if let s = c.state { fm.append("state: \(s)") }
        let tags = it.tags.prefix(30).map { quoted($0.name) }
        if !tags.isEmpty { fm.append("tags: [\(tags.joined(separator: ", "))]") }
        if !c.groups.isEmpty { fm.append("groups: [\(c.groups.map(quoted).joined(separator: ", "))]") }
        fm.append("canvas_position: { x: \(Int(c.rect.minX.rounded())), y: \(Int(c.rect.minY.rounded())) }")
        fm.append(contentsOf: ["---", ""])
        var body = ["# \(title(it))", ""]
        if let f = c.imageFile { body.append(contentsOf: ["![cover](../images/\(f))", ""]) }
        if let r = c.reason, !r.isEmpty { body.append(contentsOf: ["> \(r)", ""]) }
        if let s = it.summary, !s.isEmpty { body.append(contentsOf: [s, ""]) }
        let snippets = (it.snippets ?? []).filter { !$0.text.isEmpty }.sorted { $0.addedAt < $1.addedAt }.prefix(5)
        for sn in snippets { body.append(contentsOf: ["> \(sn.text)", ""]) }
        return fm.joined(separator: "\n") + "\n" + body.joined(separator: "\n")
    }

    static func readme(doc: CanvasDoc, cards: [Card], groups: [CanvasFamily]) -> String {
        let bySlug = Dictionary(uniqueKeysWithValues: cards.map { ($0.slug, $0) })
        let today = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        var L = ["# \(doc.name)", "", "\(cards.count) items · exported from Stello \(today)", "",
                 "In this folder: `items/` (one Markdown file per item), `images/` (covers), `canvas.json` (the canvas and item data).", ""]
        if !groups.isEmpty {
            L.append(contentsOf: ["## Groups", ""])
            for g in groups {
                L.append(contentsOf: ["### \(g.pills.joined(separator: " · "))", ""])
                for s in g.slugs { if let c = bySlug[s] { L.append("- [\(title(c.item))](items/\(c.file))") } }
                L.append("")
            }
        }
        let loose = cards.filter { $0.groups.isEmpty }
        if !loose.isEmpty {
            L.append(contentsOf: ["## Not in a group", ""])
            loose.forEach { L.append("- [\(title($0.item))](items/\($0.file))") }
            L.append("")
        }
        func label(_ id: String) -> String {
            if let c = bySlug[id] { return title(c.item) }
            if let n = doc.notes.first(where: { $0.id == id }) { return "“\(n.text.isEmpty ? n.kind : n.text)”" }
            return id
        }
        let ids = Set(cards.map(\.slug)).union(doc.notes.map(\.id))
        let links = doc.links.filter { ids.contains($0.a) && ids.contains($0.b) }
        if !links.isEmpty {
            L.append(contentsOf: ["## Links", ""])
            for l in links {
                let lab = (l.label ?? "").isEmpty ? "" : ": \(l.label!)"
                L.append("- \(label(l.a)) → \(label(l.b)) (\(l.kind)\(lab))")
            }
            L.append("")
        }
        if !doc.notes.isEmpty {
            L.append(contentsOf: ["## Notes", ""])
            doc.notes.forEach { L.append("- **\($0.kind)**: \($0.text)") }
            L.append("")
        }
        return L.joined(separator: "\n")
    }

    // MARK: - JSON

    static func canvasJSON(doc: CanvasDoc, cards: [Card]) throws -> Data {
        var out = doc
        out.v = CanvasDoc.version
        let canvas = try JSONSerialization.jsonObject(with: JSONEncoder().encode(out))
        let items: [[String: Any]] = cards.map { c in
            let it = c.item
            var o: [String: Any] = [
                "slug": c.slug, "title": it.title, "kind": it.kind,
                "tags": it.tags.map { ["tag": $0.name, "category": $0.category, "weight": $0.weight] },
                "x": Double(c.rect.minX), "y": Double(c.rect.minY),
                "w": Double(c.rect.width), "h": Double(c.rect.height),
                "groups": c.groups, "file": "items/" + c.file,
            ]
            o["url"] = it.sourceURL ?? NSNull()
            o["domain"] = it.domain ?? NSNull()
            o["summary"] = it.summary ?? NSNull()
            o["image"] = NSNull()
            o["image_file"] = c.imageFile.map { "images/" + $0 } ?? NSNull()
            return o
        }
        let root: [String: Any] = [
            "format": "stello-canvas", "version": 2,
            "exported_at": ISO8601DateFormatter().string(from: .now),
            "canvas": canvas, "items": items,
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

/// The zip handed to the save panel / share sheet.
struct CanvasPackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
