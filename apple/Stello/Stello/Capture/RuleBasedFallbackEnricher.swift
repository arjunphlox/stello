import Foundation

/// Offline fallback when Apple Intelligence / Foundation Models is unavailable.
struct RuleBasedFallbackEnricher: Enricher, Sendable {
    nonisolated init() {}

    nonisolated var isAvailable: Bool { true }

    nonisolated func enrich(
        title: String,
        summary: String?,
        domain: String?,
        coverImageData: Data?,
        pageText: String? = nil
    ) async throws -> EnrichmentResult {
        EnrichmentResult(visionTags: [], snippets: [], whySavedSuggestions: [])
    }
}
