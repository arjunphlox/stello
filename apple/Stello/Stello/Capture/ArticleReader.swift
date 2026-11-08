import Foundation

/// Summary + tech stack from the on-device article job (`Enricher.summarizeArticle`). The
/// summary is stored with `ArticleMeta.summaryIsGuess == true`; the tech stack is kept only
/// for tutorials.
nonisolated struct ArticleFacts: Sendable, Equatable {
    var summary: String?
    var techStack: [String] = []
}

/// On-device helpers for article items: the summary / tech-stack digest the on-device job fills gaps with, and
/// the merge a fresh read goes through on Enrich. The page readers themselves live on the
/// Worker (`src/lib/readers/article.js`), the one copy shared with web saves.
nonisolated enum ArticleReader {

    /// Most tech-stack names kept (model or rule-based).
    static let maxTechStack = 5

    static func authorRef(_ name: String) -> EntityRef {
        EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
    }

    static func looksLikeURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.")
    }

    /// Known names matched in page text, in this order. `spellings` match case-insensitively;
    /// names that are also everyday English words ("react", "swift", "rive") only match when
    /// capitalised as the name (`exactCase`).
    static let knownTechStack: [(name: String, spellings: [String], exactCase: Bool)] = [
        ("three.js", ["three.js", "threejs"], false),
        ("GSAP", ["gsap"], false),
        ("React", ["React", "React.js", "ReactJS"], true),
        ("WebGL", ["webgl"], false),
        ("GLSL", ["glsl"], false),
        ("CSS", ["css"], false),
        ("Swift", ["Swift"], true),
        ("SwiftUI", ["swiftui"], false),
        ("Rive", ["Rive"], true),
        ("Framer", ["Framer"], true),
        ("Figma", ["figma"], false),
        ("Next.js", ["next.js", "nextjs"], false),
        ("Svelte", ["svelte"], false),
        ("Vue", ["Vue", "vue.js", "vuejs"], true),
        ("Tailwind", ["tailwind", "tailwindcss"], false),
    ]

    /// Conservative rule-based tech stack: known names that appear as whole words in the text
    /// (tokens keep `.` so "three.js" / "next.js" match), at most 5, in list order. Empty when
    /// nothing is named.
    static func ruleBasedTechStack(text: String?) -> [String] {
        guard let cleaned = ToolReader.clean(text) else { return [] }
        let tokens = Set(
            cleaned.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == ".") })
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                .filter { !$0.isEmpty }
        )
        let lowerTokens = Set(tokens.map { $0.lowercased() })
        var result: [String] = []
        for entry in knownTechStack {
            let found = entry.spellings.contains { spelling in
                // A dotted spelling ("vue.js") is never an English word — any case counts.
                if entry.exactCase && !spelling.contains(".") { return tokens.contains(spelling) }
                return lowerTokens.contains(spelling.lowercased())
            }
            guard found else { continue }
            result.append(entry.name)
            if result.count == maxTechStack { break }
        }
        return result
    }

    /// Model tech-stack names: trimmed, de-duplicated (case-insensitive), at most 5.
    static func cleanTechStack(_ names: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for raw in names {
            guard let name = ToolReader.clean(raw), name.count <= 40 else { continue }
            if seen.insert(name.lowercased()).inserted { result.append(name) }
            if result.count == maxTechStack { break }
        }
        return result
    }

    /// A model summary, trimmed; nil when empty.
    static func cleanSummary(_ raw: String?) -> String? {
        ToolReader.clean(raw)
    }

    /// Whether the on-device job (or the rule-based tech stack) has something to fill.
    static func needsDigest(_ meta: ArticleMeta) -> Bool {
        meta.summary == nil || (meta.isTutorial && meta.techStack.isEmpty)
    }

    /// Fills the summary (as a guess) and — for tutorials — the tech stack from the model
    /// job; a tutorial with no model stack falls back to the rule-based names from `text`.
    /// Never replaces a summary or tech stack already stored.
    static func applyDigest(_ facts: ArticleFacts?, text: String?, to meta: inout ArticleMeta) {
        if meta.summary == nil, let summary = cleanSummary(facts?.summary) {
            meta.summary = summary
            meta.summaryIsGuess = true
        }
        guard meta.isTutorial, meta.techStack.isEmpty else { return }
        let fromModel = cleanTechStack(facts?.techStack ?? [])
        meta.techStack = fromModel.isEmpty ? ruleBasedTechStack(text: text) : fromModel
    }

    /// A refetch that reads less (bot wall, paywall) never erases what capture read; the
    /// summary and tech stack (on-device) are always kept.
    static func merge(fresh: ArticleMeta, previous: ArticleMeta?) -> ArticleMeta {
        guard let previous else { return fresh }
        var meta = fresh
        if meta.publication == nil { meta.publication = previous.publication }
        if meta.author == nil { meta.author = previous.author }
        if meta.publishedAt == nil { meta.publishedAt = previous.publishedAt }
        if meta.readingMinutes == nil { meta.readingMinutes = previous.readingMinutes }
        if meta.canonicalURL == nil { meta.canonicalURL = previous.canonicalURL }
        meta.isTutorial = meta.isTutorial || previous.isTutorial
        meta.summary = previous.summary
        meta.summaryIsGuess = previous.summaryIsGuess
        meta.techStack = previous.techStack
        return meta
    }
}
