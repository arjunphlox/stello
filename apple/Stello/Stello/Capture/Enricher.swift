import Foundation

// MARK: - Result types

struct VisionTagSpec: Sendable {
    var name: String
    var category: String
    var weight: Double
}

struct EnrichmentResult: Sendable {
    var visionTags: [VisionTagSpec]
    var snippets: [String]
    var whySavedSuggestions: [String]
}

// MARK: - Errors

enum EnricherError: Error, Equatable {
    case unavailable
}

// MARK: - Protocol

protocol Enricher {
    var isAvailable: Bool { get }
    func enrich(
        title: String,
        summary: String?,
        domain: String?,
        coverImageData: Data?
    ) async throws -> EnrichmentResult
}
