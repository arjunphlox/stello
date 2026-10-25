import Foundation

// MARK: - Result

struct PageClassificationResult: Sendable {
    var kind: ItemKind
    var individualMeta: IndividualMeta?
    /// Set only when `kind == .product`: `page` | `instagram` | `image`.
    var productSource: String? = nil
    /// Set only when `kind == .post`: `x` | `instagram` | `behance` | `dribbble` | `pinterest`.
    var postPlatform: String? = nil
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

        // Shared kind order (product-spec): gone (status, set by the caller) → post → resource →
        // book → product → tool → course → article → the existing
        // individual/foundry rules. A single post
        // on a social host is a Post, unless it carries the wishlist label — then
        // `productSource` claims it as a product (a post never reaches the product page rules
        // either way). Resource runs ahead of product (Framer Marketplace pages carry a
        // Product JSON-LD node with offers) and ahead of tool (labels).
        if let platform = postPlatform(url: baseURL, collectionLabels: collectionLabels) {
            return PageClassificationResult(kind: .post, individualMeta: nil, postPlatform: platform)
        }
        if isResource(url: baseURL, ogType: ogType, nodes: nodes, html: html, collectionLabels: collectionLabels) {
            return PageClassificationResult(kind: .resource, individualMeta: nil)
        }
        // Book after resource, before product:
        // an Amazon ISBN page is a book, even with the wishlist label.
        if isBook(url: baseURL, ogType: ogType, nodes: nodes, html: html) {
            return PageClassificationResult(kind: .book, individualMeta: nil)
        }
        if let source = productSource(
            url: baseURL, ogType: ogType, nodes: nodes, html: html, collectionLabels: collectionLabels
        ) {
            return PageClassificationResult(kind: .product, individualMeta: nil, productSource: source)
        }
        if isTool(url: baseURL, ogType: ogType, nodes: nodes, collectionLabels: collectionLabels) {
            return PageClassificationResult(kind: .tool, individualMeta: nil)
        }
        // Course after tool, before article: a course page that sets og:type article (Motion
        // Design School, LABASAD) is a course; a GitHub repo of course material stays a tool.
        if isCourse(url: baseURL, ogType: ogType, nodes: nodes, title: title, collectionLabels: collectionLabels) {
            return PageClassificationResult(kind: .course, individualMeta: nil)
        }
        // Article after course: an article page carrying tool labels is already kept out of
        // Tool by Tool's article override (og:type article / Article JSON-LD), so it lands here.
        if isArticle(url: baseURL, ogType: ogType, nodes: nodes, html: html, collectionLabels: collectionLabels) {
            return PageClassificationResult(kind: .article, individualMeta: nil)
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
        return h == "youtube.com" || (h.hasSuffix(".youtube.com") && h != "music.youtube.com") || h == "youtu.be"
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

    // MARK: - Post (deterministic rules only — extraction lives in PostReader)

    /// The post platform when the URL is a single post on a social host (`socialPostHost`)
    /// and the item is NOT wishlist-labelled (a wishlisted post is a product); else nil.
    /// Content labels (gen-ai, midjourney, …) never decide the kind.
    nonisolated static func postPlatform(url: URL, collectionLabels: [String]) -> String? {
        guard !hasWishlistLabel(collectionLabels) else { return nil }
        return socialPostHost(for: url)
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

        // SaaS landing pages often mark themselves up as a Product; only a Product with an
        // offer, on a page that doesn't also declare itself software, counts.
        let isSoftware = nodes.contains { nodeTypes($0.dict).contains(where: isSoftwareType) }
        // Course sale pages (Teachable, Podia, …) often add a Product node with offers next to
        // their Course node — the Course rule claims those.
        let isCourse = nodes.contains { nodeTypes($0.dict).contains(where: isCourseType) }
        // Bookshops add a Product node with offers next to the Book node — the Book rule
        // claims those.
        let isBook = nodes.contains { nodeTypes($0.dict).contains(where: isBookType) }

        if !isArticle && !isSoftware && !isCourse && !isBook {
            if nodes.contains(where: {
                nodeTypes($0.dict).contains(where: isProductType) && $0.dict["offers"] != nil
            }) {
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

    // MARK: - Resource (deterministic rules only — extraction lives in ResourceReader)

    /// Collection label that makes a page a resource (unless it is an article or a bare image).
    nonisolated static let digitalResourcesLabel = "digital-resources"
    /// The `books` collection label. It never decides a kind: a single book is a Book by its own
    /// signals, and a reading list stays a plain website/link (Arjun's call, 2026-10-25).
    nonisolated static let booksLabel = "books"

    /// "Digital Resources" / "digital_resources" → "digital-resources".
    nonisolated static func normalizedLabelKey(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    nonisolated static func hasLabel(_ key: String, in labels: [String]) -> Bool {
        labels.contains { normalizedLabelKey($0) == key }
    }

    /// Whether the page is a resource. Runs after the post rule and before product and tool
    /// (kind order: gone → post → resource → book → product → tool). Resource when ANY of:
    /// a Figma Community plugin / widget / file; a Framer Marketplace item page; a CodePen pen;
    /// the `digital-resources` label on a page that is not an article (Article / NewsArticle /
    /// BlogPosting JSON-LD or og:type article) and not a bare image. The label rule never
    /// claims a wishlisted item (that's a product). The `books` label makes nothing a resource:
    /// reading lists stay websites.
    nonisolated static func isResource(url: URL, ogType: String?, html: String, collectionLabels: [String]) -> Bool {
        isResource(
            url: url, ogType: ogType, nodes: jsonLDTypedNodes(from: html), html: html,
            collectionLabels: collectionLabels
        )
    }

    nonisolated private static func isResource(
        url: URL,
        ogType: String?,
        nodes: [TypedNode],
        html: String,
        collectionLabels: [String]
    ) -> Bool {
        if figmaCommunityResourceType(from: url) != nil
            || framerMarketplaceSegment(from: url) != nil
            || isCodePenPenURL(url) {
            return true
        }

        guard !hasWishlistLabel(collectionLabels), !isBareImageURL(url) else { return false }

        if hasLabel(digitalResourcesLabel, in: collectionLabels) {
            let type = ogType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isArticle = type == "article" || nodes.contains {
                nodeTypes($0.dict).contains(where: isArticleType)
            }
            if !isArticle { return true }
        }

        return false
    }

    /// Path segments under `figma.com/community/` (or `figma.com/@user/`) that name one resource.
    nonisolated private static let figmaResourceSegments: Set<String> = ["plugin", "widget", "file"]

    /// `plugin` | `widget` | `file` for a Figma Community resource page —
    /// `figma.com/community/<type>/<id>[/<slug>]`, or a `figma.com/@user/<type>/<id>…` path;
    /// nil for the Community home, search, categories, profiles and every non-community page.
    nonisolated static func figmaCommunityResourceType(from url: URL) -> String? {
        guard let host = bareHost(url), host == "figma.com" else { return nil }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return nil }
        guard parts[0] == "community" || (parts[0].hasPrefix("@") && parts[0].count > 1) else { return nil }
        let type = parts[1]
        guard figmaResourceSegments.contains(type), !parts[2].isEmpty else { return nil }
        return type
    }

    /// Second segments under `framer.com/marketplace/` that are site pages, not item types.
    nonisolated private static let framerReservedSegments: Set<String> = [
        "creators", "creator", "profile", "search", "category", "categories", "collections",
        "sell", "submit", "become-a-creator", "blog", "about", "faq", "help",
    ]

    /// Third segments that are listing / filter pages under a type, not an item slug.
    nonisolated private static let framerListingSlugs: Set<String> = [
        "category", "categories", "search", "page", "tag", "tags", "free", "paid", "popular",
        "new", "newest", "featured", "trending", "best", "all",
    ]

    /// The marketplace type segment (`templates`, `plugins`, `components`, `vectors`, …) for a
    /// `framer.com/marketplace/<type>/<slug>` item page; nil for the marketplace home, a type
    /// listing (`/marketplace/templates/`), a category page or a creator profile.
    nonisolated static func framerMarketplaceSegment(from url: URL) -> String? {
        guard let host = bareHost(url), host == "framer.com" else { return nil }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "marketplace" else { return nil }
        let type = parts[1]
        let slug = parts[2]
        guard !framerReservedSegments.contains(type), !framerListingSlugs.contains(slug), !slug.isEmpty else {
            return nil
        }
        return type
    }

    /// A single pen: `codepen.io/<user>/pen/<id>` (also the `/full/` and `/details/` views).
    nonisolated static func isCodePenPenURL(_ url: URL) -> Bool {
        guard let host = bareHost(url), host == "codepen.io" else { return false }
        let parts = url.path.split(separator: "/").map { $0.lowercased() }
        guard parts.count >= 3 else { return false }
        return ["pen", "full", "details"].contains(parts[1]) && !parts[2].isEmpty
    }

    // MARK: - Book (single-book detector — the reading-list veto; the Book kind is `isBook`)

    /// Whether the page is ONE book (not a reading list): an Amazon `/dp/<isbn10>` (or
    /// `/gp/product/<isbn10>`) URL, a `book:isbn` / `books:isbn` meta tag, a top-level /
    /// @graph Book JSON-LD node, a StoryGraph `/books/<id>`, Goodreads `/book/show/<id>`,
    /// Open Library `/books/<id>` / `/works/<id>`, Google Books or Bookshop.org book page.
    /// Looser than `isBook` (no ISBN checksum): it only keeps a page out of the reading-list
    /// rule.
    nonisolated static func isSingleBook(url: URL, html: String) -> Bool {
        isSingleBook(url: url, nodes: jsonLDTypedNodes(from: html), html: html)
    }

    nonisolated private static func isSingleBook(url: URL, nodes: [TypedNode], html: String) -> Bool {
        if let host = bareHost(url) {
            let parts = url.path.lowercased().split(separator: "/").map(String.init)
            func segment(after marker: String) -> String? {
                guard let i = parts.firstIndex(of: marker), i + 1 < parts.count else { return nil }
                return parts[i + 1]
            }
            if hostIsBrand(host, brand: "amazon") {
                let id = segment(after: "dp") ?? (parts.firstIndex(of: "gp").flatMap { i in
                    i + 2 < parts.count && parts[i + 1] == "product" ? parts[i + 2] : nil
                })
                if let id, isISBN10(id) { return true }
            }
            if host == "thestorygraph.com" || host.hasSuffix(".thestorygraph.com") {
                if segment(after: "books") != nil { return true }
            }
            if host == "goodreads.com" || host.hasSuffix(".goodreads.com") {
                if parts.count >= 3, parts[0] == "book", parts[1] == "show" { return true }
            }
            if host == "openlibrary.org" {
                if parts.count >= 2, parts[0] == "books" || parts[0] == "works" { return true }
            }
        }
        // Google Books / Bookshop.org single-book pages (added with the Book kind).
        if isKnownBookPageURL(url) { return true }
        if hasSingleBookNode(nodes) { return true }
        if !html.isEmpty {
            for attrs in CaptureService.metaTagAttributes(in: html) {
                let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
                if key == "book:isbn" || key == "books:isbn", let content = attrs["content"],
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            }
        }
        return false
    }

    /// Ten characters: nine digits then a digit or `X` (case-insensitive).
    nonisolated static func isISBN10(_ id: String) -> Bool {
        let chars = Array(id)
        guard chars.count == 10 else { return false }
        guard chars.prefix(9).allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let last = chars[9]
        return (last.isASCII && last.isNumber) || last == "x" || last == "X"
    }

    // MARK: - Book (deterministic rules only — extraction lives in BookReader)

    nonisolated static func isBookType(_ type: String) -> Bool {
        type.caseInsensitiveCompare("Book") == .orderedSame
            || type.caseInsensitiveCompare("Audiobook") == .orderedSame
    }

    /// og:type `book` / `books.book` (Goodreads, publishers).
    nonisolated static func isBookOGType(_ ogType: String?) -> Bool {
        guard let t = ogType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return t == "book" || t == "books.book"
    }

    /// Whether the page is one book. Runs after the resource rule and before product (kind
    /// order: gone → post → resource → book → product → tool → course → article → existing).
    /// Book when ANY of: a Book JSON-LD node (anywhere, @graph included — but not when the
    /// page lists several different books); og:type `book` / `books.book`; a `book:isbn` /
    /// `books:isbn` meta; an Amazon product URL whose ASIN is a checksum-valid ISBN-10
    /// (`amazonBookISBN10`); a known single-book page (`isKnownBookPageURL`: Goodreads,
    /// Open Library, Google Books, StoryGraph, Bookshop.org). Reading lists (Goodreads
    /// `/list/`, `/shelf/`, Amazon lists, "best books" posts) match none of these, and a
    /// `books`-labelled list page is already a resource. Collection labels never decide it:
    /// a wishlisted Amazon ISBN page is still a book. A bare image file is never a book.
    nonisolated static func isBook(url: URL, ogType: String?, html: String) -> Bool {
        isBook(url: url, ogType: ogType, nodes: jsonLDTypedNodes(from: html), html: html)
    }

    nonisolated private static func isBook(url: URL, ogType: String?, nodes: [TypedNode], html: String) -> Bool {
        guard !isBareImageURL(url) else { return false }

        if hasSingleBookNode(nodes) { return true }

        if isBookOGType(ogType) || hasBookISBNMeta(html: html) { return true }
        if amazonBookISBN10(from: url) != nil { return true }
        return isKnownBookPageURL(url)
    }

    /// Book JSON-LD node(s) naming one book. Several differently named Book nodes are a list
    /// of books ("best books of 2025"), not one book.
    nonisolated private static func hasSingleBookNode(_ nodes: [TypedNode]) -> Bool {
        let names = nodes
            .filter { nodeTypes($0.dict).contains(where: isBookType) }
            .map { (($0.dict["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return !names.isEmpty && Set(names.filter { !$0.isEmpty }).count <= 1
    }

    /// Whether the page has a Book JSON-LD node (anywhere, @graph included).
    nonisolated static func hasBookNode(html: String) -> Bool {
        jsonLDTypedNodes(from: html).contains { nodeTypes($0.dict).contains(where: isBookType) }
    }

    /// A non-empty `book:isbn` / `books:isbn` meta tag.
    nonisolated static func hasBookISBNMeta(html: String) -> Bool {
        guard !html.isEmpty else { return false }
        return CaptureService.metaTagAttributes(in: html).contains { attrs in
            let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            guard key == "book:isbn" || key == "books:isbn" else { return false }
            return !(attrs["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The ASIN of an Amazon product URL (`amazon.<tld>` / `amzn.*`) after `/dp/`,
    /// `/gp/product/`, `/gp/aw/d/` or `/o/ASIN/` when it is a checksum-valid ISBN-10
    /// (upper-cased X); nil for a `B0…` ASIN, an invalid checksum or any other page.
    nonisolated static func amazonBookISBN10(from url: URL) -> String? {
        guard let host = bareHost(url), hostIsBrand(host, brand: "amazon") || hostIsBrand(host, brand: "amzn") else {
            return nil
        }
        let parts = url.path.split(separator: "/").map(String.init)
        let lower = parts.map { $0.lowercased() }
        var candidates: [String] = []
        for (i, part) in lower.enumerated() {
            if part == "dp", i + 1 < parts.count { candidates.append(parts[i + 1]) }
            if part == "gp", i + 2 < parts.count, lower[i + 1] == "product" { candidates.append(parts[i + 2]) }
            if part == "gp", i + 3 < parts.count, lower[i + 1] == "aw", lower[i + 2] == "d" { candidates.append(parts[i + 3]) }
            if part == "o", i + 2 < parts.count, lower[i + 1] == "asin" { candidates.append(parts[i + 2]) }
        }
        for candidate in candidates where isValidISBN10(candidate) {
            return candidate.uppercased()
        }
        return nil
    }

    /// Nine digits then a digit or X, with a valid mod-11 checksum (`0262033844`).
    nonisolated static func isValidISBN10(_ value: String) -> Bool {
        guard isISBN10(value) else { return false }
        var sum = 0
        for (index, ch) in value.uppercased().enumerated() {
            let digit = ch == "X" ? 10 : (ch.wholeNumberValue ?? 0)
            sum += digit * (10 - index)
        }
        return sum % 11 == 0
    }

    /// Thirteen digits starting 978 / 979 with a valid mod-10 checksum (`9780262033848`).
    nonisolated static func isValidISBN13(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count == 13, chars.allSatisfy({ $0.isASCII && $0.isNumber }),
              value.hasPrefix("978") || value.hasPrefix("979") else { return false }
        var sum = 0
        for (index, ch) in chars.enumerated() {
            sum += (ch.wholeNumberValue ?? 0) * (index % 2 == 0 ? 1 : 3)
        }
        return sum % 10 == 0
    }

    /// A known single-book page: Goodreads `/book/show/<id>`; Open Library `/works/OL…W` or
    /// `/books/OL…M`; Google Books (`books.google.<tld>`) with an `id=` query or a
    /// `/books/edition/` path; StoryGraph `/books/<uuid>`; Bookshop.org `/p/books/<slug>`.
    /// Publisher pages count only through JSON-LD / og (no host list).
    nonisolated static func isKnownBookPageURL(_ url: URL) -> Bool {
        guard let host = bareHost(url) else { return false }
        func matches(_ root: String) -> Bool { host == root || host.hasSuffix("." + root) }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)

        if matches("goodreads.com") {
            return parts.count >= 3 && parts[0] == "book" && parts[1] == "show" && !parts[2].isEmpty
        }
        if matches("openlibrary.org") {
            guard parts.count >= 2 else { return false }
            let id = parts[1]
            func isOLID(_ suffix: Character) -> Bool {
                id.count > 3 && id.hasPrefix("ol") && id.last == suffix
                    && id.dropFirst(2).dropLast().allSatisfy { $0.isASCII && $0.isNumber }
            }
            return (parts[0] == "works" && isOLID("w")) || (parts[0] == "books" && isOLID("m"))
        }
        if host.hasPrefix("books.google."), hostIsBrand(host, brand: "google") {
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            if !id.isEmpty { return true }
            if let i = parts.firstIndex(of: "books"), i + 2 < parts.count, parts[i + 1] == "edition" { return true }
            return false
        }
        if matches("thestorygraph.com") {
            guard parts.count >= 2, parts[0] == "books" else { return false }
            let id = parts[1]
            return id.count >= 8 && id.allSatisfy { $0 == "-" || $0.isHexDigit }
        }
        if matches("bookshop.org") {
            return parts.count >= 3 && parts[0] == "p" && parts[1] == "books" && !parts[2].isEmpty
        }
        return false
    }

    // MARK: - Tool (deterministic rules only — extraction lives in ToolReader)

    /// Collection labels that make a page a tool (unless it is an article).
    nonisolated static let toolLabels: Set<String> = ["digital-tools", "digital-productivity", "gen-ai"]

    /// Collection labels that mark AI art (an image), never a tool — they veto the tool
    /// labels, so a `gen-ai` + `midjourney` gallery page isn't filed as a tool.
    nonisolated static let aiArtOnlyLabels: Set<String> = [
        "midjourney", "nijijourney", "ai-art", "stable-diffusion", "dall-e",
    ]

    /// "Gen AI" / "gen_ai" / "GEN-AI" → "gen-ai". False when an AI-art label is also present.
    nonisolated static func hasToolLabel(_ labels: [String]) -> Bool {
        let keys = labels.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "_", with: "-")
        }
        guard !keys.contains(where: aiArtOnlyLabels.contains) else { return false }
        return keys.contains(where: toolLabels.contains)
    }

    /// Whether the page is a tool. Runs after the post and product rules (kind order:
    /// gone → post → product → tool). Tool when ANY of: a GitHub repo URL; an App Store app
    /// URL; a SoftwareApplication / WebApplication / MobileApplication JSON-LD node; a
    /// `digital-tools` / `digital-productivity` / `gen-ai` collection label. An article
    /// (Article / NewsArticle / BlogPosting JSON-LD, or og:type article) is never a tool —
    /// except a GitHub repo or an App Store URL, which always is (GitHub sets og:type object,
    /// and a stray article node must not override a repo). A bare image file is never a tool.
    nonisolated static func isTool(url: URL, ogType: String?, html: String, collectionLabels: [String]) -> Bool {
        isTool(url: url, ogType: ogType, nodes: jsonLDTypedNodes(from: html), collectionLabels: collectionLabels)
    }

    nonisolated private static func isTool(
        url: URL,
        ogType: String?,
        nodes: [TypedNode],
        collectionLabels: [String]
    ) -> Bool {
        if githubRepo(from: url) != nil || isAppStoreAppURL(url) { return true }

        let type = ogType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isArticle = type == "article" || nodes.contains {
            nodeTypes($0.dict).contains(where: isArticleType)
        }
        if isArticle { return false }

        if nodes.contains(where: { nodeTypes($0.dict).contains(where: isSoftwareType) }) { return true }
        // A tool label never wins over an article-shaped URL (dated path, /blog/<slug>, Medium,
        // Substack, Codrops): the gen-ai label was wrong 3 of 4 times on such pages.
        let articleURL = urlPathDate(url) != nil || hasArticlePathSlug(url)
            || isMediumPost(url) || isSubstackPost(url) || isCodropsArticle(url)
        if hasToolLabel(collectionLabels), !isBareImageURL(url), !articleURL { return true }
        return false
    }

    /// First path segments on github.com that are site pages, not `<owner>/<repo>`.
    nonisolated private static let githubReservedOwners: Set<String> = [
        "orgs", "topics", "features", "marketplace", "settings", "about", "pricing", "collections",
        "sponsors", "explore", "trending", "login", "logout", "join", "signup", "search", "new",
        "notifications", "issues", "pulls", "dashboard", "organizations", "enterprise", "enterprises",
        "security", "site", "team", "customer-stories", "readme", "apps", "codespaces", "users",
        "events", "contact", "home", "nonprofit", "premium-support", "resources", "solutions",
        "sitemap", "watching", "stars", "account", "copilot", "mobile", "education", "partners",
        "github-copilot", "community", "discussions", "advisories", "blog", "changelog",
    ]

    /// `(owner, repo)` for `github.com/<owner>/<repo>[/…]`; nil for gist.github.com, site pages
    /// (`/orgs`, `/topics`, `/features`, `/marketplace`, …) and owner-only profile URLs.
    nonisolated static func githubRepo(from url: URL) -> (owner: String, repo: String)? {
        guard let host = bareHost(url), host == "github.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.lowercased().hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !githubReservedOwners.contains(owner.lowercased()), !owner.isEmpty, !repo.isEmpty else { return nil }
        let allowed: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        guard owner.allSatisfy(allowed), repo.allSatisfy(allowed) else { return nil }
        return (owner, repo)
    }

    /// An App Store app page: `apps.apple.com/<cc>/app/<name>/id<n>`, `itunes.apple.com/…/app/…`,
    /// or a `macappstore://` / `itms-apps://` link.
    nonisolated static func isAppStoreAppURL(_ url: URL) -> Bool {
        if let scheme = url.scheme?.lowercased(), ["macappstore", "itms-apps", "itms-appss"].contains(scheme) {
            return true
        }
        guard let host = bareHost(url), host == "apps.apple.com" || host == "itunes.apple.com" else { return false }
        let parts = url.path.lowercased().split(separator: "/")
        guard let i = parts.firstIndex(of: "app") else { return false }
        return i + 1 < parts.count
    }

    /// A Mac App Store link: the `macappstore://` scheme or an App Store URL carrying `mt=12`.
    nonisolated static func isMacAppStoreURL(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "macappstore" { return true }
        guard isAppStoreAppURL(url) else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { $0.name == "mt" && $0.value == "12" }
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

    nonisolated private static func isSoftwareType(_ type: String) -> Bool {
        ["SoftwareApplication", "WebApplication", "MobileApplication"].contains {
            type.caseInsensitiveCompare($0) == .orderedSame
        }
    }

    /// Article-like schema.org types. Shared by the article rule and the article overrides in
    /// the product / resource / tool rules (so a TechArticle review never becomes a tool).
    nonisolated static let articleTypeNames: [String] = [
        "Article", "BlogPosting", "NewsArticle", "TechArticle", "Report", "ScholarlyArticle",
    ]

    nonisolated static func isArticleType(_ type: String) -> Bool {
        articleTypeNames.contains {
            type.caseInsensitiveCompare($0) == .orderedSame
        }
    }

    // MARK: - Course (deterministic rules only — extraction lives in CourseReader)

    /// Collection label that breaks the tie for a course page (label + a course word in the
    /// title → course). The label alone never makes a course.
    nonisolated static let educationLabel = "education"

    /// Course hosts that also carry blogs, profiles and catalog pages: only a course path
    /// (`/course/`, `/courses/`, `/learn/`, `/classes/` + a slug — or Maven's
    /// `/<instructor>/<slug>`) counts. Webflow University also has lesson / blog pages.
    nonisolated static let multiPurposeCourseHosts: Set<String> = [
        "frontendmasters.com", "maven.com", "udemy.com", "coursera.org", "domestika.org",
        "skillshare.com", "egghead.io", "university.webflow.com",
    ]

    /// Single-purpose course sites: any path that isn't a blog post counts (the home page is
    /// the course's sales page).
    nonisolated static let singlePurposeCourseHosts: Set<String> = [
        "motiondesign.school", "superhi.com", "shiftnudge.com", "thebasics.dev", "designcourse.com",
    ]

    /// Path segments that, on a multi-purpose course host, mark one course when a slug follows.
    nonisolated private static let courseHostPathSegments: Set<String> = ["course", "courses", "learn", "classes"]

    /// First path segments on maven.com that are site pages, not an instructor.
    nonisolated private static let mavenReservedSegments: Set<String> = [
        "blog", "about", "pricing", "login", "signup", "sign-up", "search", "categories", "category",
        "topics", "teach", "business", "for-business", "careers", "jobs", "terms", "privacy", "help",
        "resources", "p", "u", "settings", "explore", "creators", "courses", "lightning-lessons",
        "guides", "articles", "events",
    ]

    /// Path segments that mark a course page anywhere: followed by a slug, or as the last
    /// segment with something before it (`/design/masterclass`).
    nonisolated static let coursePathSegments: Set<String> = [
        "course", "courses", "program", "programs", "masterclass", "bootcamp", "workshop",
    ]

    /// Whole words in a title that, with the `education` label, make a course.
    nonisolated private static let courseTitleWords: Set<String> = [
        "course", "courses", "masterclass", "masterclasses", "bootcamp", "bootcamps", "workshop",
        "workshops", "academy", "learn", "master",
    ]

    nonisolated static func isCourseType(_ type: String) -> Bool {
        type.caseInsensitiveCompare("Course") == .orderedSame
    }

    nonisolated static func isEducationEventType(_ type: String) -> Bool {
        type.caseInsensitiveCompare("EducationEvent") == .orderedSame
    }

    /// Whether the page is a course. Runs after the tool rule and before the article rule
    /// (kind order: gone → post → resource → book → product → tool → course → article →
    /// existing). Course when ANY of: a Course JSON-LD node (anywhere, @graph included); an
    /// EducationEvent node on a course-ish page (course host, course path or a course word in
    /// the title); a known course host (`isCourseHostURL`); a `course(s)` / `program(s)` /
    /// `masterclass` / `bootcamp` / `workshop` path segment (`hasCoursePathSegment`, never
    /// on a blog / dated URL); the `education` label together with a course word in the title
    /// ("course", "masterclass", "bootcamp", "workshop", "academy", "learn", "master" — whole
    /// words) on a page with no strong article signal. A course page that sets og:type article
    /// (Motion Design School, LABASAD) is a course; a blog / dated URL with Article JSON-LD and
    /// no course signal stays an article. A bare image file is never a course.
    nonisolated static func isCourse(
        url: URL,
        ogType: String?,
        html: String,
        title: String?,
        collectionLabels: [String]
    ) -> Bool {
        isCourse(
            url: url, ogType: ogType, nodes: jsonLDTypedNodes(from: html), title: title,
            collectionLabels: collectionLabels
        )
    }

    nonisolated private static func isCourse(
        url: URL,
        ogType: String?,
        nodes: [TypedNode],
        title: String?,
        collectionLabels: [String]
    ) -> Bool {
        guard !isBareImageURL(url) else { return false }

        if nodes.contains(where: { nodeTypes($0.dict).contains(where: isCourseType) }) { return true }

        if isCourseHostURL(url) || hasCoursePathSegment(url) { return true }

        let titleWord = titleHasCourseWord(title)
        let educationLabelled = hasLabel(educationLabel, in: collectionLabels)
        if titleWord || educationLabelled,
           nodes.contains(where: { nodeTypes($0.dict).contains(where: isEducationEventType) }) {
            return true
        }

        // The label is only a tie-breaker: never alone, never over a strong article signal.
        if educationLabelled, titleWord, !hasStrongArticleSignal(url: url, nodes: nodes) {
            return true
        }
        return false
    }

    /// Whether the page has a Course JSON-LD node (anywhere, @graph included).
    nonisolated static func hasCourseNode(html: String) -> Bool {
        jsonLDTypedNodes(from: html).contains { nodeTypes($0.dict).contains(where: isCourseType) }
    }

    /// Article signals that a course rule must not override: Article-family JSON-LD, a dated
    /// path, a blog-style slug, a Medium / Substack post or a dated Codrops URL.
    nonisolated private static func hasStrongArticleSignal(url: URL, nodes: [TypedNode]) -> Bool {
        nodes.contains(where: { nodeTypes($0.dict).contains(where: isArticleType) })
            || isArticleShapedURL(url)
    }

    /// A dated path, a `/blog/<slug>`-style path, a Medium / Substack post or a Codrops article.
    nonisolated static func isArticleShapedURL(_ url: URL) -> Bool {
        urlPathDate(url) != nil || hasArticlePathSlug(url)
            || isMediumPost(url) || isSubstackPost(url) || isCodropsArticle(url)
    }

    /// The known course host the URL is on (exact host or a subdomain of it), else nil.
    nonisolated static func courseHost(for url: URL) -> String? {
        guard let host = bareHost(url) else { return nil }
        func matches(_ root: String) -> Bool { host == root || host.hasSuffix("." + root) }
        // university.webflow.com is listed, webflow.com itself is not a course host.
        for root in multiPurposeCourseHosts.union(singlePurposeCourseHosts).union(["joshwcomeau.com"]).sorted()
            where matches(root) {
            return root
        }
        return nil
    }

    /// A course page on a known course host: on frontendmasters / maven / udemy / coursera /
    /// domestika / skillshare / egghead / Webflow University, a course path (`/course/`,
    /// `/courses/`, `/learn/`, `/classes/` + a slug, or maven `/<instructor>/<slug>`); on
    /// joshwcomeau.com, a `/courses` path; on a single-purpose course site (Motion Design School,
    /// SuperHi, Shift Nudge, The Basics, DesignCourse), any path that isn't a blog post.
    nonisolated static func isCourseHostURL(_ url: URL) -> Bool {
        guard let root = courseHost(for: url), let host = bareHost(url) else { return false }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)

        if root == "joshwcomeau.com" { return parts.contains("courses") }

        if singlePurposeCourseHosts.contains(root) {
            if host.hasPrefix("blog.") { return false }
            if parts.contains("blog") || isArticleShapedURL(url) { return false }
            return true
        }

        // Multi-purpose hosts: a course path segment followed by a slug.
        for (i, part) in parts.enumerated() where courseHostPathSegments.contains(part) && i + 1 < parts.count {
            let slug = parts[i + 1]
            if !slug.isEmpty, !articleListingSlugs.contains(slug) { return true }
        }
        if root == "maven.com", host == "maven.com", parts.count >= 2,
           let first = parts.first, !mavenReservedSegments.contains(first) {
            return true
        }
        return false
    }

    /// A `course(s)` / `program(s)` / `masterclass` / `bootcamp` / `workshop` path segment
    /// followed by a slug (`/courses/motion-basics`), or as the last segment with something
    /// before it (`/design/masterclass`). Never under a `/blog/` path or on a dated /
    /// blog-style URL; listing slugs (`/courses/page/2`) don't count.
    nonisolated static func hasCoursePathSegment(_ url: URL) -> Bool {
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        guard !parts.contains("blog"), !isArticleShapedURL(url) else { return false }
        for (i, part) in parts.enumerated() where coursePathSegments.contains(part) {
            if i + 1 < parts.count {
                let slug = parts[i + 1]
                if !slug.isEmpty, !articleListingSlugs.contains(slug) { return true }
            } else if i > 0 {
                return true
            }
        }
        return false
    }

    /// The format a course path names: `/program(s)/` → program, `/workshop/` → workshop.
    nonisolated static func coursePathFormat(_ url: URL) -> String? {
        guard hasCoursePathSegment(url) else { return nil }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        if parts.contains("program") || parts.contains("programs") { return "program" }
        if parts.contains("workshop") { return "workshop" }
        return nil
    }

    /// A course word ("course", "masterclass", "bootcamp", "workshop", "academy", "learn",
    /// "master") as a whole word in the title.
    nonisolated static func titleHasCourseWord(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { courseTitleWords.contains(String($0)) }
    }

    // MARK: - Article (deterministic rules only — extraction lives in ArticleReader)

    /// Collection label that breaks the og:type-article tie (label + og:type article → article).
    /// The `education` label never makes an article on its own.
    nonisolated static let newsLabel = "news"

    /// Path segments that, FOLLOWED by a slug segment, mark a single post (`/blog/<slug>`);
    /// the index (`/blog/`) alone is not an article.
    nonisolated static let articlePathSegments: Set<String> = [
        "blog", "article", "articles", "post", "posts", "news", "essays", "writing",
    ]

    /// Segments after an article path segment that are listing pages, not a post slug.
    nonisolated private static let articleListingSlugs: Set<String> = [
        "page", "tag", "tags", "category", "categories", "author", "authors", "archive", "archives",
        "feed", "rss", "atom", "search", "topic", "topics",
    ]

    /// First path segments on medium.com that are site pages, not a profile / publication.
    nonisolated private static let mediumReservedSegments: Set<String> = [
        "tag", "tags", "topic", "topics", "me", "m", "search", "membership", "about", "plans",
        "creators", "policy", "jobs", "signin", "login", "new-story", "followers", "following",
    ]

    /// Whether the page is an article. Runs after the tool rule (kind order: gone → post →
    /// resource → book → product → tool → course → article → existing). Article when ANY of:
    /// an Article / NewsArticle / BlogPosting / TechArticle / Report / ScholarlyArticle JSON-LD
    /// node; an `article:published_time` meta; a dated path (`/YYYY/MM/…`, `/YYYY/Mon/…`,
    /// `/YYYY/MM/DD/…`); a `blog` / `article(s)` / `post(s)` / `news` / `essays` / `writing`
    /// segment followed by a slug; a Medium post (beyond the profile), a Substack `/p/<slug>`
    /// or a dated Codrops URL; og:type article together with an author or date signal — or
    /// with the `news` label. og:type article alone is NOT enough (course and template pages
    /// set it). A bare image file is never an article.
    nonisolated static func isArticle(url: URL, ogType: String?, html: String, collectionLabels: [String]) -> Bool {
        isArticle(
            url: url, ogType: ogType, nodes: jsonLDTypedNodes(from: html), html: html,
            collectionLabels: collectionLabels
        )
    }

    nonisolated private static func isArticle(
        url: URL,
        ogType: String?,
        nodes: [TypedNode],
        html: String,
        collectionLabels: [String]
    ) -> Bool {
        guard !isBareImageURL(url) else { return false }

        if nodes.contains(where: { nodeTypes($0.dict).contains(where: isArticleType) }) { return true }

        let metas = html.isEmpty ? [] : CaptureService.metaTagAttributes(in: html)
        func metaContent(_ key: String) -> String? {
            for attrs in metas {
                let name = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
                if name == key, let content = attrs["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !content.isEmpty {
                    return content
                }
            }
            return nil
        }

        if metaContent("article:published_time") != nil { return true }
        if urlPathDate(url) != nil { return true }
        if hasArticlePathSlug(url) || isMediumPost(url) || isSubstackPost(url) || isCodropsArticle(url) {
            return true
        }

        let type = ogType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard type == "article" else { return false }

        if hasLabel(newsLabel, in: collectionLabels) { return true }

        let hasAuthor = metaContent("author") != nil
            || metaContent("article:author") != nil
            || metaContent("twitter:label1")?.lowercased() == "written by"
            || nodes.contains { $0.dict["author"] != nil }
        let hasDate = metaContent("article:modified_time") != nil
            || nodes.contains { $0.dict["datePublished"] != nil }
        return hasAuthor || hasDate
    }

    nonisolated private static let monthAbbreviations = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    ]

    /// The date a dated path names — `/YYYY/MM/<slug>`, `/YYYY/Mon/<slug>` (`/2025/Mar/11/x`)
    /// or `/YYYY/MM/DD/<slug>`, with a 19xx / 20xx year — as (year, month, day?). A slug
    /// segment must follow the date, so an archive listing (`/2025/03/`) doesn't count.
    nonisolated static func urlPathDate(_ url: URL) -> (year: Int, month: Int, day: Int?)? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return nil }
        for i in 0..<(parts.count - 2) {
            guard let year = pathYear(parts[i]), let month = pathMonth(parts[i + 1]) else { continue }
            var day: Int? = nil
            var next = i + 2
            if let d = Int(parts[next]), parts[next].count <= 2, parts[next].allSatisfy(\.isNumber), (1...31).contains(d) {
                day = d
                next += 1
            }
            guard next < parts.count, !parts[next].isEmpty else { continue }
            return (year, month, day)
        }
        return nil
    }

    /// "2025" → 2025 for a 19xx / 20xx year; nil otherwise.
    nonisolated private static func pathYear(_ segment: String) -> Int? {
        guard segment.count == 4, segment.allSatisfy({ $0.isASCII && $0.isNumber }),
              segment.hasPrefix("19") || segment.hasPrefix("20") else { return nil }
        return Int(segment)
    }

    /// "03" / "3" / "Mar" / "mar" → 3; nil otherwise.
    nonisolated private static func pathMonth(_ segment: String) -> Int? {
        if (1...2).contains(segment.count), segment.allSatisfy({ $0.isASCII && $0.isNumber }) {
            guard let m = Int(segment), (1...12).contains(m) else { return nil }
            return m
        }
        if segment.count == 3, let index = monthAbbreviations.firstIndex(of: segment.lowercased()) {
            return index + 1
        }
        return nil
    }

    /// `…/blog/<slug>` (also article(s), post(s), news, essays, writing) — the index alone,
    /// pagination, tag / category / author listings and feeds don't count.
    nonisolated static func hasArticlePathSlug(_ url: URL) -> Bool {
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        for (i, part) in parts.enumerated() where articlePathSegments.contains(part) && i + 1 < parts.count {
            let slug = parts[i + 1]
            if slug.isEmpty || articleListingSlugs.contains(slug) || slug.hasSuffix(".xml") { continue }
            return true
        }
        return false
    }

    /// medium.com/@user/<slug> or medium.com/<publication>/<slug>; <user>.medium.com/<slug>.
    /// A profile (`medium.com/@user`, `user.medium.com`) and site pages are not posts.
    nonisolated static func isMediumPost(_ url: URL) -> Bool {
        guard let host = bareHost(url) else { return false }
        let parts = url.path.split(separator: "/").map { $0.lowercased() }
        guard let first = parts.first, !mediumReservedSegments.contains(first) else { return false }
        if host == "medium.com" { return parts.count >= 2 }
        if host.hasSuffix(".medium.com") { return !parts.isEmpty && !first.hasPrefix("@") }
        return false
    }

    /// `<name>.substack.com/p/<slug>`.
    nonisolated static func isSubstackPost(_ url: URL) -> Bool {
        guard let host = bareHost(url), host.hasSuffix(".substack.com") else { return false }
        let parts = url.path.split(separator: "/").map(String.init)
        return parts.count >= 2 && parts[0].lowercased() == "p" && !parts[1].isEmpty
    }

    /// `tympanus.net/codrops/<YYYY>/…` — a dated Codrops article or tutorial.
    nonisolated static func isCodropsArticle(_ url: URL) -> Bool {
        guard bareHost(url) == "tympanus.net" else { return false }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        return parts.count >= 3 && parts[0] == "codrops" && pathYear(parts[1]) != nil
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
