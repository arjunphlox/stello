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

    /// Prompts are only rule-read (`PostReader.extractPrompt`) — there is nothing to guess.
    nonisolated func guessPrompt(text: String?, aiModel: String?) async throws -> String? {
        nil
    }

    /// Conservative keyword pass ("Download for Mac", "free plan … per month"); nil when the
    /// text says nothing clear.
    nonisolated func guessToolFacts(text: String?) async throws -> ToolFacts? {
        ToolReader.ruleBasedFacts(text: text)
    }
}
