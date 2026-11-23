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

    // MARK: - Revisits and Gaps (web canvas.js `visit`, `famMeta`)

    @Test func revisitsGlowWithinTwoWeeksAndFadeAfterFourMonths() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        #expect(CanvasVisit.of(lastOpened: nil, count: 0, now: now) == nil)
        #expect(CanvasVisit.of(lastOpened: now.addingTimeInterval(-3 * day), count: 3, now: now) == .glow(count: 3))
        #expect(CanvasVisit.of(lastOpened: now.addingTimeInterval(-60 * day), count: 1, now: now) == nil)
        let old = now.addingTimeInterval(-200 * day)
        #expect(CanvasVisit.of(lastOpened: old, count: 1, now: now) == .fade(since: old))
        #expect(CanvasVisit.glow(count: 3).text == "Opened 3× recently")
        #expect(CanvasVisit.glow(count: 1).text == "Opened recently")
        let mar = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 15)))
        #expect(CanvasVisit.fade(since: mar).text == "Not opened since Mar 2026")
    }

    @Test func fadedCardsDimFurther() {
        #expect(CanvasView.cardOpacity(dim: false, fade: false) == 1)
        #expect(CanvasView.cardOpacity(dim: true, fade: false) == 0.22)
        #expect(CanvasView.cardOpacity(dim: false, fade: true) == 0.5)
        #expect(CanvasView.cardOpacity(dim: true, fade: true) == 0.18)
    }

    @Test func layerSettingsSavedBeforeGapsStillLoad() throws {
        let old = #"{"simOn":false,"alwaysLines":true,"kinds":["place"],"marks":false,"notes":true}"#
        let l = try JSONDecoder().decode(CanvasLayers.self, from: Data(old.utf8))
        #expect(!l.simOn && l.alwaysLines && !l.marks && l.notes)
        #expect(l.gaps && l.glow)
    }

    private func f(_ key: String, _ kind: SimKind) -> SimFeature {
        SimFeature(key: key, kind: kind, tag: String(key.dropFirst(2)))
    }

    @Test func maybePicksTheBestFitOffTheCanvas() {
        let members = [[f("c:blue", .colour), f("s:minimal", .style)], [f("c:blue", .colour), f("i:type", .idea)]]
        let library = [
            MaybeEntry(slug: "a", title: "On canvas", features: [f("c:blue", .colour), f("s:minimal", .style)]),
            MaybeEntry(slug: "b", title: "Blue type | Studio", features: [f("c:blue", .colour), f("i:type", .idea)]),
            MaybeEntry(slug: "c", title: "One trait", features: [f("c:blue", .colour)]),
        ]
        let pick = CanvasSimilarity.maybe(members: members, memberCount: 2, library: library, exclude: ["a"])
        #expect(pick == MaybePick(slug: "b", title: "Blue type | Studio", shared: ["blue", "type"]))
        // Dismissed or too weak: nothing.
        #expect(CanvasSimilarity.maybe(members: members, memberCount: 2, library: library, exclude: ["a", "b"]) == nil)
        #expect(CanvasSimilarity.maybe(members: [members[0]], memberCount: 1, library: library, exclude: []) == nil)
    }

    @Test func maybeTitlesAreShort() {
        #expect(CanvasSimilarity.shortTitle("Blue type | Studio") == "Blue type")
        #expect(CanvasSimilarity.shortTitle("Short") == "Short")
        #expect(CanvasSimilarity.shortTitle("A very long title that keeps going on") == "A very long title that…")
    }

    @Test func looseFeaturesSkipWebsitesAndCommonWords() {
        let tags = [ItemTag(name: "blue", category: "color", weight: 0.5),
                    ItemTag(name: "website", category: "subject", weight: 0.9),
                    ItemTag(name: "type", category: "subject", weight: 0.9)]
        let keys = CanvasSimilarity.looseFeatures(tags: tags, kindName: "Website").map(\.key)
        #expect(keys == ["c:blue", "i:type"])
        #expect(CanvasSimilarity.looseFeatures(tags: [], kindName: "Tool").map(\.key) == ["k:Tool"])
    }
}

