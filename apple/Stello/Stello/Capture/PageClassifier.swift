import Foundation

// MARK: - Result

struct PageClassificationResult: Sendable {
    var kind: ItemKind
    var individualMeta: IndividualMeta?
}

// MARK: - PageClassifier

/// Deterministic page kind + metadata from fetched HTML. No AI.
struct PageClassifier {

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
        ogType: String? = nil
    ) -> PageClassificationResult {
        // Parse JSON-LD once and pass the nodes down.
        let nodes = jsonLDTypedNodes(from: html)

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
}
