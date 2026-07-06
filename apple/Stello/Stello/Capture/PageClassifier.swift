import Foundation

// MARK: - Result

struct PageClassificationResult: Sendable {
    var kind: ItemKind
    var individualMeta: IndividualMeta?
}

// MARK: - PageClassifier

/// Deterministic page kind + metadata from fetched HTML. No AI.
struct PageClassifier {

    private static let foundrySignals = ["foundry", "typefoundry", "type-foundry", "fonts"]

    // MARK: - Public

    nonisolated static func classify(
        html: String,
        baseURL: URL,
        domain: String?,
        title: String?,
        ogDescription: String?
    ) -> PageClassificationResult {
        let isIndividual = hasIndividualSignals(html: html)
        let isFoundry = hasFoundrySignals(html: html, domain: domain, title: title)

        if isIndividual && isFoundry {
            return PageClassificationResult(kind: .link, individualMeta: nil)
        }
        if isIndividual {
            let meta = extractIndividualMeta(
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

    nonisolated private static func hasIndividualSignals(html: String) -> Bool {
        if ogType(from: html)?.lowercased() == "profile" { return true }
        return jsonLDTypedNodes(from: html).contains { nodeTypes($0).contains(where: isPersonType) }
    }

    nonisolated private static func hasFoundrySignals(html: String, domain: String?, title: String?) -> Bool {
        let hasOrg = jsonLDTypedNodes(from: html).contains { nodeTypes($0).contains(where: isOrganizationType) }
        guard hasOrg else { return false }
        return foundryKeywordMatch(domain: domain) || foundryKeywordMatch(title: title)
    }

    // MARK: - Individual metadata

    nonisolated private static func extractIndividualMeta(
        html: String,
        baseURL: URL,
        ogDescription: String?
    ) -> IndividualMeta? {
        var meta = IndividualMeta()

        if let bio = ogDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
            meta.bio = bio
        }

        if let person = jsonLDTypedNodes(from: html).first(where: { nodeTypes($0).contains(where: isPersonType) }) {
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

    nonisolated private static func jsonLDTypedNodes(from html: String) -> [[String: Any]] {
        guard let scriptRegex = try? NSRegularExpression(
            pattern: #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#,
            options: .caseInsensitive
        ) else { return [] }

        let nsHTML = html as NSString
        var nodes: [[String: Any]] = []
        for match in scriptRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            guard let bodyRange = Range(match.range(at: 1), in: html) else { continue }
            let body = String(html[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            nodes.append(contentsOf: collectTypedNodes(from: json))
        }
        return nodes
    }

    nonisolated private static func collectTypedNodes(from value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            var results: [[String: Any]] = []
            if dict["@type"] != nil { results.append(dict) }
            if let graph = dict["@graph"] {
                results.append(contentsOf: collectTypedNodes(from: graph))
            }
            return results
        }
        if let array = value as? [Any] {
            return array.flatMap { collectTypedNodes(from: $0) }
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

    // MARK: - OG type

    nonisolated private static func ogType(from html: String) -> String? {
        for attrs in metaTagAttributes(in: html) {
            let property = attrs["property"] ?? ""
            if property.lowercased() == "og:type" {
                return attrs["content"]
            }
        }
        return nil
    }

    // MARK: - Social links

    private enum SocialPlatform {
        case x, instagram, linkedIn, behance, bluesky, mastodon, threads
    }

    nonisolated private static func applySocialLinks(from html: String, baseURL: URL, to meta: inout IndividualMeta) {
        for link in anchorAndLinkTags(in: html) {
            guard let href = link.href,
                  let resolved = resolveURL(href, base: baseURL) else { continue }
            let absolute = resolved.absoluteString
            let relTokens = Set(link.rel.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
            let isRelMe = relTokens.contains("me")

            if let platform = socialPlatform(for: resolved) {
                assignSocialURL(absolute, platform: platform, to: &meta)
            } else if isRelMe, resolved.scheme?.lowercased() == "https" {
                assignSocialURL(absolute, platform: .mastodon, to: &meta)
            }
        }
    }

    nonisolated private static func socialPlatform(for url: URL) -> SocialPlatform? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }

        switch host {
        case "x.com", "twitter.com", "mobile.twitter.com":
            return .x
        case _ where host.contains("instagram.com"):
            return .instagram
        case _ where host.contains("linkedin.com"):
            return .linkedIn
        case _ where host.contains("behance.net"):
            return .behance
        case _ where host.contains("bsky.app"):
            return .bluesky
        case _ where host.contains("threads.net"):
            return .threads
        default:
            return nil
        }
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
    }

    nonisolated private static func anchorAndLinkTags(in html: String) -> [ParsedLinkTag] {
        var results: [ParsedLinkTag] = []
        let patterns = [
            #"<a\s+([^>]*)>"#,
            #"<link\s+([^>]*)>"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsHTML = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
                guard let attrRange = Range(match.range(at: 1), in: html) else { continue }
                let attrs = parseAttributes(String(html[attrRange]))
                results.append(ParsedLinkTag(
                    href: attrs["href"],
                    rel: attrs["rel"] ?? ""
                ))
            }
        }
        return results
    }

    // MARK: - Foundry keyword match

    nonisolated private static func foundryKeywordMatch(domain: String?) -> Bool {
        guard let domain, !domain.isEmpty else { return false }
        return foundryKeywordMatch(in: domain)
    }

    nonisolated private static func foundryKeywordMatch(title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        return foundryKeywordMatch(in: title)
    }

    nonisolated private static func foundryKeywordMatch(in text: String) -> Bool {
        let lowered = text.lowercased()
        return foundrySignals.contains { lowered.contains($0) }
    }

    // MARK: - HTML attribute parsing

    nonisolated private static func metaTagAttributes(in html: String) -> [[String: String]] {
        guard let metaRegex = try? NSRegularExpression(
            pattern: #"<meta\s+([^>]*)>"#,
            options: .caseInsensitive
        ) else { return [] }

        let nsHTML = html as NSString
        return metaRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).compactMap { match in
            guard let attrRange = Range(match.range(at: 1), in: html) else { return nil }
            return parseAttributes(String(html[attrRange]))
        }
    }

    nonisolated private static func parseAttributes(_ attrsStr: String) -> [String: String] {
        guard let attrRegex = try? NSRegularExpression(
            pattern: #"([\w:.-]+)\s*=\s*(?:"([^"]*?)"|'([^']*?)'|([^\s>]+))"#,
            options: .caseInsensitive
        ) else { return [:] }

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
