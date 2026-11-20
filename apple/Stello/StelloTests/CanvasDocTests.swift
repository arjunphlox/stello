import Testing
import Foundation
import CoreGraphics
@testable import Stello

/// The canvas doc is shared with the web through /api/projects (src/lib/projects.js).
@Suite("Canvas doc and camera")
@MainActor
struct CanvasDocTests {
    @Test func decodesAServerDocWithMissingArrays() throws {
        let json = #"{"name":"Moodboard","v":2,"cards":[{"slug":"a","x":10,"y":-20,"state":"use"}],"links":[{"id":"l1","a":"a","b":"b","kind":"influence","source":"web"}]}"#
        let doc = try JSONDecoder().decode(CanvasDoc.self, from: Data(json.utf8))
        #expect(doc.name == "Moodboard")
        #expect(doc.cards.first?.state == "use")
        #expect(doc.links.first?.kind == "influence")
        #expect(doc.groups.isEmpty && doc.notes.isEmpty && doc.dismissed.isEmpty)
    }

    @Test func roundTripKeepsLayer2Data() throws {
        var doc = CanvasDoc(name: "x")
        doc.notes = [.init(id: "n1", kind: "region", text: "this corner", slug: "a", rx: 0.2, ry: 0.8)]
        doc.groups = [.init(id: "g1", name: "Type", slugs: ["a", "b"])]
        let back = try JSONDecoder().decode(CanvasDoc.self, from: JSONEncoder().encode(doc))
        #expect(back == doc)
    }

    @Test func zoomKeepsThePointUnderTheAnchor() {
        var cam = CanvasCamera(x: 100, y: 50, k: 0.5)
        let anchor = CGPoint(x: 300, y: 200)
        let before = cam.toWorld(anchor)
        cam.zoom(to: 1.5, anchor: anchor)
        let after = cam.toWorld(anchor)
        #expect(abs(before.x - after.x) < 0.001 && abs(before.y - after.y) < 0.001)
        #expect(cam.k == 1.5)
    }

    @Test func zoomIsClamped() {
        var cam = CanvasCamera()
        cam.zoom(to: 50, anchor: .zero)
        #expect(cam.k == CanvasMetrics.maxZoom)
        cam.zoom(to: 0.0001, anchor: .zero)
        #expect(cam.k == CanvasMetrics.minZoom)
    }

    @Test func cardHeightMatchesTheWebClamp() {
        #expect(CanvasMetrics.cardHeight(imageWidth: 1000, imageHeight: 500, hasImage: true) == 137)
        #expect(CanvasMetrics.cardHeight(imageWidth: 100, imageHeight: 1000, hasImage: true) == (274 * 1.3).rounded())
        #expect(CanvasMetrics.cardHeight(imageWidth: nil, imageHeight: nil, hasImage: false) == (274 * 0.62).rounded())
    }

    @Test func fitFramesTheBox() {
        let cam = CanvasCamera.fit(CGRect(x: 0, y: 0, width: 1000, height: 500), in: CGSize(width: 600, height: 400), pad: 50)
        #expect(abs(cam.k - 0.5) < 0.001)
        let centre = cam.toScreen(CGPoint(x: 500, y: 250))
        #expect(abs(centre.x - 300) < 0.001 && abs(centre.y - 200) < 0.001)
    }
}
