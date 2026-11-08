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
    /// HTTP status of the final response (nil for non-HTTP responses).
    var statusCode: Int? = nil
    /// URL after redirects — the product `canonicalURL`; `sourceURL` stays untouched.
    var finalURL: URL? = nil

    /// 404 / 410: the page is gone. The item is kept (with any saved image) and still
    /// classified from its URL, but carries `status = "gone"`. Never-clearing bot walls
    /// are not detected yet.
    var isGone: Bool {
        statusCode == 404 || statusCode == 410
    }
}

// MARK: - CaptureService

enum CaptureService {

    // MARK: - Shared HTML parsing regexes

    /// Matches a `<meta ...>` tag, capturing its attribute string.
    nonisolated static let metaTagRegex = try? NSRegularExpression(
        pattern: #"<meta\s+([^>]*)>"#,
        options: .caseInsensitive
    )

    /// Matches `key="value"` / `key='value'` / `key=value` attribute pairs.
    nonisolated static let htmlAttrRegex = try? NSRegularExpression(
        pattern: #"([\w:.-]+)\s*=\s*(?:"([^"]*?)"|'([^']*?)'|([^\s>]+))"#,
        options: .caseInsensitive
    )

    /// Parses an attribute string (the captured group from `metaTagRegex`/an opening tag) into a
    /// lowercase-keyed dictionary.
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

    /// Parses all `<meta ...>` tags in `html` into per-tag attribute dictionaries.
    nonisolated static func metaTagAttributes(in html: String) -> [[String: String]] {
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
        // Decoded so the panel never shows a raw `&gt;` from og:description.
        let summary = og.description.map { String(decodeBasicEntities($0).prefix(200)) }
        let dom = domain(from: url)

        // The Worker's page readers decide the kind and fields (the one copy of the rules).
        // Unreachable (offline, signed out of the web account, or the share extension, which
        // has no web sign-in): a plain link for now, queued for the background pass to sort.
        let read = await WorkerSorter.read(url: url, page: page)
        let kind = read?.kind ?? .link
        let title = read?.title ?? ogTitle
        // Music items never carry page prose; posts and non-page products carry their own
        // text (the Worker picks which).
        let extracted = read.map(\.extractedText) ?? extractText(html: html)

        var itemImage: ItemImage? = nil
        var galleryImages: [ItemImage] = []
        if let read {
            (itemImage, galleryImages) = await downloadReadImages(read)
        } else if let imgURL = og.imageURL, let (data, w, h) = await downloadImage(url: imgURL) {
            itemImage = ItemImage(data: data, source: "og", isPrimary: true, width: w, height: h)
        }

        let slug = makeSlug(from: title, context: context)
        let tagSpecs = RuleTagger.generateTags(title: title, description: summary, domain: dom)

        let item = Item(
            slug: slug, title: title, sourceURL: normalized, domain: read?.domain ?? dom,
            summary: summary, extractedText: extracted,
            status: ((page?.isGone ?? false) || (read?.isGone ?? false)) ? "gone" : "active",
            enrichmentStatus: read == nil ? WorkerSorter.unsortedStatus : "text_done",
            kind: kind.rawValue,
            metadataJSON: read?.metadataJSON
        )
        context.insert(item)

        if let img = itemImage {
            context.insert(img)
            img.item = item
        }
        for img in galleryImages {
            context.insert(img)
            img.item = item
        }

        item.tags = tagSpecs.map { ItemTag(name: $0.name, category: $0.category, weight: $0.weight) }

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

        item.tags = tagSpecs.map { ItemTag(name: $0.name, category: $0.category, weight: $0.weight) }

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

        item.tags = [ItemTag(name: "image-upload", category: "format", weight: 0.4)]

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
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        // Read the (nearly) whole document, not a 50KB head-slice: real pages put og:image
        // deep — measured 2026-07-16: midday.ai at byte ~238k of 986k, fonts.google.com at
        // ~196k of 198k — and a mid-tag truncation also leaves <style>/<script> blocks
        // unterminated, which defeats extractText's stripping (CSS leaked into snippets).
        // 2MB bounds memory; beyond that a page is not going to yield better metadata.
        let slice = data.prefix(2_000_000)
        guard let html = String(data: slice, encoding: .utf8)
                      ?? String(data: slice, encoding: .isoLatin1) else { return nil }
        return PageFetchResult(
            html: html,
            og: parseOG(html: html, baseURL: url),
            statusCode: (response as? HTTPURLResponse)?.statusCode,
            finalURL: response.url
        )
    }

    static func fetchOG(url: URL) async -> OGResult {
        await fetchPage(url: url)?.og ?? OGResult()
    }

    /// Parses OG/Twitter meta tags order-independently (no assumption on attribute order within a tag).
    nonisolated static func parseOG(html: String, baseURL: URL) -> OGResult {
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
    /// `limit: nil` returns the whole text (article reading time counts every word).
    static func extractText(html: String, limit: Int? = 4_000) -> String? {
        guard !html.isEmpty else { return nil }
        // Prefer body content: everything before <body> is metadata/CSS/JS, never prose.
        var page = html
        if let bodyRange = page.range(of: "<body", options: .caseInsensitive) {
            page = String(page[bodyRange.lowerBound...])
        }
        // The page's own prose lives in <article>, else <main>: reading only that keeps
        // site menus, sign-in prompts and sidebars out of the text the snippets are picked
        // from. A region with too little prose (a card on a home page) falls back to the
        // whole body. Same rules as the Worker's `extractText` (src/lib/readers/html.js).
        for tag in ["article", "main"] {
            guard let region = between(page, tag: tag), let text = proseText(region),
                  text.split(separator: " ").count >= minRegionWords else { continue }
            return limit.map { String(text.prefix($0)) } ?? text
        }
        guard let text = proseText(page) else { return nil }
        return limit.map { String(text.prefix($0)) } ?? text
    }

    /// A region under this many words isn't the page's prose.
    static let minRegionWords = 60

    /// From the first `<tag` to the last `</tag>` (spans nested and sibling elements).
    private static func between(_ html: String, tag: String) -> String? {
        guard let start = html.range(of: "<\(tag)[\\s>]", options: [.regularExpression, .caseInsensitive]),
              let end = html.range(of: "</\(tag)>", options: [.backwards, .caseInsensitive]),
              start.lowerBound < end.lowerBound else { return nil }
        return String(html[start.lowerBound..<end.lowerBound])
    }

    /// Tag-stripped prose: code blocks and page chrome (menus, headers and footers,
    /// sidebars, forms, buttons) dropped, entities decoded, code-like tokens filtered.
    private static func proseText(_ html: String) -> String? {
        var text = html
        // The trailing `|$` variant also swallows unterminated blocks (a truncated page
        // once leaked raw Tailwind CSS into snippets because its </style> was cut off).
        for tag in ["script", "style", "noscript", "svg", "template"] {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?(</\(tag)>|$)",
                with: " ", options: [.regularExpression, .caseInsensitive]
            )
        }
        // Chrome: only whole elements go, so an unclosed <header> never eats the page.
        for tag in ["nav", "header", "footer", "aside", "form", "button", "dialog", "select"] {
            text = text.replacingOccurrences(
                of: "<\(tag)[\\s>][\\s\\S]*?</\(tag)>",
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
        return text.isEmpty ? nil : text
    }

    nonisolated private static let basicEntities: [(String, String)] = [
        ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ("&mdash;", "—"), ("&ndash;", "–"),
        ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"),
    ]

    /// The common named / numeric HTML entities → characters. Shared with the panel's
    /// `PanelDedupe.normalize` and the og description that becomes `item.summary`.
    nonisolated static func decodeBasicEntities(_ s: String) -> String {
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

    /// Concurrent `downloadImage` over `urls`, results in input order (nil = failed).
    static func downloadImages(_ urls: [URL]) async -> [(Data, Int, Int)?] {
        guard !urls.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, (Data, Int, Int)?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask { (index, await downloadImage(url: url)) }
            }
            var results = [(Data, Int, Int)?](repeating: nil, count: urls.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results
        }
    }

    /// The images a Worker read points at. A product gallery / post media: first = cover,
    /// the rest `gallery` (Instagram and X media URLs are signed / expiring, so the bytes are
    /// copied now). Otherwise the cover alone. Fallbacks (og:image behind a gallery, book
    /// covers) are tried in order when nothing downloads.
    static func downloadReadImages(_ read: WorkerRead) async -> (cover: ItemImage?, gallery: [ItemImage]) {
        var cover: ItemImage? = nil
        var gallery: [ItemImage] = []
        if read.imageSource == "product" || read.imageSource == "post" {
            for (data, w, h) in await downloadImages(read.imageURLs).compactMap({ $0 }) {
                if cover == nil {
                    cover = ItemImage(data: data, source: read.imageSource, isPrimary: true, width: w, height: h)
                } else {
                    gallery.append(ItemImage(
                        data: data, source: read.imageSource, isPrimary: false, width: w, height: h,
                        role: ItemImageRole.gallery.rawValue
                    ))
                }
            }
        } else if let first = read.imageURLs.first, let (data, w, h) = await downloadImage(url: first) {
            cover = ItemImage(data: data, source: "og", isPrimary: true, width: w, height: h)
        }
        if cover == nil {
            let fallbackSource = read.kind == .book ? "book" : "og"
            for url in read.fallbackImageURLs {
                if let (data, w, h) = await downloadImage(url: url) {
                    cover = ItemImage(data: data, source: fallbackSource, isPrimary: true, width: w, height: h)
                    break
                }
            }
        }
        return (cover, gallery)
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

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
