import Foundation
import SwiftData

enum StelloStore {
    static let appGroupID = "group.com.phloxpage.Stello"
    static let cloudKitContainerID = "iCloud.com.phloxpage.Stello"

    /// Main app container — App Group SQLite with CloudKit sync.
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self, LocalAttachment.self])
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
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(appGroupID)
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Local container fallback — App Group path unavailable (e.g. entitlement not yet provisioned).
    static func makeLocalContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainerID))
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// In-memory container for unit tests — no App Group, no CloudKit.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, Tag.self, ItemImage.self, Snippet.self, LocalAttachment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
