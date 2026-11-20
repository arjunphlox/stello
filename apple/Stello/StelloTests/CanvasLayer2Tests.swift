import Testing
import Foundation
import CoreGraphics
@testable import Stello

/// Layer 2 names and the Package export (web canvas.js `L2`, canvas-export.js).
@Suite("Canvas Layer 2 and Package export")
@MainActor
struct CanvasLayer2Tests {
    @Test func linkKindsKeepTheServerNames() {
        #expect(L2Kind.partOf.rawValue == "part_of")
        #expect(L2Kind(rawValue: "maybe") == .maybe)
        #expect(L2Kind(rawValue: "similar") == nil)
    }

    @Test func linkLabelsReadAsOnTheWeb() {
        #expect(L2Kind.influence.text(nil) == "inspired")
        #expect(L2Kind.influence.text(" type ") == "inspired: type")
        #expect(L2Kind.contrast.text("") == "vs")
        #expect(L2Kind.contrast.text("colour") == "vs · colour")
        #expect(L2Kind.partOf.text("x") == "part of")
        #expect(L2Kind.maybe.text(nil) == nil)
        #expect(L2Kind.question.text("x") == nil)
    }

    @Test func emptyCanvasTapMakesASetOrAQuestion() {
        #expect(L2Kind.partOf.noteOnEmpty == "set")
        #expect(L2Kind.question.noteOnEmpty == "question")
        #expect(L2Kind.influence.noteOnEmpty == nil)
        #expect(L2Kind.influence.asksLabel && L2Kind.contrast.asksLabel && !L2Kind.partOf.asksLabel)
    }

    @Test func slugNamesAreFileSafe() {
        #expect(CanvasPackageExporter.slugName("Moodboard: Lisbon / 2026!") == "moodboard-lisbon-2026")
        #expect(CanvasPackageExporter.slugName("   ") == "canvas")
        #expect(CanvasPackageExporter.slugName("Café") == "caf")
        #expect(CanvasPackageExporter.slugName(String(repeating: "a", count: 90)).count == 60)
    }

    private func card(_ slug: String, title: String) -> CanvasPackageExporter.Card {
        let item = Item(slug: slug, title: title, sourceURL: "https://example.com/\(slug)",
                        domain: "example.com", summary: "A summary", kind: "website")
        var c = CanvasPackageExporter.Card(slug: slug, item: item,
                                           rect: CGRect(x: 10.4, y: -20.6, width: 274, height: 200),
                                           state: "use", reason: "Great type")
        c.file = "001-\(slug).md"
        return c
    }

    @Test func itemMarkdownHasFrontMatterAndReason() {
        let md = CanvasPackageExporter.itemMarkdown(card("a", title: "Say \"hi\""))
        #expect(md.hasPrefix("---\ntitle: \"Say \\\"hi\\\"\""))
        #expect(md.contains("url: https://example.com/a"))
        #expect(md.contains("state: use"))
        #expect(md.contains("canvas_position: { x: 10, y: -21 }"))
        #expect(md.contains("# Say \"hi\""))
        #expect(md.contains("> Great type"))
        #expect(md.contains("A summary"))
    }

    @Test func readmeListsLooseItemsLinksAndNotes() {
        var doc = CanvasDoc(name: "Trip")
        doc.notes = [.init(id: "n1", kind: "question", text: "Why blue?", x: 0, y: 0,
                           near: nil, slug: nil, rx: nil, ry: nil, slugs: nil)]
        doc.links = [
            .init(id: "l1", a: "a", b: "n1", kind: "question", label: nil, source: "mac"),
            .init(id: "l2", a: "a", b: "gone", kind: "influence", label: nil, source: "mac"),
        ]
        let text = CanvasPackageExporter.readme(doc: doc, cards: [card("a", title: "Alpha")], groups: [])
        #expect(text.hasPrefix("# Trip\n"))
        #expect(text.contains("## Not in a group"))
        #expect(text.contains("- [Alpha](items/001-a.md)"))
        #expect(text.contains("- Alpha → “Why blue?” (question)"))
        #expect(!text.contains("gone"))
        #expect(text.contains("- **question**: Why blue?"))
    }

    @Test func canvasJSONIsTheWebFormat() throws {
        let data = try CanvasPackageExporter.canvasJSON(doc: CanvasDoc(name: "Trip"), cards: [card("a", title: "Alpha")])
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["format"] as? String == "stello-canvas")
        #expect(root["version"] as? Int == 2)
        let items = try #require(root["items"] as? [[String: Any]])
        #expect(items.first?["file"] as? String == "items/001-a.md")
        #expect((root["canvas"] as? [String: Any])?["name"] as? String == "Trip")
    }
}
