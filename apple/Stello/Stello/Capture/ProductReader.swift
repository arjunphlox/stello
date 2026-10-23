import Foundation

// MARK: - Types

/// A product name/brand guess — what the rule-based fallback and the on-device model both
/// return for Instagram / bare-image products (no structured data to read). Every value is
/// stored on `ProductMeta` with its `…IsGuess` flag set.
nonisolated struct ProductGuess: Sendable, Equatable {
    var productName: String?
    var brand: String?
}

/// What Instagram's public og tags say about a post.
nonisolated struct InstagramPostInfo: Sendable, Equatable {
    /// Bare handle, no "@".
    var handle: String?
    var displayName: String?
    var caption: String?
}

/// Result of the deterministic product readers: metadata, the gallery image URLs (cover
/// first, capped at `ProductReader.galleryCap`) and the title the item should carry.
nonisolated struct ProductExtraction: Sendable {
    var meta: ProductMeta
    var imageURLs: [URL]
    var title: String?
}

// MARK: - ProductReader

/// Pure, network-free product readers (Shopify `.json`, Product JSON-LD, og price tags,
/// Instagram og caption/creator, bare-image filename). The only network step — fetching the
/// Shopify `.json` — lives in `CaptureService.extractProduct`, which then calls `build`.
nonisolated enum ProductReader {

    /// Panel gallery cap (product-spec: "gallery (cap 8 of the shop's images)").
    static let galleryCap = 8

    // MARK: - Shopify `.json`

    nonisolated struct ShopifyEnvelope: Decodable {
        var product: ShopifyProduct
    }

    nonisolated struct ShopifyProduct: Decodable {
        var title: String?
        var vendor: String?
        var productType: String?
        var handle: String?
        var variants: [ShopifyVariant]?
        var images: [ShopifyImage]?
        var image: ShopifyImage?
        // Decoded with `.convertFromSnakeCase` (`product_type` → `productType`); no
        // all-caps "URL" names here, so the OEmbedResponse key pitfall doesn't apply.
    }

    nonisolated struct ShopifyVariant: Decodable {
        /// `.json` sends "2699.00" (string); some themes/proxies send a number — both decode.
        var price: LenientString?
    }

    nonisolated struct ShopifyImage: Decodable {
        var src: String?
        var width: Int?
        var height: Int?
    }

    /// Decodes a JSON string OR number into its string form.
    nonisolated struct LenientString: Decodable {
        var value: String

        init(_ value: String) { self.value = value }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                value = s
            } else if let i = try? container.decode(Int.self) {
                value = String(i)
            } else {
                let d = try container.decode(Double.self)
                value = String(d)
            }
        }
    }

    /// `<scheme>://<host>/products/<handle>.json` — query stripped, any
    /// `/collections/<x>/` prefix dropped. Nil when the URL isn't a `/products/` page.
    static func shopifyJSONURL(for url: URL) -> URL? {
        guard let handle = PageClassifier.shopifyHandle(from: url),
              let host = url.host, !host.isEmpty else { return nil }
        var comps = URLComponents()
        comps.scheme = url.scheme ?? "https"
        comps.host = host
        comps.port = url.port
        comps.path = "/products/\(handle).json"
        return comps.url
    }

    static func parseShopifyProduct(_ data: Data) -> ShopifyProduct? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Only the `.json` envelope — the `.js` endpoint prices in cents and would misread.
        return (try? decoder.decode(ShopifyEnvelope.self, from: data))?.product
    }

    static func applyShopify(_ product: ShopifyProduct, to meta: inout ProductMeta, images: inout [URL], base: URL) {
        if let title = clean(product.title) {
            meta.productName = title
            meta.productNameIsGuess = nil
        }
        if let vendor = clean(product.vendor) {
            meta.brand = brandRef(vendor)
            meta.brandIsGuess = nil
        }
        if meta.category == nil { meta.category = clean(product.productType) }

        let prices = (product.variants ?? []).compactMap { normalizePrice($0.price?.value) }
        if let first = prices.first {
            meta.price = first
            let decimals = prices.compactMap { Decimal(string: $0) }
            if let lo = decimals.min(), let hi = decimals.max(), lo != hi {
                meta.priceMin = prices.first { Decimal(string: $0) == lo }
                meta.priceMax = prices.first { Decimal(string: $0) == hi }
            }
        }

        var srcs = (product.images ?? []).compactMap(\.src)
        if srcs.isEmpty, let single = product.image?.src { srcs = [single] }
        appendImages(srcs, base: base, to: &images)
    }

    // MARK: - Product JSON-LD

    /// Fills gaps from the first Product/ProductGroup node: name, brand (string or `{name}`
    /// or an array of either), offers (Offer | AggregateOffer | arrays, `priceSpecification`),
    /// availability, category, image. Never overwrites what Shopify already set.
    static func applyJSONLD(html: String, to meta: inout ProductMeta, images: inout [URL], base: URL) {
        let nodes = PageClassifier.jsonLDNodes(from: html)
        guard let product = nodes.first(where: { node in
            node.types.contains { $0.caseInsensitiveCompare("Product") == .orderedSame
                || $0.caseInsensitiveCompare("ProductGroup") == .orderedSame }
        })?.dict else { return }

        if meta.productName == nil, let name = string(product["name"]) {
            meta.productName = name
        }
        if meta.brand == nil, let brand = brandName(from: product["brand"]) {
            meta.brand = brandRef(brand)
        }
        if meta.category == nil, let category = string(product["category"]) {
            meta.category = category
        }

        var offers = offerSummary(from: product["offers"])
        if offers.price == nil, offers.low == nil,
           let variants = product["hasVariant"] as? [Any] {
            for case let variant as [String: Any] in variants {
                let summary = offerSummary(from: variant["offers"])
                if summary.price != nil || summary.low != nil { offers = summary; break }
            }
        }

        if meta.price == nil {
            meta.price = offers.price ?? offers.low
            if let low = offers.low, let high = offers.high, low != high {
                meta.priceMin = low
                meta.priceMax = high
            }
        }
        // JSON-LD currency wins over og (og often omits it).
        if let currency = offers.currency { meta.currency = currency }
        if meta.availability == nil, let availability = offers.availability {
            meta.availability = availabilityLabel(availability)
        }

        if images.isEmpty {
            appendImages(imageStrings(from: product["image"]), base: base, to: &images)
        }
    }

    nonisolated struct OfferSummary: Sendable {
        var price: String?
        var low: String?
        var high: String?
        var currency: String?
        var availability: String?
    }

    static func offerSummary(from value: Any?) -> OfferSummary {
        var summary = OfferSummary()

        func visit(_ value: Any?) {
            if let array = value as? [Any] {
                for element in array { visit(element) }
                return
            }
            guard let offer = value as? [String: Any] else { return }

            if summary.currency == nil { summary.currency = string(offer["priceCurrency"])?.uppercased() }
            if summary.availability == nil { summary.availability = string(offer["availability"]) }

            if let low = normalizePrice(string(offer["lowPrice"])) {
                if summary.low == nil { summary.low = low }
            }
            if let high = normalizePrice(string(offer["highPrice"])) {
                if summary.high == nil { summary.high = high }
            }
            if summary.price == nil, let price = normalizePrice(string(offer["price"])) {
                summary.price = price
            }
            if let spec = offer["priceSpecification"] {
                let specs: [Any] = (spec as? [Any]) ?? [spec]
                for case let s as [String: Any] in specs {
                    if summary.price == nil { summary.price = normalizePrice(string(s["price"])) }
                    if summary.currency == nil { summary.currency = string(s["priceCurrency"])?.uppercased() }
                }
            }
            // AggregateOffer may nest its individual offers.
            if let nested = offer["offers"] { visit(nested) }
        }

        visit(value)
        return summary
    }

    static func brandName(from value: Any?) -> String? {
        if let s = string(value) { return s }
        if let dict = value as? [String: Any] { return string(dict["name"]) }
        if let array = value as? [Any] {
            for element in array { if let name = brandName(from: element) { return name } }
        }
        return nil
    }

    static func imageStrings(from value: Any?) -> [String] {
        if let s = string(value) { return [s] }
        if let dict = value as? [String: Any] {
            return [string(dict["url"]) ?? string(dict["contentUrl"])].compactMap { $0 }
        }
        if let array = value as? [Any] { return array.flatMap(imageStrings(from:)) }
        return []
    }

    // MARK: - og price tags

    /// `product:price:amount` / `og:price:amount` (+ `…:currency`), og:site_name,
    /// `product:availability`, `product:brand`. Fills gaps only; the currency is taken
    /// only when JSON-LD gave none.
    static func applyOGTags(html: String, to meta: inout ProductMeta) {
        var amount: String?
        var currency: String?
        var siteName: String?
        var availability: String?
        var brand: String?

        for attrs in CaptureService.metaTagAttributes(in: html) {
            let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            guard let content = clean(attrs["content"]) else { continue }
            switch key {
            case "product:price:amount", "og:price:amount":
                if amount == nil { amount = normalizePrice(content) }
            case "product:price:currency", "og:price:currency":
                if currency == nil { currency = content.uppercased() }
            case "og:site_name":
                if siteName == nil { siteName = content }
            case "product:availability", "og:availability":
                if availability == nil { availability = content }
            case "product:brand", "og:brand":
                if brand == nil { brand = content }
            default:
                break
            }
        }

        if meta.price == nil { meta.price = amount }
        if meta.currency == nil { meta.currency = currency }
        if meta.shop == nil { meta.shop = siteName }
        if meta.availability == nil, let availability { meta.availability = availabilityLabel(availability) }
        if meta.brand == nil, let brand { meta.brand = brandRef(brand) }
    }

    // MARK: - Instagram og caption / creator

    private static let instagramDescriptionRegex = try? NSRegularExpression(
        pattern: #"^\s*[\d.,]+[KkMm]?\s+likes?(?:,\s*[\d.,]+[KkMm]?\s+comments?)?\s*-\s*([A-Za-z0-9._]+)\s+on\s+([^:]+?):\s*([\s\S]*)$"#,
        options: []
    )

    private static let instagramTitleRegex = try? NSRegularExpression(
        pattern: #"^([\s\S]+?)\s+on\s+Instagram:\s*([\s\S]*)$"#,
        options: []
    )

    private static let handleInParensRegex = try? NSRegularExpression(
        pattern: #"\(@([A-Za-z0-9._]+)\)"#,
        options: []
    )

    /// og:description "N likes, M comments - handle on date: caption"; og:title
    /// "Name on Instagram: caption". Either alone is enough for what it carries.
    static func parseInstagramOG(title: String?, description: String?) -> InstagramPostInfo {
        var info = InstagramPostInfo()

        if let description, let regex = instagramDescriptionRegex,
           let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
            if let r = Range(match.range(at: 1), in: description) { info.handle = String(description[r]) }
            if let r = Range(match.range(at: 3), in: description) { info.caption = cleanCaption(String(description[r])) }
        }

        if let title, let regex = instagramTitleRegex,
           let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            if let r = Range(match.range(at: 1), in: title) {
                var name = String(title[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let handleRegex = handleInParensRegex,
                   let hm = handleRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                   let hr = Range(hm.range(at: 1), in: name),
                   let whole = Range(hm.range, in: name) {
                    if info.handle == nil { info.handle = String(name[hr]) }
                    name.removeSubrange(whole)
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                info.displayName = name.isEmpty ? nil : name
            }
            if info.caption == nil, let r = Range(match.range(at: 2), in: title) {
                info.caption = cleanCaption(String(title[r]))
            }
        }

        return info
    }

    /// Strips Instagram's wrapping quotes and trailing ". " from a caption.
    static func cleanCaption(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".") && (s.dropLast().hasSuffix("\"") || s.dropLast().hasSuffix("”")) {
            s = String(s.dropLast())
        }
        if let first = s.first, let last = s.last, s.count >= 2,
           (first == "\"" || first == "“") && (last == "\"" || last == "”") {
            s = String(s.dropFirst().dropLast())
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // MARK: - Bare image filename → title

    private static let genericFilenameWords: Set<String> = [
        "img", "image", "images", "photo", "pic", "dsc", "screenshot", "file", "untitled", "copy", "final",
    ]

    /// `umbra-buddy-wall-hooks-set-of-3-black-3.jpg` → "Umbra buddy wall hooks set of 3 black".
    /// Drops trailing counters, size suffixes (`1024x1024`, `@2x`) and hash-like tokens;
    /// nil when nothing descriptive is left (e.g. `IMG_1234.jpg`).
    static func titleFromImageFilename(_ url: URL) -> String? {
        let base = url.deletingPathExtension().lastPathComponent
        let decoded = base.removingPercentEncoding ?? base
        var tokens = decoded
            .split(whereSeparator: { "-_ +.@".contains($0) })
            .map { String($0).lowercased() }
            .filter { !isNoiseToken($0) }

        while let last = tokens.last, last.allSatisfy(\.isNumber) {
            tokens.removeLast()
        }
        guard !tokens.isEmpty,
              tokens.contains(where: { !genericFilenameWords.contains($0) && !$0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        let sentence = tokens.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    private static func isNoiseToken(_ token: String) -> Bool {
        // Size suffixes: 1024x1024, 600x, x800, 2x.
        if token.range(of: #"^\d*x\d*$"#, options: .regularExpression) != nil, token != "x" { return true }
        // Hashes / ids: long hex-ish runs with at least one digit (a1b2c3d4…).
        if token.count >= 8, token.contains(where: \.isNumber),
           token.allSatisfy({ $0.isHexDigit }) { return true }
        return false
    }

    // MARK: - Rule-based guess (fallback for the on-device job)

    /// Filename slug → sentence-case name; never a brand (nothing reliable to read it from).
    /// Captions are not parsed by rule — too free-form; only the on-device model guesses there.
    static func ruleBasedGuess(caption: String?, filename: String?) -> ProductGuess {
        var guess = ProductGuess()
        if let filename = clean(filename) {
            // A full URL keeps its path; a bare name (may contain spaces) becomes a file URL.
            let url: URL? = filename.contains("://") ? URL(string: filename) : URL(fileURLWithPath: filename)
            if let url { guess.productName = titleFromImageFilename(url) }
        }
        return guess
    }

    /// Applies a guess without clobbering read (non-guess) values.
    static func applyGuess(_ guess: ProductGuess, to meta: inout ProductMeta) {
        if let name = clean(guess.productName), meta.productName == nil || meta.productNameIsGuess == true {
            meta.productName = name
            meta.productNameIsGuess = true
        }
        if let brand = clean(guess.brand), meta.brand == nil || meta.brandIsGuess == true {
            meta.brand = brandRef(brand)
            meta.brandIsGuess = true
        }
    }

    // MARK: - Build

    /// Assembles `ProductMeta` + gallery URLs for one product page. `shopify` is the decoded
    /// `.json` when the caller fetched one. `now` stamps "price when saved".
    static func build(
        sourceURL: URL,
        finalURL: URL?,
        source: String,
        html: String,
        ogTitle: String?,
        ogDescription: String?,
        ogImageURL: URL?,
        shopify: ShopifyProduct?,
        now: Date = .now
    ) -> ProductExtraction {
        let landing = finalURL ?? sourceURL
        var meta = ProductMeta()
        meta.source = source
        meta.canonicalURL = landing.absoluteString
        var images: [URL] = []
        var title: String? = nil

        switch source {
        case "instagram":
            let info = parseInstagramOG(title: ogTitle, description: ogDescription)
            meta.creatorHandle = info.handle
            if let name = info.displayName ?? info.handle.map({ "@\($0)" }) {
                meta.creator = EntityRef(name: name, slug: nil, kind: ItemKind.individual.rawValue)
            }
            meta.caption = info.caption
            meta.originalPostURL = sourceURL.absoluteString
            if let ogImageURL { images = [ogImageURL] }
            title = info.caption.map(shortTitle(fromCaption:))

        case "image":
            meta.shop = bareHost(landing)
            if let name = titleFromImageFilename(sourceURL) {
                meta.productName = name
                meta.productNameIsGuess = true
            }
            images = [sourceURL]
            title = meta.productName

        default:
            if let shopify { applyShopify(shopify, to: &meta, images: &images, base: landing) }
            applyJSONLD(html: html, to: &meta, images: &images, base: landing)
            applyOGTags(html: html, to: &meta)
            if meta.productName == nil { meta.productName = clean(ogTitle) }
            if meta.shop == nil { meta.shop = bareHost(landing) }
            meta.buyURL = landing.absoluteString
            if images.isEmpty, let ogImageURL { images = [ogImageURL] }
            title = meta.productName
        }

        if meta.price != nil { meta.pricedAt = now }
        if meta.priceMin != nil, meta.priceMin == meta.priceMax {
            meta.priceMin = nil
            meta.priceMax = nil
        }

        var seen = Set<String>()
        images = images.filter { seen.insert($0.absoluteString).inserted }
        return ProductExtraction(meta: meta, imageURLs: Array(images.prefix(galleryCap)), title: title)
    }

    // MARK: - Helpers

    /// "Rs. 2,699.00" → "2699.00"; nil when there are no digits or the value is zero
    /// (Shopify/JSON-LD use 0 as a "no price" placeholder).
    static func normalizePrice(_ raw: String?) -> String? {
        guard let raw else { return nil }
        guard let firstDigit = raw.firstIndex(where: \.isNumber) else { return nil }
        let kept = raw[firstDigit...].filter { $0.isNumber || $0 == "." }
        let trimmed = kept.hasSuffix(".") ? String(kept.dropLast()) : String(kept)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value > 0 else { return nil }
        return trimmed
    }

    /// schema.org availability URL or og value → short human label.
    static func availabilityLabel(_ raw: String) -> String {
        let last = raw.split(separator: "/").last.map(String.init) ?? raw
        let key = last.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
        switch key {
        case "instock", "in-stock": return "in stock"
        case "outofstock", "out-of-stock", "oos": return "out of stock"
        case "soldout": return "sold out"
        case "preorder", "pre-order": return "pre-order"
        case "presale": return "pre-sale"
        case "backorder": return "backorder"
        case "discontinued": return "discontinued"
        case "limitedavailability": return "limited"
        case "onlineonly": return "online only"
        case "instoreonly": return "in store only"
        default: return last.lowercased()
        }
    }

    static func brandRef(_ name: String) -> EntityRef {
        EntityRef(name: name, slug: nil, kind: "brand")
    }

    /// First line of a caption, capped — an item title, not the whole post.
    static func shortTitle(fromCaption caption: String) -> String {
        let firstLine = caption.split(whereSeparator: \.isNewline).first.map(String.init) ?? caption
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(79)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func bareHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }

    private static func appendImages(_ srcs: [String], base: URL, to images: inout [URL]) {
        for src in srcs {
            var s = src.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("//") { s = "https:" + s }
            if let url = URL(string: s, relativeTo: base)?.absoluteURL { images.append(url) }
        }
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return clean(s) }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func clean(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
