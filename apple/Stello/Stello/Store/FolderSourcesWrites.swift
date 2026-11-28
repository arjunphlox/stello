import Foundation
import SwiftData
import os

let folderLog = Logger(subsystem: "com.arjunphlox.Stello", category: "folders")

/// Folder writes (folder engine plan 4b, part 2; web twin: the writing half of `folders.js`).
/// Saves and edits write the item's v2 file, deletes move copies to `.trash/<day>/`, and
/// copies of one item in two folders merge into the main copy. `FolderWriteObserver`
/// calls in here when SwiftData history shows a change.
extension FolderSources {
    /// What Stello last wrote for an item, so it can tell its own file from one changed
    /// outside Stello (that one is merged, never overwritten).
    struct Written: Codable, Equatable {
        var folderID: UUID
        var path: String
        var modified: Double
        var size: Int
        /// Notes a merge brought in from outside Stello (SwiftData doesn't hold them), kept
        /// on later writes.
        var extra: String?
    }

    private static var writtenURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolderIndex", isDirectory: true)
            .appendingPathComponent("written.json")
    }
    private static var writtenCache: [String: Written]?
    private var written: [String: Written] {
        get {
            if let c = Self.writtenCache { return c }
            let loaded = (try? Data(contentsOf: Self.writtenURL)).flatMap { try? JSONDecoder().decode([String: Written].self, from: $0) } ?? [:]
            Self.writtenCache = loaded
            return loaded
        }
        set {
            Self.writtenCache = newValue
            try? FileManager.default.createDirectory(at: Self.writtenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(newValue) { try? data.write(to: Self.writtenURL, options: .atomic) }
        }
    }

    var canWrite: Bool { folders.contains { isWritable($0.id) } }

    /// Entities (people/places files) and used paths of one folder, from its index.
    private func context(_ folderID: UUID) -> (entities: [FolderWriter.Entity], paths: Set<String>) {
        var entities: [FolderWriter.Entity] = []
        var paths = Set<String>()
        for (path, e) in indexes[folderID] ?? [:] {
            paths.insert(path.lowercased())
            if let ent = e.ent {
                entities.append(.init(id: e.id, name: ent.name.isEmpty ? e.id : ent.name, kind: ent.kind,
                                      aliases: ent.aliases, isPlace: path.hasPrefix("places/"), path: path))
            }
        }
        return (entities, paths)
    }

    private func noteIndexed(_ folderID: UUID, _ path: String, id: String, _ stat: FolderFiles.Stat, ent: FolderIndexEntry.EntityInfo? = nil) {
        var files = indexes[folderID] ?? [:]
        var entry = FolderIndexEntry(id: id, modified: stat.modified, size: stat.size)
        entry.ent = ent ?? files[path]?.ent
        files[path] = entry
        indexes[folderID] = files
        if changedDuringScan[folderID] != nil { changedDuringScan[folderID]?[path] = .some(entry) }
    }

    private func noteRemoved(_ folderID: UUID, _ path: String) {
        indexes[folderID]?[path] = nil
        if changedDuringScan[folderID] != nil { changedDuringScan[folderID]?[path] = .some(nil) }
    }

    /// The item's main copy: the oldest-added writable folder holding it, else the file
    /// Stello last wrote for it (the index may not list a file written seconds ago).
    private func mainCopy(_ itemID: UUID) -> Location? {
        if let loc = locations(for: itemID).first(where: { isWritable($0.folderID) }) { return loc }
        guard let w = written[itemID.uuidString.lowercased()], isWritable(w.folderID), let root = roots[w.folderID],
              let folder = folders.first(where: { $0.id == w.folderID }) else { return nil }
        let url = root.appendingPathComponent(w.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Location(folderID: w.folderID, name: folder.name, fileURL: url)
    }

    private func finishWrites(_ folderIDs: Set<UUID>) {
        for id in folderIDs {
            guard let i = folders.firstIndex(where: { $0.id == id }), let files = indexes[id] else { continue }
            folders[i].count = Self.countItems(files)
            Self.saveIndex(id, files)
        }
        persist()
        rebuildLookup()
    }

    /// Writes one item to its main copy, or to the new-saves folder when no folder holds it.
    /// Returns the folder-relative path written (or already up to date), nil when nothing could be.
    @discardableResult
    func write(_ item: Item) -> String? {
        let main = mainCopy(item.id)
        guard let folderID = main?.folderID ?? savesFolderID.flatMap({ isWritable($0) ? $0 : nil }) ?? folders.first(where: { isWritable($0.id) })?.id,
              let root = roots[folderID] else { return nil }
        let itemID = item.id.uuidString.lowercased()
        var (entities, paths) = context(folderID)
        var existing: (path: String, copy: FolderWriter.Copy)?
        var current: FolderFiles.Read?
        if let main, let rel = relativePath(main, root: root) {
            current = FolderFiles.read(root.appendingPathComponent(rel))
            if let current, let copy = FolderWriter.readCopy(current.text) { existing = (rel, copy) }
        }
        let (wire, localExts) = Self.wire(item)
        let out = FolderWriter.itemFile(wire, entities: entities, paths: &paths, existing: existing, localExts: localExts)
        var text = out.text
        var extra: String?
        if let existing, let current {
            let last = written[itemID]
            let ours = last?.folderID == folderID && last?.path == existing.path && last?.modified == current.modified && last?.size == current.size
            if !ours {
                let mine = FolderWriter.Copy(header: out.header, body: out.body, modified: item.updatedAt.timeIntervalSince1970)
                var other = existing.copy
                other.modified = current.modified
                let merged = FolderWriter.merge(mine, other)
                text = FolderWriter.copyText(merged)
                let body = FolderWriter.trim(out.body)
                if merged.body != body {
                    extra = !body.isEmpty && merged.body.hasPrefix(body + "\n\n") ? String(merged.body.dropFirst(body.count + 2)) : merged.body
                }
            } else if let kept = last?.extra {
                extra = kept
                text = FolderWriter.copyText(.init(header: out.header, body: FolderWriter.mergeNotes(FolderWriter.trim(out.body), kept)))
            }
            if text == current.text {
                written[itemID] = Written(folderID: folderID, path: existing.path, modified: current.modified, size: current.size, extra: extra)
                return existing.path
            }
        }
        do {
            for e in out.entities where !FileManager.default.fileExists(atPath: root.appendingPathComponent(e.path).path) {
                let stat = try FolderFiles.write(Data(e.text.utf8), to: root.appendingPathComponent(e.path))
                noteIndexed(folderID, e.path, id: e.entity.id, stat, ent: .init(name: e.entity.name, kind: e.entity.kind, aliases: e.entity.aliases))
            }
            copyMedia(item, out.media, root: root)
            let stat = try FolderFiles.write(Data(text.utf8), to: root.appendingPathComponent(out.path))
            noteIndexed(folderID, out.path, id: itemID, stat)
            written[itemID] = Written(folderID: folderID, path: out.path, modified: stat.modified, size: stat.size, extra: extra)
            finishWrites([folderID])
            folderLog.info("wrote \(out.path, privacy: .public) (\(existing == nil ? "new" : "update", privacy: .public))")
            return out.path
        } catch {
            folderLog.error("write failed \(itemID, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Copies an item's images into media/: bytes this device holds, else the web copy.
    private func copyMedia(_ item: Item, _ media: [FolderWriter.MediaCopy], root: URL) {
        guard !media.isEmpty else { return }
        let images = Self.orderedImages(item)
        for m in media {
            let dest = root.appendingPathComponent(m.file)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            if m.index < images.count, let data = images[m.index].data {
                _ = try? FolderFiles.write(data, to: dest)
            } else if !m.remote.isEmpty {
                let url = m.remote.hasPrefix("http") ? URL(string: m.remote) : URL(string: m.remote, relativeTo: SyncAPI.baseURL)
                guard let url else { continue }
                Task.detached(priority: .utility) {
                    guard let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return }
                    _ = try? FolderFiles.write(data, to: dest)
                }
            }
        }
    }

    /// Deleted in Stello: every copy goes to its own folder's .trash/<day>/, with its images.
    func trash(itemID: UUID) {
        let id = itemID.uuidString.lowercased()
        var touched = Set<UUID>()
        var locs = locations(for: itemID).filter { isWritable($0.folderID) }
        if locs.isEmpty, let main = mainCopy(itemID) { locs = [main] }
        if locs.isEmpty { folderLog.info("delete \(id, privacy: .public): no copy in a writable folder") }
        for loc in locs {
            guard let root = roots[loc.folderID], let rel = relativePath(loc, root: root) else { continue }
            let file = root.appendingPathComponent(rel)
            let media = FolderFiles.read(file).flatMap { FolderWriter.readCopy($0.text) }.map { Self.mediaFiles(of: $0, at: rel) } ?? []
            do {
                try FolderFiles.move(file, to: root.appendingPathComponent(FolderWriter.trashPath(rel)))
                for m in media { try? FolderFiles.move(root.appendingPathComponent(m), to: root.appendingPathComponent(FolderWriter.trashPath(m))) }
                noteRemoved(loc.folderID, rel)
                for m in media { noteRemoved(loc.folderID, m) }
                touched.insert(loc.folderID)
                folderLog.info("moved \(rel, privacy: .public) to .trash")
            } catch {
                folderLog.error("move to .trash failed \(rel, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        var w = written; w[id] = nil; written = w
        if !touched.isEmpty { finishWrites(touched) }
    }

    /// Copies that changed in `changedIn` merge into the main copy (oldest-added folder). A
    /// change to the main copy itself pulls nothing in, so a Stello edit is never undone
    /// by an older copy elsewhere. Reads and writes run off the main thread.
    func mergeCopies(_ ids: Set<String>, changedIn: UUID) {
        var jobs: [(id: String, mainFolder: UUID, files: [URL], mainRel: String)] = []
        for id in ids {
            let locs = (lookup[id] ?? []).filter { isWritable($0.folderID) }
            guard locs.count > 1, locs[0].folderID != changedIn, locs.contains(where: { $0.folderID == changedIn }),
                  let mainRoot = roots[locs[0].folderID], let rel = relativePath(locs[0], root: mainRoot) else { continue }
            jobs.append((id, locs[0].folderID, locs.map(\.fileURL), rel))
        }
        guard !jobs.isEmpty else { return }
        let work = jobs
        Task.detached(priority: .utility) {
            var results: [(UUID, String, String, FolderFiles.Stat)] = []
            for job in work {
                guard let first = FolderFiles.read(job.files[0]), var acc = FolderWriter.readCopy(first.text) else { continue }
                acc.modified = first.modified
                for url in job.files.dropFirst() {
                    guard let r = FolderFiles.read(url), var copy = FolderWriter.readCopy(r.text) else { continue }
                    copy.modified = r.modified
                    acc = FolderWriter.merge(acc, copy)
                }
                let text = FolderWriter.copyText(acc)
                if text == first.text { continue }
                if let stat = try? FolderFiles.write(Data(text.utf8), to: job.files[0]) { results.append((job.mainFolder, job.mainRel, job.id, stat)) }
            }
            guard !results.isEmpty else { return }
            let done = results
            await MainActor.run {
                for (folder, rel, id, stat) in done { self.noteIndexed(folder, rel, id: id, stat) }
                self.finishWrites(Set(done.map(\.0)))
            }
        }
    }

    private func relativePath(_ loc: Location, root: URL) -> String? {
        let base = root.standardizedFileURL.path
        let full = loc.fileURL.standardizedFileURL.path
        return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : nil
    }

    /// Folder-relative media files a copy's images point at (media/… only).
    nonisolated static func mediaFiles(of copy: FolderWriter.Copy, at rel: String) -> [String] {
        var out: [String] = []
        for img in copy.header["images"]?.array ?? [] {
            guard let file = img["file"]?.string else { continue }
            var parts = rel.split(separator: "/").dropLast().map(String.init)
            for seg in file.split(separator: "/") {
                if seg == ".." { if !parts.isEmpty { parts.removeLast() } } else if seg != "." { parts.append(String(seg)) }
            }
            if parts.first == "media" { out.append(parts.joined(separator: "/")) }
        }
        return out
    }

    // MARK: - Item → wire (ordered, like the web's D1 row)

    private static func orderedImages(_ item: Item) -> [ItemImage] {
        // A stable order (SwiftData keeps none), so the same item always writes the same file.
        (item.images ?? []).filter { SyncWire.webPath(of: $0) != nil || $0.data != nil }.sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary }
            let ka = SyncWire.webPath(of: a) ?? a.sourceURL ?? "", kb = SyncWire.webPath(of: b) ?? b.sourceURL ?? ""
            if ka != kb { return ka < kb }
            return (a.data?.count ?? 0) < (b.data?.count ?? 0)
        }
    }

    /// The item in the sync API's field names, as ordered JSON, plus local-only image extensions.
    static func wire(_ item: Item) -> (FolderWriter.Obj, [Int: String]) {
        typealias J = FolderWriter.JSON
        let v = SyncWire.values(of: item)
        var o = FolderWriter.Obj()
        o["id"] = .string(item.id.uuidString.lowercased())
        for f in SyncWire.allFields where !["tags", "images", "snippets", "metadata"].contains(f) { o[f] = J(any: v[f]) }
        o["metadata"] = item.metadataJSON.flatMap(FolderWriter.parse) ?? .null
        o["tags"] = .array(item.tags.map {
            .object(.init([("tag", .string($0.name)), ("category", .string($0.category)), ("weight", .number($0.weight)), ("source", .string($0.source))]))
        })
        var exts: [Int: String] = [:]
        o["images"] = .array(orderedImages(item).enumerated().map { i, image in
            var row = FolderWriter.Obj()
            if let path = SyncWire.webPath(of: image) { row["path"] = .string(path) }
            else if let data = image.data {
                exts[i] = SyncBridge.contentType(of: data).split(separator: "/").last.map { $0 == "jpeg" ? "jpg" : String($0) } ?? "img"
            }
            row["source"] = .string(image.source)
            row["is_primary"] = .bool(image.isPrimary)
            row["role"] = .string(image.role)
            if let w = image.width { row["width"] = .number(Double(w)) }
            if let h = image.height { row["height"] = .number(Double(h)) }
            if let l = image.label { row["label"] = .string(l) }
            return .object(row)
        })
        o["snippets"] = J(any: v["snippets"])
        if case .array(let a)? = o["snippets"] {
            // Keep the web's key order (text, source, added_at).
            o["snippets"] = .array(a.map { s in .object(.init(["text", "source", "added_at"].compactMap { k in s[k].map { (k, $0) } })) })
        }
        return (o, exts)
    }
}

/// File operations for folder writes, safe off the main thread.
nonisolated enum FolderFiles {
    struct Stat: Sendable { var modified: Double; var size: Int }
    struct Read: Sendable { var text: String; var modified: Double; var size: Int }

    static func stat(_ url: URL) -> Stat? {
        guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
        return Stat(modified: v.contentModificationDate?.timeIntervalSince1970 ?? 0, size: v.fileSize ?? 0)
    }

    static func read(_ url: URL) -> Read? {
        guard let data = try? Data(contentsOf: url), let s = stat(url) else { return nil }
        return Read(text: String(decoding: data, as: UTF8.self), modified: s.modified, size: s.size)
    }

    /// Atomic write (temp file + rename), creating folders as needed.
    @discardableResult
    static func write(_ data: Data, to url: URL) throws -> Stat {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return stat(url) ?? Stat(modified: Date().timeIntervalSince1970, size: data.count)
    }

    /// Moves a file inside one folder; an existing file at the destination gets a -2, -3… name.
    static func move(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path) else { return }
        try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        var dest = to
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = to.deletingLastPathComponent().appendingPathComponent("\(to.deletingPathExtension().lastPathComponent)-\(n).\(to.pathExtension)")
            n += 1
        }
        try fm.moveItem(at: from, to: dest)
    }

    /// Removes .trash/<day> folders older than 30 days.
    static func clearTrash(root: URL, now: Date = .now) {
        let trash = root.appendingPathComponent(FolderWriter.trashDir, isDirectory: true)
        guard let days = try? FileManager.default.contentsOfDirectory(atPath: trash.path) else { return }
        for day in days where FolderWriter.trashExpired(day, now: now) {
            try? FileManager.default.removeItem(at: trash.appendingPathComponent(day))
        }
    }
}
