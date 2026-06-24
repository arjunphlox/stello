import Foundation

// Value type returned from the tagger pipeline; converted to Tag model objects at save time.
struct TagSpec: Equatable {
    let name: String
    let category: String
    let weight: Double
}

/// Deterministic, offline rule-based tagger. Exact port of enrich-rules.js + call-site params.
struct RuleTagger {

    // MARK: - FORMAT_MAP

    static let formatMap: [String: String] = [
        "instagram.com": "instagram",
        "x.com": "tweet",
        "twitter.com": "tweet",
        "pinterest.com": "pinterest",
        "behance.net": "behance",
        "dribbble.com": "dribbble",
        "youtube.com": "youtube",
        "youtu.be": "youtube",
        "vimeo.com": "vimeo",
        "codepen.io": "codepen",
        "codesandbox.io": "codesandbox",
        "github.com": "github",
        "medium.com": "article",
        "substack.com": "article",
        "figma.com": "figma",
        "tiktok.com": "tiktok",
        "linkedin.com": "linkedin",
        "reddit.com": "reddit",
        "producthunt.com": "producthunt",
        "awwwards.com": "awwwards",
        "are.na": "arena",
        "notion.so": "notion",
        "notion.site": "notion"
    ]

    // MARK: - TOOL_RULES (weight 0.7)

    static let toolRules: [(pattern: String, tag: String)] = [
        ("figma", "figma"), ("framer", "framer"), ("webflow", "webflow"),
        ("sketch app", "sketch"), ("sketch design", "sketch"),
        ("adobe illustrator", "illustrator"), ("illustrator", "illustrator"),
        ("photoshop", "photoshop"), ("after effects", "after-effects"),
        ("aftereffects", "after-effects"), ("premiere", "premiere"),
        ("final cut", "final-cut-pro"), ("procreate", "procreate"),
        ("blender", "blender"), ("cinema 4d", "cinema-4d"),
        ("cinema4d", "cinema-4d"), ("c4d", "cinema-4d"),
        ("midjourney", "midjourney"), ("stable diffusion", "stable-diffusion"),
        ("dall-e", "dall-e"), ("dalle", "dall-e"), ("chatgpt", "chatgpt"),
        ("openai", "openai"), ("spline", "spline"), ("rive", "rive"),
        ("lottie", "lottie"), ("gsap", "gsap"), ("three.js", "three-js"),
        ("threejs", "three-js"), ("react", "react"), ("nextjs", "nextjs"),
        ("next.js", "nextjs"), ("tailwind", "tailwind"), ("swift", "swift"),
        ("swiftui", "swiftui"), ("visionos", "visionos"),
        ("vision pro", "vision-pro"), ("unity", "unity"),
        ("unreal", "unreal-engine"), ("notion", "notion"),
        ("obsidian", "obsidian"), ("linear", "linear"),
        ("airtable", "airtable"), ("zapier", "zapier"),
        ("wordpress", "wordpress"), ("shopify", "shopify"),
        ("vercel", "vercel"), ("supabase", "supabase"),
        ("firebase", "firebase"), ("claude", "claude"), ("cursor", "cursor"),
        ("p5.js", "p5-js"), ("d3.js", "d3-js"), ("anime.js", "anime-js"),
        ("origami", "origami-studio"), ("principle", "principle"),
        ("protopie", "protopie"), ("marvel", "marvel"),
        ("invision", "invision"), ("zeplin", "zeplin"), ("github", "github"),
        ("lightroom", "lightroom"), ("davinci resolve", "davinci-resolve"),
        ("capcut", "capcut"), ("canva", "canva")
    ]

    // MARK: - STYLE_RULES (weight 0.65)

    static let styleRules: [(pattern: String, tag: String)] = [
        ("minimalist", "minimalist"), ("minimal", "minimalist"),
        ("brutalist", "brutalist"), ("editorial", "editorial"),
        ("retro", "retro"), ("vintage", "vintage"), ("futuristic", "futuristic"),
        ("geometric", "geometric"), ("organic", "organic"), ("flat", "flat"),
        ("skeuomorphic", "skeuomorphic"), ("neumorphic", "neumorphism"),
        ("glassmorphism", "glassmorphism"), ("gradient", "gradient"),
        ("monochrome", "monochrome"), ("isometric", "isometric"),
        ("3d", "3d"), ("hand-drawn", "hand-drawn"), ("hand drawn", "hand-drawn"),
        ("handwritten", "handwritten"), ("grunge", "grunge"), ("clean", "clean"),
        ("bold", "bold"), ("serif", "serif"), ("sans-serif", "sans-serif"),
        ("display", "display"), ("script", "script"),
        ("calligraphy", "calligraphic"), ("pixel", "pixel-art"),
        ("voxel", "voxel"), ("wireframe", "wireframe"), ("low-poly", "low-poly"),
        ("abstract", "abstract"), ("swiss", "swiss-style"), ("bauhaus", "bauhaus"),
        ("art deco", "art-deco"), ("art nouveau", "art-nouveau"),
        ("psychedelic", "psychedelic"), ("neon", "neon"), ("glitch", "glitch"),
        ("halftone", "halftone"), ("stipple", "stipple"),
        ("watercolor", "watercolor"), ("collage", "collage"),
        ("photorealistic", "photorealistic"), ("cinematic", "cinematic"),
        ("animated", "animated"), ("interactive", "interactive"),
        ("responsive", "responsive"), ("modular", "modular"),
        ("grid", "grid-based"), ("typographic", "typographic"),
        ("experimental", "experimental"), ("generative", "generative"),
        ("procedural", "procedural"), ("parametric", "parametric"),
        ("data-driven", "data-driven")
    ]

    // MARK: - MOOD_RULES (weight 0.55)

    static let moodRules: [(pattern: String, tag: String)] = [
        ("dark", "dark"), ("light", "light"), ("vibrant", "vibrant"),
        ("colorful", "vibrant"), ("calm", "calm"), ("serene", "calm"),
        ("peaceful", "calm"), ("elegant", "elegant"),
        ("luxurious", "luxurious"), ("luxury", "luxurious"),
        ("premium", "premium"), ("playful", "playful"), ("fun", "playful"),
        ("whimsical", "whimsical"), ("energetic", "energetic"),
        ("dynamic", "dynamic"), ("professional", "professional"),
        ("corporate", "corporate"), ("friendly", "friendly"), ("warm", "warm"),
        ("cool", "cool"), ("moody", "moody"), ("dramatic", "dramatic"),
        ("mysterious", "mysterious"), ("dreamy", "dreamy"),
        ("nostalgic", "nostalgic"), ("techy", "techy"), ("craft", "crafted"),
        ("artisan", "crafted"), ("handmade", "crafted"), ("raw", "raw"),
        ("subtle", "subtle"), ("delicate", "delicate")
    ]

    // MARK: - LOCATION_RULES (weight 0.6)

    static let locationRules: [(pattern: String, tag: String)] = [
        ("tokyo", "japan"), ("japan", "japan"), ("japanese", "japan"),
        ("india", "india"), ("indian", "india"), ("mumbai", "india"),
        ("bangalore", "india"), ("delhi", "india"), ("london", "uk"),
        ("british", "uk"), ("england", "uk"), ("berlin", "germany"),
        ("german", "germany"), ("paris", "france"), ("french", "france"),
        ("new york", "usa"), ("nyc", "usa"), ("san francisco", "usa"),
        ("california", "usa"), ("los angeles", "usa"), ("seattle", "usa"),
        ("portland", "usa"), ("brooklyn", "usa"), ("vancouver", "canada"),
        ("toronto", "canada"), ("canada", "canada"),
        ("amsterdam", "netherlands"), ("dutch", "netherlands"),
        ("copenhagen", "denmark"), ("danish", "denmark"),
        ("stockholm", "sweden"), ("swedish", "sweden"),
        ("helsinki", "finland"), ("finnish", "finland"),
        ("milan", "italy"), ("italian", "italy"), ("zurich", "switzerland"),
        ("swiss", "switzerland"), ("seoul", "south-korea"),
        ("korean", "south-korea"), ("singapore", "singapore"),
        ("sydney", "australia"), ("australian", "australia"),
        ("melbourne", "australia"), ("oslo", "norway"),
        ("norwegian", "norway"), ("barcelona", "spain"), ("spanish", "spain"),
        ("lisbon", "portugal"), ("portuguese", "portugal"),
        ("prague", "czech-republic"), ("jakarta", "indonesia"),
        ("bangkok", "thailand"), ("dubai", "uae"),
        ("são paulo", "brazil"), ("sao paulo", "brazil"),
        ("brazilian", "brazil"), ("mexico", "mexico"), ("china", "china"),
        ("chinese", "china"), ("beijing", "china"), ("shanghai", "china"),
        ("taiwan", "taiwan"), ("taipei", "taiwan")
    ]

    // MARK: - TLD_LOCATION (weight 0.3)

    static let tldLocation: [(tld: String, tag: String)] = [
        (".jp", "japan"), (".de", "germany"), (".fr", "france"), (".uk", "uk"),
        (".co.uk", "uk"), (".it", "italy"), (".nl", "netherlands"),
        (".se", "sweden"), (".dk", "denmark"), (".no", "norway"),
        (".fi", "finland"), (".ch", "switzerland"), (".kr", "south-korea"),
        (".au", "australia"), (".br", "brazil"), (".mx", "mexico"),
        (".cn", "china"), (".tw", "taiwan"), (".sg", "singapore"),
        (".pt", "portugal")
    ]

    // MARK: - STOP_WORDS

    static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
        "has", "have", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "can", "this", "that", "it", "its", "not",
        "no", "so", "if", "as", "into", "about", "up", "out", "all", "more",
        "also", "how", "what", "when", "where", "who", "which", "than", "then",
        "just", "like", "over", "such", "very", "your", "my", "our", "their",
        "new", "one", "two", "three", "four", "five", "first", "last", "most",
        "other", "some", "any", "each", "every", "both", "few", "many",
        "inside", "story", "part", "page", "view", "click", "here", "see",
        "use", "using", "used", "make", "made", "get", "got", "know",
        "www", "http", "https", "com", "net", "org", "middot", "nbsp", "amp", "quot"
    ]

    static let stopWordsExt: Set<String> = [
        "this", "that", "with", "from", "have", "been", "will", "about", "more",
        "also", "your", "their", "which", "when", "what", "where", "years",
        "building", "based", "tool", "looking", "find", "work", "best", "need",
        "help", "want", "take", "give", "keep", "thing"
    ]

    static let platformNoise: Set<String> = [
        "are", "awwwards", "behance", "codepen", "codesandbox", "dribbble",
        "figma", "github", "instagram", "linkedin", "medium", "notion",
        "pinterest", "producthunt", "reddit", "substack", "tiktok", "twitter",
        "vimeo", "x", "youtube", "youtu"
    ]

    // MARK: - Pipeline: generateTags

    static func generateTags(
        title: String,
        description: String?,
        domain: String?
    ) -> [TagSpec] {
        var tags: [TagSpec] = []

        // 1. Format tag
        tags.append(formatTagFor(domain: domain))

        // 2. Domain tag (weight 0.6)
        if let d = domain, !d.isEmpty {
            tags.append(TagSpec(name: d, category: "domain", weight: 0.6))
        }

        // 3. Subject mining from title (≤5, minLen 3, start 0.8, step 0.1, floor 0.5)
        let afterStep2 = Set(tags.map(\.name))
        tags.append(contentsOf: mineSubjectKeywords(
            from: title,
            limit: 5, minLen: 3,
            weightStart: 0.8, weightStep: 0.1, weightFloor: 0.5,
            extraStops: afterStep2
        ))

        // 4. Subject mining from description (≤3, minLen 4, start 0.5, step 0, floor 0.5)
        if let desc = description, !desc.isEmpty {
            let descExtra = Set(tags.map(\.name))
                .union(stopWordsExt)
                .union(platformNoise)
            tags.append(contentsOf: mineSubjectKeywords(
                from: desc,
                limit: 3, minLen: 4,
                weightStart: 0.5, weightStep: 0, weightFloor: 0.5,
                extraStops: descExtra
            ))
        }

        // 5. Rule enrichment (tool / style / mood / location)
        let combinedText = title + " " + (description ?? "")
        let existingNames = Set(tags.map(\.name))
        tags.append(contentsOf: runRuleEnrichment(
            text: combinedText,
            domain: domain ?? "",
            existingNames: existingNames
        ))

        // Dedupe by name, keeping first (highest weight from earlier steps)
        var seen = Set<String>()
        let deduped = tags.filter { seen.insert($0.name).inserted }

        // Sort by weight desc, cap to 12
        return Array(deduped.sorted { $0.weight > $1.weight }.prefix(12))
    }

    // MARK: - formatTagFor

    static func formatTagFor(domain: String?) -> TagSpec {
        guard let d = domain, !d.isEmpty else {
            return TagSpec(name: "text-note", category: "format", weight: 0.4)
        }
        if let mapped = formatMap[d] {
            return TagSpec(name: mapped, category: "format", weight: 0.5)
        }
        return TagSpec(name: "website", category: "format", weight: 0.4)
    }

    // MARK: - mineSubjectKeywords

    static func mineSubjectKeywords(
        from text: String,
        limit: Int,
        minLen: Int,
        weightStart: Double,
        weightStep: Double,
        weightFloor: Double,
        extraStops: Set<String>
    ) -> [TagSpec] {
        let lowered = text.lowercased()
        guard let regex = try? NSRegularExpression(pattern: "[a-zA-Z]{\(minLen),}") else { return [] }
        let matches = regex.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))

        var seen = Set<String>()
        var results: [TagSpec] = []

        for match in matches {
            guard results.count < limit,
                  let range = Range(match.range, in: lowered) else { continue }
            let word = String(lowered[range])
            guard !seen.contains(word),
                  !stopWords.contains(word),
                  !extraStops.contains(word) else { continue }
            seen.insert(word)
            let w = max(weightFloor, round2(weightStart - Double(results.count) * weightStep))
            results.append(TagSpec(name: word, category: "subject", weight: w))
        }

        return results
    }

    // MARK: - runRuleEnrichment

    static func runRuleEnrichment(
        text: String,
        domain: String,
        existingNames: Set<String>
    ) -> [TagSpec] {
        let lowered = text.lowercased()
        var results: [TagSpec] = []
        var addedNames = Set<String>()

        func addIfNew(name: String, category: String, weight: Double) {
            guard !existingNames.contains(name), !addedNames.contains(name) else { return }
            results.append(TagSpec(name: name, category: category, weight: weight))
            addedNames.insert(name)
        }

        for (pattern, tag) in toolRules where wordBoundaryMatch(pattern: pattern, in: lowered) {
            addIfNew(name: tag, category: "tool", weight: 0.7)
        }
        for (pattern, tag) in styleRules where wordBoundaryMatch(pattern: pattern, in: lowered) {
            addIfNew(name: tag, category: "style", weight: 0.65)
        }
        for (pattern, tag) in moodRules where wordBoundaryMatch(pattern: pattern, in: lowered) {
            addIfNew(name: tag, category: "mood", weight: 0.55)
        }
        for (pattern, tag) in locationRules where wordBoundaryMatch(pattern: pattern, in: lowered) {
            addIfNew(name: tag, category: "location", weight: 0.6)
        }

        // TLD fallback
        let domainLow = domain.lowercased()
        for (tld, tag) in tldLocation where domainLow.hasSuffix(tld) {
            addIfNew(name: tag, category: "location", weight: 0.3)
        }

        return results
    }

    // MARK: - wordBoundaryMatch

    static func wordBoundaryMatch(pattern: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(escaped)\\b",
            options: .caseInsensitive
        ) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
