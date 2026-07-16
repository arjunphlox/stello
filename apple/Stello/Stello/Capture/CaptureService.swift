import Foundation
import SwiftData
import ImageIO

// MARK: - Types

enum CaptureInput {
    case url(URL)
    case text(String)
    case image(Data)
}

struct OGResult {
    var title: String?
    var description: String?
    var imageURL: URL?
    var ogType: String?
}

struct PageFetchResult {
    var html: String
    var og: OGResult
}

// MARK: - CaptureService

enum CaptureService {

    // MARK: - Shared HTML parsing regexes

    /// Matches a `<meta ...>` tag, capturing its attribute string. Shared with PageClassifier.
    nonisolated static let metaTagRegex = try? NSRegularExpression(
        pattern: #"<meta\s+([^>]*)>"#,
        options: .caseInsensitive
    )

    /// Matches `key="value"` / `key='value'` / `key=value` attribute pairs. Shared with PageClassifier.
    nonisolated static let htmlAttrRegex = try? NSRegularExpression(
        pattern: #"([\w:.-]+)\s*=\s*(?:"([^"]*?)"|'([^']*?)'|([^\s>]+))"#,
        options: .caseInsensitive
    )

    /// Parses an attribute string (the captured group from `metaTagRegex`/an opening tag) into a
    /// lowercase-keyed dictionary. Shared with PageClassifier to avoid duplicating the regex.
    nonisolated static func parseAttributes(_ attrsStr: String) -> [String: String] {
        guard let attrRegex = htmlAttrRegex else { return [:] }
        var attrs: [String: String] = [:]
        let nsAttrs = attrsStr as NSString
        for match in attrRegex.matches(in: attrsStr, range: NSRange(location: 0, length: nsAttrs.length)) {
            guard let keyRange = Range(match.range(at: 1), in: attrsStr) else { continue }
            let key = String(attrsStr[keyRange]).lowercased()
            var value = ""
            for group in 2...4 {
                let range = match.range(at: group)
                if range.location != NSNotFound, let valueRange = Range(range, in: attrsStr) {
                    value = String(attrsStr[valueRange])
                    break
                }
            }
            attrs[key] = value
        }
        return attrs
    }

    /// Parses all `<meta ...>` tags in `html` into per-tag attribute dictionaries. Shared with PageClassifier.
    static func metaTagAttributes(in html: String) -> [[String: String]] {
        guard let metaRegex = metaTagRegex else { return [] }
        let nsHTML = html as NSString
        return metaRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).compactMap { match in
            guard let attrRange = Range(match.range(at: 1), in: html) else { return nil }
            return parseAttributes(String(html[attrRange]))
        }
    }

    // MARK: - Input Classification

    /// Inspects text and returns capture inputs in order.
    /// One or more URL matches → each becomes .url; no URL + length > 5 → .text.
    static func classify(text: String) -> [CaptureInput] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#) else {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.count > 5 ? [.text(t)] : []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        if matches.isEmpty {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.count > 5 ? [.text(t)] : []
        }

        return matches.compactMap { m -> CaptureInput? in
            guard let r = Range(m.range, in: text),
                  let url = URL(string: String(text[r])) else { return nil }
            return .url(url)
        }
    }

    // MARK: - URL Capture

    @discardableResult
    static func captureURL(_ url: URL, context: ModelContext) async throws -> Item {
        // Dedup by normalized URL
        let normalized = normalizeURL(url)
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.sourceURL == normalized }
        )
        if let existing = try? context.fetch(descriptor), let first = existing.first {
            return first
        }

        let page = await fetchPage(url: url)
        let og = page?.og ?? OGResult()
        let html = page?.html ?? ""
        let ogTitle = og.title ?? url.host ?? url.absoluteString
        let summary = og.description.map { String($0.prefix(200)) }
        let dom = domain(from: url)

        let classification = PageClassifier.classify(
            html: html,
            baseURL: url,
            domain: dom,
            title: ogTitle,
            ogDescription: og.description,
            ogType: og.ogType
        )

        // Music classification: deterministic host/og:type match (no extra network beyond
        // the page fetch above), or — for plain youtube.com/youtu.be — a confirmed oEmbed
        // signal. Only attempted when the generic classifier left the page as `link`.
        var kind = classification.kind
        var musicResult: MusicExtractionResult? = nil
        if kind == .link {
            musicResult = await classifyAndExtractMusic(
                sourceURL: url, domain: dom, title: ogTitle, ogType: og.ogType, page: page
            )
            if musicResult != nil { kind = .music }
        }

        let title: String
        if let raw = musicResult?.rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            title = raw
        } else {
            title = ogTitle
        }
        // Music items never carry page prose — no snippets/why-saved job has one to work from.
        let extracted = musicResult != nil ? nil : extractText(html: html)

        var itemImage: ItemImage? = nil
        if let musicResult {
            var downloaded: (Data, Int, Int)? = nil
            if let coverURL = musicResult.coverImageURL {
                downloaded = await downloadImage(url: coverURL)
            }
            if downloaded == nil, let fallbackURL = musicResult.coverFallbackURL {
                downloaded = await downloadImage(url: fallbackURL)
            }
            if let (data, w, h) = downloaded {
                itemImage = ItemImage(data: data, source: "og", isPrimary: true, width: w, height: h)
            }
        } else if let imgURL = og.imageURL, let (data, w, h) = await downloadImage(url: imgURL) {
            itemImage = ItemImage(data: data, source: "og", isPrimary: true, width: w, height: h)
        }

        let slug = makeSlug(from: title, context: context)
        let tagSpecs = RuleTagger.generateTags(title: title, description: summary, domain: dom)

        let item = Item(
            slug: slug, title: title, sourceURL: normalized, domain: dom,
            summary: summary, extractedText: extracted, enrichmentStatus: "text_done",
            kind: kind.rawValue
        )
        if let meta = classification.individualMeta {
            item.setMetadata(meta)
        }
        if let musicResult {
            item.setMetadata(musicResult.meta)
        }
        context.insert(item)

        if let img = itemImage {
            context.insert(img)
            img.item = item
        }

        for spec in tagSpecs {
            let tag = Tag(name: spec.name, category: spec.category, weight: spec.weight)
            context.insert(tag)
            tag.item = item
        }

        try context.save()
        return item
    }

    // MARK: - Text Capture

    @discardableResult
    static func captureText(_ text: String, context: ModelContext) throws -> Item {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let title = words.prefix(5).joined(separator: " ")
        let summary = String(text.prefix(200))

        let slug = makeSlug(from: title, context: context)
        let tagSpecs = RuleTagger.generateTags(title: title, description: summary, domain: nil)

        let item = Item(slug: slug, title: title, summary: summary, enrichmentStatus: "text_done")
        context.insert(item)

        for spec in tagSpecs {
            let tag = Tag(name: spec.name, category: spec.category, weight: spec.weight)
            context.insert(tag)
            tag.item = item
        }

        try context.save()
        return item
    }

    // MARK: - Image Capture

    @discardableResult
    static func captureImage(_ data: Data, context: ModelContext) throws -> Item {
        let (w, h) = imageDimensions(data: data)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let title = "Image upload — \(formatter.string(from: Date()))"

        let slug = makeSlug(from: title, context: context)

        let item = Item(slug: slug, title: title, enrichmentStatus: "text_done")
        context.insert(item)

        let img = ItemImage(data: data, source: "manual", isPrimary: true, width: w, height: h)
        context.insert(img)
        img.item = item

        let tag = Tag(name: "image-upload", category: "format", weight: 0.4)
        context.insert(tag)
        tag.item = item

        try context.save()
        return item
    }

    // MARK: - OG Fetching

    static func fetchPage(url: URL) async -> PageFetchResult? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        // Read the (nearly) whole document, not a 50KB head-slice: real pages put og:image
        // deep — measured 2026-07-16: midday.ai at byte ~238k of 986k, fonts.google.com at
        // ~196k of 198k — and a mid-tag truncation also leaves <style>/<script> blocks
        // unterminated, which defeats extractText's stripping (CSS leaked into snippets).
        // 2MB bounds memory; beyond that a page is not going to yield better metadata.
        let slice = data.prefix(2_000_000)
        guard let html = String(data: slice, encoding: .utf8)
                      ?? String(data: slice, encoding: .isoLatin1) else { return nil }
        return PageFetchResult(html: html, og: parseOG(html: html, baseURL: url))
    }

    static func fetchOG(url: URL) async -> OGResult {
        await fetchPage(url: url)?.og ?? OGResult()
    }

    /// Parses OG/Twitter meta tags order-independently (no assumption on attribute order within a tag).
    static func parseOG(html: String, baseURL: URL) -> OGResult {
        var result = OGResult()
        let nsHTML = html as NSString

        for attrs in metaTagAttributes(in: html) {
            let property = attrs["property"] ?? ""
            let name = attrs["name"] ?? ""
            let content = attrs["content"] ?? ""

            switch property {
            case "og:title":        if result.title == nil { result.title = content }
            case "og:description":  if result.description == nil { result.description = content }
            case "og:image":        if result.imageURL == nil { result.imageURL = resolve(content, base: baseURL) }
            case "og:type":         if result.ogType == nil { result.ogType = content }
            case "twitter:image":   if result.imageURL == nil { result.imageURL = resolve(content, base: baseURL) }
            default: break
            }
            switch name {
            case "description":     if result.description == nil { result.description = content }
            case "twitter:image":   if result.imageURL == nil { result.imageURL = resolve(content, base: baseURL) }
            default: break
            }
        }

        // <title> fallback when og:title is absent.
        if result.title == nil,
           let titleRe = try? NSRegularExpression(
               pattern: #"<title[^>]*>([^<]+)</title>"#, options: .caseInsensitive
           ),
           let m = titleRe.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)),
           let r = Range(m.range(at: 1), in: html) {
            result.title = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    // MARK: - Plain-Text Extraction

    /// Readability-lite plain-text extraction from raw page HTML: drops `<script>`/`<style>`
    /// blocks and all remaining tags, decodes the common HTML entities, collapses whitespace,
    /// and caps the result at ~4,000 characters — the on-device model's context is small, so
    /// this is what AI enrichment (and search) sees instead of just title+summary.
    static func extractText(html: String) -> String? {
        guard !html.isEmpty else { return nil }
        var text = html
        // Prefer body content: everything before <body> is metadata/CSS/JS, never prose.
        if let bodyRange = text.range(of: "<body", options: .caseInsensitive) {
            text = String(text[bodyRange.lowerBound...])
        }
        // Strip container blocks whose CONTENT is never prose. The trailing `|$` variant
        // also swallows unterminated blocks (a truncated page once leaked raw Tailwind CSS
        // into snippets because its </style> was cut off).
        for tag in ["script", "style", "noscript", "svg", "template"] {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?(</\(tag)>|$)",
                with: " ", options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = decodeBasicEntities(text)
        // Scrub CSS/JS residue that survives tag-stripping (custom properties, rule bodies).
        text = text.replacingOccurrences(
            of: #"--[A-Za-z0-9_-]+\s*:[^;{}]{0,120};?"#, with: " ", options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Word-level prose filter: drop tokens that read as code (braces/semicolons/
        // assignments) or as un-prose-like runs (very long unbroken identifiers/URLs).
        let words = text.split(separator: " ").filter { word in
            word.count <= 40 && !word.contains("{") && !word.contains("}")
                && !word.contains(";") && !word.contains("=") && !word.hasPrefix("--")
        }
        text = words.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return String(text.prefix(4_000))
    }

    private static let basicEntities: [(String, String)] = [
        ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ("&mdash;", "—"), ("&ndash;", "–"),
        ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"),
    ]

    private static func decodeBasicEntities(_ s: String) -> String {
        var result = s
        for (entity, replacement) in basicEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    // MARK: - Image Download

    static func downloadImage(url: URL) async -> (Data, Int, Int)? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (raw, _) = try? await URLSession.shared.data(for: request),
              raw.count >= 500 else { return nil }
        let processed = downsizeIfNeeded(data: raw, maxDimension: 2000) ?? raw
        let (w, h) = imageDimensions(data: processed)
        return (processed, w, h)
    }

    // MARK: - Slug

    /// Pure slug generator — accepts an isUnique closure so it's testable without SwiftData.
    static func makeSlug(from title: String, isUnique: (String) -> Bool) -> String {
        let base = title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        let root = base
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let rootOrFallback = root.isEmpty ? "item" : root

        var candidate = rootOrFallback
        var n = 2
        while !isUnique(candidate) {
            candidate = "\(rootOrFallback)-\(n)"
            n += 1
        }
        return candidate
    }

    /// SwiftData-backed overload: checks existing Item.slug values via ModelContext.
    static func makeSlug(from title: String, context: ModelContext) -> String {
        makeSlug(from: title) { slug in
            let descriptor = FetchDescriptor<Item>(
                predicate: #Predicate<Item> { $0.slug == slug }
            )
            return (try? context.fetch(descriptor).isEmpty) ?? true
        }
    }

    // MARK: - Image Helpers

    static func imageDimensions(data: Data) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return (0, 0) }
        return (w, h)
    }

    private static func downsizeIfNeeded(data: Data, maxDimension: Int) -> Data? {
        let (w, h) = imageDimensions(data: data)
        guard max(w, h) > maxDimension,
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    // MARK: - Music Extraction

    struct MusicExtractionResult {
        var meta: MusicMeta
        var coverImageURL: URL?
        /// YouTube-only: `hqdefault` retry when `coverImageURL` (maxresdefault) 404s or is
        /// undersized — `downloadImage` already floors at 500 bytes, so a failed maxres
        /// naturally falls through here.
        var coverFallbackURL: URL?
        var rawTitle: String?
    }

    struct OEmbedResponse: Decodable {
        var title: String?
        var authorName: String?
        var thumbnailURL: String?
        var html: String?
        var iframeURL: String?

        // Explicit keys (not `.convertFromSnakeCase`, which would produce "thumbnailUrl" —
        // lowercase "rl" — and silently fail to match the all-caps "URL" property names).
        enum CodingKeys: String, CodingKey {
            case title, html
            case authorName = "author_name"
            case thumbnailURL = "thumbnail_url"
            case iframeURL = "iframe_url"
        }
    }

    struct DeezerSearchResponse: Decodable {
        var data: [DeezerSearchResult]
    }
    struct DeezerSearchResult: Decodable {
        var id: Int
    }
    struct DeezerAlbumResponse: Decodable {
        var title: String?
        var upc: String?
        var releaseDate: String?
        var label: String?
        var genres: DeezerGenres?
        var tracks: DeezerTracksWrapper?
    }
    struct DeezerGenres: Decodable {
        var data: [DeezerGenre]
    }
    struct DeezerGenre: Decodable {
        var name: String
    }
    struct DeezerTracksWrapper: Decodable {
        var data: [DeezerTrackEntry]
    }
    struct DeezerTrackEntry: Decodable {
        var title: String
        var duration: Int?
    }

    private static let musicTitleDescriptorWords: Set<String> = [
        "video", "audio", "song", "official", "video song", "full video", "full song",
        "lyrical", "lyrical video", "music video", "official video", "official audio",
    ]

    private static let musicEditionKeywords = [
        "remaster", "edition", "version", "deluxe", "anniversary", "live", "mono", "stereo",
        "reissue", "expanded",
    ]

    private static let editionSuffixRegex = try? NSRegularExpression(
        pattern: #"\s*\(([^)]+)\)\s*$"#, options: []
    )

    private static let curatorByRegex = try? NSRegularExpression(
        pattern: #"\bby\s+(.+)$"#, options: .caseInsensitive
    )

    private static let oembedSrcRegex = try? NSRegularExpression(
        pattern: #"src=["']([^"']+)["']"#, options: .caseInsensitive
    )

    struct RuleParsedMusicTitle {
        var artist: String?
        var track: String?
        var film: String?
    }

    /// Deterministic classification (host / og:type) + best-effort structured extraction for
    /// music platforms. Returns nil when the URL/page doesn't classify as music — callers
    /// must leave `kind` untouched in that case. Plain `youtube.com`/`youtu.be` requires an
    /// oEmbed round-trip to confirm (author ends " - Topic"/"VEVO", or the title reads as a
    /// music upload); every other platform classifies from `domain`/`ogType` alone.
    static func classifyAndExtractMusic(
        sourceURL: URL,
        domain host: String?,
        title: String?,
        ogType: String?,
        page: PageFetchResult?
    ) async -> MusicExtractionResult? {
        guard let host else { return nil }

        var resolvedPlatform = PageClassifier.musicPlatform(forHost: host)
        var youTubeOEmbed: OEmbedResponse? = nil

        if resolvedPlatform == nil {
            if PageClassifier.isPlainYouTubeHost(host) {
                youTubeOEmbed = await fetchOEmbed(youtubeOEmbedURL(for: sourceURL))
                guard PageClassifier.isMusicYouTubeSignal(
                    authorName: youTubeOEmbed?.authorName,
                    title: youTubeOEmbed?.title ?? title
                ) else { return nil }
                resolvedPlatform = "youtube"
            } else if PageClassifier.isMusicOGType(ogType) {
                resolvedPlatform = "unknown"
            } else {
                return nil
            }
        }

        guard let platform = resolvedPlatform else { return nil }
        let subtype = PageClassifier.musicSubtype(url: sourceURL, ogType: ogType, platform: platform)

        var meta = MusicMeta()
        meta.subtype = subtype
        meta.platform = platform
        meta.canonicalURL = sourceURL.absoluteString

        var rawTitle = title
        var coverURL: URL? = nil
        var coverFallbackURL: URL? = nil

        switch platform {
        case "apple-music", "deezer", "bandcamp", "unknown":
            // Direct page fetch already happened by the time we get here (capture-time
            // fetch, or the force-enrich refetch) — bot-friendly hosts, no extra network.
            if let page {
                rawTitle = page.og.title ?? rawTitle
                coverURL = page.og.imageURL
                applyMusicJSONLD(html: page.html, to: &meta)
            }

        case "spotify":
            if let response = await fetchOEmbed(URL(string: "https://open.spotify.com/oembed?url=\(percentEncodeForMusic(sourceURL.absoluteString))")) {
                rawTitle = response.title ?? rawTitle
                coverURL = response.thumbnailURL.flatMap { URL(string: $0) }
                meta.embedURL = embedURL(from: response)
            }

        case "youtube", "youtube-music":
            let response = youTubeOEmbed ?? (await fetchOEmbed(youtubeOEmbedURL(for: sourceURL)))
            if let response {
                rawTitle = response.title ?? rawTitle
                meta.embedURL = embedURL(from: response)
                if let author = response.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                    let cleaned = author
                        .replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        meta.artists = [EntityRef(name: cleaned, slug: nil, kind: ItemKind.individual.rawValue)]
                    }
                }
            }
            if let videoID = youtubeVideoID(from: sourceURL) {
                coverURL = URL(string: "https://i.ytimg.com/vi/\(videoID)/maxresdefault.jpg")
                coverFallbackURL = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
            }

        case "tidal":
            if let response = await fetchOEmbed(URL(string: "https://oembed.tidal.com/?url=\(percentEncodeForMusic(sourceURL.absoluteString))")) {
                rawTitle = response.title ?? rawTitle
                coverURL = response.thumbnailURL.flatMap { URL(string: $0) }
                meta.embedURL = embedURL(from: response)
            }

        case "mixcloud":
            if let response = await fetchOEmbed(URL(string: "https://app.mixcloud.com/oembed/?url=\(percentEncodeForMusic(sourceURL.absoluteString))&format=json")) {
                rawTitle = response.title ?? rawTitle
                coverURL = response.thumbnailURL.flatMap { URL(string: $0) }
                meta.embedURL = embedURL(from: response)
                if let author = response.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                    meta.artists = [EntityRef(name: author, slug: nil, kind: ItemKind.individual.rawValue)]
                }
            }

        case "soundcloud":
            if let response = await fetchOEmbed(URL(string: "https://soundcloud.com/oembed?url=\(percentEncodeForMusic(sourceURL.absoluteString))&format=json")) {
                rawTitle = response.title ?? rawTitle
                coverURL = response.thumbnailURL.flatMap { URL(string: $0) }
                meta.embedURL = embedURL(from: response)
                if let author = response.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                    meta.artists = [EntityRef(name: author, slug: nil, kind: ItemKind.individual.rawValue)]
                }
            }

        default:
            break
        }

        applyRuleTitleParsing(rawTitle: rawTitle, platform: platform, to: &meta)
        applyCurator(rawTitle: rawTitle, description: page?.og.description, subtype: subtype, to: &meta)

        // Cross-platform resolver — one search + one detail call, best-effort, silent on failure.
        if let searchTitle = (meta.cleanTitle ?? rawTitle)?.trimmingCharacters(in: .whitespacesAndNewlines), !searchTitle.isEmpty {
            if let deezer = await deezerResolve(artist: meta.artists.first?.name, title: searchTitle) {
                applyDeezerData(deezer, to: &meta)
            }
        }

        return MusicExtractionResult(
            meta: meta, coverImageURL: coverURL, coverFallbackURL: coverFallbackURL, rawTitle: rawTitle
        )
    }

    // MARK: - Music: oEmbed

    private static func percentEncodeForMusic(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func youtubeOEmbedURL(for url: URL) -> URL? {
        URL(string: "https://www.youtube.com/oembed?url=\(percentEncodeForMusic(url.absoluteString))&format=json")
    }

    private static func fetchOEmbed(_ endpoint: URL?) async -> OEmbedResponse? {
        guard let endpoint else { return nil }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        // OEmbedResponse declares explicit snake_case CodingKeys — default key strategy.
        return try? JSONDecoder().decode(OEmbedResponse.self, from: data)
    }

    private static func embedURL(from oembed: OEmbedResponse) -> String? {
        if let iframeURL = oembed.iframeURL, !iframeURL.isEmpty { return iframeURL }
        guard let html = oembed.html, let regex = oembedSrcRegex else { return nil }
        let ns = html as NSString
        guard let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    private static func youtubeVideoID(from url: URL) -> String? {
        if let host = url.host?.lowercased(), host.contains("youtu.be") {
            let comps = url.pathComponents.filter { $0 != "/" }
            return comps.first
        }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return comps.queryItems?.first(where: { $0.name == "v" })?.value
    }

    // MARK: - Music: Deezer resolver

    /// Best-effort cross-platform lookup — exactly one search call + one detail call, silent
    /// on any failure (never blocks the rest of the pipeline).
    private static func deezerResolve(artist: String?, title: String) async -> DeezerAlbumResponse? {
        let query = [artist, title].compactMap { $0 }.joined(separator: " ")
        guard let searchURL = URL(string: "https://api.deezer.com/search/album?q=\(percentEncodeForMusic(query))") else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let (searchData, _) = try? await URLSession.shared.data(for: URLRequest(url: searchURL, timeoutInterval: 10)),
              let searchResult = try? decoder.decode(DeezerSearchResponse.self, from: searchData),
              let albumID = searchResult.data.first?.id,
              let albumURL = URL(string: "https://api.deezer.com/album/\(albumID)") else { return nil }

        guard let (albumData, _) = try? await URLSession.shared.data(for: URLRequest(url: albumURL, timeoutInterval: 10)) else { return nil }
        return try? decoder.decode(DeezerAlbumResponse.self, from: albumData)
    }

    static func applyDeezerData(_ deezer: DeezerAlbumResponse, to meta: inout MusicMeta) {
        if meta.upc == nil { meta.upc = deezer.upc }
        if meta.label == nil { meta.label = deezer.label }
        if meta.releaseYear == nil, let releaseDate = deezer.releaseDate, releaseDate.count >= 4 {
            meta.releaseYear = String(releaseDate.prefix(4))
        }
        if meta.genres.isEmpty, let names = deezer.genres?.data.map(\.name), !names.isEmpty {
            meta.genres = names
        }
        if meta.trackList.isEmpty, let tracks = deezer.tracks?.data, !tracks.isEmpty {
            meta.trackList = tracks.map { MusicTrackEntry(name: $0.title, durationSeconds: $0.duration) }
            let total = meta.trackList.compactMap(\.durationSeconds).reduce(0, +)
            meta.totalDurationSeconds = total > 0 ? total : nil
        }
    }

    // MARK: - Music: JSON-LD (Apple Music / Deezer / Bandcamp direct-fetch platforms)

    private static func applyMusicJSONLD(html: String, to meta: inout MusicMeta) {
        for node in PageClassifier.jsonLDNodes(from: html) {
            let types = node.types
            let dict = node.dict

            if types.contains(where: { $0.caseInsensitiveCompare("MusicAlbum") == .orderedSame }) {
                if meta.cleanTitle == nil, let name = dict["name"] as? String { meta.cleanTitle = name }
                if meta.genres.isEmpty { meta.genres = musicStringArray(dict["genre"]) }
                if meta.releaseYear == nil, let date = dict["datePublished"] as? String, date.count >= 4 {
                    meta.releaseYear = String(date.prefix(4))
                }
                if meta.label == nil {
                    if let labelDict = dict["recordLabel"] as? [String: Any], let name = labelDict["name"] as? String {
                        meta.label = name
                    } else if let labelString = dict["recordLabel"] as? String {
                        meta.label = labelString
                    }
                }
                if meta.artists.isEmpty, let byArtist = dict["byArtist"] {
                    meta.artists = musicEntityRefs(from: byArtist)
                }
                if meta.trackList.isEmpty, let trackNodes = dict["track"] {
                    meta.trackList = musicTrackEntries(from: trackNodes)
                    let total = meta.trackList.compactMap(\.durationSeconds).reduce(0, +)
                    meta.totalDurationSeconds = total > 0 ? total : nil
                }
            }

            if types.contains(where: { $0.caseInsensitiveCompare("MusicComposition") == .orderedSame }) {
                if meta.artists.isEmpty, let composer = dict["composer"] {
                    meta.artists = musicEntityRefs(from: composer)
                }
            }

            if types.contains(where: { $0.caseInsensitiveCompare("MusicGroup") == .orderedSame }) {
                if meta.artists.isEmpty, let name = dict["name"] as? String {
                    meta.artists = [EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)]
                }
            }

            if types.contains(where: { $0.caseInsensitiveCompare("AudioObject") == .orderedSame }) {
                if meta.previewAudioURL == nil, let contentURL = dict["contentUrl"] as? String {
                    meta.previewAudioURL = contentURL
                }
            }
        }
    }

    private static func musicStringArray(_ value: Any?) -> [String] {
        if let s = value as? String { return [s] }
        if let arr = value as? [Any] { return arr.compactMap { $0 as? String } }
        return []
    }

    private static func musicEntityRefs(from value: Any) -> [EntityRef] {
        func ref(from dict: [String: Any]) -> EntityRef? {
            guard let name = dict["name"] as? String else { return nil }
            return EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
        }
        if let dict = value as? [String: Any] { return ref(from: dict).map { [$0] } ?? [] }
        if let arr = value as? [Any] { return arr.compactMap { ($0 as? [String: Any]).flatMap(ref) } }
        if let s = value as? String { return [EntityRef(name: s, slug: nil, kind: ItemKind.individual.rawValue)] }
        return []
    }

    private static func musicTrackEntries(from value: Any) -> [MusicTrackEntry] {
        func entry(from dict: [String: Any]) -> MusicTrackEntry? {
            guard let name = dict["name"] as? String else { return nil }
            let duration = (dict["duration"] as? String).flatMap(parseISO8601MusicDuration)
            return MusicTrackEntry(name: name, durationSeconds: duration)
        }
        if let arr = value as? [Any] {
            return arr.compactMap { item -> MusicTrackEntry? in
                guard let dict = item as? [String: Any] else { return nil }
                if let inner = dict["item"] as? [String: Any] { return entry(from: inner) }
                return entry(from: dict)
            }
        }
        if let dict = value as? [String: Any] { return entry(from: dict).map { [$0] } ?? [] }
        return []
    }

    private static func parseISO8601MusicDuration(_ s: String) -> Int? {
        guard s.hasPrefix("PT") else { return nil }
        var seconds = 0
        var buffer = ""
        for char in s.dropFirst(2) {
            if char.isNumber {
                buffer.append(char)
            } else if let value = Int(buffer) {
                switch char {
                case "H": seconds += value * 3600
                case "M": seconds += value * 60
                case "S": seconds += value
                default: break
                }
                buffer = ""
            } else {
                buffer = ""
            }
        }
        return seconds > 0 ? seconds : nil
    }

    // MARK: - Music: title parsing (rule-based; AI refinement lives in FoundationModelsEnricher)

    /// Deterministic first pass at YouTube's compound title grammar. Western convention
    /// splits "Artist - Track" on the dash; Indian film-music titles instead read
    /// "Track - Video Song | Film | Cast | Singers | Composer" — the part after the dash is
    /// a descriptor, not an artist, and the first pipe segment is the film.
    static func ruleParseYouTubeMusicTitle(_ rawTitle: String) -> RuleParsedMusicTitle {
        let pipeSegments = rawTitle.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = RuleParsedMusicTitle()
        let firstSegment = pipeSegments.first ?? rawTitle.trimmingCharacters(in: .whitespaces)
        var isFilmGrammar = false

        if let dashRange = firstSegment.range(of: " - ") {
            let before = String(firstSegment[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let after = String(firstSegment[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if musicTitleDescriptorWords.contains(after.lowercased()) {
                result.track = before
                isFilmGrammar = true
            } else {
                result.artist = before
                result.track = after
            }
        } else {
            result.track = firstSegment
        }

        if isFilmGrammar, pipeSegments.count >= 2 {
            result.film = pipeSegments[1]
        }

        return result
    }

    /// Splits a "(Remastered 2004)"-style trailing suffix into `edition`, only when the
    /// bracketed text reads as an edition marker (not just any parenthetical, e.g. a
    /// "(Calvin Harris, Disciples Cover)" credit stays part of the title).
    static func splitMusicEdition(from rawTitle: String) -> (title: String, edition: String?) {
        guard let regex = editionSuffixRegex else { return (rawTitle.trimmingCharacters(in: .whitespaces), nil) }
        let ns = rawTitle as NSString
        guard let match = regex.firstMatch(in: rawTitle, range: NSRange(location: 0, length: ns.length)),
              let fullRange = Range(match.range, in: rawTitle),
              let innerRange = Range(match.range(at: 1), in: rawTitle) else {
            return (rawTitle.trimmingCharacters(in: .whitespaces), nil)
        }
        let bracketed = String(rawTitle[innerRange]).trimmingCharacters(in: .whitespaces)
        let base = String(rawTitle[..<fullRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let lower = bracketed.lowercased()
        guard musicEditionKeywords.contains(where: { lower.contains($0) }) else {
            return (rawTitle.trimmingCharacters(in: .whitespaces), nil)
        }
        return (base, bracketed)
    }

    private static func applyRuleTitleParsing(rawTitle: String?, platform: String, to meta: inout MusicMeta) {
        guard let rawTitle, !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let (splitTitle, edition) = splitMusicEdition(from: rawTitle)
        if meta.edition == nil { meta.edition = edition }

        guard platform == "youtube" || platform == "youtube-music" else {
            if meta.cleanTitle == nil { meta.cleanTitle = splitTitle }
            return
        }

        let parsed = ruleParseYouTubeMusicTitle(splitTitle)
        if meta.cleanTitle == nil { meta.cleanTitle = parsed.track ?? splitTitle }
        if meta.artists.isEmpty, let artist = parsed.artist {
            meta.artists = [EntityRef(name: artist, slug: nil, kind: ItemKind.individual.rawValue)]
        }
        if meta.film == nil { meta.film = parsed.film }
    }

    /// Best-effort curator extraction for playlists — "Focus Zone by Arjun Phlox" style
    /// titles/descriptions. Never fabricates a curator when no "by <name>" text is present.
    static func applyCurator(rawTitle: String?, description: String?, subtype: String, to meta: inout MusicMeta) {
        guard subtype == "playlist", meta.curator == nil, let regex = curatorByRegex else { return }
        for candidate in [rawTitle, description].compactMap({ $0 }) {
            let ns = candidate as NSString
            guard let match = regex.firstMatch(in: candidate, range: NSRange(location: 0, length: ns.length)),
                  let range = Range(match.range(at: 1), in: candidate) else { continue }
            let name = String(candidate[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            meta.curator = EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
            return
        }
    }

    // MARK: - URL Helpers

    static func normalizeURL(_ url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        comps.scheme = comps.scheme?.lowercased()
        comps.host = comps.host?.lowercased()
        if comps.path.hasSuffix("/"), comps.path.count > 1 {
            comps.path = String(comps.path.dropLast())
        }
        return comps.url?.absoluteString ?? url.absoluteString
    }

    static func domain(from url: URL) -> String? {
        guard var host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host.isEmpty ? nil : host
    }

    private static func resolve(_ urlString: String, base: URL) -> URL? {
        URL(string: urlString, relativeTo: base)?.absoluteURL
    }
}
