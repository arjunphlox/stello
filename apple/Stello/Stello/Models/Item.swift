import Foundation
import SwiftData

@Model
final class Item {
    /// Kept in delete history so the web sync bridge can send the delete (`SyncBridge`).
    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var slug: String = ""
    var title: String = ""
    var sourceURL: String?
    var domain: String?
    var author: String?
    var summary: String?
    var bodyMarkdown: String?
    /// Readability-lite page text captured for AI enrichment + search — distinct from
    /// `bodyMarkdown`, which is user-authored content rendered as a "Notes" card.
    var extractedText: String?
    /// `active`, or `gone` when the source page answered 404/410 (item + saved image kept).
    var status: String = "active"
    var needsReview: Bool = true
    var addedAt: Date = Date.now
    var analyzedAt: Date?
    var updatedAt: Date = Date.now
    var lastOpenedAt: Date?
    var openCount: Int = 0
    var enrichmentStatus: String = "pending"
    var enrichmentError: String?
    /// Card type: `typeface`, `website`, `individual`, `studio`, `foundry`, `place`, `music`,
    /// `product`, `post`, `tool`, `resource`, `book`, `course`, `article`, or `link` (default).
    var kind: String = "link"
    /// Codable per-kind metadata (`TypefaceMeta`, `WebsiteMeta`, …) encoded as JSON.
    var metadataJSON: String?
  /// JSON-encoded `[String]` of suggested why-saved reasons from AI enrichment.
    var whySavedSuggestionsJSON: String?

    /// JSON-encoded `[ItemTag]`, nil when the item has none. Read and write through `tags`.
    var tagsJSON: String?
    /// Width over height of the cover the card shows, or 0 for no cover. Kept here so the
    /// grid can place every card without reading image rows or bytes.
    var coverAspect: Double = 0
    /// JSON-encoded `[String]` of audience ids this item is shared with (Family, a trip
    /// list, …); nil or empty = private. Read and write through `audiences`. Synced to
    /// the web as `audiences` (docs/plans/audience-sharing.md).
    var audiencesJSON: String?
    /// Bumped on save when any of the item's images or snippets change, so SwiftData's
    /// change history names the item and the web sync bridge sends the new list.
    /// Set by `SyncChildTracking`; never set it by hand.
    var imagesChangedAt: Date?
    var snippetsChangedAt: Date?

    @Transient var tagCache = ItemTagCache()

    @Relationship(deleteRule: .cascade, inverse: \ItemImage.item)
    var images: [ItemImage]?

    @Relationship(deleteRule: .cascade, inverse: \Snippet.item)
    var snippets: [Snippet]?

    @Relationship(deleteRule: .cascade, inverse: \LocalAttachment.item)
    var attachments: [LocalAttachment]?

    init(
        id: UUID = UUID(),
        slug: String = "",
        title: String = "",
        sourceURL: String? = nil,
        domain: String? = nil,
        author: String? = nil,
        summary: String? = nil,
        bodyMarkdown: String? = nil,
        extractedText: String? = nil,
        status: String = "active",
        needsReview: Bool = true,
        addedAt: Date = .now,
        analyzedAt: Date? = nil,
        updatedAt: Date = .now,
        enrichmentStatus: String = "pending",
        enrichmentError: String? = nil,
        kind: String = "link",
        metadataJSON: String? = nil,
        whySavedSuggestionsJSON: String? = nil
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.sourceURL = sourceURL
        self.domain = domain
        self.author = author
        self.summary = summary
        self.bodyMarkdown = bodyMarkdown
        self.extractedText = extractedText
        self.status = status
        self.needsReview = needsReview
        self.addedAt = addedAt
        self.analyzedAt = analyzedAt
        self.updatedAt = updatedAt
        self.enrichmentStatus = enrichmentStatus
        self.enrichmentError = enrichmentError
        self.kind = kind
        self.metadataJSON = metadataJSON
        self.whySavedSuggestionsJSON = whySavedSuggestionsJSON
    }
}

extension Item {
    /// Audience ids, sorted and without repeats (the web stores them the same way).
    var audiences: [String] {
        get {
            guard let json = audiencesJSON,
                  let list = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return [] }
            return list
        }
        set {
            let clean = Array(Set(newValue.map { $0.lowercased() })).sorted()
            let json = clean.isEmpty ? nil : (try? JSONEncoder().encode(clean)).map { String(decoding: $0, as: UTF8.self) }
            if json != audiencesJSON { audiencesJSON = json }
        }
    }
}

// Hashable conformance required for NavigationLink(value:).
extension Item: Hashable {
    static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
