import Foundation

// MARK: - Types

/// Platforms + pricing guessed from page text — what the on-device job and the rule-based
/// keyword pass both return when the readers found none. Stored on `ToolMeta` with its
/// `…IsGuess` flags set.
nonisolated struct ToolFacts: Sendable, Equatable {
    var platforms: [String] = []
    var pricing: String?
}

/// Result of the deterministic tool readers: metadata and the title the item should carry
/// (nil = keep the page title).
nonisolated struct ToolExtraction: Sendable {
    var meta: ToolMeta
    var title: String?
}

// MARK: - ToolReader

/// Pure, network-free tool readers (SoftwareApplication JSON-LD, og / meta tags, GitHub REST
/// JSON, redirects). The only network step — the GitHub `repos/<owner>/<repo>` call — lives
/// in `CaptureService.extractTool`, which then calls `build`.
nonisolated enum ToolReader {

    // MARK: - GitHub REST

    // Decoded with `.convertFromSnakeCase` (`stargazers_count` → `stargazersCount`,
    // `spdx_id` → `spdxId`, `html_url` → `htmlUrl`) — no all-caps "URL" property names.

    nonisolated struct GitHubRepo: Decodable, Sendable {
        var name: String?
        var fullName: String?
        var description: String?
        var htmlUrl: String?
        var homepage: String?
        var stargazersCount: Int?
        var language: String?
        var license: GitHubLicense?
        var pushedAt: String?
        var topics: [String]?
        var owner: GitHubOwner?
        var archived: Bool?
    }

    nonisolated struct GitHubLicense: Decodable, Sendable {
        var spdxId: String?
        var name: String?
    }

    nonisolated struct GitHubOwner: Decodable, Sendable {
        var login: String?
    }

    /// `https://api.github.com/repos/<owner>/<repo>`; nil when the URL isn't a repo.
    static func githubAPIURL(for url: URL) -> URL? {
        guard let repo = PageClassifier.githubRepo(from: url) else { return nil }
        return URL(string: "https://api.github.com/repos/\(repo.owner)/\(repo.repo)")
    }

    /// The decoded repo for a 200 response; nil for 403 / 429 (rate limit: 60 calls/hour
    /// unauthenticated), 404, anything else, or JSON we can't read — capture never fails on it.
    static func parseGitHubRepo(data: Data?, statusCode: Int?) -> GitHubRepo? {
        guard let data else { return nil }
        if let statusCode, statusCode != 200 { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let repo = try? decoder.decode(GitHubRepo.self, from: data),
              repo.fullName != nil || repo.name != nil else { return nil }
        return repo
    }

    /// SPDX id ("MIT"), else the licence name; GitHub's "NOASSERTION" (an unrecognised
    /// licence file) falls back to the name ("Other").
    static func licenseLabel(_ license: GitHubLicense?) -> String? {
        if let id = clean(license?.spdxId), id.uppercased() != "NOASSERTION" { return id }
        return clean(license?.name)
    }

    static func parseISODate(_ raw: String?) -> Date? {
        guard let raw = clean(raw) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
    }

    static func applyGitHub(_ repo: GitHubRepo, to meta: inout ToolMeta) {
        if let full = clean(repo.fullName) ?? clean(repo.name) { meta.name = full }
        if let description = clean(repo.description) { meta.tagline = description }
        if let login = clean(repo.owner?.login) { meta.maker = makerRef(login) }
        meta.stars = repo.stargazersCount
        meta.language = clean(repo.language)
        meta.license = licenseLabel(repo.license)
        meta.lastPushedAt = parseISODate(repo.pushedAt)
        meta.topics = (repo.topics ?? []).compactMap { clean($0) }
        meta.homepageURL = clean(repo.homepage)
        if let html = clean(repo.htmlUrl) { meta.repoURL = html }
        if meta.license != nil { meta.pricing = "open source" }
    }

    /// GitHub's og:description adds "Contribute to owner/repo development by creating an
    /// account on GitHub." — dropped, so the tagline is the repo's own sentence.
    static func cleanGitHubDescription(_ raw: String?) -> String? {
        guard var text = clean(raw) else { return nil }
        if let range = text.range(of: "Contribute to ", options: .backwards),
           text[range.lowerBound...].hasSuffix("on GitHub.") {
            text = String(text[..<range.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(" -") { text = String(text.dropLast(2)) }
        return clean(text)
    }

    // MARK: - SoftwareApplication JSON-LD

    static func isSoftwareTypeName(_ type: String) -> Bool {
        ["SoftwareApplication", "WebApplication", "MobileApplication"].contains {
            type.caseInsensitiveCompare($0) == .orderedSame
        }
    }

    /// Fills from the first SoftwareApplication / WebApplication / MobileApplication node:
    /// name, operatingSystem (string or array), applicationCategory, offers, maker
    /// (author / creator / publisher). Returns the node's own @type names for the subtype.
    @discardableResult
    static func applyJSONLD(html: String, to meta: inout ToolMeta) -> [String] {
        let nodes = PageClassifier.jsonLDNodes(from: html)
        guard let node = nodes.first(where: { $0.types.contains(where: isSoftwareTypeName) }) else { return [] }
        let app = node.dict

        if meta.name == nil { meta.name = ProductReader.string(app["name"]) }
        if meta.platforms.isEmpty { meta.platforms = platforms(from: app["operatingSystem"]) }
        if meta.category == nil { meta.category = cleanCategory(app["applicationCategory"]) }

        // A repo already marked "open source" keeps that label; JSON-LD can only add a price.
        let offers = offerPricing(from: app["offers"])
        if meta.pricing == nil { meta.pricing = offers.pricing }
        if meta.price == nil, offers.price != nil {
            meta.price = offers.price
            meta.currency = offers.currency
        }
        if meta.pricing == nil, isTrue(app["isAccessibleForFree"]) {
            meta.pricing = "free"
        }

        if meta.maker == nil {
            for key in ["author", "creator", "publisher"] {
                if let name = ProductReader.brandName(from: app[key]) {
                    meta.maker = makerRef(name)
                    break
                }
            }
        }
        return node.types
    }

    private static func isTrue(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        return ProductReader.string(value)?.lowercased() == "true"
    }

    /// "Mac OS X, Windows 10; Linux" / ["macOS", "iOS 17.0 or later"] → normalised, de-duped.
    static func platforms(from value: Any?) -> [String] {
        var raw: [String] = []
        if let s = value as? String {
            raw = [s]
        } else if let array = value as? [Any] {
            raw = array.compactMap { $0 as? String }
        }
        var result: [String] = []
        for entry in raw {
            for piece in entry.split(whereSeparator: { $0 == "," || $0 == ";" }) {
                if let name = normalizePlatform(String(piece)), !result.contains(name) {
                    result.append(name)
                }
            }
        }
        return result
    }

    /// "Mac OS X 10.15" / "OSX" / "macOS" → "macOS"; "Requires iOS 17.0 or later." → "iOS";
    /// "Windows 10" → "Windows"; "web browser" → "Web". Unknown short values are kept as
    /// written; nil for empty or "any"/"all".
    static func normalizePlatform(_ raw: String) -> String? {
        guard let trimmed = clean(raw) else { return nil }
        let lower = trimmed.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        func has(_ word: String) -> Bool { words.contains(word) }

        if lower.contains("watchos") || has("watch") { return "watchOS" }
        if lower.contains("visionos") || lower.contains("vision pro") { return "visionOS" }
        if lower.contains("tvos") || lower.contains("apple tv") { return "tvOS" }
        if lower.contains("ipados") || has("ipad") { return "iPadOS" }
        if has("ios") || has("iphone") { return "iOS" }
        if lower.contains("macos") || lower.contains("mac os") || has("osx") || lower.contains("os x")
            || has("mac") || has("macintosh") {
            return "macOS"
        }
        if lower.hasPrefix("win") || has("windows") { return "Windows" }
        if has("linux") || has("ubuntu") || has("debian") || has("fedora") { return "Linux" }
        if has("android") { return "Android" }
        if has("web") || has("browser") || has("online") || has("chrome") || has("firefox") || has("safari") {
            return "Web"
        }
        if ["any", "all", "cross-platform", "multi-platform", "n/a"].contains(lower) { return nil }
        return trimmed.count <= 24 ? trimmed : nil
    }

    /// "DeveloperApplication" → "Developer"; "https://schema.org/GameApplication" → "Game";
    /// "SocialNetworkingApplication" → "Social Networking"; "Productivity" stays.
    static func cleanCategory(_ value: Any?) -> String? {
        var raw: String?
        if let s = ProductReader.string(value) {
            raw = s
        } else if let array = value as? [Any] {
            raw = array.lazy.compactMap { ProductReader.string($0) }.first
        }
        guard var text = raw else { return nil }
        if let last = text.split(separator: "/").last, text.contains("/") { text = String(last) }
        if text.hasSuffix("Application"), text.count > "Application".count {
            text = String(text.dropLast("Application".count))
        }
        // Split CamelCase ("SocialNetworking" → "Social Networking"); leaves "Photo & Video" alone.
        var spaced = ""
        var previous: Character?
        for ch in text {
            if ch.isUppercase, let p = previous, p.isLowercase { spaced.append(" ") }
            spaced.append(ch)
            previous = ch
        }
        return clean(spaced)
    }

    nonisolated struct OfferPricing: Sendable, Equatable {
        var pricing: String?
        var price: String?
        var currency: String?
    }

    /// Offer | AggregateOffer | arrays (and `priceSpecification`): a price of 0 → `free`;
    /// 0 alongside a positive price (or an AggregateOffer lowPrice 0, highPrice > 0) →
    /// `freemium`; positive only → `paid`, with the lowest positive price.
    static func offerPricing(from value: Any?) -> OfferPricing {
        var prices: [(Decimal, String)] = []
        var currency: String?

        func record(_ any: Any?) {
            guard let raw = ProductReader.string(any) else { return }
            let compact = raw.replacingOccurrences(of: ",", with: "")
            if let firstDigit = compact.firstIndex(where: \.isNumber) {
                let kept = compact[firstDigit...].filter { $0.isNumber || $0 == "." }
                let trimmed = kept.hasSuffix(".") ? String(kept.dropLast()) : String(kept)
                if let number = Decimal(string: trimmed) { prices.append((number, trimmed)) }
            } else if raw.lowercased() == "free" {
                prices.append((0, "0"))
            }
        }

        func visit(_ value: Any?) {
            if let array = value as? [Any] {
                for element in array { visit(element) }
                return
            }
            guard let offer = value as? [String: Any] else { return }
            if currency == nil { currency = ProductReader.string(offer["priceCurrency"])?.uppercased() }
            record(offer["price"])
            record(offer["lowPrice"])
            record(offer["highPrice"])
            if let spec = offer["priceSpecification"] {
                let specs: [Any] = (spec as? [Any]) ?? [spec]
                for case let s as [String: Any] in specs {
                    record(s["price"])
                    if currency == nil { currency = ProductReader.string(s["priceCurrency"])?.uppercased() }
                }
            }
            if let nested = offer["offers"] { visit(nested) }
        }

        visit(value)
        guard !prices.isEmpty else { return OfferPricing() }
        let hasFree = prices.contains { $0.0 == 0 }
        let paid = prices.filter { $0.0 > 0 }.min { $0.0 < $1.0 }
        switch (hasFree, paid) {
        case (true, nil): return OfferPricing(pricing: "free", price: nil, currency: nil)
        case (true, let p?): return OfferPricing(pricing: "freemium", price: p.1, currency: currency)
        case (false, let p?): return OfferPricing(pricing: "paid", price: p.1, currency: currency)
        default: return OfferPricing()
        }
    }

    // MARK: - og / meta tags

    nonisolated struct PageTags: Sendable {
        var siteName: String?
        var metaDescription: String?
    }

    static func pageTags(html: String) -> PageTags {
        var tags = PageTags()
        for attrs in CaptureService.metaTagAttributes(in: html) {
            guard let content = clean(attrs["content"]) else { continue }
            if (attrs["property"] ?? "").lowercased() == "og:site_name", tags.siteName == nil {
                tags.siteName = content
            }
            if (attrs["name"] ?? "").lowercased() == "description", tags.metaDescription == nil {
                tags.metaDescription = content
            }
        }
        return tags
    }

    /// og:site_name values that name a store or code host, not the tool's maker.
    private static let storeSiteNames: Set<String> = [
        "app store", "mac app store", "github", "chrome web store", "firefox add-ons",
        "microsoft edge add-ons", "hugging face", "google play", "product hunt",
    ]

    private static let appStoreLinkRegex = try? NSRegularExpression(
        pattern: #"href\s*=\s*["']((?:https?:)?//(?:apps|itunes)\.apple\.com/[^"'\s>]+)["']"#,
        options: .caseInsensitive
    )

    /// The first apps.apple.com / itunes.apple.com app link on the page (a "Download on the
    /// App Store" badge), or nil.
    static func firstAppStoreLink(in html: String) -> String? {
        guard let regex = appStoreLinkRegex else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range(at: 1), in: html) else { continue }
            var link = String(html[r]).replacingOccurrences(of: "&amp;", with: "&")
            if link.hasPrefix("//") { link = "https:" + link }
            if let url = URL(string: link), PageClassifier.isAppStoreAppURL(url) { return link }
        }
        return nil
    }

    // MARK: - Subtype

    /// github → library; App Store → app; Chrome Web Store / add-on hosts → extension;
    /// a huggingface.co model page → AI model; MobileApplication or native platforms only →
    /// app; else web app.
    static func subtype(url: URL, jsonLDTypes: [String], meta: ToolMeta, siteName: String?) -> String {
        if PageClassifier.githubRepo(from: url) != nil { return "library" }
        if PageClassifier.isAppStoreAppURL(url) { return "app" }

        let host = ProductReader.bareHost(url) ?? ""
        let path = url.path.lowercased()
        if host == "chromewebstore.google.com" || (host == "chrome.google.com" && path.hasPrefix("/webstore"))
            || host == "addons.mozilla.org" || (host == "microsoftedge.microsoft.com" && path.hasPrefix("/addons"))
            || siteName?.lowercased() == "chrome web store"
            || (meta.category?.lowercased().contains("extension") ?? false) {
            return "extension"
        }
        if host == "huggingface.co" {
            let parts = url.path.split(separator: "/").map { $0.lowercased() }
            let nonModel: Set<String> = [
                "spaces", "datasets", "docs", "blog", "models", "papers", "learn", "pricing", "posts",
                "collections", "organizations", "settings", "login", "join", "tasks", "enterprise",
            ]
            if parts.count >= 2, let first = parts.first, !nonModel.contains(first) { return "AI model" }
        }
        if jsonLDTypes.contains(where: { $0.caseInsensitiveCompare("MobileApplication") == .orderedSame }) {
            return "app"
        }
        if jsonLDTypes.contains(where: { $0.caseInsensitiveCompare("WebApplication") == .orderedSame }) {
            return "web app"
        }
        let native = meta.platforms.filter { $0 != "Web" }
        if !native.isEmpty, !meta.platforms.contains("Web") { return "app" }
        return "web app"
    }

    // MARK: - Build

    /// Assembles `ToolMeta` for one tool page. `github` is the decoded REST repo when the
    /// caller fetched one (nil when rate-limited / not a repo — og tags still read).
    static func build(
        sourceURL: URL,
        finalURL: URL?,
        html: String,
        ogDescription: String?,
        github: GitHubRepo? = nil
    ) -> ToolExtraction {
        var meta = ToolMeta()
        let tags = pageTags(html: html)
        let repoRef = PageClassifier.githubRepo(from: sourceURL)
            ?? finalURL.flatMap { PageClassifier.githubRepo(from: $0) }
        let isRepo = repoRef != nil

        // 1. GitHub REST (repos only); the URL alone still gives the repo, name and owner.
        if let github { applyGitHub(github, to: &meta) }
        if let repoRef {
            if meta.repoURL == nil { meta.repoURL = "https://github.com/\(repoRef.owner)/\(repoRef.repo)" }
            if meta.name == nil { meta.name = "\(repoRef.owner)/\(repoRef.repo)" }
            if meta.maker == nil { meta.maker = makerRef(repoRef.owner) }
        }

        // 2. SoftwareApplication JSON-LD.
        let types = applyJSONLD(html: html, to: &meta)

        // 3. og / meta tags.
        if meta.tagline == nil {
            let description = ogDescription ?? tags.metaDescription
            meta.tagline = isRepo ? cleanGitHubDescription(description) : clean(description)
        }
        if meta.maker == nil, let site = tags.siteName, !storeSiteNames.contains(site.lowercased()) {
            meta.maker = makerRef(site)
        }

        // App Store.
        if PageClassifier.isAppStoreAppURL(sourceURL) {
            meta.appStoreURL = sourceURL.absoluteString
            if meta.platforms.isEmpty, PageClassifier.isMacAppStoreURL(sourceURL) { meta.platforms = ["macOS"] }
        } else {
            meta.appStoreURL = firstAppStoreLink(in: html)
        }

        // 4. Redirects: canonical only when the host changed.
        if let finalURL,
           let landed = ProductReader.bareHost(finalURL),
           landed != ProductReader.bareHost(sourceURL) {
            meta.canonicalURL = finalURL.absoluteString
        }

        meta.subtype = subtype(url: sourceURL, jsonLDTypes: types, meta: meta, siteName: tags.siteName)
        if meta.pricing == nil, meta.price != nil { meta.pricing = "paid" }

        // Title: the JSON-LD / repo name (App Store's og:title reads "X on the App Store",
        // GitHub's "GitHub - owner/repo: …"); nil keeps the page title.
        return ToolExtraction(meta: meta, title: meta.name)
    }

    // MARK: - Guess (on-device job + conservative rule-based fallback)

    /// Whether the readers left a gap the guess may fill.
    static func needsGuess(_ meta: ToolMeta) -> Bool {
        (meta.platforms.isEmpty || meta.platformsAreGuess) || (meta.pricing == nil || meta.pricingIsGuess)
    }

    /// A cheap keyword pass over the page text — conservative: only explicit download /
    /// store wording sets a platform, and only plain "free plan … per month"-style wording
    /// sets pricing. Nil when nothing clear is said.
    static func ruleBasedFacts(text: String?) -> ToolFacts? {
        guard let lower = clean(text)?.lowercased() else { return nil }
        var platforms: [String] = []
        func add(_ name: String) { if !platforms.contains(name) { platforms.append(name) } }

        if lower.contains("download for mac") || lower.contains("download for macos")
            || lower.contains("mac app store") {
            add("macOS")
        }
        if lower.contains("download for windows") { add("Windows") }
        if lower.contains("download for linux") { add("Linux") }
        if lower.contains("download on the app store") { add("iOS") }
        if lower.contains("get it on google play") { add("Android") }

        var pricing: String?
        let mentionsFreePlan = lower.contains("free plan") || lower.contains("free tier") || lower.contains("free forever")
        let mentionsPaid = lower.contains("per month") || lower.contains("/month") || lower.contains("/mo")
            || lower.contains("pro plan") || lower.contains("upgrade to pro")
        if mentionsFreePlan && mentionsPaid {
            pricing = "freemium"
        } else if lower.contains("100% free") || lower.contains("completely free") {
            pricing = "free"
        }

        guard !platforms.isEmpty || pricing != nil else { return nil }
        return ToolFacts(platforms: platforms, pricing: pricing)
    }

    /// "Free" / "open-source" / "Freemium" / "Paid" → the stored vocabulary; nil otherwise.
    static func normalizePricing(_ raw: String?) -> String? {
        guard let key = clean(raw)?.lowercased().replacingOccurrences(of: "-", with: " ") else { return nil }
        switch key {
        case "free": return "free"
        case "paid", "subscription", "one time purchase", "one-time purchase": return "paid"
        case "freemium", "free trial", "free with in app purchases", "free with paid plans": return "freemium"
        case "open source", "oss": return "open source"
        default: return nil
        }
    }

    /// Fills only what the readers left empty (or an earlier guess), setting the flags;
    /// read values are never replaced.
    static func applyGuess(_ facts: ToolFacts, to meta: inout ToolMeta) {
        var platforms: [String] = []
        for raw in facts.platforms {
            if let name = normalizePlatform(raw), !platforms.contains(name) { platforms.append(name) }
        }
        if !platforms.isEmpty, meta.platforms.isEmpty || meta.platformsAreGuess {
            meta.platforms = platforms
            meta.platformsAreGuess = true
        }
        if let pricing = normalizePricing(facts.pricing), meta.pricing == nil || meta.pricingIsGuess {
            meta.pricing = pricing
            meta.pricingIsGuess = true
        }
    }

    // MARK: - Refresh merge

    /// A refetch that reads less (rate-limited GitHub, bot wall) never erases what capture
    /// read; an earlier guess survives only while nothing is read in its place.
    static func merge(fresh: ToolMeta, previous: ToolMeta?) -> ToolMeta {
        guard let previous else { return fresh }
        var meta = fresh
        if meta.subtype == nil { meta.subtype = previous.subtype }
        if meta.name == nil { meta.name = previous.name }
        if meta.tagline == nil { meta.tagline = previous.tagline }
        if meta.platforms.isEmpty {
            meta.platforms = previous.platforms
            meta.platformsAreGuess = previous.platformsAreGuess
        }
        if meta.category == nil { meta.category = previous.category }
        if meta.pricing == nil {
            meta.pricing = previous.pricing
            meta.pricingIsGuess = previous.pricingIsGuess
        }
        if meta.price == nil {
            meta.price = previous.price
            meta.currency = previous.currency
        }
        if meta.maker == nil { meta.maker = previous.maker }
        if meta.repoURL == nil { meta.repoURL = previous.repoURL }
        if meta.stars == nil { meta.stars = previous.stars }
        if meta.language == nil { meta.language = previous.language }
        if meta.license == nil { meta.license = previous.license }
        if meta.lastPushedAt == nil { meta.lastPushedAt = previous.lastPushedAt }
        if meta.topics.isEmpty { meta.topics = previous.topics }
        if meta.homepageURL == nil { meta.homepageURL = previous.homepageURL }
        if meta.appStoreURL == nil { meta.appStoreURL = previous.appStoreURL }
        if meta.canonicalURL == nil { meta.canonicalURL = previous.canonicalURL }
        return meta
    }

    // MARK: - Helpers

    static func makerRef(_ name: String) -> EntityRef {
        EntityRef(name: name, slug: nil, kind: "maker")
    }

    static func clean(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
