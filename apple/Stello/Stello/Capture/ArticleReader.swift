import Foundation

// MARK: - Types

/// Summary + tech stack from the on-device article job (`Enricher.summarizeArticle`). The
/// summary is stored with `ArticleMeta.summaryIsGuess == true`; the tech stack is kept only
/// for tutorials.
nonisolated struct ArticleFacts: Sendable, Equatable {
    var summary: String?
    var techStack: [String] = []
}

// MARK: - ArticleReader

/// Pure, network-free article readers: Article-family JSON-LD (author, publisher,
/// datePublished), meta tags (og:site_name, author, article:author, article:published_time,
/// twitter "Written by"), the date in the URL path, and reading time from the page text.
/// Everything comes from the capture-time page fetch — no extra network.
nonisolated enum ArticleReader {

    /// Words per minute for the reading-time estimate.
    static let wordsPerMinute = 230

    /// Most tech-stack names kept (model or rule-based).
    static let maxTechStack = 5

    // MARK: - Meta tags

    nonisolated struct PageTags: Sendable {
        var siteName: String?
        var author: String?
        var articleAuthor: String?
        var publishedTime: String?
        var twitterLabel1: String?
        var twitterData1: String?
    }

    static func pageTags(html: String) -> PageTags {
        var tags = PageTags()
        guard !html.isEmpty else { return tags }
        for attrs in CaptureService.metaTagAttributes(in: html) {
            guard let content = ToolReader.clean(attrs["content"]) else { continue }
            let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            switch key {
            case "og:site_name": if tags.siteName == nil { tags.siteName = content }
            case "author": if tags.author == nil { tags.author = content }
            case "article:author": if tags.articleAuthor == nil { tags.articleAuthor = content }
            case "article:published_time": if tags.publishedTime == nil { tags.publishedTime = content }
            case "twitter:label1": if tags.twitterLabel1 == nil { tags.twitterLabel1 = content }
            case "twitter:data1": if tags.twitterData1 == nil { tags.twitterData1 = content }
            default: break
            }
        }
        return tags
    }

    // MARK: - JSON-LD

    /// The first Article-family node, else the first node carrying an author / publisher /
    /// datePublished (a WebPage with article fields).
    static func articleNode(html: String) -> [String: Any]? {
        guard !html.isEmpty else { return nil }
        let nodes = PageClassifier.jsonLDNodes(from: html)
        if let node = nodes.first(where: { $0.types.contains(where: PageClassifier.isArticleType) }) {
            return node.dict
        }
        return nodes.first(where: {
            $0.dict["author"] != nil || $0.dict["datePublished"] != nil || $0.dict["publisher"] != nil
        })?.dict
    }

    // MARK: - Author

    /// JSON-LD `author` (string, `{name, url}` object or array → first named), else meta
    /// `author`, else `article:author` when it isn't a URL, else `twitter:data1` when
    /// `twitter:label1` is "Written by". URL-only values are never a name.
    static func author(node: [String: Any]?, tags: PageTags, base: URL) -> EntityRef? {
        if let node, var ref = ResourceReader.makerRef(from: node["author"], base: base), !looksLikeURL(ref.name) {
            ref.kind = ItemKind.individual.rawValue
            return ref
        }
        for candidate in [tags.author, tags.articleAuthor] {
            if let name = candidate, !looksLikeURL(name) { return authorRef(name) }
        }
        if tags.twitterLabel1?.lowercased() == "written by", let name = tags.twitterData1, !looksLikeURL(name) {
            return authorRef(name)
        }
        return nil
    }

    static func authorRef(_ name: String) -> EntityRef {
        EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
    }

    static func looksLikeURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.")
    }

    // MARK: - Publication

    /// og:site_name, else JSON-LD `publisher.name`, else the host without `www.`.
    static func publication(node: [String: Any]?, tags: PageTags, url: URL) -> String? {
        if let site = tags.siteName { return site }
        if let node, let name = ProductReader.brandName(from: node["publisher"]) { return name }
        return ProductReader.bareHost(url)
    }

    // MARK: - Dates

    /// JSON-LD `datePublished`, else `article:published_time`, else the URL path date.
    static func publishedAt(node: [String: Any]?, tags: PageTags, url: URL) -> Date? {
        if let node, let date = parseDate(ProductReader.string(node["datePublished"])) { return date }
        if let date = parseDate(tags.publishedTime) { return date }
        return urlDate(url)
    }

    /// ISO 8601: full date-time (with or without fractional seconds / zone), or a bare date.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw = ToolReader.clean(raw) else { return nil }
        if let date = ToolReader.parseISODate(raw) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if raw.count == 10, let date = iso.date(from: raw) { return date }
        // "2025-03-11T09:30:00" (no zone) — read as UTC.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        if raw.count > 10, let date = iso.date(from: String(raw.prefix(10))) { return date }
        return nil
    }

    /// The URL path date (`/2025/Mar/11/…`, `/2020/06/…`) at 12:00 UTC — midday, so the
    /// day reads the same in every time zone; the 1st when the path names no day.
    static func urlDate(_ url: URL) -> Date? {
        guard let parts = PageClassifier.urlPathDate(url) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(
            year: parts.year, month: parts.month, day: parts.day ?? 1, hour: 12
        ))
    }

    // MARK: - Reading time

    /// Words ÷ 230, rounded up, at least 1; nil when there is no text.
    static func readingMinutes(text: String?) -> Int? {
        guard let text else { return nil }
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0 else { return nil }
        return max(1, (words + wordsPerMinute - 1) / wordsPerMinute)
    }

    // MARK: - Tutorial

    /// Codrops (tympanus.net), a `tutorial` / `tutorials` path segment, or a title that starts
    /// with "How to" / "Tutorial".
    static func isTutorial(url: URL, title: String?) -> Bool {
        if ProductReader.bareHost(url) == "tympanus.net" { return true }
        let parts = url.path.lowercased().split(separator: "/")
        if parts.contains("tutorial") || parts.contains("tutorials") { return true }
        guard let lower = ToolReader.clean(title)?.lowercased() else { return false }
        return lower.hasPrefix("how to") || lower.hasPrefix("tutorial")
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

    // MARK: - Build

    /// Assembles `ArticleMeta` for one article page. `pageText` is the page's full plain text
    /// (`CaptureService.extractText(html:limit: nil)`) for the reading time; `ogTitle` only
    /// decides the tutorial flag. The summary and tech stack come later from the on-device job.
    static func build(
        sourceURL: URL,
        finalURL: URL?,
        html: String,
        ogTitle: String?,
        pageText: String?
    ) -> ArticleMeta {
        var meta = ArticleMeta()
        let url = finalURL ?? sourceURL
        let tags = pageTags(html: html)
        let node = articleNode(html: html)

        meta.publication = publication(node: node, tags: tags, url: sourceURL)
        meta.author = author(node: node, tags: tags, base: url)
        meta.publishedAt = publishedAt(node: node, tags: tags, url: sourceURL)
            ?? finalURL.flatMap { urlDate($0) }
        meta.readingMinutes = readingMinutes(text: pageText)
        meta.isTutorial = isTutorial(url: sourceURL, title: ogTitle)
            || (finalURL.map { isTutorial(url: $0, title: nil) } ?? false)

        if let finalURL, finalURL.absoluteString != sourceURL.absoluteString {
            meta.canonicalURL = finalURL.absoluteString
        }
        return meta
    }

    // MARK: - On-device digest

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

    // MARK: - Refresh merge

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
