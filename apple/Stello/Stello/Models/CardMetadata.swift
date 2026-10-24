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

// MARK: - Article

nonisolated struct ArticleMeta: Codable, Sendable {
    /// og:site_name, else JSON-LD `publisher.name`, else the host without `www.`.
    var publication: String?
    /// JSON-LD `author` (string / object / array → first; an object keeps its `url`), else
    /// meta `author`, `article:author` (when it isn't a URL), or `twitter:data1` labelled
    /// "Written by".
    var author: EntityRef?
    /// JSON-LD `datePublished`, else `article:published_time`, else the date in the URL path.
    var publishedAt: Date?
    /// Words in the page text ÷ 230, rounded up (min 1); nil when there is no text.
    var readingMinutes: Int?
    /// On-device summary (`summaryIsGuess == true`). The page's own description is NOT a
    /// summary — it stays the item's overview.
    var summary: String?
    var summaryIsGuess: Bool = false
    /// Codrops, a `/tutorial(s)/` path segment, or a title starting "How to" / "Tutorial".
    var isTutorial: Bool = false
    /// Tutorials only: the libraries / languages / tools the tutorial uses (max 5).
    var techStack: [String] = []
    /// Final URL after redirects — set whenever it differs from the saved URL.
    var canonicalURL: String?

    /// One short line for the grid card: "simonwillison.net · 6 min", or either part alone;
    /// nil when there is neither.
    var cardKindLine: String? {
        let parts = [ResourceMeta.nonBlank(publication), readingMinutes.map { "\($0) min" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "6 min read"; nil without a reading time.
    var readingLine: String? {
        readingMinutes.map { "\($0) min read" }
    }
}

// MARK: - Course

nonisolated struct CourseMeta: Codable, Sendable {
    /// JSON-LD `name`, else og:title with the provider suffix (" | Frontend Masters",
    /// " - Shift Nudge") stripped.
    var name: String?
    /// JSON-LD `provider` (string / object / array → first), else og:site_name, else a
    /// friendly name for a known course host, else the host without `www.`.
    var provider: EntityRef?
    /// JSON-LD `instructor` / `author` / `creator` (string / object / array → first; also
    /// `hasCourseInstance.instructor`), else meta `author`. Never the provider itself.
    var instructor: EntityRef?
    /// `self-paced` | `cohort` | `program` | `video series` | `workshop` — from `courseMode`
    /// words, an EducationEvent node (cohort) or the URL path (`/program/`, `/workshop/`);
    /// else the on-device / rule-based guess (`formatIsGuess`).
    var format: String?
    var formatIsGuess: Bool = false
    /// JSON-LD `numberOfLessons`, else the count of lesson-typed `hasPart` items; may be a
    /// rule-based guess ("24 lessons" in the page text — `lessonsIsGuess`).
    var lessons: Int?
    var lessonsIsGuess: Bool = false
    /// `timeRequired` (or `hasCourseInstance.courseWorkload`) when it is hours / minutes
    /// (ISO 8601 `PT5H30M` → 330).
    var durationMinutes: Int?
    /// Display text when the duration isn't hours / minutes ("2 weeks", "3 days") or comes
    /// from the guess ("5 hours" — `durationIsGuess`).
    var durationText: String?
    var durationIsGuess: Bool = false
    /// JSON-LD `educationalLevel` (string or DefinedTerm `name`), first letter capitalised.
    var level: String?
    /// `isAccessibleForFree`, else the offers (a price of 0 → free, a positive price → paid).
    var isFree: Bool?
    /// Lowest non-zero offer price, decimal-as-string ("39"); currency is ISO 4217.
    var price: String?
    var currency: String?
    /// JSON-LD `teaches`, `keywords` (comma string or array) and `about` names; else the
    /// on-device guess (`topicsAreGuess`). At most 8.
    var topics: [String] = []
    var topicsAreGuess: Bool = false
    /// The next cohort's start: EducationEvent `startDate` or `hasCourseInstance.startDate`
    /// (the earliest one not yet past at capture).
    var startsAt: Date?
    /// Final URL after redirects — set whenever it differs from the saved URL.
    var canonicalURL: String?

    /// One short line for the grid card: "<provider> · <format, else length, else price>" —
    /// "Maven · Cohort", "Frontend Masters · 5 h", "Shift Nudge · Free"; either part alone;
    /// nil when there is neither.
    var cardKindLine: String? {
        let detail = formatLabel ?? durationLine ?? priceLine
        let parts = [ResourceMeta.nonBlank(provider?.name), detail].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Self-paced", "Cohort", "Program", "Video series", "Workshop"; nil without a format.
    var formatLabel: String? {
        guard let format = ResourceMeta.nonBlank(format) else { return nil }
        return format.prefix(1).uppercased() + String(format.dropFirst())
    }

    /// "5 h", "5 h 30 min", "45 min" from the minutes; else the duration text ("2 weeks").
    var durationLine: String? {
        if let minutes = durationMinutes, minutes > 0 {
            let hours = minutes / 60
            let rest = minutes % 60
            switch (hours, rest) {
            case (0, _): return "\(rest) min"
            case (_, 0): return "\(hours) h"
            default: return "\(hours) h \(rest) min"
            }
        }
        return ResourceMeta.nonBlank(durationText)
    }

    /// "24 lessons · 5 h 30 min", or either part alone; nil when there is neither.
    var lengthLine: String? {
        var lessonsText: String? = nil
        if let lessons, lessons > 0 { lessonsText = lessons == 1 ? "1 lesson" : "\(lessons) lessons" }
        let parts = [lessonsText, durationLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Free", "$39", or "Paid" (not free, no price read); nil when nothing is known.
    var priceLine: String? {
        if isFree == true { return "Free" }
        if let formatted = ProductMeta.formattedPrice(price, currency: currency) { return formatted }
        return isFree == false ? "Paid" : nil
    }
}

// MARK: - Book

nonisolated struct BookMeta: Codable, Sendable {
    /// JSON-LD `name`, else og:title with a store / site suffix stripped, else Open Library.
    var title: String?
    /// Open Library `subtitle` (or a "Title: Subtitle" JSON-LD name split by the reader).
    var subtitle: String?
    /// JSON-LD `author` (string / object / array), `book:author` / `books:author` meta, else
    /// Open Library `authors[].name`, else the on-device guess (`authorsAreGuess`).
    var authors: [EntityRef] = []
    /// JSON-LD `publisher` (string / object), else Open Library `publishers[0].name`.
    var publisher: String?
    /// The year from JSON-LD `datePublished` / `book:release_date`, else Open Library
    /// `publish_date`; may come from the on-device guess when nothing was read.
    var publishedYear: Int?
    /// JSON-LD `numberOfPages`, else Open Library `number_of_pages`.
    var pages: Int?
    /// Checksum-valid, hyphen-free ISBNs; each is derived from the other when only one is read
    /// (an ISBN-13 only converts back when it starts with 978).
    var isbn10: String?
    var isbn13: String?
    /// JSON-LD `inLanguage` as given ("en", "English").
    var language: String?
    /// Open Library `subjects[].name` (or JSON-LD `genre` / `about`). At most 8.
    var subjects: [String] = []
    /// `hardcover` | `paperback` | `ebook` | `audiobook` — JSON-LD `bookFormat`.
    var format: String?
    /// JSON-LD `image` / og:image, else the Open Library cover (large, then medium).
    var coverURL: String?
    /// Open Library book page; set whenever the lookup found the ISBN (or the saved URL is
    /// an Open Library page).
    var openLibraryURL: String?
    /// The saved URL when it is a Goodreads book page.
    var goodreadsURL: String?
    /// The saved URL when it is an Amazon book page (or `amazon.com/dp/<isbn10>` built from
    /// the ISBN).
    var amazonURL: String?
    /// Final URL after redirects — set whenever it differs from the saved URL.
    var canonicalURL: String?
    /// True when `authors` came from the on-device guess, not a reader.
    var authorsAreGuess: Bool = false

    /// One short line for the grid card: "Author · Year" — the first author ("+N" when there
    /// are more: "Thomas H. Cormen +3 · 2009"); either part alone; nil when there is neither.
    var cardKindLine: String? {
        let parts = [firstAuthorLine, publishedYear.map(String.init)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Thomas H. Cormen", "Thomas H. Cormen +3"; nil without an author.
    var firstAuthorLine: String? {
        let names = authors.compactMap { ResourceMeta.nonBlank($0.name) }
        guard let first = names.first else { return nil }
        return names.count > 1 ? "\(first) +\(names.count - 1)" : first
    }

    /// "Thomas H. Cormen, Charles E. Leiserson"; nil without an author.
    var authorsLine: String? {
        let names = authors.compactMap { ResourceMeta.nonBlank($0.name) }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// The ISBN-13 when known, else the ISBN-10.
    var isbnLine: String? {
        ResourceMeta.nonBlank(isbn13) ?? ResourceMeta.nonBlank(isbn10)
    }

    /// "1312 pages" / "1 page"; nil without a positive count.
    var pagesLine: String? {
        guard let pages, pages > 0 else { return nil }
        return pages == 1 ? "1 page" : "\(pages) pages"
    }

    /// "Hardcover", "Paperback", "Ebook", "Audiobook"; nil without a format.
    var formatLabel: String? {
        guard let format = ResourceMeta.nonBlank(format) else { return nil }
        return format.prefix(1).uppercased() + String(format.dropFirst())
    }

    /// A language code ("en", "en-US", "eng") as its English name ("English"); any other text
    /// as given.
    var languageLabel: String? {
        guard let language = ResourceMeta.nonBlank(language) else { return nil }
        let code = language.split(separator: "-").first.map(String.init) ?? language
        if code.count <= 3, code.allSatisfy(\.isLetter),
           let name = Locale(identifier: "en").localizedString(forLanguageCode: code.lowercased()) {
            return name
        }
        return language
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

    func articleMeta() -> ArticleMeta? {
        guard kind == ItemKind.article.rawValue else { return nil }
        return decodeMetadata(ArticleMeta.self)
    }

    func courseMeta() -> CourseMeta? {
        guard kind == ItemKind.course.rawValue else { return nil }
        return decodeMetadata(CourseMeta.self)
    }

    func bookMeta() -> BookMeta? {
        guard kind == ItemKind.book.rawValue else { return nil }
        return decodeMetadata(BookMeta.self)
    }
}

enum ItemKind: String, Sendable {
    case typeface, website, individual, studio, foundry, place, music, product, post, tool, resource, book, course, article, link
}

enum ItemImageRole: String, Sendable {
    case cover, specimen, graphic, gallery, preview
}
