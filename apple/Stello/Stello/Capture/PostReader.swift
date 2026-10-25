import Foundation

// MARK: - Types

/// Result of the deterministic post readers: metadata, the media image URLs (photos and
/// video/GIF posters, cover first, capped at `PostReader.mediaCap`), the title the item
/// should carry (Post title rule), and whether the post is gone (X tombstone / 404).
nonisolated struct PostExtraction: Sendable {
    var meta: PostMeta
    var imageURLs: [URL]
    var title: String?
    var isGone: Bool
}

/// The oEmbed fields the post readers use (Behance). Plain values so the pure reader never
/// depends on `CaptureService.OEmbedResponse`.
nonisolated struct PostOEmbedInfo: Sendable, Equatable {
    var title: String?
    var authorName: String?
    var authorURL: String?
    var thumbnailURL: String?
}

/// What the AI-art rules read from labels, tags and text.
nonisolated struct AIArtSignal: Sendable, Equatable {
    var isAIArt: Bool
    var model: String?
}

// MARK: - PostReader

/// Pure, network-free post readers (X syndication JSON, Instagram / Behance / Dribbble /
/// Pinterest og tags, Behance oEmbed), the Post title rule and the AI-art rules. The only
/// network steps (the syndication and oEmbed fetches) live in `CaptureService.extractPost`,
/// which then calls `build`.
nonisolated enum PostReader {

    /// Media cap (post-spec: "put all photos into item images (cap 8, first = cover)").
    static let mediaCap = 8

    /// Post title rule: "@handle: first ~8 words of the text…".
    static let titleWordCount = 8

    // MARK: - X: tweet id + syndication token

    /// `/<handle>/status/<id>` (also `/i/status/<id>`, `/i/web/status/<id>`) → the numeric id.
    static func tweetID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(where: { $0.lowercased() == "status" || $0.lowercased() == "statuses" }),
              i + 1 < parts.count else { return nil }
        let id = parts[i + 1]
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return id
    }

    /// The handle in `/<handle>/status/<id>`; nil for `/i/status/…` style paths.
    static func handleFromXURL(_ url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(where: { $0.lowercased() == "status" }), i > 0 else { return nil }
        let handle = parts[i - 1]
        guard !["i", "web"].contains(handle.lowercased()) else { return nil }
        return handle.isEmpty ? nil : handle
    }

    /// The public embed widget's token: `((id / 1e15) * π).toString(36)` with every `0` and
    /// `.` removed. The endpoint accepts any non-empty token today; this still reproduces the
    /// widget so a stricter check later doesn't break capture. Falls back to "a".
    static func syndicationToken(for id: String) -> String {
        guard let number = Double(id), number.isFinite, number > 0 else { return "a" }
        let token = base36String((number / 1e15) * Double.pi)
            .replacingOccurrences(of: "0", with: "")
            .replacingOccurrences(of: ".", with: "")
        return token.isEmpty ? "a" : token
    }

    private static let base36Digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    /// JavaScript `Number.prototype.toString(36)` for a non-negative Double — a port of V8's
    /// `DoubleToRadixCString`: fraction digits are emitted until they fall below half the
    /// distance to the next Double, with round-half-even carry back through the digits.
    /// (Checked against node for 3,500 ids while porting.)
    static func base36String(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < 9.0e15 else { return "0" }
        let radix = 36
        var integer = value.rounded(.down)
        var fraction = value - integer
        var delta = max(0.5 * (value.nextUp - value), Double.leastNonzeroMagnitude)
        var fractionDigits: [Int] = []

        if fraction >= delta {
            repeat {
                fraction *= Double(radix)
                delta *= Double(radix)
                let digit = Int(fraction)
                fractionDigits.append(digit)
                fraction -= Double(digit)
                if fraction > 0.5 || (fraction == 0.5 && (digit & 1) == 1) {
                    if fraction + delta > 1 {
                        // Round up, carrying back through the digits already written.
                        while true {
                            guard let last = fractionDigits.popLast() else {
                                integer += 1
                                break
                            }
                            if last + 1 < radix {
                                fractionDigits.append(last + 1)
                                break
                            }
                        }
                        break
                    }
                }
            } while fraction >= delta
        }

        var whole = UInt64(integer)
        var integerDigits: [Character] = []
        repeat {
            integerDigits.insert(base36Digits[Int(whole % UInt64(radix))], at: 0)
            whole /= UInt64(radix)
        } while whole > 0

        var result = String(integerDigits)
        if !fractionDigits.isEmpty {
            result += "." + String(fractionDigits.map { base36Digits[$0] })
        }
        return result
    }

    /// `https://cdn.syndication.twimg.com/tweet-result?id=<id>&lang=en&token=<token>`.
    static func syndicationURL(forTweetID id: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "cdn.syndication.twimg.com"
        comps.path = "/tweet-result"
        comps.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "token", value: syndicationToken(for: id)),
        ]
        return comps.url
    }

    // MARK: - X: syndication JSON

    // Decoded with `.convertFromSnakeCase` (`media_url_https` → `mediaUrlHttps`,
    // `screen_name` → `screenName`) — property names avoid all-caps "URL" for that reason.

    nonisolated struct SyndicationTweet: Decodable, Sendable {
        var idStr: String?
        var text: String?
        var createdAt: String?
        var user: SyndicationUser?
        var mediaDetails: [SyndicationMedia]?
        var photos: [SyndicationPhoto]?
        var video: SyndicationVideo?
    }

    nonisolated struct SyndicationUser: Decodable, Sendable {
        var name: String?
        var screenName: String?
    }

    nonisolated struct SyndicationMedia: Decodable, Sendable {
        /// `photo` | `video` | `animated_gif`.
        var type: String?
        var mediaUrlHttps: String?
        var originalInfo: SyndicationSize?
    }

    nonisolated struct SyndicationSize: Decodable, Sendable {
        var width: Int?
        var height: Int?
    }

    nonisolated struct SyndicationPhoto: Decodable, Sendable {
        var url: String?
        var width: Int?
        var height: Int?
    }

    nonisolated struct SyndicationVideo: Decodable, Sendable {
        var poster: String?
    }

    nonisolated enum SyndicationOutcome: Sendable {
        case tweet(SyndicationTweet)
        /// 404 / 410, an empty body, or a `TweetTombstone` — the tweet is deleted or withheld.
        case gone
        /// Network failure, another status, or JSON we can't read — fall back to og tags.
        case unavailable
    }

    static func parseSyndication(data: Data?, statusCode: Int?) -> SyndicationOutcome {
        if statusCode == 404 || statusCode == 410 { return .gone }
        guard let data else { return .unavailable }
        if let statusCode, statusCode != 200 { return .unavailable }

        let body = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty || body == "{}" { return .gone }

        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .unavailable
        }
        if (object["__typename"] as? String) == "TweetTombstone" || object["tombstone"] != nil {
            return .gone
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let tweet = try? decoder.decode(SyndicationTweet.self, from: data) else { return .unavailable }
        if clean(tweet.text) == nil && tweet.user == nil && (tweet.mediaDetails ?? []).isEmpty {
            return .gone
        }
        return .tweet(tweet)
    }

    /// Media image URLs (photo URLs; the poster for video/GIF), the post-level media type and
    /// the media count for one tweet.
    static func tweetMedia(_ tweet: SyndicationTweet) -> (urls: [String], mediaType: String?, count: Int) {
        let details = tweet.mediaDetails ?? []
        var urls = details.compactMap { clean($0.mediaUrlHttps) }
        var types = details.compactMap { $0.type?.lowercased() }
        if urls.isEmpty {
            urls = (tweet.photos ?? []).compactMap { clean($0.url) }
            types = Array(repeating: "photo", count: urls.count)
        }
        if urls.isEmpty, let poster = clean(tweet.video?.poster) {
            urls = [poster]
            types = ["video"]
        }
        let count = max(details.count, urls.count)
        return (urls, mediaTypeLabel(types: types, count: count), count)
    }

    /// `carousel` for 2+ media, else `video` / `gif` / `image` from the first item's type.
    static func mediaTypeLabel(types: [String], count: Int) -> String? {
        guard count > 0 else { return nil }
        if count > 1 { return "carousel" }
        switch types.first {
        case "video": return "video"
        case "animated_gif", "gif": return "gif"
        default: return "image"
        }
    }

    /// Syndication `created_at` is ISO 8601 ("2024-05-01T12:00:00.000Z"); the legacy API
    /// format ("Wed May 01 12:00:00 +0000 2024") is accepted too.
    static func parseTweetDate(_ raw: String?) -> Date? {
        guard let raw = clean(raw) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let legacy = DateFormatter()
        legacy.locale = Locale(identifier: "en_US_POSIX")
        legacy.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return legacy.date(from: raw)
    }

    /// Drops the trailing t.co media/quote links the syndication text carries and decodes
    /// the HTML entities it keeps (`&amp;`).
    static func cleanTweetText(_ raw: String?) -> String? {
        guard var text = raw else { return nil }
        text = text.replacingOccurrences(
            of: #"(\s*https?://t\.co/[A-Za-z0-9]+)+\s*$"#, with: "", options: .regularExpression
        )
        return clean(decodeEntities(text))
    }

    // MARK: - X: og fallback

    private static let xTitleHandleRegex = try? NSRegularExpression(
        pattern: #"^([\s\S]+?)\s+\(@([A-Za-z0-9_]+)\)\s+on\s+(?:X|Twitter)\s*(?::\s*([\s\S]*))?$"#,
        options: []
    )

    private static let xTitleTextRegex = try? NSRegularExpression(
        pattern: #"^([\s\S]+?)\s+on\s+(?:X|Twitter)\s*:\s*([\s\S]*)$"#,
        options: []
    )

    /// og:title "Name (@handle) on X" / "Name on X: "text"" (also "… on Twitter"), with
    /// og:description as the text when the title doesn't carry it.
    static func parseXOG(title: String?, description: String?) -> (name: String?, handle: String?, text: String?) {
        var name: String?
        var handle: String?
        var text: String?

        if let title = clean(title) {
            let range = NSRange(title.startIndex..., in: title)
            if let regex = xTitleHandleRegex, let m = regex.firstMatch(in: title, range: range) {
                if let r = Range(m.range(at: 1), in: title) { name = clean(String(title[r])) }
                if let r = Range(m.range(at: 2), in: title) { handle = String(title[r]) }
                if let r = Range(m.range(at: 3), in: title) { text = ProductReader.cleanCaption(String(title[r])) }
            } else if let regex = xTitleTextRegex, let m = regex.firstMatch(in: title, range: range) {
                if let r = Range(m.range(at: 1), in: title) { name = clean(String(title[r])) }
                if let r = Range(m.range(at: 2), in: title) { text = ProductReader.cleanCaption(String(title[r])) }
            }
        }
        if text == nil, let description { text = ProductReader.cleanCaption(description) }
        return (name, handle, text)
    }

    // MARK: - og extras

    nonisolated struct OGExtras: Sendable {
        var url: String?
        var hasVideo: Bool = false
    }

    /// og:url and whether the page declares an og:video.
    static func ogExtras(html: String) -> OGExtras {
        var extras = OGExtras()
        for attrs in CaptureService.metaTagAttributes(in: html) {
            let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            guard let content = clean(attrs["content"]) else { continue }
            switch key {
            case "og:url":
                if extras.url == nil { extras.url = content }
            case "og:video", "og:video:url", "og:video:secure_url":
                extras.hasVideo = true
            default:
                break
            }
        }
        return extras
    }

    // MARK: - Behance / Dribbble / Pinterest

    /// `https://www.behance.net/services/oembed?url=<post URL without its query>`.
    static func behanceOEmbedURL(for url: URL) -> URL? {
        guard let host = url.host, !host.isEmpty else { return nil }
        let post = "https://\(host)\(url.path)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = post.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://www.behance.net/services/oembed?url=\(encoded)")
    }

    private static let dribbbleTitleRegex = try? NSRegularExpression(
        pattern: #"^([\s\S]+?)\s+by\s+([\s\S]+?)\s+(?:on|\|)\s+Dribbble$"#,
        options: [.caseInsensitive]
    )

    private static let pinterestDiscoveredRegex = try? NSRegularExpression(
        pattern: #"^This Pin was discovered by\s+([^.]+?)\."#,
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

    /// Pinterest's boilerplate description ("This Pin was discovered by Jane. Discover (and
    /// save!) your own Pins on Pinterest.") names the pinner but is not the pin's text.
    static func parsePinterestDescription(_ description: String?) -> (author: String?, text: String?) {
        guard let description = clean(description) else { return (nil, nil) }
        if let regex = pinterestDiscoveredRegex,
           let m = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
            let author = Range(m.range(at: 1), in: description).flatMap { clean(String(description[$0])) }
            return (author, nil)
        }
        if description.lowercased().hasPrefix("discover recipes, home ideas") { return (nil, nil) }
        return (nil, description)
    }

    // MARK: - Title rule

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

    // MARK: - AI art

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
        #"(?im)(?:^|\s)(?:--|—)(?:ar|v|style|sref|niji|chaos|stylize)(?=[ \t]+[^\s\-—]|[ \t]*$)"#

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

    // MARK: - Prompt extraction

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

    // MARK: - Build

    /// Assembles `PostMeta` + media URLs + title for one single post. `syndication` is the X
    /// endpoint's outcome when the caller fetched it; `oembed` is Behance's oEmbed. Sites
    /// that block servers give whatever their og tags say — this never fails.
    static func build(
        sourceURL: URL,
        finalURL: URL?,
        platform: String,
        html: String,
        ogTitle: String?,
        ogDescription: String?,
        ogImageURL: URL?,
        ogType: String?,
        syndication: SyndicationOutcome? = nil,
        oembed: PostOEmbedInfo? = nil
    ) -> PostExtraction {
        let landing = finalURL ?? sourceURL
        let extras = ogExtras(html: html)
        let ogVideo = extras.hasVideo || (ogType?.lowercased().hasPrefix("video") ?? false)

        var meta = PostMeta()
        meta.platform = platform
        meta.canonicalURL = extras.url ?? landing.absoluteString

        var imageStrings: [String] = []
        var mediaFromReader = false
        var isGone = false
        var titleSource = ogTitle

        switch platform {
        case "x":
            let id = tweetID(from: sourceURL) ?? tweetID(from: landing)
            if case .tweet(let tweet)? = syndication {
                meta.text = cleanTweetText(tweet.text)
                meta.authorHandle = clean(tweet.user?.screenName)
                if let name = clean(tweet.user?.name) {
                    meta.author = EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
                }
                meta.postedAt = parseTweetDate(tweet.createdAt)
                let media = tweetMedia(tweet)
                imageStrings = media.urls
                meta.mediaType = media.mediaType
                meta.mediaCount = media.count > 0 ? media.count : nil
                mediaFromReader = true
            } else {
                if case .gone? = syndication { isGone = true }
                let og = parseXOG(title: ogTitle, description: ogDescription)
                meta.text = og.text
                meta.authorHandle = og.handle
                if let name = og.name {
                    meta.author = EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
                }
            }
            if meta.authorHandle == nil { meta.authorHandle = handleFromXURL(sourceURL) }
            if let id {
                meta.canonicalURL = "https://x.com/\(meta.authorHandle ?? "i")/status/\(id)"
                meta.embedURL = "https://platform.twitter.com/embed/Tweet.html?id=\(id)"
            }

        case "instagram":
            let info = ProductReader.parseInstagramOG(title: ogTitle, description: ogDescription)
            meta.authorHandle = info.handle
            if let name = info.displayName ?? info.handle.map({ "@\($0)" }) {
                meta.author = EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
            }
            meta.text = info.caption
            meta.postedAt = info.postedAt
            let segments = sourceURL.path.split(separator: "/").map(String.init)
            let lowered = segments.map { $0.lowercased() }
            let isReel = lowered.contains { ["reel", "reels", "tv"].contains($0) }
            if let i = lowered.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }), i + 1 < segments.count {
                meta.embedURL = "https://www.instagram.com/p/\(segments[i + 1])/embed"
            }
            if let ogImageURL { imageStrings = [ogImageURL.absoluteString] }
            if !imageStrings.isEmpty {
                meta.mediaType = (ogVideo || isReel) ? "video" : "image"
                meta.mediaCount = imageStrings.count
                mediaFromReader = true
            }

        case "behance":
            if let name = clean(oembed?.authorName) {
                meta.author = EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
            }
            if let authorURL = clean(oembed?.authorURL).flatMap({ URL(string: $0) }),
               let handle = authorURL.path.split(separator: "/").first.map(String.init), !handle.isEmpty {
                meta.authorHandle = handle
            }
            meta.text = ProductReader.cleanCaption(ogDescription ?? "")
            if titleSource == nil { titleSource = oembed?.title }
            if let ogImageURL {
                imageStrings = [ogImageURL.absoluteString]
            } else if let thumb = clean(oembed?.thumbnailURL) {
                imageStrings = [thumb]
            }

        case "dribbble":
            if let author = parseDribbbleTitle(ogTitle).author {
                meta.author = EntityRef(name: author, slug: nil, kind: ItemKind.individual.rawValue)
            }
            meta.text = ProductReader.cleanCaption(ogDescription ?? "")
            if let ogImageURL { imageStrings = [ogImageURL.absoluteString] }

        default: // pinterest
            let pin = parsePinterestDescription(ogDescription)
            if let author = pin.author {
                meta.author = EntityRef(name: author, slug: nil, kind: ItemKind.individual.rawValue)
            }
            meta.text = pin.text
            if let ogImageURL { imageStrings = [ogImageURL.absoluteString] }
        }

        // og tags keep HTML entities (`&gt;`, `&amp;`); the syndication text is already decoded.
        meta.text = meta.text.map(decodeEntities)

        var images: [URL] = []
        var seen = Set<String>()
        for raw in imageStrings {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("//") { s = "https:" + s }
            guard let url = URL(string: s, relativeTo: landing)?.absoluteURL,
                  seen.insert(url.absoluteString).inserted else { continue }
            images.append(url)
        }
        // og-only: X without syndication falls back to the page's og:image.
        if images.isEmpty, !mediaFromReader, let ogImageURL { images = [ogImageURL] }
        images = Array(images.prefix(mediaCap))

        if !mediaFromReader, !images.isEmpty {
            meta.mediaType = ogVideo ? "video" : "image"
            meta.mediaCount = images.count
        }

        let title = postTitle(
            currentTitle: titleSource,
            handle: meta.authorHandle,
            authorName: meta.author?.name,
            text: meta.text
        )
        return PostExtraction(meta: meta, imageURLs: images, title: title, isGone: isGone)
    }

    // MARK: - Helpers

    static func decodeEntities(_ s: String) -> String {
        CaptureService.decodeBasicEntities(s)
    }

    static func clean(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
