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

    nonisolated func enrichVisionOnly(coverImageData: Data?) async throws -> [VisionTagSpec] {
        []
    }

    /// Filename slug → sentence-case name, no brand (captions aren't parsed by rule).
    nonisolated func guessProduct(caption: String?, filename: String?) async throws -> ProductGuess {
        ProductReader.ruleBasedGuess(caption: caption, filename: filename)
    }
}
