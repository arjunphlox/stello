import Foundation

// MARK: - Shared

/// Cross-reference to another Stello item or external label.
struct EntityRef: Codable, Hashable, Sendable {
    var name: String
    var slug: String?
    var kind: String
    /// External page for the entity (e.g. a resource maker's profile). Optional and last, so
    /// older JSON decodes and every existing `EntityRef(name:slug:kind:)` call still compiles.
    var url: String? = nil
}

struct FAQItem: Codable, Hashable, Sendable {
    var question: String
    var answer: String
}

// MARK: - Typeface

nonisolated struct TypefaceMeta: Codable, Sendable {
    var overview: String?
    var description: String?
    var specimenURL: String?
    var specimenLink: String?
    var typeDesigner: [EntityRef] = []
    var typeDesignerFallback: String?
    var typeFoundry: EntityRef?
    var distributedOn: [EntityRef] = []
    var license: String?
    var paidOrFree: String?
    var trialAvailability: Bool?
    var studentDiscount: Bool?
    var releaseYear: String?
    var lastUpdate: String?
    var version: String?
    var familyCount: String?
    var familyFontNames: [EntityRef] = []
    var weightsCount: String?
    var weightCount: Int?
    var weightTypes: [String] = []
    var stylesCount: String?
    var styleCount: Int?
    var styleTypes: [String] = []
    var languageSupport: Int?
    var languagesCount: String?
    var languagesRegion: [String] = []
    var formatsCount: String?
    var formatsCount2: Int?
    var availableFormats: [String] = []
    var startingPrice: String?
    var variableFontSupport: Bool?
    var openTypeFeatures: [String] = []
    var classification: [String] = []
    var personality: [String] = []
    var highlights: String?
    var useCase: String?
    var designFeatures: String?
    var pairingFonts: String?
    var similarFonts: String?
    var forkFonts: String?
    var faqs: [FAQItem] = []
    var creatives: [EntityRef] = []
    var websites: [EntityRef] = []
}

// MARK: - Website

nonisolated struct WebsiteMeta: Codable, Sendable {
    var tagline: String?
    var description: String?
    var categories: [String] = []
    var traits: [String] = []
    var agencyStudio: EntityRef?
    var focusAreas: [String] = []
    var versionHistory: String?
    var contentFormats: [String] = []
    var review: String?
    var platform: [String] = []
    var techStack: [String] = []
    var founders: [EntityRef] = []
    var founderName: String?
    var brandingMadeBy: [EntityRef] = []
    var siteDesignerAgency: [EntityRef] = []
    var agencyName: String?
    var agencyURL: String?
    var creatives: [EntityRef] = []
    var contactDetails: String?
    var socialLinks: String?
    var typography: [EntityRef] = []
    var typefaceCount: String?
    var typeFoundries: [EntityRef] = []
    var webPages: [String] = []
    var webPagesCount: String?
    var keyComponents: [String] = []
    var keyComponentsCount: String?
    var firstPublished: String?
    var dateAdded: String?
    var dateUpdated: String?
}

// MARK: - Individual (Creative)

nonisolated struct IndividualMeta: Codable, Sendable {
    var pronouns: String?
    var bio: String?
    var location: EntityRef?
    var institutions: String?
    var website: EntityRef?
    var fallbackWebsite: String?
    var ownWebsite: String?
    var professions: [String] = []
    var traits: [String] = []
    var professionalExperience: Int?
    var currentRole: String?
    var currentEmployer: String?
    var notableWorks: String?
    var signatureStyle: String?
    var ownProductsList: String?
    var speaking: String?
    var workshops: String?
    var communityWork: String?
    var toolsAndTechStack: String?
    var email: String?
    var xURL: String?
    var instagramURL: String?
    var linkedInURL: String?
    var behanceURL: String?
    var bluesky: String?
    var mastodon: String?
    var threads: String?
    var blogLink: String?
    var shopLink: String?
    var favouriteBook: String?
    var funFact: String?
    var hobbies: String?
    var typefaces: [EntityRef] = []
    var typeFoundries: [EntityRef] = []
}

// MARK: - Studio

nonisolated struct StudioMeta: Codable, Sendable {
    var work: [EntityRef] = []
    var team: [EntityRef] = []
}

// MARK: - Foundry

nonisolated struct FoundryMeta: Codable, Sendable {
    var description: String?
    var category: String?
    var geography: EntityRef?
    var foundedYear: String?
    var foundersDesigners: [EntityRef] = []
    var priceRange: String?
    var trialFonts: Bool?
    var studentDiscount: Bool?
    var licensingTypes: [String] = []
    var designPhilosophy: String?
    var popularFonts: [String] = []
    var specialisation: [String] = []
    var customServices: [String] = []
    var social: String?
    var email: String?
    var thoughts: String?
    var distribution: [String] = []
    var typefaces: [EntityRef] = []
    var websites: [EntityRef] = []
    var creatives: [EntityRef] = []
}

// MARK: - Place

nonisolated struct PlaceMeta: Codable, Sendable {
    var city: String?
    var country: String?
}

// MARK: - Music

nonisolated struct MusicTrackEntry: Codable, Hashable, Sendable {
    var name: String
    var durationSeconds: Int?
}

nonisolated struct MusicMeta: Codable, Sendable {
    /// album | track | playlist | artist | mix
    var subtype: String?
    /// The clean track/song/album title, descriptors stripped (e.g. "Official Video").
    var cleanTitle: String?
    /// A "(Remastered 2004)"-style suffix split off the raw title.
    var edition: String?
    var artists: [EntityRef] = []
    var curator: EntityRef?
    var isOwnPlaylist: Bool?
    var platform: String?
    var canonicalURL: String?
    var embedURL: String?
    var releaseYear: String?
    var label: String?
    var genres: [String] = []
    var trackList: [MusicTrackEntry] = []
    var totalDurationSeconds: Int?
    var upc: String?
    /// The film this song is from — Indian film-music grammar titles only.
    var film: String?
    var previewAudioURL: String?
}

// MARK: - Product

nonisolated struct ProductMeta: Codable, Sendable {
    /// Shopify `title`, JSON-LD `name`, og:title — or an on-device / filename guess
    /// (`productNameIsGuess == true`), which the panel marks as a guess.
    var productName: String?
    var productNameIsGuess: Bool?
    /// Shopify `vendor` or JSON-LD `brand` (string or `{name}`); may be a guess (`brandIsGuess`).
    var brand: EntityRef?
    var brandIsGuess: Bool?
    /// Decimal-as-string with grouping stripped (e.g. "2699.00"). Snapshot at capture.
    var price: String?
    /// Set only when variants / an AggregateOffer span a range.
    var priceMin: String?
    var priceMax: String?
    /// ISO 4217 code (e.g. "INR"). og tags may lack it — JSON-LD is preferred.
    var currency: String?
    /// When `price` was read — the capture date ("Price when saved").
    var pricedAt: Date?
    /// Human label from schema.org availability: "in stock", "out of stock", "pre-order"…
    var availability: String?
    /// og:site_name, else the host.
    var shop: String?
    /// Shopify `product_type`.
    var category: String?
    /// `page` | `instagram` | `image`.
    var source: String?
    /// Instagram posting account (display name); the bare handle lives in `creatorHandle`.
    var creator: EntityRef?
    var creatorHandle: String?
    /// Instagram caption — input to the on-device name/brand guess (Instagram has no price).
    var caption: String?
    var buyURL: String?
    /// Final URL after redirects.
    var canonicalURL: String?
    /// The Instagram (or other) post the product was saved from.
    var originalPostURL: String?

    /// One short line for the grid card: "₹2,699 · Stuffcool", or "via @handle" for an
    /// Instagram product; nil when there is nothing to say.
    var cardKindLine: String? {
        let priceText = ProductMeta.formattedPrice(price, currency: currency)
        let brandText = brand?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [priceText, brandText].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        if let handle = creatorHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !handle.isEmpty {
            return "via @\(handle)"
        }
        return nil
    }

    /// Display price: ("2699.00", "INR") → "₹2,699"; ("19.5", "USD") → "$19.50".
    /// Fixed en_US grouping so it reads the same on every device locale.
    static func formattedPrice(_ price: String?, currency: String?) -> String? {
        guard let raw = price?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: cleaned) else { return raw }

        let fraction = cleaned.split(separator: ".", maxSplits: 1).dropFirst().first ?? ""
        let isWhole = fraction.allSatisfy { $0 == "0" }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = isWhole ? 0 : 2
        formatter.maximumFractionDigits = isWhole ? 0 : 2
        guard let number = formatter.string(from: value as NSDecimalNumber) else { return raw }

        guard let code = currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !code.isEmpty else { return number }
        if let symbol = currencySymbols[code] { return symbol + number }
        return "\(code) \(number)"
    }

    private static let currencySymbols: [String: String] = [
        "INR": "₹", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "CNY": "¥",
        "KRW": "₩", "AUD": "A$", "CAD": "CA$", "SGD": "S$", "NZD": "NZ$", "HKD": "HK$",
    ]
}

// MARK: - Post

nonisolated struct PostMeta: Codable, Sendable {
    /// `x` | `instagram` | `behance` | `dribbble` | `pinterest` (from the host).
    var platform: String?
    /// The posting account (display name); the bare handle lives in `authorHandle`.
    var author: EntityRef?
    /// Bare handle, no "@".
    var authorHandle: String?
    /// The tweet / caption / project description.
    var text: String?
    /// `image` | `video` | `gif` | `carousel`.
    var mediaType: String?
    var mediaCount: Int?
    var postedAt: Date?
    /// Set from collection labels / tags (midjourney, gen-ai, …) or Midjourney `--` params
    /// in the text. Labels only flag AI art on items that are already a Post.
    var isAIArt: Bool = false
    /// "Midjourney", "Stable Diffusion", "DALL·E" — nil when the signal names no model.
    var aiModel: String?
    /// Rule-read from the text (`promptIsGuess == false`) or the on-device guess (`true`).
    var prompt: String?
    var promptIsGuess: Bool = false
    var canonicalURL: String?
    var embedURL: String?

    /// One short line for the grid card: "@handle"; nil when there is no handle.
    var cardKindLine: String? {
        guard let handle = authorHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !handle.isEmpty else {
            return nil
        }
        return "@\(handle)"
    }
}

// MARK: - Tool

nonisolated struct ToolMeta: Codable, Sendable {
    /// `app` | `web app` | `library` | `extension` | `AI model`.
    var subtype: String?
    /// JSON-LD `name` or the GitHub repo's `owner/repo`.
    var name: String?
    /// og:description (else meta description); a GitHub repo's own description wins.
    var tagline: String?
    /// Normalised: macOS, iOS, iPadOS, watchOS, visionOS, tvOS, Windows, Linux, Android, Web.
    var platforms: [String] = []
    /// Set when `platforms` came from the on-device / rule-based guess.
    var platformsAreGuess: Bool = false
    /// JSON-LD `applicationCategory`, "Application" suffix stripped ("Developer").
    var category: String?
    /// `free` | `paid` | `freemium` | `open source`.
    var pricing: String?
    /// Lowest non-zero price, decimal-as-string ("4.99"); currency is ISO 4217.
    var price: String?
    var currency: String?
    var pricingIsGuess: Bool = false
    /// JSON-LD author / creator / publisher, og:site_name, or the GitHub owner.
    var maker: EntityRef?
    // GitHub (REST `repos/<owner>/<repo>`; unauthenticated, skipped when rate-limited).
    var repoURL: String?
    var stars: Int?
    var language: String?
    /// SPDX id ("MIT"), else the licence name.
    var license: String?
    var lastPushedAt: Date?
    var topics: [String] = []
    /// The repo's own `homepage`.
    var homepageURL: String?
    /// The URL itself when it is an App Store page, else the first apps.apple.com link on it.
    var appStoreURL: String?
    /// Final URL after redirects — set only when its host differs from the saved one.
    var canonicalURL: String?

    /// One short line for the grid card: "Mac · Free", "Web · Freemium", "Mac, iOS +1 · $4.99";
    /// a repo: "Open source · ★ 12.4k"; nil when there is nothing to say.
    var cardKindLine: String? {
        if repoURL != nil {
            var parts: [String] = []
            if pricing == "open source" { parts.append("Open source") }
            if let stars, stars > 0 { parts.append("★ \(ToolMeta.compactCount(stars))") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let parts = [platformsLine(maxShown: 2, short: true), priceLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Mac, iOS +2" (short names, capped) or "macOS, iOS, Windows" (full).
    func platformsLine(maxShown: Int? = nil, short: Bool = false) -> String? {
        let names = platforms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        let shown = maxShown.map { Array(names.prefix($0)) } ?? names
        var line = shown.map { short ? ToolMeta.shortPlatformName($0) : $0 }.joined(separator: ", ")
        if names.count > shown.count { line += " +\(names.count - shown.count)" }
        return line
    }

    /// "$4.99" for a paid tool with a price, else "Free" / "Freemium" / "Paid" / "Open source".
    var priceLine: String? {
        if pricing == "paid" || (pricing == nil && price != nil),
           let formatted = ProductMeta.formattedPrice(price, currency: currency) {
            return formatted
        }
        switch pricing {
        case "free": return "Free"
        case "freemium": return "Freemium"
        case "paid": return "Paid"
        case "open source": return "Open source"
        default: return nil
        }
    }

    static func shortPlatformName(_ platform: String) -> String {
        platform == "macOS" ? "Mac" : platform
    }

    /// 12_400 → "12.4k", 1_250_000 → "1.3M", 980 → "980".
    static func compactCount(_ value: Int) -> String {
        func trimmed(_ v: Double) -> String {
            let s = String(format: "%.1f", v)
            return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        if value >= 1_000_000 { return trimmed(Double(value) / 1_000_000) + "M" }
        if value >= 1_000 { return trimmed(Double(value) / 1_000) + "k" }
        return String(value)
    }
}

// MARK: - Resource

nonisolated struct ResourceMeta: Codable, Sendable {
    /// `plugin` | `widget` | `file` | `template` | `component` | `pen` | `mockup` | `icon set` |
    /// `library` | `reading list` (from the URL path, the `books` label, conservative title
    /// words, or a site home page); nil when nothing says.
    var subtype: String?
    /// `Figma` | `FigJam` | `Framer` | `CodePen` — from the host.
    var worksWith: [String] = []
    /// JSON-LD `name`, else og:title with the platform suffix (" | Figma", " — … for Framer")
    /// stripped.
    var name: String?
    /// JSON-LD `creator` (Figma) or `brand` (Framer); `maker.url` is the maker's page.
    var maker: EntityRef?
    /// `free` | `paid`.
    var pricing: String?
    /// Lowest non-zero price, decimal-as-string ("49"); currency is ISO 4217.
    var price: String?
    var currency: String?
    /// Figma `interactionStatistic` UseAction / DownloadAction count.
    var users: Int?
    /// Figma `interactionStatistic` LikeAction count.
    var likes: Int?
    /// Final URL after redirects — set whenever it differs from the saved URL (Figma redirects
    /// to a longer slug on the same host).
    var canonicalURL: String?

    /// One short line for the grid card: "Figma plugin · Free", "Framer template · $49",
    /// "Figma plugin · 12.4k users" (no price known), "Reading list"; nil when there is no data.
    var cardKindLine: String? {
        let parts = [typeLine, priceLine ?? usersLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Figma plugin", "Framer template", "CodePen pen", "Reading list", "Figma", "Template".
    var typeLine: String? {
        let sub = ResourceMeta.nonBlank(subtype)
        if sub == "reading list" { return "Reading list" }
        let host = ResourceMeta.nonBlank(worksWith.first)
        switch (host, sub) {
        case let (host?, sub?): return "\(host) \(sub)"
        case let (host?, nil): return host
        case let (nil, sub?): return sub.prefix(1).uppercased() + String(sub.dropFirst())
        default: return nil
        }
    }

    /// "Free", "$49", or "Paid" (paid with no price read); nil when pricing is unknown.
    var priceLine: String? {
        if pricing == "free" { return "Free" }
        if let formatted = ProductMeta.formattedPrice(price, currency: currency) { return formatted }
        return pricing == "paid" ? "Paid" : nil
    }

    /// "12.4k users"; nil when there is no positive count.
    var usersLine: String? {
        guard let users, users > 0 else { return nil }
        return users == 1 ? "1 user" : "\(ToolMeta.compactCount(users)) users"
    }

    static func nonBlank(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

// MARK: - Item metadata helpers

extension Item {
    private func decodeMetadata<T: Decodable>(_ type: T.Type) -> T? {
        guard let json = metadataJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setMetadata<T: Encodable>(_ meta: T) {
        guard let data = try? JSONEncoder().encode(meta),
              let string = String(data: data, encoding: .utf8) else { return }
        metadataJSON = string
    }

    func typefaceMeta() -> TypefaceMeta? {
        guard kind == ItemKind.typeface.rawValue else { return nil }
        return decodeMetadata(TypefaceMeta.self)
    }

    func websiteMeta() -> WebsiteMeta? {
        guard kind == ItemKind.website.rawValue else { return nil }
        return decodeMetadata(WebsiteMeta.self)
    }

    func individualMeta() -> IndividualMeta? {
        guard kind == ItemKind.individual.rawValue else { return nil }
        return decodeMetadata(IndividualMeta.self)
    }

    func studioMeta() -> StudioMeta? {
        guard kind == ItemKind.studio.rawValue else { return nil }
        return decodeMetadata(StudioMeta.self)
    }

    func foundryMeta() -> FoundryMeta? {
        guard kind == ItemKind.foundry.rawValue else { return nil }
        return decodeMetadata(FoundryMeta.self)
    }

    func placeMeta() -> PlaceMeta? {
        guard kind == ItemKind.place.rawValue else { return nil }
        return decodeMetadata(PlaceMeta.self)
    }

    func musicMeta() -> MusicMeta? {
        guard kind == ItemKind.music.rawValue else { return nil }
        return decodeMetadata(MusicMeta.self)
    }

    func productMeta() -> ProductMeta? {
        guard kind == ItemKind.product.rawValue else { return nil }
        return decodeMetadata(ProductMeta.self)
    }

    func postMeta() -> PostMeta? {
        guard kind == ItemKind.post.rawValue else { return nil }
        return decodeMetadata(PostMeta.self)
    }

    func toolMeta() -> ToolMeta? {
        guard kind == ItemKind.tool.rawValue else { return nil }
        return decodeMetadata(ToolMeta.self)
    }

    func resourceMeta() -> ResourceMeta? {
        guard kind == ItemKind.resource.rawValue else { return nil }
        return decodeMetadata(ResourceMeta.self)
    }
}

enum ItemKind: String, Sendable {
    case typeface, website, individual, studio, foundry, place, music, product, post, tool, resource, link
}

enum ItemImageRole: String, Sendable {
    case cover, specimen, graphic, gallery, preview
}
