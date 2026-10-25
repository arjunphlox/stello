import Foundation

// MARK: - Types

/// Result of the deterministic resource readers: metadata and the title the item should carry
/// (nil = keep the page title).
nonisolated struct ResourceExtraction: Sendable {
    var meta: ResourceMeta
    var title: String?
}

// MARK: - ResourceReader

/// Pure, network-free resource readers (Figma Community / Framer Marketplace / CodePen pages
/// and `digital-resources` / `books`-labelled pages): CreativeWork / Product JSON-LD, og:title
/// and redirects. Everything comes from the capture-time page fetch — no extra network.
nonisolated enum ResourceReader {

    // MARK: - JSON-LD

    /// Node types that describe the resource itself (not the site, breadcrumbs or org).
    static let resourceNodeTypes: [String] = [
        "CreativeWork", "SoftwareApplication", "WebApplication", "SoftwareSourceCode",
        "Product", "ProductGroup", "IndividualProduct", "DigitalDocument", "VisualArtwork",
    ]

    static func isResourceNodeType(_ type: String) -> Bool {
        resourceNodeTypes.contains { type.caseInsensitiveCompare($0) == .orderedSame }
    }

    /// Fills from the first CreativeWork / Product / SoftwareApplication-style node: name,
    /// maker (creator → brand → author), offers, isAccessibleForFree, interactionStatistic.
    static func applyJSONLD(html: String, base: URL, to meta: inout ResourceMeta) {
        let nodes = PageClassifier.jsonLDNodes(from: html)
        guard let node = nodes.first(where: { $0.types.contains(where: isResourceNodeType) })?.dict else { return }

        if meta.name == nil { meta.name = strippedName(ProductReader.string(node["name"])) }

        if meta.maker == nil {
            for key in ["creator", "brand", "author"] {
                if let ref = makerRef(from: node[key], base: base) {
                    meta.maker = ref
                    break
                }
            }
        }

        // Offers: price 0 → free; any positive price → paid at the lowest positive price.
        let offers = ToolReader.offerPricing(from: node["offers"])
        if meta.pricing == nil {
            switch offers.pricing {
            case "free":
                meta.pricing = "free"
            case "paid", "freemium":
                meta.pricing = "paid"
                meta.price = offers.price
                meta.currency = offers.currency
            default:
                break
            }
        }
        if meta.pricing == nil, isTrue(node["isAccessibleForFree"]) { meta.pricing = "free" }

        let counts = interactionCounts(from: node["interactionStatistic"])
        if meta.users == nil { meta.users = counts.users }
        if meta.likes == nil { meta.likes = counts.likes }
    }

    private static func isTrue(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        return ProductReader.string(value)?.lowercased() == "true"
    }

    /// `creator` / `brand` / `author`: a string, a `{name, url}` object, or an array of either
    /// (first named one wins). A relative `url` resolves against the page.
    static func makerRef(from value: Any?, base: URL) -> EntityRef? {
        if let raw = value as? String, let name = ToolReader.clean(raw) {
            return ToolReader.makerRef(name)
        }
        if let dict = value as? [String: Any] {
            guard let name = ProductReader.string(dict["name"]) ?? ProductReader.string(dict["alternateName"]) else {
                return nil
            }
            var ref = ToolReader.makerRef(name)
            if let raw = ProductReader.string(dict["url"]) ?? ProductReader.string(dict["sameAs"]),
               let resolved = URL(string: raw, relativeTo: base)?.absoluteURL {
                ref.url = resolved.absoluteString
            }
            return ref
        }
        if let array = value as? [Any] {
            for element in array {
                if let ref = makerRef(from: element, base: base) { return ref }
            }
        }
        return nil
    }

    // MARK: - Interaction statistics

    private static let usersInteractionKeys: Set<String> = [
        "useaction", "downloadaction", "installaction", "userdownloads",
    ]
    private static let likesInteractionKeys: Set<String> = ["likeaction", "userlikes"]

    /// `interactionStatistic`: one InteractionCounter or an array of them. `interactionType`
    /// may be a string ("https://schema.org/UseAction", "LikeAction") or an object
    /// (`{"@type": "LikeAction"}`); legacy counters carry the type in their own `@type`
    /// ("UserLikes", "UserDownloads"). Use / Download / Install → users; Like → likes. The
    /// count may be a number or a string ("12,400", "12.4k"). The largest count per bucket wins.
    static func interactionCounts(from value: Any?) -> (users: Int?, likes: Int?) {
        var users: Int?
        var likes: Int?

        func visit(_ value: Any?) {
            if let array = value as? [Any] {
                for element in array { visit(element) }
                return
            }
            guard let counter = value as? [String: Any],
                  let count = parseCount(counter["userInteractionCount"]) else { return }
            let keys = [interactionKey(counter["interactionType"]), interactionKey(counter["@type"])].compactMap { $0 }
            if keys.contains(where: usersInteractionKeys.contains) {
                users = max(users ?? 0, count)
            } else if keys.contains(where: likesInteractionKeys.contains) {
                likes = max(likes ?? 0, count)
            }
        }

        visit(value)
        return (users, likes)
    }

    /// "https://schema.org/UseAction" → "useaction"; `{"@type": "LikeAction"}` → "likeaction".
    private static func interactionKey(_ value: Any?) -> String? {
        if let s = ProductReader.string(value) {
            let last = s.split(separator: "/").last.map(String.init) ?? s
            return last.lowercased()
        }
        if let dict = value as? [String: Any] {
            return interactionKey(dict["@type"]) ?? interactionKey(dict["@id"]) ?? interactionKey(dict["name"])
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap { interactionKey($0) }.first
        }
        return nil
    }

    /// 12400 / "12,400" / "12.4k" / "1.2M" → Int; nil for anything else or a negative value.
    static func parseCount(_ value: Any?) -> Int? {
        if let n = value as? Int { return n >= 0 ? n : nil }
        if let d = value as? Double { return d >= 0 ? Int(d.rounded()) : nil }
        guard let raw = ProductReader.string(value) else { return nil }
        var text = raw.lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        var multiplier = 1.0
        if text.hasSuffix("k") {
            multiplier = 1_000
            text = String(text.dropLast())
        } else if text.hasSuffix("m") {
            multiplier = 1_000_000
            text = String(text.dropLast())
        }
        guard let number = Double(text), number >= 0 else { return nil }
        return Int((number * multiplier).rounded())
    }

    // MARK: - Name

    /// Platform suffixes on og:title / JSON-LD names (matched case-insensitively at the end).
    private static let fixedNameSuffixes = [
        " | figma community", " | figma", " - figma community", " - figma",
        " | framer marketplace", " - framer marketplace", " — framer marketplace", " – framer marketplace",
        " | codepen", " - codepen", " on codepen",
    ]

    /// "Iconify | Figma" → "Iconify"; "Portfolio — Free Website Template for Framer" →
    /// "Portfolio"; "Nova - Framer Marketplace" → "Nova"; "CodePen - Wavy text" → "Wavy text".
    static func strippedName(_ raw: String?) -> String? {
        guard var text = ToolReader.clean(raw) else { return nil }

        var changed = true
        while changed {
            changed = false
            let lower = text.lowercased()
            for suffix in fixedNameSuffixes where lower.hasSuffix(suffix) && lower.count > suffix.count {
                text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                break
            }
            // " — Free Website Template for Framer" / " - UI Kit for Framer": cut at the last
            // separator before the "for Framer" tail.
            if !changed, text.lowercased().hasSuffix(" for framer") {
                let cut = [" — ", " – ", " - ", " | "]
                    .compactMap { text.range(of: $0, options: .backwards)?.lowerBound }
                    .max()
                if let cut, cut > text.startIndex {
                    text = String(text[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }

        for prefix in ["CodePen - ", "CodePen — "] where text.hasPrefix(prefix) && text.count > prefix.count {
            text = String(text.dropFirst(prefix.count))
        }
        return ToolReader.clean(text)
    }

    /// "Free" as a word in the og:title ("Portfolio — Free Website Template for Framer").
    static func titleSaysFree(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains("free")
    }

    // MARK: - Subtype + works with

    /// The subtype the URL path names: Figma plugin / widget / file; Framer Marketplace
    /// templates → template, plugins → plugin, components → component (other segments, e.g.
    /// vectors, → nil so the title words decide); a CodePen pen → pen.
    static func pathSubtype(url: URL) -> String? {
        if let type = PageClassifier.figmaCommunityResourceType(from: url) { return type }
        if let segment = PageClassifier.framerMarketplaceSegment(from: url) {
            switch segment {
            case "templates", "template": return "template"
            case "plugins", "plugin": return "plugin"
            case "components", "component": return "component"
            default: return nil
            }
        }
        if PageClassifier.isCodePenPenURL(url) { return "pen" }
        return nil
    }

    /// Conservative title words → subtype: mockup(s) → mockup; icons / icon set / icon pack →
    /// icon set; UI kit → file. Nil otherwise.
    static func titleSubtype(_ title: String?) -> String? {
        guard let lower = title?.lowercased() else { return nil }
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains("mockup") || words.contains("mockups") { return "mockup" }
        if words.contains("icons") || words.contains("iconset") || lower.contains("icon set") || lower.contains("icon pack") {
            return "icon set"
        }
        if lower.contains("ui kit") || lower.contains("ui-kit") || words.contains("uikit") { return "file" }
        return nil
    }

    /// Path subtype (source URL, then the redirect target) → title words → `library` for a site
    /// home page → nil.
    static func subtype(sourceURL: URL, finalURL: URL?, title: String?, collectionLabels: [String]) -> String? {
        if let fromPath = pathSubtype(url: sourceURL) ?? finalURL.flatMap({ pathSubtype(url: $0) }) {
            return fromPath
        }
        if let fromTitle = titleSubtype(title) { return fromTitle }
        let path = sourceURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty, sourceURL.query == nil { return "library" }
        return nil
    }

    /// Figma (FigJam when the title says so) / Framer / CodePen, from the host.
    static func worksWith(url: URL, title: String?) -> [String] {
        switch ProductReader.bareHost(url) {
        case "figma.com"?:
            return (title?.lowercased().contains("figjam") ?? false) ? ["FigJam"] : ["Figma"]
        case "framer.com"?:
            return ["Framer"]
        case "codepen.io"?:
            return ["CodePen"]
        default:
            return []
        }
    }

    // MARK: - Build

    /// Assembles `ResourceMeta` for one resource page. `ogTitle` is the page's og:title (or
    /// `<title>`); `collectionLabels` only matter for the `reading list` subtype.
    static func build(
        sourceURL: URL,
        finalURL: URL?,
        html: String,
        ogTitle: String?,
        collectionLabels: [String] = []
    ) -> ResourceExtraction {
        var meta = ResourceMeta()

        // 1. JSON-LD (CreativeWork / Product).
        applyJSONLD(html: html, base: finalURL ?? sourceURL, to: &meta)

        // 2. og:title: name fallback (suffix stripped), "Free" in the title.
        if meta.name == nil { meta.name = strippedName(ogTitle) }
        if meta.pricing == nil, titleSaysFree(ogTitle) { meta.pricing = "free" }

        // 3. Redirects: canonical whenever the final URL differs from the saved one.
        if let finalURL, finalURL.absoluteString != sourceURL.absoluteString {
            meta.canonicalURL = finalURL.absoluteString
        }

        let title = ogTitle ?? meta.name
        meta.subtype = subtype(sourceURL: sourceURL, finalURL: finalURL, title: title, collectionLabels: collectionLabels)
        meta.worksWith = worksWith(url: sourceURL, title: title)
        if meta.worksWith.isEmpty, let finalURL { meta.worksWith = worksWith(url: finalURL, title: title) }
        if meta.subtype == "reading list" { meta.worksWith = [] }

        return ResourceExtraction(meta: meta, title: meta.name)
    }

    // MARK: - Refresh merge

    /// A refetch that reads less (bot wall, login interstitial) never erases what capture read.
    static func merge(fresh: ResourceMeta, previous: ResourceMeta?) -> ResourceMeta {
        guard let previous else { return fresh }
        var meta = fresh
        if meta.subtype == nil { meta.subtype = previous.subtype }
        if meta.worksWith.isEmpty { meta.worksWith = previous.worksWith }
        if meta.name == nil { meta.name = previous.name }
        if meta.maker == nil { meta.maker = previous.maker }
        if meta.pricing == nil { meta.pricing = previous.pricing }
        if meta.price == nil {
            meta.price = previous.price
            meta.currency = previous.currency
        }
        if meta.users == nil { meta.users = previous.users }
        if meta.likes == nil { meta.likes = previous.likes }
        if meta.canonicalURL == nil { meta.canonicalURL = previous.canonicalURL }
        return meta
    }
}
