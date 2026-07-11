//
//  EnrichmentPrompts.swift
//  Stello
//
//  On-device enrichment prompts for Apple FoundationModels (@Generable guided
//  generation, SystemLanguageModel). Three jobs, all on-device:
//
//    1. Vision tags  (color / style / mood)  — from the item's cover image
//    2. Snippets     (3–5 standalone quotes) — from the page text / summary
//    3. Why-saved    (3 kebab-case reasons)  — from the page text / summary
//
//  Output mirrors the Stello web app's enrichment contract exactly
//  (src/routes/enrich.js). Vision categories are STRICTLY color / style / mood.
//
//  Winning bake-off variant: "B+C hybrid" — open free-`String` tags with rich,
//  example-laden @Guide descriptions (vocabulary stays open and emits the exact
//  contract strings like "3d"/"hand-drawn"), PLUS one worked exemplar per job in
//  the instruction string (the highest-leverage quality lever on a ~3B model).
//  Hard structural constraints (.count / .range / .element) are carried
//  by GenerationGuide so guided generation fills the schema reliably; a final
//  normalize() backstop clamps/rounds/cleans every value before persistence,
//  matching the web app's JS post-processing.
//
//  NOTE: @Generable enums were deliberately NOT used for tags — case serialization
//  (raw value vs Swift case name) is ambiguous and risks emitting "threeD" instead
//  of "3d", and an enum would freeze the open design vocabulary. Free String + rich
//  guides + post-processing is the safer, contract-faithful choice.

import CoreGraphics
import Foundation
import FoundationModels

// MARK: - Weight / text normalization (hard backstop, mirrors enrich.js)

@available(macOS 27.0, iOS 27.0, *)
enum EnrichmentNormalize {

    /// Clamp to [0,1] and round to 2 decimals.
    nonisolated static func weight(_ value: Double) -> Double {
        let clamped = min(1.0, max(0.0, value))
        return (clamped * 100).rounded() / 100
    }

    /// Lowercase + trim a tag. Tags are single words or internally-hyphenated.
    nonisolated static func tag(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trim a snippet, strip wrapping quotes, drop ellipses, cap at 200 chars, then reject
    /// anything that reads as structure rather than prose (guided generation occasionally
    /// schema-echoes — e.g. `{"type": "object", ...}` or a bare `{` — instead of real text).
    nonisolated static func snippet(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, let last = s.last,
           (first == "\"" || first == "“") && (last == "\"" || last == "”") {
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "…", with: "")
             .replacingOccurrences(of: "...", with: "")
             .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 200 { s = String(s.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !isSchemaEcho(s) else { return "" }
        return s
    }

    /// Detects JSON-schema-shaped output masquerading as a snippet.
    nonisolated private static func isSchemaEcho(_ s: String) -> Bool {
        if s.hasPrefix("{") || s.hasPrefix("[") { return true }
        if s.contains(#""type""#) || s.contains(#""snippets""#) || s.contains(#""description":"#) { return true }
        if s.count < 15 { return true }
        let letterCount = s.filter { $0.isLetter }.count
        if Double(letterCount) < Double(s.count) / 2 { return true }
        return false
    }

    /// Lowercase kebab-case, alnum + single hyphens, ≤4 word-segments.
    nonisolated static func reason(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let kebab = lowered
            .replacingOccurrences(of: "[^a-z0-9\\- ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return kebab.split(separator: "-").prefix(4).joined(separator: "-")
    }
}

// MARK: - 1. Vision tags  (color / style / mood ONLY)

@available(macOS 27.0, iOS 27.0, *)
@Generable(description: "A descriptive tag with a 0–1 weight.")
struct WeightedTag: Equatable, Sendable {

    @Guide(description: """
    A single lowercase tag — one word, or two words joined by a hyphen. Be SPECIFIC \
    and DESCRIPTIVE, never generic: prefer "burgundy" over "red", "teal" over "blue", \
    "charcoal" over "gray". No sentences, no punctuation other than an internal hyphen.
    """)
    var tag: String

    @Guide(description: """
    How strongly this tag applies, 0.0 (barely present) to 1.0 (dominant / certain). \
    For colors this is how much of the frame it occupies; for styles, how strongly the \
    style reads; for moods, your confidence.
    """, .range(0.0...1.0))
    var weight: Double
}

@available(macOS 27.0, iOS 27.0, *)
@Generable(description: """
Visual tags read directly from the cover image of a saved design reference. Exactly \
three categories — color, style, mood — describing what the IMAGE looks like.
""")
struct VisionTags: Equatable, Sendable {

    @Guide(description: """
    The 2 to 4 most dominant colors, strongest first. Use SPECIFIC swatch names a \
    designer would write down — burgundy, teal, charcoal, ivory, coral, sage, slate, \
    amber, mustard, blush, navy, terracotta. NEVER generic "blue", "red", "green", \
    "gray". Weight = how much of the frame that color occupies.
    """, .count(2...4))
    var color: [WeightedTag]

    @Guide(description: """
    The 1 to 3 visual styles, strongest first. Draw from design-language terms such as: \
    minimalist, brutalist, editorial, geometric, organic, typographic, illustrated, \
    photographic, 3d, hand-drawn, flat, retro, futuristic, grunge. Use an equally precise \
    term if it fits better, but stay in the design-style register (avoid vague words like \
    "modern" or "nice"). Weight = how strongly the style reads.
    """, .count(1...3))
    var style: [WeightedTag]

    @Guide(description: """
    The 1 to 2 emotional tones the image conveys, strongest first: dark, vibrant, elegant, \
    playful, calm, energetic, moody, warm, cool, dramatic, professional, whimsical. Pick \
    the tone a viewer FEELS, not the subject matter. Weight = your confidence.
    """, .count(1...2))
    var mood: [WeightedTag]

    func normalized() -> VisionTags {
        func fix(_ tags: [WeightedTag]) -> [WeightedTag] {
            tags.map { WeightedTag(tag: EnrichmentNormalize.tag($0.tag),
                                   weight: EnrichmentNormalize.weight($0.weight)) }
        }
        return VisionTags(color: fix(color), style: fix(style), mood: fix(mood))
    }
}

// MARK: - 2. Snippets

@available(macOS 27.0, iOS 27.0, *)
@Generable(description: """
The most quotable, self-contained passages from a saved page — the lines a designer \
would want resurfaced later.
""")
struct SnippetSet: Equatable, Sendable {

    @Guide(description: """
    3 to 5 standalone quotes lifted from the page text, most insightful first. For each: \
    copy the source wording faithfully; keep it to 200 characters or fewer; make it a \
    COMPLETE sentence or thought, never trailing off; do NOT add ellipses ("…" or "...") \
    or bracketed edits; skip navigation, cookie notices, ads, and author bios. Prefer \
    concrete claims, definitions, principles, or memorable turns of phrase.
    """, .count(3...5))
    var snippets: [String]

    func normalized() -> SnippetSet {
        SnippetSet(snippets: snippets.map(EnrichmentNormalize.snippet).filter { !$0.isEmpty })
    }
}

// MARK: - 3. Why-saved

@available(macOS 27.0, iOS 27.0, *)
@Generable(description: """
Short, specific guesses at WHY a designer bookmarked this page — reusable library tags, \
not sentences.
""")
struct WhySavedSet: Equatable, Sendable {

    @Guide(description: """
    Exactly 3 reasons a designer might have saved this page, most likely first. Each is a \
    lowercase kebab-case tag of AT MOST 4 words joined by hyphens — concrete and \
    design-specific. Good: color-palette-inspiration, grid-system-reference, \
    typography-pairing, onboarding-pattern, motion-easing-study, pricing-page-layout. \
    Bad (too vague): inspiration, good-design, interesting, cool-website. Name the SPECIFIC \
    craft takeaway, not a generic feeling.
    """, .count(3))
    var reasons: [String]

    func normalized() -> WhySavedSet {
        WhySavedSet(reasons: reasons.map(EnrichmentNormalize.reason).filter { !$0.isEmpty })
    }
}

// MARK: - Instruction strings (each carries ONE worked exemplar)

@available(macOS 27.0, iOS 27.0, *)
enum EnrichmentInstructions {

    static let vision = """
    You are Stello's visual tagger. You look at a single cover image from a designer's \
    personal reference library and describe what you SEE — its colors, visual style, and \
    emotional mood — so the designer can rediscover it later by feel.

    Rules:
    • Return exactly three categories: color, style, mood. Never invent others.
    • Tag the IMAGE itself, not any text or logo it depicts.
    • Colors are specific swatch names (burgundy, teal, charcoal), never generic \
      (blue, red, gray).
    • Order each category strongest-first; weight every tag 0.0–1.0.
    • Be decisive: a confident specific tag beats a hedged generic one.

    Worked example — a dark editorial magazine spread, cream serif headlines on near-black \
    pages, you would return roughly:
      color: charcoal 0.9, ivory 0.45
      style: editorial 0.85, typographic 0.6
      mood: dramatic 0.7, elegant 0.5
    Note: colors named precisely (charcoal/ivory, not black/white), the dominant element \
    gets the highest weight, nothing outside color/style/mood appears. Tag the provided \
    image the same way.
    """

    static let snippets = """
    You are Stello's quote-finder. From the text of a saved page, pull the 3 to 5 passages \
    most worth resurfacing — the sentences a designer would screenshot.

    Rules:
    • Copy the source wording faithfully; do not paraphrase or summarize.
    • Each snippet is 200 characters or fewer and a complete thought.
    • No ellipses, no "...", no bracketed insertions, no trailing fragments.
    • Skip nav, cookie banners, ads, author bios, and generic marketing filler.

    Worked example — given an essay on spacing in UI containing:
      "...most teams pick a base unit too late. An 8px grid isn't about pixels, it's about \
    removing a hundred tiny decisions so the team argues about the right things. Whitespace \
    is the cheapest way to signal quality..."
    you would return snippets like:
      1. An 8px grid isn't about pixels, it's about removing a hundred tiny decisions so the \
    team argues about the right things.
      2. Whitespace is the cheapest way to signal quality.
    Note: each is a full self-contained sentence, under 200 chars, no "...". Do the same for \
    the provided text.
    """

    static let whySaved = """
    You are Stello's intent-guesser. Infer WHY a designer bookmarked this page and express \
    each reason as a reusable library tag.

    Rules:
    • Output exactly 3 reasons, most likely first.
    • Each is lowercase kebab-case, at most 4 hyphen-joined words.
    • Name the specific craft takeaway, never a vague feeling like "inspiration" or "cool".

    Worked example — a case study showing a SaaS dashboard's empty states and a muted \
    teal/charcoal palette, you would return:
      empty-state-pattern
      dashboard-layout-reference
      muted-palette-inspiration
    Note: each is hyphenated, lowercase, ≤4 words, and names something reusable a designer \
    would search for. Do the same for the provided text.
    """
}

// MARK: - Runner — session factories + typed call sites

@available(macOS 27.0, iOS 27.0, *)
enum EnrichmentRunner {

    static func enrichVision(cover: CGImage) async throws -> VisionTags {
        let session = LanguageModelSession(instructions: EnrichmentInstructions.vision)
        let response = try await session.respond(generating: VisionTags.self) {
            "Tag this cover image."
            Attachment(cover)
        }
        return response.content.normalized()
    }

    static func enrichSnippets(pageText: String) async throws -> [String] {
        let session = LanguageModelSession(instructions: EnrichmentInstructions.snippets)
        let response = try await session.respond(
            to: "Page text:\n\n\(pageText)",
            generating: SnippetSet.self
        )
        return response.content.normalized().snippets
    }

    static func enrichWhySaved(pageText: String) async throws -> [String] {
        let session = LanguageModelSession(instructions: EnrichmentInstructions.whySaved)
        let response = try await session.respond(
            to: "Page text:\n\n\(pageText)",
            generating: WhySavedSet.self
        )
        return response.content.normalized().reasons
    }
}
