import Testing
import Foundation
@testable import Stello

@Suite("DropImportValidation")
struct DropImportValidationTests {

    @Test("classifies accepted image extensions")
    func imageExtensions() {
        for ext in ["png", "jpg", "jpeg", "heic", "webp", "gif"] {
            let url = URL(fileURLWithPath: "/tmp/test.\(ext)")
            #expect(DropImportValidation.classify(url: url) == .image)
        }
    }

    @Test("classifies accepted video extensions")
    func videoExtensions() {
        for ext in ["mp4", "mov"] {
            let url = URL(fileURLWithPath: "/tmp/clip.\(ext)")
            #expect(DropImportValidation.classify(url: url) == .video)
        }
    }

    @Test("classifies markdown and plain text")
    func textExtensions() {
        #expect(DropImportValidation.classify(url: URL(fileURLWithPath: "/tmp/note.md")) == .markdown)
        #expect(DropImportValidation.classify(url: URL(fileURLWithPath: "/tmp/note.txt")) == .plainText)
    }

    @Test("rejects unsupported extensions")
    func unsupported() {
        #expect(DropImportValidation.classify(url: URL(fileURLWithPath: "/tmp/file.pdf")) == nil)
        #expect(DropImportValidation.classify(url: URL(fileURLWithPath: "/tmp/file.zip")) == nil)
    }

    @Test("video over 50 MB is rejected")
    func videoSizeLimit() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("oversize-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let payload = Data(repeating: 0, count: DropImportValidation.maxVideoBytes + 1)
        try payload.write(to: url)
        let result = DropImportValidation.validateFile(at: url, kind: .video)
        if case .failure(.videoTooLarge) = result {} else {
            Issue.record("Expected videoTooLarge rejection")
        }
    }

    @Test("text over 5000 characters is rejected")
    func textCharLimit() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("long-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = String(repeating: "a", count: DropImportValidation.maxTextCharacters + 1)
        try Data(text.utf8).write(to: url)
        let result = DropImportValidation.validateFile(at: url, kind: .plainText)
        if case .failure(.textTooLong) = result {} else {
            Issue.record("Expected textTooLong rejection")
        }
    }

    @Test("text within limit passes validation")
    func textWithinLimit() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ok-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = String(repeating: "b", count: 100)
        try Data(text.utf8).write(to: url)
        let result = DropImportValidation.validateFile(at: url, kind: .markdown)
        if case .success = result {} else {
            Issue.record("Expected success for text within limit")
        }
    }

    @Test("Item.displayLink shows local when sourceURL is nil")
    func displayLinkLocal() {
        let local = Item(title: "Dropped", sourceURL: nil)
        #expect(local.displayLink == "local")
    }

    @Test("Item.displayLink shows domain when URL exists")
    func displayLinkDomain() {
        let linked = Item(title: "Link", sourceURL: "https://figma.com/x", domain: "figma.com")
        #expect(linked.displayLink == "figma.com")
    }
}
