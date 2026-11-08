import Foundation

/// Platforms + pricing guessed from page text — what the on-device job and the rule-based
/// keyword pass both return when the readers found none. Stored on `ToolMeta` with its
/// `…IsGuess` flags set.
nonisolated struct ToolFacts: Sendable, Equatable {
    var platforms: [String] = []
    var pricing: String?
}

/// On-device helpers for tool items: the platforms / pricing guess the on-device job fills gaps with, and
/// the merge a fresh read goes through on Enrich. The page readers themselves live on the
/// Worker (`src/lib/readers/tool.js`), the one copy shared with web saves.
nonisolated enum ToolReader {

    /// Whether the readers left a gap the guess may fill.
    static func needsGuess(_ meta: ToolMeta) -> Bool {
        (meta.platforms.isEmpty || meta.platformsAreGuess) || (meta.pricing == nil || meta.pricingIsGuess)
    }

    /// A cheap keyword pass over the page text — conservative: only explicit download /
    /// store wording sets a platform, and only plain "free plan … per month"-style wording
    /// sets pricing. Nil when nothing clear is said.
    static func ruleBasedFacts(text: String?) -> ToolFacts? {
        guard let lower = clean(text)?.lowercased() else { return nil }
        var platforms: [String] = []
        func add(_ name: String) { if !platforms.contains(name) { platforms.append(name) } }

        if lower.contains("download for mac") || lower.contains("download for macos")
            || lower.contains("mac app store") {
            add("macOS")
        }
        if lower.contains("download for windows") { add("Windows") }
        if lower.contains("download for linux") { add("Linux") }
        if lower.contains("download on the app store") { add("iOS") }
        if lower.contains("get it on google play") { add("Android") }

        var pricing: String?
        let mentionsFreePlan = lower.contains("free plan") || lower.contains("free tier") || lower.contains("free forever")
        let mentionsPaid = lower.contains("per month") || lower.contains("/month") || lower.contains("/mo")
            || lower.contains("pro plan") || lower.contains("upgrade to pro")
        if mentionsFreePlan && mentionsPaid {
            pricing = "freemium"
        } else if lower.contains("100% free") || lower.contains("completely free") {
            pricing = "free"
        }

        guard !platforms.isEmpty || pricing != nil else { return nil }
        return ToolFacts(platforms: platforms, pricing: pricing)
    }

    /// "Free" / "open-source" / "Freemium" / "Paid" → the stored vocabulary; nil otherwise.
    static func normalizePricing(_ raw: String?) -> String? {
        guard let key = clean(raw)?.lowercased().replacingOccurrences(of: "-", with: " ") else { return nil }
        switch key {
        case "free": return "free"
        case "paid", "subscription", "one time purchase", "one-time purchase": return "paid"
        case "freemium", "free trial", "free with in app purchases", "free with paid plans": return "freemium"
        case "open source", "oss": return "open source"
        default: return nil
        }
    }

    /// Fills only what the readers left empty (or an earlier guess), setting the flags;
    /// read values are never replaced.
    static func applyGuess(_ facts: ToolFacts, to meta: inout ToolMeta) {
        var platforms: [String] = []
        for raw in facts.platforms {
            if let name = normalizePlatform(raw), !platforms.contains(name) { platforms.append(name) }
        }
        if !platforms.isEmpty, meta.platforms.isEmpty || meta.platformsAreGuess {
            meta.platforms = platforms
            meta.platformsAreGuess = true
        }
        if let pricing = normalizePricing(facts.pricing), meta.pricing == nil || meta.pricingIsGuess {
            meta.pricing = pricing
            meta.pricingIsGuess = true
        }
    }

    /// "Mac OS X 10.15" / "OSX" / "macOS" → "macOS"; "Requires iOS 17.0 or later." → "iOS";
    /// "Windows 10" → "Windows"; "web browser" → "Web". Unknown short values are kept as
    /// written; nil for empty or "any"/"all".
    static func normalizePlatform(_ raw: String) -> String? {
        guard let trimmed = clean(raw) else { return nil }
        let lower = trimmed.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        func has(_ word: String) -> Bool { words.contains(word) }

        if lower.contains("watchos") || has("watch") { return "watchOS" }
        if lower.contains("visionos") || lower.contains("vision pro") { return "visionOS" }
        if lower.contains("tvos") || lower.contains("apple tv") { return "tvOS" }
        if lower.contains("ipados") || has("ipad") { return "iPadOS" }
        if has("ios") || has("iphone") { return "iOS" }
        if lower.contains("macos") || lower.contains("mac os") || has("osx") || lower.contains("os x")
            || has("mac") || has("macintosh") {
            return "macOS"
        }
        if lower.hasPrefix("win") || has("windows") { return "Windows" }
        if has("linux") || has("ubuntu") || has("debian") || has("fedora") { return "Linux" }
        if has("android") { return "Android" }
        if has("web") || has("browser") || has("online") || has("chrome") || has("firefox") || has("safari") {
            return "Web"
        }
        if ["any", "all", "cross-platform", "multi-platform", "n/a"].contains(lower) { return nil }
        return trimmed.count <= 24 ? trimmed : nil
    }

    /// A refetch that reads less (rate-limited GitHub, bot wall) never erases what capture
    /// read; an earlier guess survives only while nothing is read in its place.
    static func merge(fresh: ToolMeta, previous: ToolMeta?) -> ToolMeta {
        guard let previous else { return fresh }
        var meta = fresh
        if meta.subtype == nil { meta.subtype = previous.subtype }
        if meta.name == nil { meta.name = previous.name }
        if meta.tagline == nil { meta.tagline = previous.tagline }
        if meta.platforms.isEmpty {
            meta.platforms = previous.platforms
            meta.platformsAreGuess = previous.platformsAreGuess
        }
        if meta.category == nil { meta.category = previous.category }
        if meta.pricing == nil {
            meta.pricing = previous.pricing
            meta.pricingIsGuess = previous.pricingIsGuess
        }
        if meta.price == nil {
            meta.price = previous.price
            meta.currency = previous.currency
        }
        if meta.maker == nil { meta.maker = previous.maker }
        if meta.repoURL == nil { meta.repoURL = previous.repoURL }
        if meta.stars == nil { meta.stars = previous.stars }
        if meta.language == nil { meta.language = previous.language }
        if meta.license == nil { meta.license = previous.license }
        if meta.lastPushedAt == nil { meta.lastPushedAt = previous.lastPushedAt }
        if meta.topics.isEmpty { meta.topics = previous.topics }
        if meta.homepageURL == nil { meta.homepageURL = previous.homepageURL }
        if meta.appStoreURL == nil { meta.appStoreURL = previous.appStoreURL }
        if meta.canonicalURL == nil { meta.canonicalURL = previous.canonicalURL }
        return meta
    }

    /// An App Store app page: `apps.apple.com/<cc>/app/<name>/id<n>`, `itunes.apple.com/…/app/…`,
    /// or a `macappstore://` / `itms-apps://` link.
    static func isAppStoreAppURL(_ url: URL) -> Bool {
        if let scheme = url.scheme?.lowercased(), ["macappstore", "itms-apps", "itms-appss"].contains(scheme) {
            return true
        }
        guard let host = ProductReader.bareHost(url), host == "apps.apple.com" || host == "itunes.apple.com" else { return false }
        let parts = url.path.lowercased().split(separator: "/")
        guard let i = parts.firstIndex(of: "app") else { return false }
        return i + 1 < parts.count
    }

    static func makerRef(_ name: String) -> EntityRef {
        EntityRef(name: name, slug: nil, kind: "maker")
    }

    static func clean(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
