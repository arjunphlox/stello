import XCTest
@testable import Stello

/// Folder sources (folder engine plan 4b): header ids, skipped folders, the scan and
/// display paths. Web twin: test/folders.test.js.
final class FolderSourcesTests: XCTestCase {
    func testHeaderIDReadsOnlyTheHeader() {
        XCTAssertEqual(FolderScanner.headerID("---\nid: \"AB-1\"\ntitle: \"T\"\n---\nbody"), "ab-1")
        XCTAssertEqual(FolderScanner.headerID("---\r\ntitle: \"T\"\r\nid: \"b-2\"\r\n---\r\n"), "b-2")
        XCTAssertNil(FolderScanner.headerID("---\ntitle: \"T\"\n---\nid: \"body\"\n"))
        XCTAssertNil(FolderScanner.headerID("# note\nid: \"x\""))
        XCTAssertNil(FolderScanner.headerID(""))
    }

    func testSkipsMediaProjectsAndDotFolders() {
        for name in ["media", "projects", ".stello-v1", ".trash"] { XCTAssertTrue(FolderScanner.skipsDirectory(name), name) }
        for name in ["items", "people", "places", "2026"] { XCTAssertFalse(FolderScanner.skipsDirectory(name), name) }
    }

    func testScanIndexesItemFilesAndReusesUnchangedOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("items/2026/11"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("media/x"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".stello-v1"), withIntermediateDirectories: true)
        try "---\nid: \"a\"\n---\n".write(to: root.appendingPathComponent("items/2026/11/a.md"), atomically: true, encoding: .utf8)
        try "---\nid: \"m\"\n---\n".write(to: root.appendingPathComponent("media/x/m.md"), atomically: true, encoding: .utf8)
        try "---\nid: \"old\"\n---\n".write(to: root.appendingPathComponent(".stello-v1/o.md"), atomically: true, encoding: .utf8)
        try "plain note".write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        guard case .success(let first, _) = FolderScanner.scan(root: root, previous: [:]) else { return XCTFail("scan failed") }
        XCTAssertEqual(first.mapValues(\.id), ["items/2026/11/a.md": "a"])

        // An unchanged file keeps its old entry (not re-read).
        var seeded = first
        seeded["items/2026/11/a.md"]?.id = "cached"
        guard case .success(let second, _) = FolderScanner.scan(root: root, previous: seeded) else { return XCTFail("rescan failed") }
        XCTAssertEqual(second["items/2026/11/a.md"]?.id, "cached")

        let missing = FolderScanner.scan(root: root.appendingPathComponent("gone"), previous: [:])
        if case .success = missing { XCTFail("a missing folder should fail") }
    }

    func testDisplayPathNamesTheService() {
        XCTAssertEqual(FolderSources.displayPath(URL(fileURLWithPath: "/Users/a/Library/Mobile Documents/com~apple~CloudDocs/Stello")), "iCloud Drive/Stello")
        XCTAssertEqual(FolderSources.displayPath(URL(fileURLWithPath: "/Users/a/Library/CloudStorage/Dropbox/Stello")), "Dropbox/Stello")
        XCTAssertEqual(FolderSources.displayPath(URL(fileURLWithPath: "/Users/a/Library/CloudStorage/GoogleDrive-a@b.com/My Drive/Stello")), "Google Drive/My Drive/Stello")
    }
}
