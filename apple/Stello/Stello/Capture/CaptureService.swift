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
}

// MARK: - CaptureService

enum CaptureService {

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

        let og = await fetchOG(url: url)
        let title = og.title ?? url.host ?? url.absoluteString
        let summary = og.description.map { String($0.prefix(200)) }
        let dom = domain(from: url)

        var itemImage: ItemImage? = nil
        if let imgURL = og.imageURL, let (data, w, h) = await downloadImage(url: imgURL) {
            itemImage = ItemImage(data: data, source: "og", isPrimary: true, width: w, height: h)
        }

        let slug = makeSlug(from: title, context: context)
        let tagSpecs = RuleTagger.generateTags(title: title, description: summary, domain: dom)

        let item = Item(
            slug: slug, title: title, sourceURL: normalized, domain: dom,
            summary: summary, enrichmentStatus: "text_done"
        )
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

    static func fetchOG(url: URL) async -> OGResult {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return OGResult() }
        let slice = data.prefix(50_000)
        guard let html = String(data: slice, encoding: .utf8)
                      ?? String(data: slice, encoding: .isoLatin1) else { return OGResult() }
        return parseOG(html: html, baseURL: url)
    }

    /// Parses OG/Twitter meta tags order-independently (no assumption on attribute order within a tag).
    static func parseOG(html: String, baseURL: URL) -> OGResult {
        var result = OGResult()

        guard let metaRegex = try? NSRegularExpression(
            pattern: #"<meta\s+([^>]*)>"#,
            options: .caseInsensitive
        ) else { return result }

        // Handles double-quoted, single-quoted, and unquoted attribute values.
        guard let attrRegex = try? NSRegularExpression(
            pattern: #"([\w:.-]+)\s*=\s*(?:"([^"]*?)"|'([^']*?)'|([^\s>]+))"#,
            options: .caseInsensitive
        ) else { return result }

        let nsHTML = html as NSString
        let metaMatches = metaRegex.matches(
            in: html, range: NSRange(location: 0, length: nsHTML.length)
        )

        for metaMatch in metaMatches {
            guard let attrRange = Range(metaMatch.range(at: 1), in: html) else { continue }
            let attrsStr = String(html[attrRange])
            let nsAttrs = attrsStr as NSString

            // Extract all key=value pairs from this <meta> tag into a dictionary.
            var attrs: [String: String] = [:]
            let attrMatches = attrRegex.matches(
                in: attrsStr, range: NSRange(location: 0, length: nsAttrs.length)
            )
            for am in attrMatches {
                guard let kr = Range(am.range(at: 1), in: attrsStr) else { continue }
                let key = String(attrsStr[kr]).lowercased()
                var value = ""
                for g in 2...4 {
                    let r = am.range(at: g)
                    if r.location != NSNotFound, let vr = Range(r, in: attrsStr) {
                        value = String(attrsStr[vr])
                        break
                    }
                }
                attrs[key] = value
            }

            let property = attrs["property"] ?? ""
            let name = attrs["name"] ?? ""
            let content = attrs["content"] ?? ""

            switch property {
            case "og:title":        if result.title == nil { result.title = content }
            case "og:description":  if result.description == nil { result.description = content }
            case "og:image":        if result.imageURL == nil { result.imageURL = resolve(content, base: baseURL) }
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
