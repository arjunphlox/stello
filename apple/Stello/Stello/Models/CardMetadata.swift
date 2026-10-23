import Foundation

// MARK: - Shared

/// Cross-reference to another Stello item or external label.
struct EntityRef: Codable, Hashable, Sendable {
    var name: String
    var slug: String?
    var kind: String
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
}

enum ItemKind: String, Sendable {
    case typeface, website, individual, studio, foundry, place, music, product, link
}

enum ItemImageRole: String, Sendable {
    case cover, specimen, graphic, gallery, preview
}
