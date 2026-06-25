import Foundation
import FoundationModels

// MARK: - @Generable schemas (swap prompts/schemas here after bake-off)

@Generable(description: "Vision tags, text snippets, and why-saved suggestions for a saved design reference item.")
struct EnrichmentGenerableResult {
    @Guide(description: "2–4 dominant colors visible in the cover image. Use specific names like burgundy, teal, charcoal — not generic blue/red.")
    var colorTags: [WeightedTagGenerable]

    @Guide(description: "1–3 visual design styles (e.g. minimalist, editorial, geometric, typographic).")
    var styleTags: [WeightedTagGenerable]

    @Guide(description: "1–2 emotional mood tones (e.g. calm, vibrant, elegant, playful).")
    var moodTags: [WeightedTagGenerable]

    @Guide(description: "3–5 short notable quotes or lines from the page text (each ≤ 200 characters).")
    var snippets: [String]

    @Guide(description: "Exactly 3 short suggested reasons why a designer might save this (≤ 4 words, lowercase kebab-case).")
    var whySavedSuggestions: [String]
}

@Generable(description: "A weighted tag name with confidence 0.0–1.0.")
struct WeightedTagGenerable {
    @Guide(description: "Lowercase kebab-case tag name.")
    var name: String

    @Guide(description: "Confidence or dominance from 0.0 to 1.0.")
    var weight: Double
}

// MARK: - Prompt text

enum EnrichmentPrompts {
    static let systemInstructions = """
    You enrich saved design references for a personal knowledge base.
    Assign vision tags only from what is visible in the cover image.
  Assign snippets only from the provided title and summary text — do not invent quotes.
  Suggest practical why-saved reasons a designer would revisit this item.
  Use lowercase kebab-case for tag names and why-saved suggestions.
  """

    static func userPrompt(title: String, summary: String?, domain: String?) -> String {
        var lines = ["Title: \(title)"]
        if let domain, !domain.isEmpty { lines.append("Domain: \(domain)") }
        if let summary, !summary.isEmpty { lines.append("Summary: \(summary)") }
        lines.append("Analyze the cover image (if provided) and the text above.")
        return lines.joined(separator: "\n")
    }
}
