import Foundation
import Observation
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Folder sources (folder engine plan, section 4b; web twin: `folders.js`).
///
/// The person adds one or more Stello folders; each is indexed (item id → file) so
/// Settings can list the folders and every item panel can show which folder holds it.
/// The library still comes from SwiftData; the folders are kept beside it (part 2):
/// - One folder takes new saves ("New saves go here"; the first added by default).
/// - A save or edit writes the item's v2 file (`FolderWriter`, the twin of the web's
///   src/lib/folder-write.js) to its main copy (oldest-added folder holding it), else to
///   the new-saves folder. `FolderWriteObserver` finds the changes in SwiftData history.
/// - A file changed outside Stello since Stello last wrote it is merged, never
///   overwritten; copies of one item in two folders merge the same way into the main copy.
/// - Delete moves every copy to its own folder's .trash/<day>/ (cleared after 30 days).
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
        /// Marked "New saves go here" (nil/false: not marked; the oldest-added then takes them).
        var takesSaves: Bool?
        /// The bookmark allows writing. Folders added in part 1 have read-only bookmarks
        /// and need picking once more ("Allow writing").
        var writable: Bool?
        /// Part 3, asked on Add: also turn the folder's other files (Markdown, text, CSV,
        /// bookmarks, link files) into items. nil/false: Stello items only.
        var ingest: Bool?
    }

    enum Status: Equatable { case ready, reading, unreachable(String) }

    /// One place an item's file sits. `found`: a file of the person's own that lists the
    /// item's link (part 3); Stello never writes or moves those.
    struct Location: Equatable {
        let folderID: UUID
        let name: String
        let fileURL: URL
        var found = false
    }

    var folders: [Folder] = []
    private(set) var status: [UUID: Status] = [:]
    /// Item id (lowercased UUID string) → locations, oldest-added folder first.
    private(set) var lookup: [String: [Location]] = [:]

    /// Per folder: relative path → (id, modified, size). Persisted in Application Support.
    var indexes: [UUID: [String: FolderIndexEntry]] = [:]
    /// While a folder is being read: paths Stello wrote (entry) or moved away (nil) meanwhile.
    var changedDuringScan: [UUID: [String: FolderIndexEntry?]] = [:]
    /// Part 3, per folder that reads its other files: relative path → the links it lists.
    var found: [UUID: [String: FoundEntry]] = [:]
    /// Folders whose files are being turned into items right now, and ones to read again after.
    var ingesting = Set<UUID>()
    var ingestAgain = Set<UUID>()
    /// Set at launch (FolderWriteObserver.start): where items made from files are saved.
    @ObservationIgnored var modelContainer: ModelContainer?
    private(set) var roots: [UUID: URL] = [:]
    private static let defaultsKey = "stello.folderSources"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Folder].self, from: data) {
            folders = saved.sorted { $0.addedAt < $1.addedAt }
        }
        for folder in folders {
            indexes[folder.id] = Self.loadIndex(folder.id)
            if folder.ingest == true { found[folder.id] = Self.loadFound(folder.id) }
            if let url = resolve(folder) { roots[folder.id] = url; status[folder.id] = .ready }
            else { status[folder.id] = .unreachable("Not reachable. It may have moved: use Replace.") }
        }
        rebuildLookup()
    }

    // MARK: - Reads

    func locations(for itemID: UUID) -> [Location] {
        lookup[itemID.uuidString.lowercased()] ?? []
    }

    /// Only the item's Stello files: the person's own files are never written or moved.
    func copies(for itemID: UUID) -> [Location] {
        locations(for: itemID).filter { !$0.found }
    }

    /// The folder that takes new saves: the one marked, else the oldest-added.
    var savesFolderID: UUID? {
        let ordered = folders.sorted { $0.addedAt < $1.addedAt }
        return (ordered.first { $0.takesSaves == true } ?? ordered.first)?.id
    }

    func isWritable(_ id: UUID) -> Bool {
        guard let f = folders.first(where: { $0.id == id }) else { return false }
        guard f.writable == true, roots[id] != nil else { return false }
        if case .unreachable = status[id] { return false }
        return true
    }

    func setSavesFolder(_ id: UUID) {
        for i in folders.indices { folders[i].takesSaves = folders[i].id == id }
        persist()
    }

    /// Re-reads every reachable folder (changed files only). Call on launch.
    func refreshAll() {
        for folder in folders { rescan(folder.id) }
    }

    // MARK: - Actions

    enum AddResult { case added, duplicate(String), covered(String), covers(String), failed }

    /// Whether a picked folder can be added (checked before asking what to read from it).
    func check(url: URL) -> AddResult? { clash(with: url, except: nil) }

    /// Adds a folder the person picked (from `.fileImporter`), then reads it. `ingest`: the
    /// answer to "Stello items only, or also its other files?".
    @discardableResult
    func add(url: URL, ingest: Bool = false) -> AddResult {
        if let clash = clash(with: url, except: nil) { return clash }
        guard let bookmark = Self.makeBookmark(url) else { return .failed }
        let folder = Folder(id: UUID(), name: url.lastPathComponent, bookmark: bookmark,
                            addedAt: Date(), displayPath: Self.displayPath(url),
                            takesSaves: folders.isEmpty ? true : nil, writable: true, ingest: ingest ? true : nil)
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
        folders[i].writable = true
        roots[id] = resolve(folders[i]) ?? url
        persist()
        rescan(id)
        return .added
    }

    /// Forgets a folder. Its files stay exactly as they are.
    func remove(_ id: UUID) {
        let wasSaves = savesFolderID == id
        folders.removeAll { $0.id == id }
        // The next folder in the list takes new saves.
        if wasSaves, let next = folders.sorted(by: { $0.addedAt < $1.addedAt }).first?.id {
            for i in folders.indices { folders[i].takesSaves = folders[i].id == next }
        }
        indexes[id] = nil
        found[id] = nil
        roots[id] = nil
        status[id] = nil
        try? FileManager.default.removeItem(at: Self.indexURL(id))
        try? FileManager.default.removeItem(at: Self.foundURL(id))
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
        changedDuringScan[id] = [:]
        let previous = indexes[id] ?? [:]
        let ingest = folder.ingest == true
        let previousFound = found[id] ?? [:]
        Task.detached(priority: .utility) {
            let (result, seen) = FolderScanner.scan(root: root, previous: previous, previousFound: previousFound, ingest: ingest)
            await MainActor.run { self.finishScan(id, result, found: seen) }
        }
    }

    private func finishScan(_ id: UUID, _ result: FolderScanner.Result, found seen: [String: FoundEntry] = [:]) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .failure(let message):
            status[id] = .unreachable(message)
        case .success(var files, let changed):
            // Writes and .trash moves Stello made while the read ran win over what it saw.
            for (path, entry) in changedDuringScan[id] ?? [:] { files[path] = entry }
            changedDuringScan[id] = nil
            indexes[id] = files
            if folders[i].ingest == true { found[id] = seen; Self.saveFound(id, seen) }
            folders[i].count = Self.countItems(files, found[id])
            folders[i].scannedAt = Date()
            status[id] = .ready
            Self.saveIndex(id, files)
            persist()
            rebuildLookup()
            if isWritable(id) {
                if !changed.isEmpty { mergeCopies(changed, changedIn: id) }
                if let root = roots[id] { Task.detached(priority: .utility) { FolderFiles.clearTrash(root: root) } }
            }
            if folders[i].ingest == true { ingest(id) }
            return
        }
        rebuildLookup()
    }

    /// Library items a folder holds: people and places that are only files don't count.
    /// `found`: links the person's own files list (part 3).
    nonisolated static func countItems(_ files: [String: FolderIndexEntry], _ found: [String: FoundEntry]? = nil) -> Int {
        var ids = Set(files.values.map(\.id).filter(FolderWriter.isLibraryID))
        for entry in (found ?? [:]).values { for l in entry.links where FolderWriter.isLibraryID(l.id) { ids.insert(l.id) } }
        return ids.count
    }

    func rebuildLookup() {
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
        for folder in folders.sorted(by: { $0.addedAt < $1.addedAt }) {
            guard let root = roots[folder.id], let seen = found[folder.id] else { continue }
            for (path, entry) in seen {
                for l in entry.links {
                    var list = out[l.id, default: []]
                    if !list.contains(where: { $0.folderID == folder.id && $0.found }) {
                        list.append(Location(folderID: folder.id, name: folder.name, fileURL: root.appendingPathComponent(path), found: true))
                    }
                    out[l.id] = list
                }
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

    func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func makeBookmark(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        // Read and write (part 2): Stello writes saves, edits and .trash moves.
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
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

    static func saveIndex(_ id: UUID, _ index: [String: FolderIndexEntry]) {
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexURL(id), options: .atomic) }
    }

    static func foundURL(_ id: UUID) -> URL {
        indexURL(id).deletingLastPathComponent().appendingPathComponent("\(id.uuidString).found.json")
    }

    static func loadFound(_ id: UUID) -> [String: FoundEntry] {
        guard let data = try? Data(contentsOf: foundURL(id)),
              let found = try? JSONDecoder().decode([String: FoundEntry].self, from: data) else { return [:] }
        return found
    }

    static func saveFound(_ id: UUID, _ found: [String: FoundEntry]) {
        if let data = try? JSONEncoder().encode(found) { try? data.write(to: foundURL(id), options: .atomic) }
    }
}

/// One of the person's own files a folder reads links from (part 3): what it looked like
/// when read, and the items its links became. `stale`: changed since, to be read again.
nonisolated struct FoundEntry: Codable, Equatable, Sendable {
    var modified: Double
    var size: Int
    var links: [FoundLink]
    var stale: Bool?

    struct FoundLink: Codable, Equatable, Sendable {
        var key: String
        var id: String
    }
}

/// One indexed file: its item id and what it looked like when read.
nonisolated struct FolderIndexEntry: Codable, Equatable, Sendable {
    var id: String
    var modified: Double
    var size: Int
    /// people/ and places/ files: what matching a name needs.
    var ent: EntityInfo?

    struct EntityInfo: Codable, Equatable, Sendable {
        var name: String
        var kind: String?
        var aliases: [String]
    }
}

/// Walks a folder for Stello .md files off the main thread, reading only the start of
/// files that changed since the last read. Pure apart from file reads (tests use a temp dir).
nonisolated enum FolderScanner {
    /// success: the index, plus the ids whose files changed since the previous read.
    enum Result: Sendable { case success([String: FolderIndexEntry], Set<String>), failure(String) }

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

    /// name / kind / aliases of a people/ or places/ header (one JSON value per line).
    static func headerEntity(_ text: String) -> FolderIndexEntry.EntityInfo {
        var name = "", kind: String?, aliases: [String] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).dropFirst() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { break }
            func value(_ key: String) -> FolderWriter.JSON? {
                guard line.hasPrefix(key + ":") else { return nil }
                return FolderWriter.parse(String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces))
            }
            if let v = value("name")?.string { name = v }
            if let v = value("kind")?.string { kind = v }
            if let v = value("aliases")?.array { aliases = v.compactMap(\.string) }
        }
        return .init(name: name, kind: kind, aliases: aliases)
    }

    static func scan(root: URL, previous: [String: FolderIndexEntry]) -> Result {
        scan(root: root, previous: previous, previousFound: [:], ingest: false).0
    }

    /// The Stello files, plus (when `ingest`) the person's own files that can hold links
    /// (part 3): unchanged ones keep their links, changed ones come back `stale` for
    /// `FolderSources.ingest` to read in full.
    static func scan(root: URL, previous: [String: FolderIndexEntry], previousFound: [String: FoundEntry],
                     ingest: Bool) -> (Result, [String: FoundEntry]) {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return (.failure("Not reachable. It may have moved: use Replace."), [:])
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else {
            return (.failure("Not reachable right now."), [:])
        }
        let base = root.standardizedFileURL.path
        var out: [String: FolderIndexEntry] = [:]
        var found: [String: FoundEntry] = [:]
        var changed = Set<String>()
        func maybeFound(_ path: String, _ modified: Double, _ size: Int) {
            guard ingest, size <= FolderIngest.maxFileBytes else { return }
            if let old = previousFound[path], old.modified == modified, old.size == size, old.stale != true { found[path] = old; return }
            found[path] = FoundEntry(modified: modified, size: size, links: previousFound[path]?.links ?? [], stale: true)
        }
        for case let url as URL in walker {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skipsDirectory(name) { walker.skipDescendants() }
                continue
            }
            let isMD = name.hasSuffix(".md") && !name.hasPrefix(".")
            guard isMD || (ingest && FolderIngest.ingestType(name) != nil) else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            let path = String(full.dropFirst(base.count + 1))
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? 0
            guard isMD else { maybeFound(path, modified, size); continue }
            let isEntity = path.hasPrefix("people/") || path.hasPrefix("places/")
            if let old = previous[path], old.modified == modified, old.size == size, !(isEntity && old.ent == nil) {
                out[path] = old
                continue
            }
            if ingest, let kept = previousFound[path], kept.modified == modified, kept.size == size, kept.stale != true {
                found[path] = kept
                continue
            }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = (try? handle.read(upToCount: 4096)) ?? Data()
            try? handle.close()
            let text = String(decoding: head, as: UTF8.self)
            if let id = headerID(text) {
                var entry = FolderIndexEntry(id: id, modified: modified, size: size)
                if isEntity { entry.ent = headerEntity(text) }
                out[path] = entry
                changed.insert(id)
            } else {
                maybeFound(path, modified, size)
            }
        }
        return (.success(out, changed), found)
    }
}
