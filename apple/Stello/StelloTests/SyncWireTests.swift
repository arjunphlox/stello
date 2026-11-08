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

    @Test func revisitTrackingOnlyMovesForward() throws {
        let context = try makeContext()
        let item = Item(title: "x")
        context.insert(item)
        item.openCount = 5
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        item.lastOpenedAt = opened
        #expect(SyncWire.values(of: item)["open_count"] as? Int == 5)
        // A row the web never opened can't wipe local history.
        SyncWire.apply(row(item, overriding: ["open_count": 0, "last_opened_at": NSNull()]), to: item, skipping: [])
        #expect(item.openCount == 5)
        #expect(item.lastOpenedAt == opened)
        // A newer web open wins.
        SyncWire.apply(row(item, overriding: ["open_count": 6, "last_opened_at": "2027-01-01T00:00:00.000Z"]), to: item, skipping: [])
        #expect(item.openCount == 6)
        #expect(item.lastOpenedAt.map(SyncWire.iso) == "2027-01-01T00:00:00.000Z")
    }

    @Test func plainWebSavesJoinTheClassifyQueue() throws {
        let context = try makeContext()
        func wire(_ fields: [String: Any]) -> SyncWire.Row {
            var json: [String: Any] = ["id": UUID().uuidString.lowercased(), "seq": 1, "clock": [String: Int](), "deleted_at": NSNull(),
                                       "title": "x", "slug": "x", "kind": "link", "metadata": NSNull(), "enrichment_status": "done"]
            for (k, v) in fields { json[k] = v }
            return SyncWire.Row(json)!
        }
        let plain = SyncWire.makeItem(from: wire(["source_url": "https://shop.example/lamp"]), in: context, queueClassify: true).0
        #expect(plain.enrichmentStatus == WebLibraryImporter.awaitingClassifyStatus)
        let typed = SyncWire.makeItem(from: wire(["source_url": "https://shop.example/a", "kind": "product", "metadata": ["price": "10"]]), in: context, queueClassify: true).0
        #expect(typed.enrichmentStatus == "done")
        let note = SyncWire.makeItem(from: wire([:]), in: context, queueClassify: true).0
        #expect(note.enrichmentStatus == "done")
        let firstPull = SyncWire.makeItem(from: wire(["source_url": "https://shop.example/b"]), in: context, queueClassify: false).0
        #expect(firstPull.enrichmentStatus == "done")
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
