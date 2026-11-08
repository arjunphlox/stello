import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - Fixtures

private let figmaPluginURL = "https://www.figma.com/community/plugin/735098390272716381/iconify"

// MARK: - Readers

@Suite("Resource readers")
struct ResourceReaderTests {

    @Test("Kind line variants")
    func kindLine() {
        var meta = ResourceMeta()
        #expect(meta.cardKindLine == nil)
        meta.subtype = "plugin"
        meta.worksWith = ["Figma"]
        #expect(meta.cardKindLine == "Figma plugin")
        meta.pricing = "free"
        #expect(meta.cardKindLine == "Figma plugin · Free")
        meta.pricing = nil
        meta.users = 12_400
        #expect(meta.cardKindLine == "Figma plugin · 12.4k users")
        meta.users = 1
        #expect(meta.cardKindLine == "Figma plugin · 1 user")

        var paid = ResourceMeta()
        paid.subtype = "template"
        paid.worksWith = ["Framer"]
        paid.pricing = "paid"
        #expect(paid.cardKindLine == "Framer template · Paid")
        paid.price = "49"
        paid.currency = "USD"
        paid.users = 900
        #expect(paid.cardKindLine == "Framer template · $49")

        var reading = ResourceMeta()
        reading.subtype = "reading list"
        #expect(reading.cardKindLine == "Reading list")

        var library = ResourceMeta()
        library.subtype = "library"
        #expect(library.cardKindLine == "Library")
    }

    @Test("A refetch that reads less never erases what capture read")
    func merge() {
        var previous = ResourceMeta()
        previous.name = "Iconify"
        previous.maker = ToolReader.makerRef("Vjacheslav")
        previous.users = 100
        previous.subtype = "plugin"
        previous.worksWith = ["Figma"]
        var fresh = ResourceMeta()
        fresh.likes = 5
        let merged = ResourceReader.merge(fresh: fresh, previous: previous)
        #expect(merged.name == "Iconify")
        #expect(merged.maker?.name == "Vjacheslav")
        #expect(merged.users == 100)
        #expect(merged.likes == 5)
        #expect(merged.subtype == "plugin")
        #expect(merged.worksWith == ["Figma"])
    }
}

// MARK: - Item level + refresh

@Suite("Resource items")
struct ResourceItemTests {

    @Test("Item kind line, typed panel, domain pill and search")
    @MainActor
    func itemLevel() {
        var meta = ResourceMeta()
        meta.subtype = "plugin"
        meta.worksWith = ["Figma"]
        meta.name = "Iconify"
        meta.maker = ToolReader.makerRef("Vjacheslav Trushkin")
        meta.pricing = "free"
        meta.canonicalURL = figmaPluginURL
        let item = Item(
            title: "Saved thing", sourceURL: "https://www.figma.com/community/plugin/735098390272716381",
            domain: "figma.com", kind: ItemKind.resource.rawValue
        )
        item.setMetadata(meta)

        #expect(item.resourceMeta() != nil)
        #expect(item.toolMeta() == nil)
        #expect(item.cardKindLine == "Figma plugin · Free")
        #expect(item.hasRichTypedPanel)
        #expect(item.displayLink == "figma.com")
        for query in ["iconify", "vjacheslav trushkin", "plugin", "figma"] {
            #expect(ItemFilter.apply([item], searchText: query, selectedTagNames: []).count == 1, "\(query)")
        }
    }

    @Test("Old JSON without the EntityRef url still decodes")
    @MainActor
    func entityRefBackCompat() throws {
        let json = #"{"name":"Studio","kind":"maker"}"#
        let ref = try JSONDecoder().decode(EntityRef.self, from: Data(json.utf8))
        #expect(ref.name == "Studio")
        #expect(ref.url == nil)
    }

}
