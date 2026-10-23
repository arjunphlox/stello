import Foundation

/// Fixed enrichment output for unit tests — no live model dependency.
struct MockEnricher: Enricher, Sendable {
    let isAvailable: Bool
    let result: EnrichmentResult
    let error: Error?

    nonisolated init(
        isAvailable: Bool = true,
        result: EnrichmentResult = MockEnricher.defaultResult,
        error: Error? = nil
    ) {
        self.isAvailable = isAvailable
        self.result = result
        self.error = error
    }

    nonisolated static let defaultResult = EnrichmentResult(
        visionTags: [
            VisionTagSpec(name: "teal", category: "color", weight: 0.85),
            VisionTagSpec(name: "minimalist", category: "style", weight: 0.7),
            VisionTagSpec(name: "calm", category: "mood", weight: 0.6),
        ],
        snippets: [
            "Auto layout handles the hardest part of responsive design.",
            "Constraints and padding work together in Figma frames.",
        ],
        whySavedSuggestions: [
            "layout-reference",
            "auto-layout-patterns",
            "design-system-tips",
        ]
    )

    nonisolated func enrich(
        title: String,
        summary: String?,
        domain: String?,
        coverImageData: Data?,
        pageText: String? = nil
    ) async throws -> EnrichmentResult {
        if let error { throw error }
        guard isAvailable else { throw EnricherError.unavailable }
        return result
    }

    nonisolated func enrichVisionOnly(coverImageData: Data?) async throws -> [VisionTagSpec] {
        if let error { throw error }
        guard isAvailable else { throw EnricherError.unavailable }
        return result.visionTags
    }

    /// Deterministic stand-in for the on-device guess: the rule-based filename reading.
    nonisolated func guessProduct(caption: String?, filename: String?) async throws -> ProductGuess {
        if let error { throw error }
        guard isAvailable else { throw EnricherError.unavailable }
        return ProductReader.ruleBasedGuess(caption: caption, filename: filename)
    }

    /// No deterministic stand-in for a prompt guess — nil, like the rule-based fallback.
    nonisolated func guessPrompt(text: String?, aiModel: String?) async throws -> String? {
        if let error { throw error }
        guard isAvailable else { throw EnricherError.unavailable }
        return nil
    }

    /// No deterministic stand-in for the tool-facts guess — nil (the caller then tries the
    /// rule-based keyword pass).
    nonisolated func guessToolFacts(text: String?) async throws -> ToolFacts? {
        if let error { throw error }
        guard isAvailable else { throw EnricherError.unavailable }
        return nil
    }
}
