import Foundation
import SwiftData
import os

/// Changes made in a folder show up in Stello (grid part 1, Nov 28 2026; web twin:
/// `readFiles` in folders.js). After a folder is read, its Stello files that changed since
/// the last read are read in full:
/// - A file edited outside Stello updates its item, only the fields the file changed
///   (`FolderReader.fileEdits`). The change then syncs like any edit.
/// - A Stello file whose item this Mac doesn't have adds it (`FolderReader.itemFromFile`),
///   with its pictures taken from the folder's media/.
/// - A file Stello wrote itself changes nothing. Only an item's main copy is read: a copy
///   in a later folder merges into it first (`mergeCopies`).
/// - On a folder's first read only new items are taken, never edits.
extension FolderSources {
    nonisolated struct ChangedRead: Sendable {
        var path: String
        var text: String
        var modified: Double
        var size: Int
    }

    func readChanged(_ id: UUID) {
        guard modelContainer != nil, let root = roots[id], let list = unread[id], !list.isEmpty else { return }
        if reading.contains(id) { readAgain.insert(id); return }
        reading.insert(id)
        let paths = Array(list.keys)
        Task.detached(priority: .utility) {
            let scoped = root.startAccessingSecurityScopedResource()
            defer { if scoped { root.stopAccessingSecurityScopedResource() } }
            var reads: [ChangedRead] = []
            for path in paths {
                guard let r = FolderFiles.read(root.appendingPathComponent(path)) else { continue }
                reads.append(ChangedRead(path: path, text: r.text, modified: r.modified, size: r.size))
            }
            let done = reads
            await MainActor.run { self.finishChanged(id, root: root, done, asked: paths) }
        }
    }

    private func finishChanged(_ id: UUID, root: URL, _ reads: [ChangedRead], asked: [String]) {
        defer {
            reading.remove(id)
            if readAgain.remove(id) != nil { readChanged(id) }
        }
        guard let container = modelContainer else { return }
        let db = ModelContext(container)
        let (entities, paths) = context(id)
        let files = indexes[id] ?? [:]
        var list = unread[id] ?? [:]
        var log = written
        var edited = 0, added = 0
        for read in reads {
            let takeEdits = list[read.path] == true
            guard let entry = files[read.path], FolderWriter.isLibraryID(entry.id),
                  let itemID = UUID(uuidString: entry.id),
                  let main = copies(for: itemID).first, main.folderID == id,
                  relativePath(main, root: root) == read.path else { continue }
            let key = itemID.uuidString.lowercased()
            var one = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            one.fetchLimit = 1
            let item = try? db.fetch(one).first
            if let item {
                let last = log[key]
                if let last, last.folderID == id, last.path == read.path, last.modified == read.modified, last.size == read.size { continue }
                guard takeEdits else { continue }
                let (wire, _) = Self.wire(item)
                if let fields = FolderReader.fileEdits(wire, text: read.text, path: read.path, entities: entities, paths: paths) {
                    var values = (FolderReader.plain(.object(fields)) as? [String: Any]) ?? [:]
                    values["id"] = key
                    guard let row = SyncWire.Row(values) else { continue }
                    SyncWire.apply(row, to: item, skipping: [])
                    if fields["images"] != nil { _ = SyncWire.applyImages(row, to: item) }
                    edited += 1
                    folderLog.info("read edit \(read.path, privacy: .public): \(fields.keys.joined(separator: ","), privacy: .public)")
                }
                // What the file holds is what Stello has now: don't write it back.
                log[key] = Written(folderID: id, path: read.path, modified: read.modified, size: read.size, extra: nil)
            } else if let made = FolderReader.itemFromFile(read.text, path: read.path, entities: entities, modified: read.modified) {
                var values = (FolderReader.plain(.object(made.fields)) as? [String: Any]) ?? [:]
                values["id"] = made.id
                guard let row = SyncWire.Row(values) else { continue }
                let (newItem, images) = SyncWire.makeItem(from: row, in: db, queueClassify: true)
                addPictures(images, of: read, root: root)
                _ = newItem
                log[key] = Written(folderID: id, path: read.path, modified: read.modified, size: read.size, extra: nil)
                added += 1
                folderLog.info("read new item \(read.path, privacy: .public)")
            }
        }
        for path in asked { list[path] = nil }
        written = log
        if edited + added > 0 {
            do { try db.save() } catch {
                folderLog.error("could not save folder changes: \(error.localizedDescription, privacy: .public)")
                return // the files stay to read next time
            }
            if added > 0 { NotificationCenter.default.post(name: SyncBridge.webSavesQueued, object: nil) }
        }
        unread[id] = list
        Self.saveUnread(id, list)
    }

    /// Pictures of an item new to this Mac: the bytes already copied into the folder's media/.
    private func addPictures(_ images: [(ItemImage, String)], of read: ChangedRead, root: URL) {
        guard !images.isEmpty, let copy = FolderWriter.readCopy(read.text) else { return }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let dir = (read.path as NSString).deletingLastPathComponent
        for (image, path) in images {
            guard let entry = (copy.header["images"]?.array ?? []).first(where: { $0["path"]?.string == path }),
                  let file = entry["file"]?.string else { continue }
            let url = root.appendingPathComponent(dir).appendingPathComponent(file).standardizedFileURL
            if let data = try? Data(contentsOf: url), !data.isEmpty { image.data = data }
        }
    }

    /// Writes items this Mac holds that no folder has into the new-saves folder (the check
    /// in Settings › Folders). Returns how many were written.
    @discardableResult
    func putBack(_ items: [Item]) -> Int {
        var wrote = 0
        for item in items where !holds(item.id) { if write(item) != nil { wrote += 1 } }
        return wrote
    }
}
