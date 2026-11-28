import Foundation
import SwiftData
import os

/// Folder ingest (folder engine plan 4b, part 3; web twin: `ingestFolder` in folders.js).
/// A folder added with "Also its other files" turns every link in its Markdown, text, CSV,
/// bookmark and link files into an item, kept up to date as the files change:
/// - A link the library already holds isn't added twice. The source files stay in the
///   folder but don't show in Stello.
/// - A new link becomes a plain link (no AI, no page read on this path) with the same id
///   on every device, so the web and the Mac never make it twice. The background pass sorts it.
/// - A link that leaves a file keeps its item: nothing is lost.
/// - A link the file listed before whose item was deleted in Stello stays deleted.
/// Stello never writes or moves the person's own files; new items are written as Stello
/// files by `FolderWriteObserver` into the folder they came from (`origin`), with their pictures.
extension FolderSources {
    /// One changed file, read and parsed off the main thread.
    nonisolated struct IngestRead: Sendable {
        var path: String
        var modified: Double
        var size: Int
        var links: [FolderIngest.Link]
        /// A Markdown note with writing of its own: it becomes an item itself.
        var note: FolderIngest.NoteItem?
    }

    /// Reads the folder's changed files and adds items for links the library doesn't hold.
    func ingest(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }), folder.ingest == true,
              let root = roots[id], modelContainer != nil else { return }
        if ingesting.contains(id) { ingestAgain.insert(id); return }
        let stale = (found[id] ?? [:]).filter { $0.value.stale == true }.map(\.key)
        guard !stale.isEmpty else { return }
        ingesting.insert(id)
        Task.detached(priority: .utility) {
            let reads = Self.readFiles(root: root, paths: stale)
            await MainActor.run { self.finishIngest(id, reads) }
        }
    }

    /// Every folder that reads its other files (at launch, once the library is open).
    func ingestAll() {
        for folder in folders where folder.ingest == true { ingest(folder.id) }
    }

    /// Turn reading the folder's other files on or off. Off keeps the items already made.
    func setIngest(_ id: UUID, _ on: Bool) {
        guard let i = folders.firstIndex(where: { $0.id == id }), (folders[i].ingest == true) != on else { return }
        folders[i].ingest = on ? true : nil
        if !on {
            found[id] = nil
            try? FileManager.default.removeItem(at: Self.foundURL(id))
            folders[i].count = Self.countItems(indexes[id] ?? [:])
        }
        persist()
        rebuildLookup()
        if on { rescan(id) }
    }

    nonisolated static func readFiles(root: URL, paths: [String]) -> [IngestRead] {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        var out: [IngestRead] = []
        for path in paths {
            let url = root.appendingPathComponent(path)
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let size = values.fileSize, size <= FolderIngest.maxFileBytes,
                  let data = try? Data(contentsOf: url) else { continue }
            let modified = values.contentModificationDate ?? .now
            let text = String(decoding: data, as: UTF8.self)
            let note = FolderIngest.isWrittenNote(path: path, text: text)
                ? FolderIngest.noteItem(path: path, text: text, id: FolderIngest.noteItemID(path), modified: modified, now: FolderIngest.iso(.now))
                : nil
            out.append(IngestRead(path: path, modified: modified.timeIntervalSince1970, size: size,
                                  links: FolderIngest.readLinks(path: path, text: text, modified: modified), note: note))
        }
        return out
    }

    private func finishIngest(_ id: UUID, _ reads: [IngestRead]) {
        defer {
            ingesting.remove(id)
            if ingestAgain.remove(id) != nil { ingest(id) }
        }
        guard let container = modelContainer, var seen = found[id] else { return }
        let context = ModelContext(container)
        var byKey: [String: String] = [:]
        var ids = Set<String>()
        var descriptor = FetchDescriptor<Item>()
        descriptor.propertiesToFetch = [\.id, \.sourceURL]
        for item in (try? context.fetch(descriptor)) ?? [] {
            let itemID = item.id.uuidString.lowercased()
            ids.insert(itemID)
            if let url = item.sourceURL, !url.isEmpty { byKey[FolderIngest.normaliseURL(url)] = itemID }
        }
        let now = FolderIngest.iso(.now)
        var fresh = Set<String>()
        var made = 0
        var notes: [(read: IngestRead, note: FolderIngest.NoteItem)] = []
        for read in reads {
            let wasNote = seen[read.path]?.note
            // A note with real writing of its own is an item itself (its links still are too).
            if wasNote == nil, let note = read.note {
                let key = note.id.uuidString.lowercased()
                notes.append((read, note))
                if !ids.contains(key), !fresh.contains(key) {
                    fresh.insert(key)
                    origin[key] = id
                    insert(note, into: context)
                    made += 1
                }
            }
            let before = Set((seen[read.path]?.links ?? []).map(\.key))
            var links: [FoundEntry.FoundLink] = []
            for link in read.links {
                var itemID = byKey[link.key]
                if itemID == nil {
                    let uuid = FolderIngest.linkItemID(link.key)
                    let key = uuid.uuidString.lowercased()
                    itemID = key
                    if !ids.contains(key), !before.contains(link.key), !fresh.contains(key) {
                        fresh.insert(key)
                        origin[key] = id
                        insert(FolderIngest.newItem(link, id: uuid, now: now), into: context)
                        made += 1
                    }
                }
                links.append(.init(key: link.key, id: itemID!))
            }
            seen[read.path] = FoundEntry(modified: read.modified, size: read.size, links: links, stale: nil, note: wasNote)
        }
        if made > 0 {
            do { try context.save() } catch {
                folderLog.error("folder files: could not save \(made) new items: \(error.localizedDescription, privacy: .public)")
                return // the files stay stale and are read again next time
            }
            folderLog.info("folder files: \(made) new items")
        }
        // Written notes get Stello's details at their top, in the same file.
        for (read, note) in notes {
            let noteID = note.id
            var one = FetchDescriptor<Item>(predicate: #Predicate { $0.id == noteID })
            one.fetchLimit = 1
            guard let item = try? context.fetch(one).first else { continue }
            if writeNote(item, folderID: id, path: read.path, extra: note.extra, text: note.text, modified: read.modified, size: read.size) {
                seen[read.path]?.note = noteID.uuidString.lowercased()
            }
        }
        if made > 0 {
            // Plain links: let the background pass sort them now, as for new web saves.
            NotificationCenter.default.post(name: SyncBridge.webSavesQueued, object: nil)
        }
        found[id] = seen
        Self.saveFound(id, seen)
        if let i = folders.firstIndex(where: { $0.id == id }) { folders[i].count = Self.countItems(indexes[id] ?? [:], seen) }
        persist()
        rebuildLookup()
    }

    private func insert(_ n: FolderIngest.NoteItem, into context: ModelContext) {
        let parse = ISO8601DateFormatter()
        parse.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let item = Item(id: n.id, slug: n.slug, title: n.title, sourceURL: nil, domain: nil,
                        summary: nil, bodyMarkdown: n.body, status: "active", needsReview: false,
                        addedAt: parse.date(from: n.addedAt) ?? .now,
                        enrichmentStatus: "text_done", kind: "")
        context.insert(item)
        item.tags = [ItemTag(name: "note", category: "format", weight: FolderIngest.noteTagWeight)]
            + n.subjects.map { ItemTag(name: $0, category: "subject", weight: FolderIngest.noteTagWeight) }
    }

    private func insert(_ n: FolderIngest.NewItem, into context: ModelContext) {
        let parse = ISO8601DateFormatter()
        parse.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let item = Item(id: n.id, slug: n.slug, title: n.title, sourceURL: n.sourceURL, domain: n.domain,
                        summary: n.summary, bodyMarkdown: n.body, status: "active", needsReview: false,
                        addedAt: parse.date(from: n.addedAt) ?? .now,
                        enrichmentStatus: WorkerSorter.unsortedStatus, kind: "link")
        context.insert(item)
        item.tags = n.tags.map { ItemTag(name: $0, category: "subject", weight: FolderIngest.tagWeight) }
    }
}
