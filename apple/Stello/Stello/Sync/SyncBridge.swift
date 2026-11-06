import Foundation
import SwiftData
#if os(iOS)
import BackgroundTasks
#endif

/// Keeps the web copy of the library (Cloudflare D1 + R2, behind the Stello Worker) in
/// step with this device's SwiftData + CloudKit library. Design:
/// docs/plans/apple-web-sync.md.
///
/// One cycle = push, then pull:
/// - **Push**: reads SwiftData's change history since the last token, keeps the
///   transactions this device made (not CloudKit imports, not the bridge's own writes),
///   and sends each changed item's changed fields with the transaction time as the clock.
///   Images the web doesn't have yet are uploaded first.
/// - **Pull**: fetches rows changed on the server since the saved cursor and applies
///   them, except fields this device changed more recently than the server did (that
///   covers edits made on another Apple device that arrived through CloudKit and haven't
///   reached the web yet).
///
/// Each Apple device pushes only its own edits, so a value never echoes back as "new".
/// Work runs in batches of 100 with a yield between them, on a context authored
/// `stello.sync`, so the grid never stalls and the bridge's writes are skipped by the
/// next history read.
@MainActor
final class SyncBridge {
    static let shared = SyncBridge()

    nonisolated static let author = "stello.sync"
    #if os(iOS)
    nonisolated static let refreshTaskID = "com.arjunphlox.Stello.webSync"
    #endif

    private static let cursorKey = "webSync.cursor"
    private static let tokenKey = "webSync.historyToken"
    private static let linkedKey = "webSync.linked"
    /// When link-up started. History reads with no token yet start here, so the bridge
    /// never walks the whole import history.
    private static let linkedAtKey = "webSync.linkedAt"
    private static let batch = 100

    private var container: ModelContainer?
    private var running = false
    private var again = false
    private var debounce: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    /// When this device last changed each field, ms. Filled from history (own edits and
    /// CloudKit imports), so a pull never overwrites a newer local value.
    private var localFieldTimes: [UUID: [String: Int]] = [:]

    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?

    nonisolated static var isDisabled: Bool { WebInboxProcessor.isDisabled }

    func start(container: ModelContainer) {
        guard !Self.isDisabled else { return }
        self.container = container
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { note in
            // The bridge's own saves don't need another cycle.
            let author = (note.object as? ModelContext)?.author
            guard author != Self.author else { return }
            MainActor.assumeIsolated { SyncBridge.shared.scheduleSoon() }
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.sync()
            }
        }
        Task { await sync() }
    }

    nonisolated static func requestSync(reason: String) {
        Task { @MainActor in shared.scheduleSoon() }
    }

    /// Sign-out: forget cursor and history position, so the next sign-in links up again.
    nonisolated static func resetState() {
        let d = UserDefaults.standard
        d.removeObject(forKey: cursorKey)
        d.removeObject(forKey: tokenKey)
        d.removeObject(forKey: linkedKey)
        d.removeObject(forKey: linkedAtKey)
    }

    private func scheduleSoon() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    // MARK: - Cycle

    func sync() async {
        guard let container, let api = SyncAccount.api else { return }
        if running { again = true; return }
        running = true
        defer { running = false }
        repeat {
            again = false
            let context = ModelContext(container)
            context.author = Self.author
            context.autosaveEnabled = false
            do {
                if !UserDefaults.standard.bool(forKey: Self.linkedKey) {
                    try await linkUp(api: api, context: context)
                } else {
                    try await pushHistory(api: api, context: context)
                }
                try await pull(api: api, context: context)
                lastSyncAt = .now
                lastError = nil
            } catch SyncAPI.Failure.unauthorized {
                SyncAccount.tokenRejected()
                lastError = "Signed out of the web account."
                return
            } catch {
                lastError = String(describing: error)
                print("⚠️ Web sync failed: \(error)")
                return
            }
        } while again
    }

    // MARK: - First link-up

    /// First run on this device: send every item in full (clock = its `updatedAt`) so the
    /// server keeps whichever side is newer per field, then the pull brings back the result.
    private func linkUp(api: SyncAPI, context: ModelContext) async throws {
        // History from now on is read normally; everything before is covered by the full push.
        UserDefaults.standard.set(Date.now.addingTimeInterval(-1).timeIntervalSince1970, forKey: Self.linkedAtKey)
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\.addedAt)])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batch
            let items = try context.fetch(descriptor)
            if items.isEmpty { break }
            try await uploadMissingImages(items, api: api, context: context)
            let changes = items.map { item in
                SyncWire.Change(id: item.id, fields: SyncWire.values(of: item), clock: clockAll(SyncWire.ms(item.updatedAt)), full: true)
            }
            _ = try await api.push(changes)
            offset += items.count
            await Task.yield()
        }
        UserDefaults.standard.set(true, forKey: Self.linkedKey)
    }

    private func clockAll(_ ms: Int) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: SyncWire.allFields.map { ($0, ms) })
    }

    // MARK: - Push

    private func pushHistory(api: SyncAPI, context: ModelContext) async throws {
        let read = try readHistory(context: context, after: loadToken())
        guard !read.changes.isEmpty else { saveToken(read.lastToken); return }

        let ids = Array(read.changes.keys)
        for start in stride(from: 0, to: ids.count, by: Self.batch) {
            let slice = Array(ids[start..<min(start + Self.batch, ids.count)])
            var changes: [SyncWire.Change] = []
            var live: [Item] = []
            for id in slice {
                guard let pending = read.changes[id] else { continue }
                if pending.deletedAt != nil {
                    changes.append(.init(id: id, fields: ["deleted_at": pending.deletedAt!], clock: ["deleted_at": pending.deletedAt!], full: false))
                } else if let item = fetchItem(id, context) {
                    live.append(item)
                }
            }
            try await uploadMissingImages(live, api: api, context: context)
            for item in live {
                guard let pending = read.changes[item.id] else { continue }
                // New items go in full; edits send only what changed.
                let fields = pending.inserted ? nil : pending.fields
                let values = SyncWire.values(of: item, only: fields.map { Set($0) })
                let clock = pending.inserted ? clockAll(pending.latest) : pending.clock
                changes.append(.init(id: item.id, fields: values, clock: clock, full: pending.inserted))
            }
            guard !changes.isEmpty else { continue }
            let result = try await api.push(changes)
            // The server doesn't have it (made before link-up on another device, or
            // purged there): send the whole item once.
            let missing = Set(result.results.filter { $0.status == "needs_full" }.compactMap { $0.id.flatMap(UUID.init) })
            if !missing.isEmpty {
                let full = live.filter { missing.contains($0.id) }.map {
                    SyncWire.Change(id: $0.id, fields: SyncWire.values(of: $0), clock: clockAll(SyncWire.ms($0.updatedAt)), full: true)
                }
                if !full.isEmpty { _ = try await api.push(full) }
            }
            await Task.yield()
        }
        saveToken(read.lastToken)
    }

    /// Uploads covers this device captured itself, so the web copy can show them.
    private func uploadMissingImages(_ items: [Item], api: SyncAPI, context: ModelContext) async throws {
        var uploaded = false
        for item in items {
            for image in item.images ?? [] where SyncWire.webPath(of: image) == nil {
                guard let data = image.data, !data.isEmpty else { continue }
                image.remotePath = try await api.uploadImage(data, contentType: Self.contentType(of: data))
                uploaded = true
            }
        }
        if uploaded { try context.save() }
    }

    private static func contentType(of data: Data) -> String {
        let b = [UInt8](data.prefix(12))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if b.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if b.count >= 12, b[0...3] == [0x52, 0x49, 0x46, 0x46], b[8...11] == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        if b.count >= 12, b[4...7] == [0x66, 0x74, 0x79, 0x70] { return b[8...11] == [0x61, 0x76, 0x69, 0x66] ? "image/avif" : "image/heic" }
        return "image/jpeg"
    }

    // MARK: - Pull

    private func pull(api: SyncAPI, context: ModelContext) async throws {
        var cursor = UserDefaults.standard.integer(forKey: Self.cursorKey)
        // Edits made since the push (here, or arriving from another Apple device) are
        // newer than anything the server sent before them.
        let pendingIDs = Set(try readHistory(context: context, after: loadToken()).changes.keys)

        while true {
            let page = try await api.pull(since: cursor)
            var downloads: [(ItemImage, String)] = []
            for start in stride(from: 0, to: page.items.count, by: Self.batch) {
                for row in page.items[start..<min(start + Self.batch, page.items.count)] {
                    if pendingIDs.contains(row.id) || row.purged { continue }
                    downloads += apply(row, context: context)
                }
                try context.save()
                await Task.yield()
            }
            cursor = page.cursor
            UserDefaults.standard.set(cursor, forKey: Self.cursorKey)
            if !downloads.isEmpty { try await download(downloads, api: api, context: context) }
            if !page.more { break }
        }
        pruneLocalFieldTimes()
    }

    private func apply(_ row: SyncWire.Row, context: ModelContext) -> [(ItemImage, String)] {
        let existing = fetchItem(row.id, context)
        if let deletedAt = row.deletedAt {
            // Deleted on the web, unless this device changed the item since.
            if let existing, (localFieldTimes[row.id]?.values.max() ?? 0) <= deletedAt {
                context.delete(existing)
            }
            return []
        }
        guard let item = existing else {
            return SyncWire.makeItem(from: row, in: context).1
        }
        let serverClock = row.values["clock"] as? [String: Int] ?? [:]
        let local = localFieldTimes[row.id] ?? [:]
        let skip = Set(local.compactMap { field, t in t > (serverClock[field] ?? 0) ? field : nil })
        SyncWire.apply(row, to: item, skipping: skip)
        return skip.contains("images") ? [] : SyncWire.applyImages(row, to: item)
    }

    /// Fetches web images 6 at a time and stores the bytes on the new rows.
    private func download(_ jobs: [(ItemImage, String)], api: SyncAPI, context: ModelContext) async throws {
        for start in stride(from: 0, to: jobs.count, by: 6) {
            let slice = Array(jobs[start..<min(start + 6, jobs.count)])
            let paths = slice.map(\.1)
            let results: [Int: Data] = await withTaskGroup(of: (Int, Data?).self) { group in
                for (i, path) in paths.enumerated() {
                    group.addTask { (i, try? await api.downloadImage(path: path)) }
                }
                var out: [Int: Data] = [:]
                for await (i, data) in group { if let data { out[i] = data } }
                return out
            }
            for (i, data) in results { slice[i].0.data = data }
            try context.save()
        }
    }

    // MARK: - History

    private struct Pending {
        var fields: [String] = []
        var clock: [String: Int] = [:]
        var inserted = false
        var deletedAt: Int?
        var latest = 0
        var fromImport = true
    }

    private struct HistoryRead {
        var changes: [UUID: Pending] = [:]
        var lastToken: DefaultHistoryToken?
    }

    /// Own transactions become pending pushes; CloudKit imports only update
    /// `localFieldTimes`. The bridge's own transactions are skipped.
    private func readHistory(context: ModelContext, after token: DefaultHistoryToken?) throws -> HistoryRead {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token {
            descriptor.predicate = #Predicate { $0.token > token }
        } else {
            let since = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.linkedAtKey))
            descriptor.predicate = #Predicate { $0.timestamp > since }
        }
        let transactions = try context.fetchHistory(descriptor)
        var read = HistoryRead(lastToken: token)
        for transaction in transactions {
            read.lastToken = transaction.token
            if transaction.author == Self.author { continue }
            let isImport = transaction.author?.hasPrefix("NSCloudKitMirroringDelegate") == true
            let time = SyncWire.ms(transaction.timestamp)
            for change in transaction.changes {
                switch change {
                case .insert(let insert as DefaultHistoryInsert<Item>):
                    guard let id = fetchItem(insert.changedPersistentIdentifier, context)?.id else { continue }
                    note(id, fields: SyncWire.allFields, time: time, isImport: isImport, into: &read) { $0.inserted = true }
                case .update(let update as DefaultHistoryUpdate<Item>):
                    guard let id = fetchItem(update.changedPersistentIdentifier, context)?.id else { continue }
                    let fields = update.updatedAttributes.compactMap { SyncWire.fieldForKeyPath[$0] }
                    if fields.isEmpty { continue }
                    note(id, fields: fields, time: time, isImport: isImport, into: &read) { _ in }
                case .delete(let delete as DefaultHistoryDelete<Item>):
                    guard let id = delete.tombstone[\.id] else { continue }
                    note(id, fields: [], time: time, isImport: isImport, into: &read) { $0.deletedAt = time }
                default:
                    continue // images/snippets show up through Item.imagesChangedAt/snippetsChangedAt
                }
            }
        }
        // Imports never push; drop items whose only changes came from CloudKit.
        read.changes = read.changes.filter { !$0.value.fromImport }
        return read
    }

    private func note(_ id: UUID, fields: [String], time: Int, isImport: Bool, into read: inout HistoryRead, _ edit: (inout Pending) -> Void) {
        var times = localFieldTimes[id] ?? [:]
        for f in fields { times[f] = max(times[f] ?? 0, time) }
        if fields.isEmpty { times["deleted_at"] = time }
        localFieldTimes[id] = times
        guard !isImport else { return }
        var p = read.changes[id] ?? Pending()
        p.fromImport = false
        for f in fields where !p.fields.contains(f) { p.fields.append(f) }
        for f in fields { p.clock[f] = max(p.clock[f] ?? 0, time) }
        p.latest = max(p.latest, time)
        edit(&p)
        read.changes[id] = p
    }

    /// Keeps a week of local field times; anything older has long reached the server.
    private func pruneLocalFieldTimes() {
        let cutoff = SyncWire.ms(.now.addingTimeInterval(-7 * 24 * 3600))
        localFieldTimes = localFieldTimes.filter { ($0.value.values.max() ?? 0) > cutoff }
    }

    private func fetchItem(_ id: UUID, _ context: ModelContext) -> Item? {
        var d = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// nil for an item deleted since (a fetch, unlike `model(for:)`, never hands back a
    /// fault for a row that's gone).
    private func fetchItem(_ pid: PersistentIdentifier, _ context: ModelContext) -> Item? {
        var d = FetchDescriptor<Item>(predicate: #Predicate { $0.persistentModelID == pid })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func loadToken() -> DefaultHistoryToken? {
        guard let data = UserDefaults.standard.data(forKey: Self.tokenKey) else { return nil }
        return try? JSONDecoder().decode(DefaultHistoryToken.self, from: data)
    }

    private func saveToken(_ token: DefaultHistoryToken?) {
        guard let token, let data = try? JSONEncoder().encode(token) else { return }
        UserDefaults.standard.set(data, forKey: Self.tokenKey)
    }

    // MARK: - iPhone background refresh

    #if os(iOS)
    nonisolated static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            scheduleBackgroundRefresh()
            let work = Task { @MainActor in await SyncBridge.shared.sync() }
            task.expirationHandler = { work.cancel() }
            Task {
                await work.value
                task.setTaskCompleted(success: true)
            }
        }
    }

    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    #endif
}

/// Marks an item when its images or snippets change, so the change shows up in
/// SwiftData history as an Item update the bridge can push (child rows don't name their
/// item once they're deleted).
enum SyncChildTracking {
    static let install: Void = {
        NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { note in
            guard Thread.isMainThread, let context = note.object as? ModelContext, context.author != SyncBridge.author else { return }
            nonisolated(unsafe) let saving = context
            MainActor.assumeIsolated { mark(saving) }
        }
    }()

    private static func mark(_ context: ModelContext) {
        let now = Date.now
        var images = Set<PersistentIdentifier>()
        var snippets = Set<PersistentIdentifier>()
        for model in context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray {
            if let image = model as? ItemImage, let item = image.item, !item.isDeleted, images.insert(item.persistentModelID).inserted {
                item.imagesChangedAt = now
            } else if let snippet = model as? Snippet, let item = snippet.item, !item.isDeleted, snippets.insert(item.persistentModelID).inserted {
                item.snippetsChangedAt = now
            }
        }
    }
}
