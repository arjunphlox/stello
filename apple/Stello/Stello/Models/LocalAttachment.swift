import Foundation
import SwiftData

/// Local-only file reference — video bytes live on disk, not in SwiftData external storage,
/// so CloudKit only syncs the (device-local) path string.
@Model
final class LocalAttachment {
    var id: UUID = UUID()
    /// Absolute path under Application Support (device-local; non-resolving on other devices).
    var localPath: String = ""
    var mediaType: String = "video"
    var createdAt: Date = Date.now
    var fileName: String?

    var item: Item?

    init(
        localPath: String,
        mediaType: String = "video",
        fileName: String? = nil,
        createdAt: Date = .now
    ) {
        self.localPath = localPath
        self.mediaType = mediaType
        self.fileName = fileName
        self.createdAt = createdAt
    }
}

extension Item {
    /// Domain pill / panel meta label — dropped items with no URL read "local". A tool or
    /// resource whose URL redirected shows the canonical host (`sourceURL` is untouched).
    var displayLink: String {
        guard sourceURL != nil else { return "local" }
        let canonicalString: String?
        switch kind {
        case ItemKind.tool.rawValue: canonicalString = toolMeta()?.canonicalURL
        case ItemKind.resource.rawValue: canonicalString = resourceMeta()?.canonicalURL
        default: canonicalString = nil
        }
        if let canonical = canonicalString.flatMap({ URL(string: $0) }),
           var host = canonical.host?.lowercased(), !host.isEmpty {
            if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
            return host
        }
        return domain ?? ""
    }

    var hasVideoAttachment: Bool {
        attachments?.contains { $0.mediaType == "video" } == true
    }
}
