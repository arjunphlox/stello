import CloudKit
import Foundation
import SwiftData

/// Applies saves and edits made in the Stello web app.
///
/// The web app reads the library straight from iCloud (CloudKit JS) but never
/// writes SwiftData's mirrored records. Instead it drops `StelloInbox` records
/// into the private `StelloInbox` zone. This processor subscribes to that zone
/// (silent push), turns each request into a real change through the normal
/// capture + enrichment pipeline, then deletes the request. SwiftData's own
/// CloudKit sync carries the result back to the web.
///
/// Request shape (`payload` is JSON):
///   capture  { url } | { text } | { kind: "image" } + `image` asset
///   update   { itemID, changes: { why_saved, what_works, new_snippets, removed_snippets,
///              primary_image, remove_images, add_image } }   (images by fingerprint)
///   delete   { itemID }
///   reenrich { itemID }
@MainActor
final class WebInboxProcessor {
    static let shared = WebInboxProcessor()

    nonisolated static let recordType = "StelloInbox"
    nonisolated static let zoneID = CKRecordZone.ID(zoneName: "StelloInbox", ownerName: CKCurrentUserDefaultName)
    nonisolated private static let subscriptionID = "stello-web-inbox"
    private static let subscribedKey = "webInbox.subscribed.v1"

    private var context: ModelContext?
    private var coordinator: EnrichmentCoordinator?
    private var isProcessing = false
    private var runAgain = false

    private var database: CKDatabase {
        CKContainer(identifier: StelloStore.cloudKitContainerID).privateCloudDatabase
    }

    /// Call once at launch with the app's main context.
    /// Screenshot and test runs use a throwaway store; processing there would
    /// apply web saves to it and then delete them from iCloud.
    nonisolated static var isDisabled: Bool {
        let info = ProcessInfo.processInfo
        return info.arguments.contains("-screenshotCleanStore")
            || info.environment["XCTestConfigurationFilePath"] != nil
    }

    func start(context: ModelContext, coordinator: EnrichmentCoordinator) {
        guard !Self.isDisabled else { return }
        self.context = context
        self.coordinator = coordinator
        Task {
            await ensureZoneAndSubscription()
            await processPending()
        }
    }

    // MARK: - Setup

    private func ensureZoneAndSubscription() async {
        guard !UserDefaults.standard.bool(forKey: Self.subscribedKey) else { return }
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
            let subscription = CKRecordZoneSubscription(zoneID: Self.zoneID, subscriptionID: Self.subscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true   // silent push → background wake
            subscription.notificationInfo = info
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            UserDefaults.standard.set(true, forKey: Self.subscribedKey)
        } catch {
            print("⚠️ Web inbox setup failed: \(error)")
        }
    }

    /// True when a push payload is for the inbox zone (vs SwiftData's own sync pushes).
    nonisolated static func isInboxNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return false }
        return note.subscriptionID == subscriptionID
    }

    // MARK: - Processing

    /// Fetches every outstanding request and applies them oldest first.
    func processPending() async {
        guard !Self.isDisabled, context != nil else { return }
        if isProcessing { runAgain = true; return }
        isProcessing = true
        defer { isProcessing = false }
        repeat {
            runAgain = false
            let records = await fetchRequests()
            for record in records {
                await apply(record)
            }
        } while runAgain
    }

    private func fetchRequests() async -> [CKRecord] {
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        do {
            while true {
                let changes = try await database.recordZoneChanges(inZoneWith: Self.zoneID, since: token)
                for (_, result) in changes.modificationResultsByID {
                    if case .success(let mod) = result, mod.record.recordType == Self.recordType {
                        records.append(mod.record)
                    }
                }
                token = changes.changeToken
                if !changes.moreComing { break }
            }
        } catch let error as CKError where error.code == .zoneNotFound {
            UserDefaults.standard.set(false, forKey: Self.subscribedKey)
            await ensureZoneAndSubscription()
        } catch {
            print("⚠️ Web inbox fetch failed: \(error)")
        }
        return records.sorted {
            ($0["createdAt"] as? Double ?? 0) < ($1["createdAt"] as? Double ?? 0)
        }
    }

    private func apply(_ record: CKRecord) async {
        guard let context, let coordinator else { return }
        let action = record["action"] as? String ?? ""
        let payloadText = record["payload"] as? String ?? "{}"
        let payload = (try? JSONSerialization.jsonObject(with: Data(payloadText.utf8))) as? [String: Any] ?? [:]
        let assetData = (record["image"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }

        do {
            switch action {
            case "capture":
                try await capture(payload, imageData: assetData, context: context, coordinator: coordinator)
            case "update":
                if let item = item(for: payload, context: context) {
                    try applyChanges(payload["changes"] as? [String: Any] ?? [:], to: item, imageData: assetData, context: context)
                }
            case "delete":
                if let item = item(for: payload, context: context) {
                    context.delete(item)
                    try context.save()
                }
            case "reenrich":
                if let item = item(for: payload, context: context) {
                    await coordinator.enrichItem(item, context: context, force: true)
                }
            default:
                break   // unknown action from a newer web build: drop it
            }
            try await database.deleteRecord(withID: record.recordID)
        } catch {
            // Leave the request for the next push or launch.
            print("⚠️ Web inbox request \(record.recordID.recordName) failed: \(error)")
        }
    }

    private func capture(
        _ payload: [String: Any], imageData: Data?, context: ModelContext, coordinator: EnrichmentCoordinator
    ) async throws {
        let item: Item
        if let urlString = payload["url"] as? String, let url = URL(string: urlString) {
            item = try await CaptureService.captureURL(url, context: context)
        } else if let imageData {
            item = try CaptureService.captureImage(imageData, context: context)
        } else if let text = payload["text"] as? String, !text.isEmpty {
            item = try CaptureService.captureText(text, context: context)
        } else {
            return
        }
        await coordinator.enrichItem(item, context: context)
    }

    private func item(for payload: [String: Any], context: ModelContext) -> Item? {
        if let idString = payload["itemID"] as? String, let id = UUID(uuidString: idString) {
            let byID = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
            if let found = try? context.fetch(byID).first { return found }
        }
        if let slug = payload["slug"] as? String {
            let bySlug = FetchDescriptor<Item>(predicate: #Predicate { $0.slug == slug })
            return try? context.fetch(bySlug).first
        }
        return nil
    }

    // MARK: - Edits

    private func applyChanges(_ changes: [String: Any], to item: Item, imageData: Data?, context: ModelContext) throws {
        if let reasons = changes["why_saved"] as? [String] {
            for reason in reasons where !reason.isEmpty {
                try EnrichmentService.addIntentTag(name: reason, to: item, context: context)
            }
            item.needsReview = false
        }
        if let whatWorks = changes["what_works"] as? String {
            item.needsReview = false
            let trimmed = whatWorks.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { addSnippet(trimmed, source: "what-works", to: item, context: context) }
        }
        for text in changes["new_snippets"] as? [String] ?? [] {
            addSnippet(text, source: "manual", to: item, context: context)
        }
        if let removed = changes["removed_snippets"] as? [String], !removed.isEmpty {
            for snippet in item.snippets ?? [] where removed.contains(snippet.text) {
                context.delete(snippet)
            }
        }
        if let fingerprint = changes["primary_image"] as? [String: Any],
           let target = matchImage(fingerprint, in: item) {
            for image in item.images ?? [] { image.isPrimary = (image === target) }
        }
        for fingerprint in changes["remove_images"] as? [[String: Any]] ?? [] {
            if let image = matchImage(fingerprint, in: item) { context.delete(image) }
        }
        if changes["add_image"] as? Bool == true, let imageData {
            let (w, h) = CaptureService.imageDimensions(data: imageData)
            let image = ItemImage(data: imageData, source: "manual", isPrimary: (item.images ?? []).isEmpty, width: w, height: h)
            context.insert(image)
            image.item = item
        }
        item.updatedAt = .now
        try context.save()
    }

    private func addSnippet(_ text: String, source: String, to item: Item, context: ModelContext) {
        guard !(item.snippets ?? []).contains(where: { $0.text == text }) else { return }
        let snippet = Snippet(text: text, source: source)
        context.insert(snippet)
        snippet.item = item
    }

    /// Images are matched by what the web can see: size, source and role.
    private func matchImage(_ fingerprint: [String: Any], in item: Item) -> ItemImage? {
        let width = fingerprint["width"] as? Int
        let height = fingerprint["height"] as? Int
        let source = fingerprint["source"] as? String
        let role = fingerprint["role"] as? String
        return (item.images ?? []).first { image in
            (width == nil || image.width == width)
                && (height == nil || image.height == height)
                && (source == nil || image.source == source)
                && (role == nil || image.role == role)
        }
    }
}
