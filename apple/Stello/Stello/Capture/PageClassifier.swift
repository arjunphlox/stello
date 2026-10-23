import Foundation

// MARK: - Result

struct PageClassificationResult: Sendable {
    var kind: ItemKind
    var individualMeta: IndividualMeta?
    /// Set only when `kind == .product`: `page` | `instagram` | `image`.
    var productSource: String? = nil
}

// MARK: - PageClassifier

/// Deterministic page kind + metadata from fetched HTML. No AI.
nonisolated struct PageClassifier {

    /// Strong foundry keywords — matched as whole words in the title or domain.
    /// ("type-foundry" and "typefoundry" both tokenize to these on word boundaries.)
    private static let foundryStrongKeywords: Set<String> = ["foundry", "typefoundry"]

    // MARK: - Compiled regexes (hoisted — built once, not per classify call)

    private static let jsonLDScriptRegex = try? NSRegularExpression(
        pattern: #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#,
        options: .caseInsensitive
    )

    private static let anchorTagRegex = try? NSRegularExpression(
        pattern: #"<a\s+([^>]*)>"#,
        options: .caseInsensitive
    )

    private static let linkTagRegex = try? NSRegularExpression(
        pattern: #"<link\s+([^>]*)>"#,
        options: .caseInsensitive
    )

    // MARK: - JSON-LD node model

    /// A typed JSON-LD node plus whether it appeared at the top level of a script
    /// (root object or root-array element) as opposed to nested inside `@graph`.
    private struct TypedNode {
        var dict: [String: Any]
        var topLevel: Bool
    }

    // MARK: - Public

    /// `ogType` comes from `OGResult.ogType` (parsed once in `CaptureService.parseOG`) —
    /// PageClassifier no longer re-scans the metas itself.
    nonisolated static func classify(
        html: String,
        baseURL: URL,
        domain: String?,
        title: String?,
        ogDescription: String?,
        ogType: String? = nil,
        collectionLabels: [String] = []
    ) -> PageClassificationResult {
        // Parse JSON-LD once and pass the nodes down.
        let nodes = jsonLDTypedNodes(from: html)

        // Shared kind order (product-spec): gone (status, set by the caller) → post → product →
        // tool → the existing individual/foundry rules. A single post on a social host is
        // decided inside `productSource`: wishlist-labelled → product, otherwise it stays
        // whatever it is today (Post kind is not built yet) and never reaches the product
        // page rules.
        if let source = productSource(
            url: baseURL, ogType: ogType, nodes: nodes, html: html, collectionLabels: collectionLabels
        ) {
            return PageClassificationResult(kind: .product, individualMeta: nil, productSource: source)
        }

        let isIndividual = hasIndividualSignals(nodes: nodes, ogType: ogType)
        let isFoundry = hasFoundrySignals(nodes: nodes, domain: domain, title: title)

        // Conflicting or weak signals → stay link.
        if isIndividual && isFoundry {
            return PageClassificationResult(kind: .link, individualMeta: nil)
        }
        if isIndividual {
            let meta = extractIndividualMeta(
                nodes: nodes,
                html: html,
                baseURL: baseURL,
                ogDescription: ogDescription
            )
            return PageClassificationResult(kind: .individual, individualMeta: meta)
        }
        if isFoundry {
            return PageClassificationResult(kind: .foundry, individualMeta: nil)
        }
        return PageClassificationResult(kind: .link, individualMeta: nil)
    }

    // MARK: - Kind signals

    /// A Person only counts as an "individual" signal when it is the page's subject:
    /// a top-level JSON-LD node, or the target of `mainEntity`/`about` — or the page declares
    /// og:type=profile. An author/publisher Person nested inside an Article/@graph context
    /// (Yoast-style author blocks) must NOT flip the page to individual.
    nonisolated private static func hasIndividualSignals(nodes: [TypedNode], ogType: String?) -> Bool {
        if ogType?.lowercased() == "profile" { return true }
        return primaryPerson(in: nodes) != nil
    }

    /// Strong keywords ("foundry", "typefoundry") must match as whole words in the title or
    /// domain — never bare substrings. The weak "fonts" keyword only counts as a full domain
    /// label (e.g. fonts.example.com); "The 10 Best Free Fonts of 2026" is not a foundry.
    nonisolated private static func hasFoundrySignals(nodes: [TypedNode], domain: String?, title: String?) -> Bool {
        let hasOrg = nodes.contains { nodeTypes($0.dict).contains(where: isOrganizationType) }
        guard hasOrg else { return false }
        if let title, strongFoundryWordMatch(in: title) { return true }
        if let domain {
            if strongFoundryWordMatch(in: domain) { return true }
            if domain.lowercased().split(separator: ".").contains("fonts") { return true }
        }
        return false
    }

    nonisolated private static func strongFoundryWordMatch(in text: String) -> Bool {
        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return tokens.contains { foundryStrongKeywords.contains(String($0)) }
    }

    /// The Person node that is plausibly the page's subject:
    /// top-level, or referenced via another node's `mainEntity`/`about` (inline or by `@id`).
    nonisolated private static func primaryPerson(in nodes: [TypedNode]) -> [String: Any]? {
        if let top = nodes.first(where: { $0.topLevel && nodeTypes($0.dict).contains(where: isPersonType) }) {
            return top.dict
        }
        for node in nodes {
            for key in ["mainEntity", "about"] {
                guard let ref = node.dict[key] else { continue }
                if let dict = ref as? [String: Any] {
                    if nodeTypes(dict).contains(where: isPersonType) { return dict }
                    if let id = dict["@id"] as? String,
                       let resolved = person(withID: id, in: nodes) {
                        return resolved
                    }
                } else if let id = ref as? String,
                          let resolved = person(withID: id, in: nodes) {
                    return resolved
                }
            }
        }
        return nil
    }

    nonisolated private static func person(withID id: String, in nodes: [TypedNode]) -> [String: Any]? {
        nodes.first {
            ($0.dict["@id"] as? String) == id && nodeTypes($0.dict).contains(where: isPersonType)
        }?.dict
    }

    // MARK: - Individual metadata

    nonisolated private static func extractIndividualMeta(
        nodes: [TypedNode],
        html: String,
        baseURL: URL,
        ogDescription: String?
    ) -> IndividualMeta? {
        var meta = IndividualMeta()

        if let bio = ogDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
            meta.bio = bio
        }

        // Only the page-subject Person feeds role/location — never a nested author node.
        if let person = primaryPerson(in: nodes) {
            if let role = stringValue(person["jobTitle"]) {
                meta.currentRole = role
            }
            if let location = postalAddressString(from: person["address"]) {
                meta.location = EntityRef(name: location, slug: slugify(location), kind: ItemKind.place.rawValue)
            }
        }

        applySocialLinks(from: html, baseURL: baseURL, to: &meta)

        return individualMetaHasContent(meta) ? meta : nil
    }

    // MARK: - JSON-LD

    nonisolated private static func jsonLDTypedNodes(from html: String) -> [TypedNode] {
        guard let scriptRegex = jsonLDScriptRegex else { return [] }

        let nsHTML = html as NSString
        var nodes: [TypedNode] = []
        for match in scriptRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            guard let bodyRange = Range(match.range(at: 1), in: html) else { continue }
            let body = String(html[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            nodes.append(contentsOf: collectTypedNodes(from: json, topLevel: true))
        }
        return nodes
    }

    nonisolated private static func collectTypedNodes(from value: Any, topLevel: Bool) -> [TypedNode] {
        if let dict = value as? [String: Any] {
            var results: [TypedNode] = []
            if dict["@type"] != nil { results.append(TypedNode(dict: dict, topLevel: topLevel)) }
            if let graph = dict["@graph"] {
                // @graph members are NOT top-level subjects (Yoast puts every author Person here).
                results.append(contentsOf: collectTypedNodes(from: graph, topLevel: false))
            }
            return results
        }
        if let array = value as? [Any] {
            return array.flatMap { collectTypedNodes(from: $0, topLevel: topLevel) }
        }
        return []
    }

    nonisolated private static func nodeTypes(_ node: [String: Any]) -> [String] {
        typeNames(from: node["@type"])
    }

    nonisolated private static func typeNames(from value: Any?) -> [String] {
        if let string = value as? String { return [normalizeSchemaType(string)] }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }.map(normalizeSchemaType)
        }
        return []
    }

    nonisolated private static func normalizeSchemaType(_ raw: String) -> String {
        if let last = raw.split(separator: "/").last, !last.isEmpty {
            return String(last)
        }
        return raw
    }

    nonisolated private static func isPersonType(_ type: String) -> Bool {
        type.caseInsensitiveCompare("Person") == .orderedSame
    }

    nonisolated private static func isOrganizationType(_ type: String) -> Bool {
        type.caseInsensitiveCompare("Organization") == .orderedSame
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    nonisolated private static func postalAddressString(from value: Any?) -> String? {
        if let s = stringValue(value) { return s }
        guard let dict = value as? [String: Any] else { return nil }
        let parts = [
            stringValue(dict["addressLocality"]),
            stringValue(dict["addressRegion"]),
            stringValue(dict["addressCountry"]),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: - Social links

    private enum SocialPlatform: Hashable {
        case x, instagram, linkedIn, behance, bluesky, mastodon, threads
    }

    /// rel=me links are the author's own identity claims and win over body anchors; body anchors
    /// only fill a platform slot rel=me hasn't already claimed. Share/intent widgets are skipped.
    /// Unrecognized hosts (even rel=me) are dropped — no blind mastodon fallback.
    nonisolated private static func applySocialLinks(from html: String, baseURL: URL, to meta: inout IndividualMeta) {
        var relMeClaimed: Set<SocialPlatform> = []

        func process(_ links: [ParsedLinkTag], relMePass: Bool) {
            for link in links where link.isRelMe == relMePass {
                guard let href = link.href,
                      let resolved = resolveURL(href, base: baseURL),
                      !isShareOrIntentLink(resolved),
                      let platform = socialPlatform(for: resolved) else { continue }
                if relMePass {
                    relMeClaimed.insert(platform)
                    assignSocialURL(resolved.absoluteString, platform: platform, to: &meta)
                } else if !relMeClaimed.contains(platform) {
                    assignSocialURL(resolved.absoluteString, platform: platform, to: &meta)
                }
            }
        }

        let allLinks = anchorAndLinkTags(in: html)
        process(allLinks, relMePass: true)
        process(allLinks, relMePass: false)
    }

    /// Share/intent widgets (e.g. `twitter.com/intent/tweet`, `/share`) are not the page owner's
    /// own profile link and must be ignored entirely, not assigned to any platform slot.
    nonisolated private static func isShareOrIntentLink(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/intent") || path.contains("/share")
    }

    /// Exact-host or dot-suffix matching only — no bare substring `.contains`, which would also
    /// match a spoofed host (`linkedin.com.evil.net`).
    nonisolated private static func socialPlatform(for url: URL) -> SocialPlatform? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }

        func matches(_ root: String) -> Bool {
            host == root || host.hasSuffix("." + root)
        }

        if matches("x.com") || matches("twitter.com") { return .x }
        if matches("instagram.com") { return .instagram }
        if matches("linkedin.com") { return .linkedIn }
        if matches("behance.net") { return .behance }
        if matches("bsky.app") { return .bluesky }
        if matches("threads.net") || matches("threads.com") { return .threads }
        if matches("mastodon.social") || matches("mastodon.online") { return .mastodon }
        return nil
    }

    nonisolated private static func assignSocialURL(_ url: String, platform: SocialPlatform, to meta: inout IndividualMeta) {
        switch platform {
        case .x:
            if meta.xURL == nil { meta.xURL = url }
        case .instagram:
            if meta.instagramURL == nil { meta.instagramURL = url }
        case .linkedIn:
            if meta.linkedInURL == nil { meta.linkedInURL = url }
        case .behance:
            if meta.behanceURL == nil { meta.behanceURL = url }
        case .bluesky:
            if meta.bluesky == nil { meta.bluesky = url }
        case .mastodon:
            if meta.mastodon == nil { meta.mastodon = url }
        case .threads:
            if meta.threads == nil { meta.threads = url }
        }
    }

    private struct ParsedLinkTag {
        var href: String?
        var rel: String

        var isRelMe: Bool {
            rel.lowercased()
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .contains("me")
        }
    }

    nonisolated private static func anchorAndLinkTags(in html: String) -> [ParsedLinkTag] {
        var results: [ParsedLinkTag] = []
        let nsHTML = html as NSString
        for regex in [anchorTagRegex, linkTagRegex] {
            guard let regex else { continue }
            for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
                guard let attrRange = Range(match.range(at: 1), in: html) else { continue }
                // Shared attribute parser — single implementation in CaptureService.
                let attrs = CaptureService.parseAttributes(String(html[attrRange]))
                results.append(ParsedLinkTag(
                    href: attrs["href"],
                    rel: attrs["rel"] ?? ""
                ))
            }
        }
        return results
    }

    // MARK: - Helpers

    nonisolated private static func resolveURL(_ urlString: String, base: URL) -> URL? {
        URL(string: urlString, relativeTo: base)?.absoluteURL
    }

    nonisolated private static func slugify(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    nonisolated private static func individualMetaHasContent(_ meta: IndividualMeta) -> Bool {
        meta.bio != nil
            || meta.currentRole != nil
            || meta.location != nil
            || meta.xURL != nil
            || meta.instagramURL != nil
            || meta.linkedInURL != nil
            || meta.behanceURL != nil
            || meta.bluesky != nil
            || meta.mastodon != nil
            || meta.threads != nil
    }

    // MARK: - Music (deterministic host / og:type rules only — extraction lives in CaptureService)

    /// Known music-platform hosts → a stable platform label, matched against the already
    /// www-stripped domain from `CaptureService.domain(from:)`. Bandcamp is a dot-suffix
    /// match (`artist.bandcamp.com`); everything else is exact-or-subdomain, same convention
    /// as `socialPlatform(for:)` above.
    nonisolated static func musicPlatform(forHost host: String) -> String? {
        let h = host.lowercased()
        func matches(_ root: String) -> Bool { h == root || h.hasSuffix("." + root) }

        if matches("open.spotify.com") { return "spotify" }
        if matches("music.apple.com") { return "apple-music" }
        if matches("bandcamp.com") { return "bandcamp" }
        if matches("soundcloud.com") { return "soundcloud" }
        if matches("music.youtube.com") { return "youtube-music" }
        if matches("tidal.com") { return "tidal" }
        if matches("mixcloud.com") { return "mixcloud" }
        if matches("deezer.com") { return "deezer" }
        return nil
    }

    /// Plain `youtube.com`/`youtu.be` — NOT `music.youtube.com`, matched above — is only a
    /// music CANDIDATE. `isMusicYouTubeSignal` must confirm it via oEmbed author/title before
    /// it counts; a generic vlog upload must stay `link`.
    nonisolated static func isPlainYouTubeHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "youtube.com" || h.hasSuffix(".youtube.com") || h == "youtu.be"
    }

    nonisolated private static let musicOGTypes: Set<String> = [
        "music.album", "music.song", "music.playlist", "music.musician",
    ]

    nonisolated static func isMusicOGType(_ ogType: String?) -> Bool {
        guard let t = ogType?.lowercased() else { return false }
        return musicOGTypes.contains(t)
    }

    /// Conservative promotion rule for plain YouTube: an auto-generated artist channel
    /// (`"<Artist> - Topic"`), a VEVO channel, or a title explicitly marked as a music upload.
    nonisolated static func isMusicYouTubeSignal(authorName: String?, title: String?) -> Bool {
        if let authorName {
            let a = authorName.lowercased()
            if a.hasSuffix(" - topic") || a.contains("vevo") { return true }
        }
        if let title {
            let t = title.lowercased()
            if t.contains("official music video") || t.contains("official audio") || t.contains("video song") {
                return true
            }
        }
        return false
    }

    /// Subtype (album | track | playlist | artist | mix) from og:type first, then URL path
    /// conventions. Falls back to "track" — the safest default for a single saved song.
    nonisolated static func musicSubtype(url: URL, ogType: String?, platform: String?) -> String {
        if platform == "mixcloud" { return "mix" }

        if let t = ogType?.lowercased() {
            switch t {
            case "music.playlist": return "playlist"
            case "music.musician": return "artist"
            case "music.album": return "album"
            case "music.song": return "track"
            default: break
            }
        }

        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""

        if path.contains("/playlist/") || path.contains("pl.u-") || path.contains("/sets/") { return "playlist" }
        if path.contains("/artist/") { return "artist" }
        if path.contains("/album/") { return query.contains("i=") ? "track" : "album" }
        if path.contains("/track/") { return "track" }
        return "track"
    }

    /// Exposes the deterministic JSON-LD node scan for kind-specific extractors (music) that
    /// need typed nodes without duplicating the parsing regex — flattened type list per node.
    nonisolated static func jsonLDNodes(from html: String) -> [(types: [String], dict: [String: Any])] {
        jsonLDTypedNodes(from: html).map { (nodeTypes($0.dict), $0.dict) }
    }

    // MARK: - Product (deterministic rules only — extraction lives in ProductReader)

    /// The collection label that turns a social post or a bare image file into a product.
    nonisolated static let wishlistLabel = "wishlist"

    nonisolated static func hasWishlistLabel(_ labels: [String]) -> Bool {
        labels.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wishlistLabel }
    }

    /// Product source (`page` | `instagram` | `image`) when the page classifies as a product,
    /// else nil. Order (first match wins, per product-spec):
    /// 1. single post on a social host → product ONLY with the wishlist label (source
    ///    `instagram` for Instagram, else `page`); without it → nil, and the page rules below
    ///    are skipped (a post is a post, even if it happens to carry og:type product);
    /// 2. og:type product; 3. a Product JSON-LD subject; 4. a Shopify `/products/<handle>`
    ///    page; 5. an Amazon product / Kickstarter project page; 6. a bare image file URL
    ///    carrying the wishlist label → `image`.
    /// An article (og:type article) never classifies from JSON-LD/path alone — review
    /// roundups embed Products.
    nonisolated static func productSource(
        url: URL,
        ogType: String?,
        html: String,
        collectionLabels: [String]
    ) -> String? {
        productSource(
            url: url, ogType: ogType, nodes: jsonLDTypedNodes(from: html), html: html,
            collectionLabels: collectionLabels
        )
    }

    nonisolated private static func productSource(
        url: URL,
        ogType: String?,
        nodes: [TypedNode],
        html: String,
        collectionLabels: [String]
    ) -> String? {
        let wishlisted = hasWishlistLabel(collectionLabels)

        if let postHost = socialPostHost(for: url) {
            guard wishlisted else { return nil }
            return postHost == "instagram" ? "instagram" : "page"
        }

        let type = ogType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isProductOGType(type) { return "page" }

        // Any Article node counts (Yoast puts it in @graph, i.e. not top-level).
        let isArticle = type == "article" || nodes.contains {
            nodeTypes($0.dict).contains(where: isArticleType)
        }

        if !isArticle {
            if nodes.contains(where: { nodeTypes($0.dict).contains(where: isProductType) }) {
                return "page"
            }
            if isShopifyProductURL(url) && (html.isEmpty || hasShopifyMarker(html) || isMyShopifyHost(url)) {
                return "page"
            }
        }

        if isAmazonProductURL(url) || isKickstarterProjectURL(url) { return "page" }

        if wishlisted && isBareImageURL(url) { return "image" }

        return nil
    }

    nonisolated static func isProductOGType(_ ogType: String?) -> Bool {
        guard let t = ogType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !t.isEmpty else {
            return false
        }
        return t == "product" || t == "og:product" || t.hasPrefix("product.")
    }

    nonisolated private static func isProductType(_ type: String) -> Bool {
        type.caseInsensitiveCompare("Product") == .orderedSame
            || type.caseInsensitiveCompare("ProductGroup") == .orderedSame
            || type.caseInsensitiveCompare("IndividualProduct") == .orderedSame
    }

    nonisolated private static func isArticleType(_ type: String) -> Bool {
        ["Article", "BlogPosting", "NewsArticle"].contains {
            type.caseInsensitiveCompare($0) == .orderedSame
        }
    }

    // MARK: Product — host / path rules

    /// Lowercased host with a leading `www.` removed.
    nonisolated private static func bareHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }

    /// `brand.tld` / `brand.co.tld` / `sub.brand.tld` — the brand must be the registrable
    /// label, so `amazon.com.evil.net` and `notamazon.com` don't match.
    nonisolated private static func hostIsBrand(_ host: String, brand: String) -> Bool {
        let labels = host.split(separator: ".").map(String.init)
        guard let index = labels.lastIndex(of: brand) else { return false }
        let suffix = labels[(index + 1)...]
        return (1...2).contains(suffix.count) && suffix.allSatisfy { (2...3).contains($0.count) }
    }

    /// `instagram` | `x` | `behance` | `dribbble` | `pinterest` when the URL is a SINGLE post
    /// on that host (not a profile, feed or board); else nil.
    nonisolated static func socialPostHost(for url: URL) -> String? {
        guard let host = bareHost(url) else { return nil }
        func matches(_ root: String) -> Bool { host == root || host.hasSuffix("." + root) }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)

        if matches("instagram.com") {
            // /p/<code>, /reel/<code>, /reels/<code>, /tv/<code>, and /<user>/p/<code>
            let markers: Set<String> = ["p", "reel", "reels", "tv"]
            if let i = parts.firstIndex(where: { markers.contains($0) }), i + 1 < parts.count { return "instagram" }
            return nil
        }
        if matches("x.com") || matches("twitter.com") {
            if let i = parts.firstIndex(of: "status"), i + 1 < parts.count { return "x" }
            return nil
        }
        if matches("behance.net") {
            if let i = parts.firstIndex(of: "gallery"), i + 1 < parts.count { return "behance" }
            return nil
        }
        if matches("dribbble.com") {
            if let i = parts.firstIndex(of: "shots"), i + 1 < parts.count { return "dribbble" }
            return nil
        }
        if hostIsBrand(host, brand: "pinterest") || host == "pin.it" {
            if host == "pin.it" { return parts.isEmpty ? nil : "pinterest" }
            if let i = parts.firstIndex(of: "pin"), i + 1 < parts.count { return "pinterest" }
            return nil
        }
        return nil
    }

    /// `/products/<handle>` — also under `/collections/<x>/products/<handle>`.
    nonisolated static func isShopifyProductURL(_ url: URL) -> Bool {
        shopifyHandle(from: url) != nil
    }

    /// The product handle from a Shopify-style path (without any `.json`/`.js` suffix).
    nonisolated static func shopifyHandle(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let i = parts.lastIndex(where: { $0.lowercased() == "products" }), i + 1 < parts.count else {
            return nil
        }
        var handle = parts[i + 1]
        for ext in [".json", ".js", ".oembed", ".xml"] where handle.lowercased().hasSuffix(ext) {
            handle = String(handle.dropLast(ext.count))
        }
        return handle.isEmpty ? nil : handle
    }

    nonisolated private static func isMyShopifyHost(_ url: URL) -> Bool {
        guard let host = bareHost(url) else { return false }
        return host == "myshopify.com" || host.hasSuffix(".myshopify.com")
    }

    /// A `/products/` path alone is ambiguous (SaaS sites use it for feature pages), so the
    /// page must also show it's a Shopify storefront.
    nonisolated private static func hasShopifyMarker(_ html: String) -> Bool {
        html.contains("cdn.shopify.com") || html.contains("/cdn/shop/")
            || html.contains("Shopify.shop") || html.contains("shopify-digital-wallet")
    }

    nonisolated static func isAmazonProductURL(_ url: URL) -> Bool {
        guard let host = bareHost(url) else { return false }
        // Short links only ever point at a product.
        if host == "amzn.to" || host == "amzn.in" || host == "amzn.eu" || host == "a.co" { return true }
        guard hostIsBrand(host, brand: "amazon") else { return false }
        let path = url.path.lowercased()
        return path.contains("/dp/") || path.contains("/gp/product/") || path.contains("/gp/aw/d/")
    }

    nonisolated static func isKickstarterProjectURL(_ url: URL) -> Bool {
        guard let host = bareHost(url), host == "kickstarter.com" || host.hasSuffix(".kickstarter.com") else {
            return false
        }
        let parts = url.path.lowercased().split(separator: "/")
        // /projects/<creator>/<project>
        return parts.first == "projects" && parts.count >= 3
    }

    nonisolated static let bareImageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif"]

    nonisolated static func isBareImageURL(_ url: URL) -> Bool {
        bareImageExtensions.contains(url.pathExtension.lowercased())
    }
}
