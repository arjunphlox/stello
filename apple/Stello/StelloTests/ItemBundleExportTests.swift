import Foundation
import Testing
@testable import Stello

@Suite("Item bundle export")
struct ItemBundleExportTests {

    @Test("Bundle zip is non-empty and contains markdown entry")
    func bundleZipContainsMarkdown() throws {
        let cover = try #require(SampleCoverGenerator.cover(seed: 7))
        let image = ItemImage(data: cover.data, isPrimary: true, width: cover.width, height: cover.height)
        let snippets = [
            Snippet(text: "First note", source: "manual"),
            Snippet(text: "Second note", source: "ai"),
        ]
        let markdown = "# Sample\n\n- **Domain:** figma.com\n"

        let zip = try ItemBundleExporter.createBundleZip(
            exportName: "sample-item",
            markdown: markdown,
            images: [image],
            snippets: snippets,
            videoAttachments: []
        )

        #expect(!zip.isEmpty)
        #expect(zip.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        let mdName = Data("sample-item.md".utf8)
        #expect(zip.range(of: mdName) != nil)
    }

    @Test("Image extension detection")
    func imageExtensions() {
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(ItemBundleExporter.imageExtension(for: pngHeader) == "png")
    }
}
