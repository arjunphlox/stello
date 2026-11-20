import Testing
import Foundation
import CoreGraphics
@testable import Stello

/// Layer 1 rules, ported from canvas.js (buildIndex / simFor / familiesOf / suggestOf).
@Suite("Canvas similarity and grouping")
@MainActor
struct CanvasSimilarityTests {
    private func tag(_ name: String, _ cat: String, _ w: Double = 0.9) -> ItemTag {
        ItemTag(name: name, category: cat, weight: w)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat = 0) -> CGRect {
        CGRect(x: x, y: y, width: CanvasMetrics.cardWidth, height: 200)
    }

    @Test func featuresSkipCommonWordsAndTheSiteName() {
        let f = CanvasSimilarity.features(
            tags: [tag("blue", "color"), tag("minimal", "style"), tag("website", "subject"),
                   tag("figma", "subject"), tag("typography", "subject"), tag("lisbon", "location")],
            kindName: "Website", domain: "figma.com")
        let keys = Set(f.map(\.key))
        #expect(keys.contains("c:blue"))
        #expect(keys.contains("l:blue|minimal"))
        #expect(keys.contains("i:typography"))
        #expect(keys.contains("p:lisbon"))
        #expect(!keys.contains("i:website"))
        #expect(!keys.contains("i:figma"))
        #expect(!keys.contains { $0.hasPrefix("k:") })
    }

    @Test func neighboursPreferRareStrongTraits() {
        var feats: [String: [SimFeature]] = [:]
        feats["a"] = CanvasSimilarity.features(tags: [tag("lisbon", "location"), tag("red", "color")], kindName: "Note", domain: nil)
        feats["b"] = CanvasSimilarity.features(tags: [tag("lisbon", "location")], kindName: "Note", domain: nil)
        feats["c"] = CanvasSimilarity.features(tags: [tag("red", "color")], kindName: "Note", domain: nil)
        for s in ["d", "e", "f", "g"] {
            feats[s] = CanvasSimilarity.features(tags: [tag("green", "color")], kindName: "Note", domain: nil)
        }
        let links = CanvasSimilarity.neighbours(of: "a", features: feats, inverted: CanvasSimilarity.invert(feats))
        #expect(links.first?.b == "b")
        #expect(links.first?.kind == .place)
        #expect(links.first?.label == "Lisbon")
    }

    @Test func familiesKeepOnlyCardsThatSitTogether() {
        var feats: [String: [SimFeature]] = [:]
        for s in ["a", "b", "c"] {
            feats[s] = CanvasSimilarity.features(tags: [tag("lisbon", "location")], kindName: "Note", domain: nil)
        }
        feats["d"] = []
        let rects = ["a": rect(0), "b": rect(300), "c": rect(5000), "d": rect(600)]
        let fams = CanvasSimilarity.families(groups: [], rects: rects, features: feats,
                                             inverted: CanvasSimilarity.invert(feats))
        #expect(fams.count == 1)
        #expect(fams.first?.slugs == ["a", "b"])
        #expect(fams.first?.pills.first == "Lisbon")
    }

    @Test func yourGroupsComeFirstAndKeepTheirName() {
        let rects = ["a": rect(0), "b": rect(5000)]
        let fams = CanvasSimilarity.families(groups: [.init(id: "g1", name: "type refs", slugs: ["a", "b"])],
                                             rects: rects, features: [:], inverted: [:])
        #expect(fams.first?.groupID == "g1")
        #expect(fams.first?.pills.first == "Type refs")
    }

    @Test func dragNearACardSuggestsAGroup() {
        let feats = ["a": [SimFeature(key: "c:red", kind: .colour, tag: "red")],
                     "b": [SimFeature(key: "c:red", kind: .colour, tag: "red")]]
        let sug = CanvasSimilarity.suggestion(for: "a", at: rect(310), rects: ["b": rect(0)],
                                              families: [], features: feats)
        #expect(sug?.members == ["b"])
        #expect(sug?.name == "Red")
        #expect(sug?.joining == false)
        #expect(CanvasSimilarity.suggestion(for: "a", at: rect(400), rects: ["b": rect(0)],
                                            families: [], features: feats) == nil)
    }

    @Test func dragNearAGroupJoinsIt() {
        let fam = CanvasFamily(id: "g:g1", name: "Refs", groupID: "g1", slugs: ["b", "c"], pills: ["Refs"])
        let sug = CanvasSimilarity.suggestion(for: "a", at: rect(0, 230), rects: ["b": rect(0), "c": rect(290)],
                                              families: [fam], features: [:])
        #expect(sug?.groupID == "g1")
        #expect(sug?.label == "Drop to add to Refs")
        #expect(sug?.box.width == 290 + CanvasMetrics.cardWidth)
    }

    @Test func droppedClearOfItsGroupLeaves() {
        #expect(CanvasSimilarity.leaves(rect(2000), others: [rect(0), rect(290)]))
        #expect(!CanvasSimilarity.leaves(rect(300, 40), others: [rect(0), rect(290)]))
    }

    @Test func routesBendAtRightAngles() {
        let pts = CanvasSimilarity.route(from: rect(0), to: rect(1000, 400))
        #expect(pts.count == 4)
        #expect(pts[0].y == pts[1].y)
        #expect(pts[1].x == pts[2].x)
        #expect(pts[2].y == pts[3].y)
        let short = CanvasSimilarity.route(from: rect(0), to: rect(300))
        #expect(short.count == 2)
    }
}
