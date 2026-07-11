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

enum EnricherError: Error, Equatable, LocalizedError {
    case unavailable
    /// Every AI job failed and produced nothing — carries the first job's error text so
    /// the panel's error surface can show WHY instead of a silent no-op.
    case allJobsFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Intelligence model unavailable"
        case .allJobsFailed(let detail): return detail
        }
    }
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
