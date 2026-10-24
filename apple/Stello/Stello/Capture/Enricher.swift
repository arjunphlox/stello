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
        coverImageData: Data?,
        pageText: String?
    ) async throws -> EnrichmentResult

    /// Vision-only entry point for kind-dispatched enrichment (music covers) that must never
    /// trigger the generic snippets/why-saved text jobs alongside it.
    func enrichVisionOnly(coverImageData: Data?) async throws -> [VisionTagSpec]

    /// Product name/brand guess for products with no structured data (Instagram caption,
    /// bare image filename). Results are stored as guesses (`ProductMeta.…IsGuess`).
    func guessProduct(caption: String?, filename: String?) async throws -> ProductGuess

    /// Prompt guess for an AI-art post whose text has no rule-readable prompt. Nil = no
    /// guess. Results are stored as guesses (`PostMeta.promptIsGuess`).
    func guessPrompt(text: String?, aiModel: String?) async throws -> String?

    /// Platforms + pricing guess for a tool whose page gave neither (no JSON-LD, no store
    /// data). Nil = no guess. Results are stored as guesses (`ToolMeta.…IsGuess`).
    func guessToolFacts(text: String?) async throws -> ToolFacts?

    /// Summary + tech stack for an article from its page text. Nil = no digest (the caller
    /// then tries the rule-based tech stack for tutorials). The summary is stored as a guess
    /// (`ArticleMeta.summaryIsGuess`).
    func summarizeArticle(text: String?) async throws -> ArticleFacts?
}
