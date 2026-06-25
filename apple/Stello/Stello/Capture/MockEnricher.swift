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
        coverImageData: Data?
    ) async throws -> EnrichmentResult {
        if let error { throw error }
        guard isAvailable else { throw EnricherError.unavailable }
        return result
    }
}
