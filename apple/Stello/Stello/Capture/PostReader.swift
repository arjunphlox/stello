import Foundation

/// What the AI-art rules read from labels, tags and text.
nonisolated struct AIArtSignal: Sendable, Equatable {
    var isAIArt: Bool
    var model: String?
}

/// On-device helpers for post items: the title rule, and the AI-art flag and prompt that
/// labels and the on-device job decide. The page readers themselves live on the Worker
/// (`src/lib/readers/post.js`), the one copy shared with web saves.
nonisolated enum PostReader {

    /// Post title rule: "@handle: first ~8 words of the text…".
    static let titleWordCount = 8

    private static let dribbbleTitleRegex = try? NSRegularExpression(
        pattern: #"^([\s\S]+?)\s+by\s+([\s\S]+?)\s+(?:on|\|)\s+Dribbble$"#,
        options: [.caseInsensitive]
    )

    /// "Shot title by Jane Doe on Dribbble" → ("Shot title", "Jane Doe").
    static func parseDribbbleTitle(_ title: String?) -> (work: String?, author: String?) {
        guard let title = clean(title), let regex = dribbbleTitleRegex,
              let m = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) else {
            return (nil, nil)
        }
        let work = Range(m.range(at: 1), in: title).flatMap { clean(String(title[$0])) }
        let author = Range(m.range(at: 2), in: title).flatMap { clean(String(title[$0])) }
        return (work, author)
    }

    private static let bareGenericTitles: Set<String> = [
        "x", "twitter", "instagram", "behance", "dribbble", "pinterest",
        "x.com", "twitter.com", "mobile.twitter.com", "instagram.com", "www.instagram.com",
        "behance.net", "www.behance.net", "dribbble.com", "pinterest.com", "www.pinterest.com",
    ]

    /// A platform title that says nothing about the post: "Name (@handle) on X", "Name on
    /// X: …", "… on Twitter", "Name on Instagram: …", "Instagram", "Behance", "Dribbble",
    /// "Pin on …", the bare host, or nothing at all.
    static func isGenericPostTitle(_ title: String?) -> Bool {
        guard let t = clean(title) else { return true }
        let lower = t.lowercased()
        if bareGenericTitles.contains(lower) { return true }
        // x.com's no-JS shell page.
        if lower.hasPrefix("javascript is not available") { return true }
        if lower.hasSuffix(" on x") || lower.hasSuffix(" on twitter")
            || lower.contains(" on x:") || lower.contains(" on twitter:")
            || lower.hasSuffix(" / x") || lower.hasSuffix(" / twitter") {
            return true
        }
        if lower.contains(" on instagram:") || lower.hasSuffix(" on instagram")
            || lower.contains("• instagram") || lower.hasSuffix("| instagram") {
            return true
        }
        if lower.hasPrefix("behance ::") || lower.hasPrefix("dribbble -") || lower.hasPrefix("dribbble |") {
            return true
        }
        if lower.hasPrefix("pin on ") || lower.hasPrefix("pin by ") { return true }
        return false
    }

    private static let workTitleSuffixes = [
        " on Behance", " :: Behance", " | Behance", " - Behance",
        " on Dribbble", " | Dribbble", " - Dribbble",
        " | Pinterest", " - Pinterest",
    ]

    /// A real work title with the platform boilerplate removed: "Brand identity on Behance"
    /// → "Brand identity", "Lamp by Jane on Dribbble" → "Lamp". Unchanged otherwise.
    static func strippedWorkTitle(_ title: String) -> String {
        if let work = parseDribbbleTitle(title).work { return work }
        for suffix in workTitleSuffixes where title.lowercased().hasSuffix(suffix.lowercased()) {
            let stripped = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? title : stripped
        }
        return title
    }

    /// The Post title rule. A real (non-generic) `currentTitle` is kept, minus platform
    /// boilerplate. A generic one becomes "@handle: first ~8 words…" (the author's name when
    /// there is no handle; no ellipsis when the text is short). No text → `currentTitle`.
    static func postTitle(currentTitle: String?, handle: String?, authorName: String?, text: String?) -> String? {
        let current = clean(currentTitle)
        if let current, !isGenericPostTitle(current) { return strippedWorkTitle(current) }
        guard let excerpt = textExcerpt(text) else { return current }
        guard let prefix = clean(handle).map({ "@\($0)" }) ?? clean(authorName) else { return excerpt }
        return "\(prefix): \(excerpt)"
    }

    /// First `titleWordCount` words of the text (links dropped), "…" only when cut.
    static func textExcerpt(_ text: String?) -> String? {
        guard let text = clean(text) else { return nil }
        let withoutLinks = text.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        let words = withoutLinks.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        if words.count <= titleWordCount { return words.joined(separator: " ") }
        var head = words.prefix(titleWordCount).joined(separator: " ")
        while let last = head.last, ",;:-–—".contains(last) { head.removeLast() }
        return head + "…"
    }

    /// Collection labels / tags that flag an (already Post) item as AI art.
    static let aiArtLabels: Set<String> = [
        "midjourney", "gen-ai", "ai-art", "stable-diffusion", "dall-e", "nijijourney",
    ]

    /// Midjourney parameters (`--ar`, `--v `, `--style`, `--sref`, `--niji`, `--chaos`,
    /// `--stylize`); an em dash counts too (iOS smart punctuation turns `--` into `—`).
    /// A parameter only counts when a value follows it on the same line (`--ar 16:9`,
    /// `--sref 123`, `--v 6`) or it ends the line / text (`--niji`) — never prose such as
    /// "the --sref's" or "--sref,".
    static let midjourneyParamPattern =

    /// "Gen AI" / "gen_ai" / "GEN-AI" → "gen-ai".
    static func normalizedLabel(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    static func hasMidjourneyParams(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return text.range(of: midjourneyParamPattern, options: .regularExpression) != nil
    }

    static func modelName(forLabel key: String) -> String? {
        switch key {
        case "midjourney", "nijijourney": return "Midjourney"
        case "stable-diffusion": return "Stable Diffusion"
        case "dall-e": return "DALL·E"
        default: return nil
        }
    }

    /// AI art from labels / tags / Midjourney params in the text; the model from the label,
    /// the params ("Midjourney"), or a model named in the text; nil when nothing names one.
    static func aiArtSignal(labels: [String], tags: [String], text: String?) -> AIArtSignal {
        var isAIArt = false
        var model: String?
        for name in labels + tags {
            let key = normalizedLabel(name)
            guard aiArtLabels.contains(key) else { continue }
            isAIArt = true
            if model == nil { model = modelName(forLabel: key) }
        }
        if hasMidjourneyParams(text) {
            isAIArt = true
            if model == nil { model = "Midjourney" }
        }
        guard isAIArt else { return AIArtSignal(isAIArt: false, model: nil) }
        if model == nil, let lower = text?.lowercased() {
            if lower.contains("midjourney") || lower.contains("nijijourney") || lower.contains("niji") {
                model = "Midjourney"
            } else if lower.contains("stable diffusion") || lower.contains("stable-diffusion") {
                model = "Stable Diffusion"
            } else if lower.contains("dall-e") || lower.contains("dall·e") || lower.contains("dalle") {
                model = "DALL·E"
            }
        }
        return AIArtSignal(isAIArt: true, model: model)
    }

    private static let promptLabelRegex = try? NSRegularExpression(
        pattern: #"\bprompt\s*(?::|—|–|-)+\s*(.+)$"#,
        options: [.caseInsensitive, .anchorsMatchLines]
    )

    private static let sentenceBreakRegex = try? NSRegularExpression(
        pattern: #"[.!?]\s+"#,
        options: []
    )

    /// Rule-read prompt: the text after "prompt:" / "Prompt —", else the sentence that
    /// carries Midjourney params (from its start through the params). Nil when neither.
    static func extractPrompt(from text: String?) -> String? {
        guard let text = clean(text) else { return nil }
        if let regex = promptLabelRegex,
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text),
           let prompt = cleanPrompt(String(text[r])) {
            return prompt
        }
        return paramsSentence(in: text)
    }

    private static func paramsSentence(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let line = String(line)
            guard let param = line.range(of: midjourneyParamPattern, options: .regularExpression) else { continue }
            var start = line.startIndex
            let head = String(line[..<param.lowerBound])
            if let regex = sentenceBreakRegex,
               let last = regex.matches(in: head, range: NSRange(head.startIndex..., in: head)).last,
               let r = Range(last.range, in: head) {
                start = line.index(line.startIndex, offsetBy: head.distance(from: head.startIndex, to: r.upperBound))
            }
            if let prompt = cleanPrompt(String(line[start...])) { return prompt }
        }
        return nil
    }

    /// Trims whitespace and wrapping quotes; nil when nothing is left.
    static func cleanPrompt(_ raw: String?) -> String? {
        guard let raw = clean(raw) else { return nil }
        return ProductReader.cleanCaption(raw)
    }

    /// Recomputes the AI-art flag and model from the current labels, tags and text (the
    /// signal is deterministic, so a removed label clears it), and rule-reads the prompt —
    /// a rule-read prompt replaces an earlier guess, never the other way round. Only call
    /// this on items that are already Post: labels never decide the kind.
    static func applyAIArt(to meta: inout PostMeta, labels: [String], tags: [String]) {
        let signal = aiArtSignal(labels: labels, tags: tags, text: meta.text)
        meta.isAIArt = signal.isAIArt
        meta.aiModel = signal.model
        guard signal.isAIArt else { return }
        if meta.prompt == nil || meta.promptIsGuess, let read = extractPrompt(from: meta.text) {
            meta.prompt = read
            meta.promptIsGuess = false
        }
    }

    static func clean(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
