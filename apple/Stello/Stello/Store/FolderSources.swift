import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Folder sources (folder engine plan, section 4b; web twin: `folders.js`).
///
/// Phase 2, part 1: read-only. The person adds one or more Stello folders; each is
/// indexed (item id → file) so Settings can list the folders and every item panel can
/// show which folder holds it. Nothing here writes to a folder, and the library still
/// comes from SwiftData.
///
/// An item's folder comes from where its file sits; it is never written into the file.
/// The same item in two folders shows once and lists both (Arjun, Nov 28 2026).
/// Removing a folder only forgets it: the folder and its files are never touched.
///
/// The folder list is kept on this device for now; sharing it between Mac, iPad and
/// iPhone through iCloud (Arjun's pick) comes with the next part.
@Observable
@MainActor
final class FolderSources {
    static let shared = FolderSources()

    struct Folder: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var bookmark: Data
        var addedAt: Date
        var count: Int = 0
        var scannedAt: Date?
        /// Last resolved location, for display (e.g. "iCloud Drive/Stello").
        var displayPath: String = ""
    }

    enum Status: Equatable { case ready, reading, unreachable(String) }

    /// One place an item's file sits.
    struct Location: Equatable {
        let folderID: UUID
        let name: String
        let fileURL: URL
    }

    private(set) var folders: [Folder] = []
    private(set) var status: [UUID: Status] = [:]
    /// Item id (lowercased UUID string) → locations, oldest-added folder first.
    private(set) var lookup: [String: [Location]] = [:]

    /// Per folder: relative path → (id, modified, size). Persisted in Application Support.
    private var indexes: [UUID: [String: FolderIndexEntry]] = [:]
    private var roots: [UUID: URL] = [:]
    private static let defaultsKey = "stello.folderSources"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Folder].self, from: data) {
            folders = saved.sorted { $0.addedAt < $1.addedAt }
        }
        for folder in folders {
            indexes[folder.id] = Self.loadIndex(folder.id)
            if let url = resolve(folder) { roots[folder.id] = url; status[folder.id] = .ready }
            else { status[folder.id] = .unreachable("Not reachable. It may have moved: use Replace.") }
        }
        rebuildLookup()
    }

    // MARK: - Reads

    func locations(for itemID: UUID) -> [Location] {
        lookup[itemID.uuidString.lowercased()] ?? []
    }

    /// Re-reads every reachable folder (changed files only). Call on launch.
    func refreshAll() {
        for folder in folders { rescan(folder.id) }
    }

    // MARK: - Actions

    enum AddResult { case added, duplicate(String), covered(String), covers(String), failed }

    /// Adds a folder the person picked (from `.fileImporter`), then reads it.
    @discardableResult
    func add(url: URL) -> AddResult {
        if let clash = clash(with: url, except: nil) { return clash }
        guard let bookmark = Self.makeBookmark(url) else { return .failed }
        let folder = Folder(id: UUID(), name: url.lastPathComponent, bookmark: bookmark,
                            addedAt: Date(), displayPath: Self.displayPath(url))
        folders.append(folder)
        roots[folder.id] = resolve(folder) ?? url
        persist()
        rescan(folder.id)
        return .added
    }

    /// Points an entry at another folder (a moved or renamed copy), keeping its place.
    @discardableResult
    func replace(_ id: UUID, with url: URL) -> AddResult {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return .failed }
        if let clash = clash(with: url, except: id) { return clash }
        guard let bookmark = Self.makeBookmark(url) else { return .failed }
        folders[i].bookmark = bookmark
        folders[i].name = url.lastPathComponent
        folders[i].displayPath = Self.displayPath(url)
        roots[id] = resolve(folders[i]) ?? url
        persist()
        rescan(id)
        return .added
    }

    /// Forgets a folder. Its files stay exactly as they are.
    func remove(_ id: UUID) {
        folders.removeAll { $0.id == id }
        indexes[id] = nil
        roots[id] = nil
        status[id] = nil
        try? FileManager.default.removeItem(at: Self.indexURL(id))
        persist()
        rebuildLookup()
    }

    /// Shows the item's file: Finder on the Mac, the Files app on iPad and iPhone.
    func reveal(_ location: Location) {
        let root = roots[location.folderID]
        let scoped = root?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { root?.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([location.fileURL])
        #else
        let folder = location.fileURL.deletingLastPathComponent()
        var parts = URLComponents(url: folder, resolvingAgainstBaseURL: false)
        parts?.scheme = "shareddocuments"
        if let url = parts?.url { UIApplication.shared.open(url) }
        #endif
    }

    // MARK: - Scanning

    func rescan(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        if status[id] == .reading { return }
        guard let root = roots[id] ?? resolve(folder) else {
            status[id] = .unreachable("Not reachable. It may have moved: use Replace.")
            return
        }
        roots[id] = root
        status[id] = .reading
        let previous = indexes[id] ?? [:]
        Task.detached(priority: .utility) {
            let result = FolderScanner.scan(root: root, previous: previous)
            await MainActor.run { self.finishScan(id, result) }
        }
    }

    private func finishScan(_ id: UUID, _ result: FolderScanner.Result) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .failure(let message):
            status[id] = .unreachable(message)
        case .success(let files):
            indexes[id] = files
            folders[i].count = Set(files.values.map(\.id)).count
            folders[i].scannedAt = Date()
            status[id] = .ready
            Self.saveIndex(id, files)
            persist()
        }
        rebuildLookup()
    }

    private func rebuildLookup() {
        var out: [String: [Location]] = [:]
        for folder in folders.sorted(by: { $0.addedAt < $1.addedAt }) {
            guard let root = roots[folder.id], let files = indexes[folder.id] else { continue }
            for (path, entry) in files {
                var list = out[entry.id, default: []]
                if !list.contains(where: { $0.folderID == folder.id }) {
                    list.append(Location(folderID: folder.id, name: folder.name,
                                         fileURL: root.appendingPathComponent(path)))
                }
                out[entry.id] = list
            }
        }
        lookup = out
    }

    // MARK: - Helpers

    private func clash(with url: URL, except: UUID?) -> AddResult? {
        let new = url.standardizedFileURL.resolvingSymlinksInPath().path
        for folder in folders where folder.id != except {
            guard let root = roots[folder.id] else { continue }
            let old = root.standardizedFileURL.resolvingSymlinksInPath().path
            if old == new { return .duplicate(folder.name) }
            if new.hasPrefix(old + "/") { return .covered(folder.name) }
            if old.hasPrefix(new + "/") { return .covers(folder.name) }
        }
        return nil
    }

    private func resolve(_ folder: Folder) -> URL? {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: options,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        // Kept open while Stello runs, so panels can reveal files at any time.
        _ = url.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if stale, let fresh = Self.makeBookmark(url),
           let i = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[i].bookmark = fresh
            persist()
        }
        return url
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func makeBookmark(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        return try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// "iCloud Drive/Stello", "Dropbox/Stello", "Google Drive/…", else the path with ~.
    nonisolated static func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let icloud = "/Library/Mobile Documents/com~apple~CloudDocs"
        if let r = path.range(of: icloud) {
            let rest = path[r.upperBound...].drop(while: { $0 == "/" })
            return rest.isEmpty ? "iCloud Drive" : "iCloud Drive/" + rest
        }
        if let r = path.range(of: "/Library/CloudStorage/") {
            let parts = path[r.upperBound...].split(separator: "/", maxSplits: 1).map(String.init)
            let provider = parts.first ?? ""
            let name = provider.hasPrefix("GoogleDrive") ? "Google Drive"
                : provider.hasPrefix("Dropbox") ? "Dropbox"
                : provider.hasPrefix("OneDrive") ? "OneDrive"
                : provider
            return parts.count > 1 ? "\(name)/\(parts[1])" : name
        }
        #if os(macOS)
        // The real home, not the sandbox container's.
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let home = String(cString: dir)
            if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        }
        #endif
        return path
    }

    private static func indexURL(_ id: UUID) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolderIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).json")
    }

    private static func loadIndex(_ id: UUID) -> [String: FolderIndexEntry] {
        guard let data = try? Data(contentsOf: indexURL(id)),
              let index = try? JSONDecoder().decode([String: FolderIndexEntry].self, from: data) else { return [:] }
        return index
    }

    private static func saveIndex(_ id: UUID, _ index: [String: FolderIndexEntry]) {
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexURL(id), options: .atomic) }
    }
}

/// One indexed file: its item id and what it looked like when read.
struct FolderIndexEntry: Codable, Equatable, Sendable {
    var id: String
    var modified: Double
    var size: Int
}

/// Walks a folder for Stello .md files off the main thread, reading only the start of
/// files that changed since the last read. Pure apart from file reads (tests use a temp dir).
enum FolderScanner {
    enum Result: Sendable { case success([String: FolderIndexEntry]), failure(String) }

    /// Folders that hold no items (media/, projects/) and private dot-folders.
    static func skipsDirectory(_ name: String) -> Bool {
        name.isEmpty || name.hasPrefix(".") || name == "media" || name == "projects" || name == "node_modules"
    }

    /// Item id from the start of a Stello file: the `id:` line of its `---` header.
    static func headerID(_ text: String) -> String? {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return nil }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).dropFirst()
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { return nil }
            guard line.hasPrefix("id:") else { continue }
            var value = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), let data = value.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(String.self, from: data) {
                value = decoded
            }
            let id = value.trimmingCharacters(in: .whitespaces).lowercased()
            return id.isEmpty ? nil : id
        }
        return nil
    }

    static func scan(root: URL, previous: [String: FolderIndexEntry]) -> Result {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return .failure("Not reachable. It may have moved: use Replace.")
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else {
            return .failure("Not reachable right now.")
        }
        let base = root.standardizedFileURL.path
        var out: [String: FolderIndexEntry] = [:]
        for case let url as URL in walker {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skipsDirectory(name) { walker.skipDescendants() }
                continue
            }
            guard name.hasSuffix(".md"), !name.hasPrefix(".") else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            let path = String(full.dropFirst(base.count + 1))
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? 0
            if let old = previous[path], old.modified == modified, old.size == size {
                out[path] = old
                continue
            }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = (try? handle.read(upToCount: 4096)) ?? Data()
            try? handle.close()
            if let id = headerID(String(decoding: head, as: UTF8.self)) {
                out[path] = FolderIndexEntry(id: id, modified: modified, size: size)
            }
        }
        return .success(out)
    }
}
