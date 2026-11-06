import Testing
import Foundation
import SwiftData
@testable import Stello

/// Item ↔ web-copy row mapping used by `SyncBridge` (wire shape: src/lib/sync.js).
@Suite("Web sync wire mapping")
@MainActor
struct SyncWireTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try StelloStore.makeInMemoryContainer())
    }

    private func row(_ item: Item, overriding extra: [String: Any] = [:]) -> SyncWire.Row {
        var json = SyncWire.values(of: item)
        json["id"] = item.id.uuidString.lowercased()
        json["seq"] = 1
        json["clock"] = [String: Int]()
        json["deleted_at"] = NSNull()
        for (k, v) in extra { json[k] = v }
        // Round-trip through JSON, as a pull would.
        let data = try! JSONSerialization.data(withJSONObject: json)
        return SyncWire.Row(try! JSONSerialization.jsonObject(with: data) as! [String: Any])!
    }

    @Test func roundTripChangesNothing() throws {
        let context = try makeContext()
        let item = Item(title: "Karst", sourceURL: "https://example.com", summary: "A typeface", status: "gone", kind: "typeface")
        item.tags = [ItemTag(name: "serif", category: "style", weight: 0.8, source: "ai")]
        item.metadataJSON = #"{"b":1,"a":"x"}"#
        context.insert(item)
        try context.save()

        let wire = SyncWire.values(of: item)
        #expect(wire["status"] as? String == "broken")
        #expect((wire["tags"] as? [[String: Any]])?.first?["tag"] as? String == "serif")

        let before = (item.title, item.tagsJSON, item.metadataJSON, item.status)
        SyncWire.apply(row(item), to: item, skipping: [])
        #expect(!context.hasChanges)
        #expect(before == (item.title, item.tagsJSON, item.metadataJSON, item.status))
    }

    @Test func applyTakesServerValuesExceptSkipped() throws {
        let context = try makeContext()
        let item = Item(title: "Old", summary: "old summary")
        context.insert(item)
        SyncWire.apply(row(item, overriding: ["title": "New", "summary": "new summary"]), to: item, skipping: ["summary"])
        #expect(item.title == "New")
        #expect(item.summary == "old summary")
    }

    @Test func snippetsAndImagesFollowTheRow() throws {
        let context = try makeContext()
        let item = Item(title: "x")
        context.insert(item)
        let r = row(item, overriding: [
            "snippets": [["text": "a quote", "source": "web", "added_at": "2026-11-06T10:00:00Z"]],
            "images": [["path": "/img/u/sync/abc.webp", "is_primary": true, "source": "web"]],
        ])
        SyncWire.apply(r, to: item, skipping: [])
        let downloads = SyncWire.applyImages(r, to: item)
        #expect(item.snippets?.map(\.text) == ["a quote"])
        #expect(downloads.count == 1)
        #expect(item.images?.first?.remotePath == "/img/u/sync/abc.webp")
        // Same row again: no new images.
        #expect(SyncWire.applyImages(r, to: item).isEmpty)
    }

    @Test func importedCoverMapsToItsWorkerPath() {
        let image = ItemImage()
        image.sourceURL = "https://stello.arjunphlox.workers.dev/img/user/slug/cover.webp"
        image.data = Data([1, 2, 3])
        #expect(SyncWire.webPath(of: image) == "/img/user/slug/cover.webp")
        let local = ItemImage(data: Data([1]))
        #expect(SyncWire.webPath(of: local) == nil)
    }
}
