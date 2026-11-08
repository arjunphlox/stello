import Testing
import Foundation
import SwiftData
@testable import Stello

/// Tool metadata as the Worker's tool reader sends it: its empty shape always carries these
/// keys (`src/lib/readers/tool.js`), which `ToolMeta`'s synthesized decoder requires.
private func toolMetadata(_ fields: [String: Any]) -> [String: Any] {
    var meta: [String: Any] = ["platforms": [String](), "platformsAreGuess": false, "pricingIsGuess": false, "topics": [String]()]
    meta.merge(fields) { _, new in new }
    return meta
}

// MARK: - WorkerRead parsing

@Suite("Worker read: /api/classify answers")
struct WorkerReadParsingTests {

    @Test("Kind, trimmed text fields, gone status, confidence")
    func fields() throws {
        let read = try #require(WorkerRead(json: [
            "kind": "tool",
            "title": "  Things 3 ",
            "summary": "",
            "domain": "culturedcode.com",
            "status": "gone",
            "confidence": 0.8,
        ]))
        #expect(read.kind == .tool)
        #expect(read.title == "Things 3")
        #expect(read.summary == nil)
        #expect(read.extractedText == nil)
        #expect(read.domain == "culturedcode.com")
        #expect(read.isGone)
        #expect(read.confidence == 0.8)
    }

    @Test("Metadata object becomes a JSON string the meta structs decode")
    func metadataJSON() throws {
        let read = try #require(WorkerRead(json: [
            "kind": "tool",
            "metadata": toolMetadata(["name": "Things 3", "platforms": ["macOS", "iOS"], "subtype": "app"]),
        ]))
        let json = try #require(read.metadataJSON)
        #expect(json.contains(#""name":"Things 3""#))
        let meta = try #require(read.meta(ToolMeta.self))
        #expect(meta.name == "Things 3")
        #expect(meta.platforms == ["macOS", "iOS"])
        #expect(meta.subtype == "app")
        // A partial object (keys the Swift struct requires missing) doesn't decode.
        let partial = try #require(WorkerRead(json: ["kind": "tool", "metadata": ["name": "Things 3"]]))
        #expect(partial.meta(ToolMeta.self) == nil)
    }

    @Test("No metadata, or null, leaves metadataJSON nil")
    func noMetadata() throws {
        #expect(try #require(WorkerRead(json: ["kind": "link"])).metadataJSON == nil)
        #expect(try #require(WorkerRead(json: ["kind": "link", "metadata": NSNull()])).metadataJSON == nil)
        #expect(try #require(WorkerRead(json: ["kind": "link"])).meta(ToolMeta.self) == nil)
    }

    @Test("Images: urls in order, source, fallbacks; bad entries dropped; og by default")
    func images() throws {
        let read = try #require(WorkerRead(json: [
            "kind": "book",
            "images": [
                "urls": ["https://example.com/cover.jpg", "https://example.com/2.jpg"],
                "source": "product",
                "fallbacks": ["https://covers.openlibrary.org/b/isbn/9780262033848-L.jpg"],
            ],
        ]))
        #expect(read.imageURLs.map(\.absoluteString) == ["https://example.com/cover.jpg", "https://example.com/2.jpg"])
        #expect(read.imageSource == "product")
        #expect(read.fallbackImageURLs.count == 1)

        let bare = try #require(WorkerRead(json: ["kind": "article"]))
        #expect(bare.imageURLs.isEmpty)
        #expect(bare.imageSource == "og")
        #expect(bare.fallbackImageURLs.isEmpty)
        #expect(!bare.isGone)
        #expect(bare.confidence == 0)
    }

    @Test("An error answer, a missing or unknown kind → nil")
    func errors() {
        #expect(WorkerRead(json: ["error": "Unauthorized"]) == nil)
        #expect(WorkerRead(json: ["error": "bad html", "kind": "article"]) == nil)
        #expect(WorkerRead(json: [:]) == nil)
        #expect(WorkerRead(json: ["kind": "spaceship"]) == nil)
    }
}

// MARK: - canApply / applyFreshRead

@Suite("Enrich: which fresh reads may be stored")
struct EnrichmentCanApplyTests {

    private func read(_ kind: String, metadata: [String: Any]? = [:]) -> WorkerRead {
        var json: [String: Any] = ["kind": kind]
        if let metadata { json["metadata"] = metadata }
        return WorkerRead(json: json)!
    }

    @Test("A plain link may become a tool; an empty kind counts as a link")
    @MainActor
    func linkToTool() {
        #expect(EnrichmentService.canApply(read("tool"), to: Item(title: "x", kind: ItemKind.link.rawValue)))
        #expect(EnrichmentService.canApply(read("tool"), to: Item(title: "x", kind: "")))
    }

    @Test("A product may migrate to a resource; the same kind reads again")
    @MainActor
    func productToResource() {
        #expect(EnrichmentService.canApply(read("resource"), to: Item(title: "x", kind: ItemKind.product.rawValue)))
        #expect(EnrichmentService.canApply(read("product"), to: Item(title: "x", kind: ItemKind.product.rawValue)))
        // Not a listed migration.
        #expect(!EnrichmentService.canApply(read("product"), to: Item(title: "x", kind: ItemKind.resource.rawValue)))
    }

    @Test("A curated kind (typeface) is never flipped to a tool")
    @MainActor
    func typefaceRefused() {
        #expect(!EnrichmentService.canApply(read("tool"), to: Item(title: "x", kind: ItemKind.typeface.rawValue)))
    }

    @Test("A link read, or a read without metadata, is never stored")
    @MainActor
    func linkReadRefused() {
        #expect(!EnrichmentService.canApply(read("link"), to: Item(title: "x", kind: ItemKind.link.rawValue)))
        #expect(!EnrichmentService.canApply(read("link"), to: Item(title: "x", kind: ItemKind.tool.rawValue)))
        #expect(!EnrichmentService.canApply(read("tool", metadata: nil), to: Item(title: "x", kind: ItemKind.link.rawValue)))
    }

    @Test("applyFreshRead turns a link into a tool and keeps a read value the refetch lost")
    @MainActor
    func applyToLink() async throws {
        let context = ModelContext(try StelloStore.makeInMemoryContainer())
        let item = Item(title: "Things", sourceURL: "https://culturedcode.com/things/", kind: ItemKind.link.rawValue)
        context.insert(item)

        await EnrichmentService.applyFreshRead(
            read("tool", metadata: toolMetadata(["name": "Things 3", "category": "Productivity"])), to: item, context: context
        )
        #expect(item.kind == ItemKind.tool.rawValue)
        #expect(item.toolMeta()?.name == "Things 3")

        // A later read that gets less (bot wall) keeps what the first read found.
        await EnrichmentService.applyFreshRead(read("tool", metadata: toolMetadata(["name": "Things 3"])), to: item, context: context)
        #expect(item.toolMeta()?.category == "Productivity")

        // A typeface never takes a tool read.
        let typeface = Item(title: "Inter", kind: ItemKind.typeface.rawValue)
        context.insert(typeface)
        await EnrichmentService.applyFreshRead(read("tool", metadata: toolMetadata(["name": "Inter"])), to: typeface, context: context)
        #expect(typeface.kind == ItemKind.typeface.rawValue)
        #expect(typeface.metadataJSON == nil)
    }
}
