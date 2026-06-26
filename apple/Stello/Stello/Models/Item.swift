import Foundation
import SwiftData

@Model
final class Item {
    var id: UUID = UUID()
    var slug: String = ""
    var title: String = ""
    var sourceURL: String?
    var domain: String?
    var author: String?
    var summary: String?
    var bodyMarkdown: String?
    var status: String = "active"
    var needsReview: Bool = true
    var addedAt: Date = Date.now
    var analyzedAt: Date?
    var updatedAt: Date = Date.now
    var enrichmentStatus: String = "pending"
    var enrichmentError: String?
  /// JSON-encoded `[String]` of suggested why-saved reasons from AI enrichment.
    var whySavedSuggestionsJSON: String?

    @Relationship(deleteRule: .cascade, inverse: \Tag.item)
    var tags: [Tag]?

    @Relationship(deleteRule: .cascade, inverse: \ItemImage.item)
    var images: [ItemImage]?

    @Relationship(deleteRule: .cascade, inverse: \Snippet.item)
    var snippets: [Snippet]?

    init(
        id: UUID = UUID(),
        slug: String = "",
        title: String = "",
        sourceURL: String? = nil,
        domain: String? = nil,
        author: String? = nil,
        summary: String? = nil,
        bodyMarkdown: String? = nil,
        status: String = "active",
        needsReview: Bool = true,
        addedAt: Date = .now,
        analyzedAt: Date? = nil,
        updatedAt: Date = .now,
        enrichmentStatus: String = "pending",
        enrichmentError: String? = nil,
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
        self.status = status
        self.needsReview = needsReview
        self.addedAt = addedAt
        self.analyzedAt = analyzedAt
        self.updatedAt = updatedAt
        self.enrichmentStatus = enrichmentStatus
        self.enrichmentError = enrichmentError
        self.whySavedSuggestionsJSON = whySavedSuggestionsJSON
    }
}

// Hashable conformance required for NavigationLink(value:).
extension Item: Hashable {
    static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
