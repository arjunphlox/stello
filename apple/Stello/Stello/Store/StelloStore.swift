import Foundation
import SwiftData

enum StelloStore {
    static let appGroupID = "group.com.arjunphlox.Stello"
    static let cloudKitContainerID = "iCloud.com.arjunphlox.Stello"

    /// Item IDs already counted as opened this app session (in-memory debounce).
    private(set) static var openedItemIDsThisSession = Set<UUID>()

    /// Records a detail-surface open for revisit tracking. Debounced per item per session.
    /// Does not mutate `updatedAt` — opens are activity, not content edits.
    static func recordOpen(for item: Item) {
        guard openedItemIDsThisSession.insert(item.id).inserted else { return }
        item.openCount += 1
        item.lastOpenedAt = .now
    }

    /// Clears session debounce — tests simulating a fresh app launch.
    static func resetRevisitSession() {
        openedItemIDsThisSession.removeAll()
    }

    /// Keeps `Item.coverAspect` right for every writer, in one place: on save, any item
    /// whose images changed gets its value recomputed. Rows that arrive through CloudKit
    /// carry the value with them.
    private static let coverAspectTracking: Void = {
        NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: nil, queue: nil
        ) { notification in
            guard Thread.isMainThread, let context = notification.object as? ModelContext else { return }
            nonisolated(unsafe) let saving = context
            MainActor.assumeIsolated { refreshCoverAspects(in: saving) }
        }
    }()

    private static func refreshCoverAspects(in context: ModelContext) {
        var touched: [PersistentIdentifier: Item] = [:]
        for model in context.insertedModelsArray + context.changedModelsArray {
            if let item = model as? Item {
                touched[item.persistentModelID] = item
            } else if let image = model as? ItemImage, let item = image.item {
                touched[item.persistentModelID] = item
            }
        }
        for item in touched.values { item.refreshCoverAspect() }
    }

    /// Main app container — App Group SQLite with CloudKit sync.
    static func makeContainer() throws -> ModelContainer {
        _ = coverAspectTracking
        let schema = Schema([Item.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Share Extension container — same App Group SQLite, no CloudKit in the extension.
    /// The main app picks up new records and syncs them to CloudKit on next launch.
    static func makeExtensionContainer() throws -> ModelContainer {
        _ = coverAspectTracking
        let schema = Schema([Item.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Local container fallback — App Group path unavailable (e.g. entitlement not yet provisioned).
    static func makeLocalContainer() throws -> ModelContainer {
        _ = coverAspectTracking
        let schema = Schema([Item.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainerID))
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// In-memory container for unit tests — no App Group, no CloudKit.
    static func makeInMemoryContainer() throws -> ModelContainer {
        _ = coverAspectTracking
        let schema = Schema([Item.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
