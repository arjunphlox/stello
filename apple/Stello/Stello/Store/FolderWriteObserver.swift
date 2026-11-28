import Foundation
import SwiftData
import os

/// Finds saves, edits and deletes in SwiftData history and hands them to `FolderSources`
/// (folder engine plan 4b, part 2). Its own history position means it sees every change:
/// made here, pulled from the web, or arriving from another Apple device through CloudKit.
/// Opening an item (last opened, open count) is not an edit and writes nothing.
///
/// The first run only records the time (a baseline), so turning writes on never rewrites
/// the folder: only changes made after it are written.
@MainActor
final class FolderWriteObserver {
    static let shared = FolderWriteObserver()
    private static let tokenKey = "stello.folderWrites.token"
    private static let sinceKey = "stello.folderWrites.since"
    /// Fields whose change alone is not an edit.
    nonisolated private static let notEdits: Set<String> = ["last_opened_at", "open_count"]

    private var container: ModelContainer?
    private var debounce: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var running = false
    private var again = false

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        // Part 3: items made from a folder's own files are saved here; read any waiting now.
        FolderSources.shared.modelContainer = container
        FolderSources.shared.ingestAll()
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FolderWriteObserver.shared.scheduleSoon() }
        }
        // didSave doesn't fire for every save path (autosave can lag), so also look every 20 s.
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.run()
            }
        }
        scheduleSoon()
    }

    /// App came to the front: look now.
    func poke() { scheduleSoon() }

    private func scheduleSoon() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    private func run() async {
        guard let container else { return }
        if running { again = true; return }
        running = true
        defer { running = false }
        repeat {
            again = false
            let tokenData = UserDefaults.standard.data(forKey: Self.tokenKey)
            // Baseline: the first run only notes the time; history after it is what gets written.
            guard let since = UserDefaults.standard.object(forKey: Self.sinceKey) as? Double else {
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.sinceKey)
                return
            }
            let scanned: ([(UUID, Change)], Data?)
            do {
                scanned = try await Task.detached(priority: .utility, operation: {
                    try Self.scan(container: container, after: tokenData, since: Date(timeIntervalSince1970: since))
                }).value
            } catch {
                folderLog.error("history read failed: \(String(describing: error), privacy: .public)")
                return
            }
            let (changes, last) = scanned
            if !changes.isEmpty {
                folderLog.info("history: \(changes.count) item change(s), can write: \(FolderSources.shared.canWrite)")
            }
            if let last { UserDefaults.standard.set(last, forKey: Self.tokenKey) }
            // Nothing to write to: just move the history position on.
            guard FolderSources.shared.canWrite, !changes.isEmpty else { continue }
            let sources = FolderSources.shared
            let context = container.mainContext
            for (id, kind) in changes {
                switch kind {
                case .deleted:
                    sources.trash(itemID: id)
                case .changed:
                    var d = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
                    d.fetchLimit = 1
                    if let item = try? context.fetch(d).first { sources.write(item) }
                }
                await Task.yield()
            }
        } while again
    }

    nonisolated enum Change: Sendable, Equatable { case changed, deleted }

    /// Item changes after `tokenData` (latest wins per item) and the newest history token.
    nonisolated private static func scan(container: ModelContainer, after tokenData: Data?, since: Date) throws -> ([(UUID, Change)], Data?) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let tokenData, let token = try? JSONDecoder().decode(DefaultHistoryToken.self, from: tokenData) {
            descriptor.predicate = #Predicate { $0.token > token }
        } else {
            descriptor.predicate = #Predicate { $0.timestamp > since }
        }
        let transactions = try context.fetchHistory(descriptor)
        var order: [UUID] = []
        var latest: [UUID: Change] = [:]
        var last: DefaultHistoryToken?
        var idFor: [PersistentIdentifier: UUID?] = [:]
        func itemID(_ pid: PersistentIdentifier) -> UUID? {
            if let known = idFor[pid] { return known }
            var d = FetchDescriptor<Item>(predicate: #Predicate { $0.persistentModelID == pid })
            d.fetchLimit = 1
            let id = (try? context.fetch(d))?.first?.id
            idFor[pid] = .some(id)
            return id
        }
        func note(_ id: UUID, _ c: Change) {
            if latest[id] == nil { order.append(id) }
            latest[id] = c
        }
        for transaction in transactions {
            last = transaction.token
            for change in transaction.changes {
                switch change {
                case .insert(let insert as DefaultHistoryInsert<Item>):
                    if let id = itemID(insert.changedPersistentIdentifier) { note(id, .changed) }
                case .update(let update as DefaultHistoryUpdate<Item>):
                    let fields = Set(update.updatedAttributes.compactMap { SyncWire.fieldForKeyPath[$0] })
                    guard !fields.isEmpty, !fields.isSubset(of: notEdits), let id = itemID(update.changedPersistentIdentifier) else { continue }
                    note(id, .changed)
                case .delete(let delete as DefaultHistoryDelete<Item>):
                    if let id = delete.tombstone[\.id] as? UUID { note(id, .deleted) }
                default:
                    continue
                }
            }
        }
        return (order.compactMap { id in latest[id].map { (id, $0) } }, last.flatMap { try? JSONEncoder().encode($0) })
    }
}
