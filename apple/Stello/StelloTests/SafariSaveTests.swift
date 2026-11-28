import XCTest
@testable import Stello

/// Saves from Safari: the inbox request round-trips, and a batch lands together on a canvas.
@MainActor
final class SafariSaveTests: XCTestCase {
    func testRequestRoundTrips() throws {
        let request = SafariSaveInbox.Request(
            id: "r1", at: Date(timeIntervalSince1970: 1_800_000_000), canvas: "new", newName: "Posters",
            groupName: "Posters", entries: [.init(kind: "image", url: "https://a.test/p.jpg", page: "https://a.test", title: "P")],
            from: "safari-drop")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(SafariSaveInbox.Request.self, from: encoder.encode(request))
        XCTAssertEqual(back, request)
    }

    func testBatchLandsRightOfExistingCardsAsOneGroup() {
        var doc = CanvasDoc(name: "Posters")
        doc.cards = [.init(slug: "old", x: 0, y: 100)]
        CanvasStore.lay(["a", "b", "c", "old", "a"], in: &doc, groupName: "Brutalist posters", height: { _ in 200 })
        let fresh = doc.cards.filter { $0.slug != "old" }
        XCTAssertEqual(fresh.map(\.slug), ["a", "b", "c"])
        XCTAssertTrue(fresh.allSatisfy { $0.x >= 274 + 160 && $0.y == 100 })
        XCTAssertEqual(Set(fresh.map(\.x)).count, 3)
        XCTAssertEqual(doc.groups.count, 1)
        XCTAssertEqual(doc.groups[0].name, "Brutalist posters")
        XCTAssertEqual(doc.groups[0].slugs, ["a", "b", "c"])
    }

    func testOneItemMakesNoGroupAndFifthCardStacks() {
        var one = CanvasDoc()
        CanvasStore.lay(["a"], in: &one, groupName: nil, height: { _ in 200 })
        XCTAssertEqual(one.cards.first?.x, 0)
        XCTAssertTrue(one.groups.isEmpty)

        var five = CanvasDoc()
        CanvasStore.lay(["a", "b", "c", "d", "e"], in: &five, groupName: nil, height: { _ in 200 })
        XCTAssertEqual(five.cards[4].x, 0)
        XCTAssertEqual(five.cards[4].y, 216)
        XCTAssertEqual(five.groups.first?.name, "From Safari")
    }
}
