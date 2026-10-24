import Foundation

// MARK: - Types

/// Format / duration text / topics guessed from page text — what the on-device job and the
/// rule-based keyword pass both return when the readers found none. Stored on `CourseMeta`
/// with its `…IsGuess` flags set.
nonisolated struct CourseFacts: Sendable, Equatable {
    var format: String?
    var durationText: String?
    var topics: [String] = []
    /// Rule-based pass only ("24 lessons" in the text); the on-device job doesn't return it.
    var lessons: Int? = nil
}

/// Result of the deterministic course readers: metadata and the title the item should carry
/// (nil = keep the page title).
nonisolated struct CourseExtraction: Sendable {
    var meta: CourseMeta
    var title: String?
}

/// A parsed `timeRequired`: minutes for an hours / minutes duration, else display text
/// ("2 weeks", "3 days") — never both.
nonisolated struct CourseDuration: Sendable, Equatable {
    var minutes: Int?
    var text: String?
}

// MARK: - CourseReader

/// Pure, network-free course readers: Course / EducationEvent JSON-LD (name, provider,
/// instructor, courseMode, numberOfLessons, timeRequired, educationalLevel, offers,
/// isAccessibleForFree, teaches / keywords / about, hasCourseInstance), og / meta tags and
/// the URL. Everything comes from the capture-time page fetch — no extra network.
nonisolated enum CourseReader {

    /// The stored format vocabulary.
    static let formats: [String] = ["self-paced", "cohort", "program", "video series", "workshop"]

    /// Most topics kept from JSON-LD.
    static let maxTopics = 8

    /// Most topics kept from the on-device guess.
    static let maxGuessedTopics = 5

    // MARK: - Meta tags

    nonisolated struct PageTags: Sendable {
        var siteName: String?
        var author: String?
    }

    static func pageTags(html: String) -> PageTags {
        var tags = PageTags()
        guard !html.isEmpty else { return tags }
        for attrs in CaptureService.metaTagAttributes(in: html) {
            guard let content = ToolReader.clean(attrs["content"]) else { continue }
            let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            switch key {
            case "og:site_name": if tags.siteName == nil { tags.siteName = content }
            case "author": if tags.author == nil { tags.author = content }
            default: break
            }
        }
        return tags
    }

    // MARK: - JSON-LD helpers

    /// "Course" / ["Thing", "https://schema.org/Course"] → normalised type names.
    static func typeNames(_ value: Any?) -> [String] {
        func normalize(_ raw: String) -> String {
            if let last = raw.split(separator: "/").last, !last.isEmpty { return String(last) }
            return raw
        }
        if let s = value as? String { return [normalize(s)] }
        if let array = value as? [Any] { return array.compactMap { $0 as? String }.map(normalize) }
        return []
    }

    /// One object or an array of objects → the objects.
    static func dicts(_ value: Any?) -> [[String: Any]] {
        if let dict = value as? [String: Any] { return [dict] }
        if let array = value as? [Any] { return array.compactMap { $0 as? [String: Any] } }
        return []
    }

    /// A string, or the strings in an array.
    static func strings(_ value: Any?) -> [String] {
        if let s = ProductReader.string(value) { return [s] }
        if let array = value as? [Any] { return array.compactMap { ProductReader.string($0) } }
        return []
    }

    /// `true` / `false` (JSON booleans or the strings); nil when absent or anything else.
    static func boolValue(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        switch ProductReader.string(value)?.lowercased() {
        case "true"?: return true
        case "false"?: return false
        default: return nil
        }
    }

    // MARK: - Name

    /// The course name: JSON-LD `name`, else og:title — either with a trailing " | Site"
    /// part dropped, and a trailing " - Provider" / " — Provider" / " – Provider" part dropped
    /// when it names the provider ("Design Systems - Shift Nudge" → "Design Systems";
    /// "Shift Nudge - Interface Design Course" keeps its tail).
    static func cleanName(_ raw: String?, providerNames: [String]) -> String? {
        guard var text = ToolReader.clean(raw) else { return nil }
        let keys = providerNames.map(normalizedKey).filter { $0.count >= 3 }

        if let range = text.range(of: " | ", options: .backwards) {
            let head = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = text[range.upperBound...]
            if !head.isEmpty, tail.count <= 40 { text = head }
        }
        for separator in [" - ", " — ", " – "] {
            guard let range = text.range(of: separator, options: .backwards) else { continue }
            let head = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = normalizedKey(String(text[range.upperBound...]))
            guard !head.isEmpty, tail.count >= 3 else { continue }
            if keys.contains(where: { $0 == tail || $0.contains(tail) || tail.contains($0) }) {
                text = head
                break
            }
        }
        return ToolReader.clean(text)
    }

    /// "Shift Nudge" / "shiftnudge.com" → "shiftnudge" / "shiftnudgecom" (letters + digits).
    static func normalizedKey(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    // MARK: - Provider

    /// Friendly names for the known course hosts (keys match `PageClassifier.courseHost`).
    static let friendlyHostNames: [String: String] = [
        "frontendmasters.com": "Frontend Masters",
        "maven.com": "Maven",
        "udemy.com": "Udemy",
        "coursera.org": "Coursera",
        "domestika.org": "Domestika",
        "skillshare.com": "Skillshare",
        "egghead.io": "egghead",
        "motiondesign.school": "Motion Design School",
        "university.webflow.com": "Webflow University",
        "superhi.com": "SuperHi",
        "designcourse.com": "DesignCourse",
        "shiftnudge.com": "Shift Nudge",
        "joshwcomeau.com": "Josh W. Comeau",
        "thebasics.dev": "The Basics",
    ]

    static func friendlyHostName(_ url: URL) -> String? {
        PageClassifier.courseHost(for: url).flatMap { friendlyHostNames[$0] }
    }

    /// JSON-LD `provider` (string, `{name, url}` object or array → first named), else
    /// og:site_name, else the friendly name of a known course host, else the host without
    /// `www.`.
    static func provider(node: [String: Any]?, tags: PageTags, url: URL, base: URL) -> EntityRef? {
        if let node, let ref = ResourceReader.makerRef(from: node["provider"], base: base) { return ref }
        if let site = tags.siteName { return ToolReader.makerRef(site) }
        if let name = friendlyHostName(url) ?? ProductReader.bareHost(url) { return ToolReader.makerRef(name) }
        return nil
    }

    // MARK: - Instructor

    /// JSON-LD `instructor`, `author`, `creator` (string, object or array → first named), then
    /// each `hasCourseInstance.instructor`, else meta `author`. URL-only values and the
    /// provider's own name are never the instructor.
    static func instructor(
        node: [String: Any]?,
        instances: [[String: Any]],
        tags: PageTags,
        base: URL,
        providerName: String?
    ) -> EntityRef? {
        let providerKey = providerName.map(normalizedKey)
        func isProvider(_ name: String) -> Bool {
            guard let providerKey, !providerKey.isEmpty else { return false }
            return normalizedKey(name) == providerKey
        }

        var candidates: [Any?] = []
        if let node { candidates += [node["instructor"], node["author"], node["creator"]] }
        for instance in instances { candidates.append(instance["instructor"]) }
        for value in candidates {
            if var ref = ResourceReader.makerRef(from: value, base: base),
               !ArticleReader.looksLikeURL(ref.name), !isProvider(ref.name) {
                ref.kind = ItemKind.individual.rawValue
                return ref
            }
        }
        if let name = tags.author, !ArticleReader.looksLikeURL(name), !isProvider(name) {
            return ArticleReader.authorRef(name)
        }
        return nil
    }

    // MARK: - Format

    /// `courseMode` words → format: "self-paced" / "on demand" / "asynchronous" → self-paced;
    /// "cohort" / "live" / "synchronous" → cohort. "online", "onsite", "blended" aren't formats
    /// → nil.
    static func format(fromCourseMode value: Any?) -> String? {
        for raw in strings(value) {
            let lower = raw.lowercased()
            let words = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            if lower.contains("self-paced") || lower.contains("self paced") || lower.contains("selfpaced")
                || lower.contains("on-demand") || lower.contains("on demand") || words.contains("ondemand")
                || words.contains("asynchronous") || lower.contains("own pace") {
                return "self-paced"
            }
            if words.contains("cohort") || words.contains("cohorts") || words.contains("live")
                || words.contains("synchronous") {
                return "cohort"
            }
        }
        return nil
    }

    // MARK: - Lessons

    static let lessonTypeNames: [String] = ["LearningResource", "Lesson", "VideoObject", "Episode", "Clip", "Chapter"]

    static func isLessonType(_ type: String) -> Bool {
        lessonTypeNames.contains { type.caseInsensitiveCompare($0) == .orderedSame }
    }

    /// `numberOfLessons`, else the number of `hasPart` items when every one is lesson-typed
    /// (LearningResource, VideoObject, Episode, …); nil otherwise.
    static func lessons(node: [String: Any]) -> Int? {
        if let count = ResourceReader.parseCount(node["numberOfLessons"]), count > 0 { return count }
        let parts = dicts(node["hasPart"])
        guard !parts.isEmpty,
              parts.allSatisfy({ typeNames($0["@type"]).contains(where: isLessonType) }) else { return nil }
        return parts.count
    }

    // MARK: - Duration

    /// ISO 8601 durations: hours / minutes / seconds → minutes (`PT5H30M` → 330, `PT90S` → 2);
    /// any year / month / week / day part → display text only (`P2W` → "2 weeks",
    /// `P1DT2H` → "1 day 2 h"). A short non-ISO value with a digit ("5 hours") is kept as
    /// text; anything else (or a zero duration) → empty.
    static func parseDuration(_ raw: String?) -> CourseDuration {
        guard let value = ToolReader.clean(raw) else { return CourseDuration() }
        let upper = value.uppercased()
        guard upper.hasPrefix("P") else {
            if value.count <= 30, value.contains(where: \.isNumber) { return CourseDuration(text: value) }
            return CourseDuration()
        }

        var years: Double?, months: Double?, weeks: Double?, days: Double?
        var hours: Double?, minutes: Double?, seconds: Double?
        var inTime = false
        var number = ""
        for ch in upper.dropFirst() {
            if ch == "T" {
                guard number.isEmpty, !inTime else { return CourseDuration() }
                inTime = true
                continue
            }
            if ch.isASCII, ch.isNumber {
                number.append(ch)
                continue
            }
            if ch == "." || ch == "," {
                number.append(".")
                continue
            }
            guard let amount = Double(number) else { return CourseDuration() }
            number = ""
            switch (inTime, ch) {
            case (false, "Y"): years = amount
            case (false, "M"): months = amount
            case (false, "W"): weeks = amount
            case (false, "D"): days = amount
            case (true, "H"): hours = amount
            case (true, "M"): minutes = amount
            case (true, "S"): seconds = amount
            default: return CourseDuration()
            }
        }
        guard number.isEmpty else { return CourseDuration() }

        let dateParts = [years, months, weeks, days].compactMap { $0 }.filter { $0 > 0 }
        let totalSeconds = (hours ?? 0) * 3_600 + (minutes ?? 0) * 60 + (seconds ?? 0)
        if dateParts.isEmpty {
            guard totalSeconds > 0 else { return CourseDuration() }
            return CourseDuration(minutes: max(1, Int((totalSeconds / 60).rounded())))
        }

        func amountText(_ amount: Double, _ singular: String, _ plural: String) -> String {
            let whole = amount.rounded() == amount
            let number = whole ? String(Int(amount)) : String(format: "%.1f", amount)
            return "\(number) \(amount == 1 ? singular : plural)"
        }
        var parts: [String] = []
        if let years, years > 0 { parts.append(amountText(years, "year", "years")) }
        if let months, months > 0 { parts.append(amountText(months, "month", "months")) }
        if let weeks, weeks > 0 { parts.append(amountText(weeks, "week", "weeks")) }
        if let days, days > 0 { parts.append(amountText(days, "day", "days")) }
        if let hours, hours > 0 { parts.append(amountText(hours, "h", "h")) }
        if let minutes, minutes > 0 { parts.append(amountText(minutes, "min", "min")) }
        return CourseDuration(text: parts.joined(separator: " "))
    }

    // MARK: - Level

    /// `educationalLevel`: a string, a DefinedTerm `{name}` or an array (first); a schema URL
    /// keeps its last path part. First letter capitalised ("beginner" → "Beginner").
    static func level(_ value: Any?) -> String? {
        guard var text = ProductReader.brandName(from: value) else { return nil }
        if ArticleReader.looksLikeURL(text), let last = text.split(separator: "/").last {
            text = String(last)
        }
        guard let cleaned = ToolReader.clean(text) else { return nil }
        return cleaned.prefix(1).uppercased() + String(cleaned.dropFirst())
    }

    // MARK: - Topics

    /// Names from a string, a `{name}` object, or an array of either.
    static func names(_ value: Any?) -> [String] {
        if let s = ProductReader.string(value) { return [s] }
        if let dict = value as? [String: Any] { return [ProductReader.string(dict["name"])].compactMap { $0 } }
        if let array = value as? [Any] { return array.flatMap { names($0) } }
        return []
    }

    /// `teaches` (strings / DefinedTerms), `keywords` (a comma-separated string or an array)
    /// and `about` names — trimmed, at most 60 characters each, de-duplicated
    /// (case-insensitive), at most 8.
    static func topics(node: [String: Any]) -> [String] {
        var raw = names(node["teaches"])
        if let keywords = node["keywords"] as? String {
            raw += keywords.split(separator: ",").map(String.init)
        } else {
            raw += names(node["keywords"])
        }
        raw += names(node["about"])
        return cleanTopics(raw, max: maxTopics)
    }

    /// Trimmed, at most 60 characters, de-duplicated (case-insensitive), at most `max`.
    static func cleanTopics(_ values: [String], max: Int) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in values {
            guard let topic = ToolReader.clean(value), topic.count <= 60 else { continue }
            if seen.insert(topic.lowercased()).inserted { result.append(topic) }
            if result.count == max { break }
        }
        return result
    }

    // MARK: - Start date

    /// The earliest EducationEvent / `hasCourseInstance` `startDate` that is not before `now`;
    /// nil when there is none (a past cohort isn't a start date worth showing).
    static func startsAt(events: [[String: Any]], instances: [[String: Any]], now: Date) -> Date? {
        (events + instances)
            .compactMap { ArticleReader.parseDate(ProductReader.string($0["startDate"])) }
            .filter { $0 >= now }
            .min()
    }

    // MARK: - Build

    /// Assembles `CourseMeta` for one course page. `ogTitle` is the page's og:title (or
    /// `<title>`); `now` decides which cohort start dates are still ahead.
    static func build(
        sourceURL: URL,
        finalURL: URL?,
        html: String,
        ogTitle: String?,
        now: Date = .now
    ) -> CourseExtraction {
        var meta = CourseMeta()
        let base = finalURL ?? sourceURL
        let tags = pageTags(html: html)
        let nodes = html.isEmpty ? [] : PageClassifier.jsonLDNodes(from: html)
        let courseNode = nodes.first(where: { $0.types.contains(where: PageClassifier.isCourseType) })?.dict
        let events = nodes.filter { $0.types.contains(where: PageClassifier.isEducationEventType) }.map { $0.dict }
        let instances = dicts(courseNode?["hasCourseInstance"])
        // An EducationEvent-only page (no Course node) still gives a name and offers.
        let primary = courseNode ?? events.first

        // 1. Provider + name.
        meta.provider = provider(node: primary, tags: tags, url: sourceURL, base: base)
        let providerNames = [
            meta.provider?.name, tags.siteName, friendlyHostName(sourceURL), ProductReader.bareHost(sourceURL),
        ].compactMap { $0 }
        meta.name = cleanName(ProductReader.string(primary?["name"]), providerNames: providerNames)
            ?? cleanName(ogTitle, providerNames: providerNames)

        // 2. Instructor.
        meta.instructor = instructor(
            node: primary, instances: instances, tags: tags, base: base, providerName: meta.provider?.name
        )

        // 3. Format: courseMode words → an EducationEvent (cohort) → the URL path.
        var mode = format(fromCourseMode: courseNode?["courseMode"])
        for instance in instances where mode == nil { mode = format(fromCourseMode: instance["courseMode"]) }
        meta.format = mode
            ?? (events.isEmpty ? nil : "cohort")
            ?? PageClassifier.coursePathFormat(sourceURL)
            ?? finalURL.flatMap { PageClassifier.coursePathFormat($0) }

        // 4. Course facts.
        if let courseNode {
            meta.lessons = lessons(node: courseNode)
            var duration = parseDuration(ProductReader.string(courseNode["timeRequired"]))
            if duration.minutes == nil, duration.text == nil {
                for workload in [courseNode["courseWorkload"]] + instances.map({ $0["courseWorkload"] }) {
                    duration = parseDuration(ProductReader.string(workload))
                    if duration.minutes != nil || duration.text != nil { break }
                }
            }
            meta.durationMinutes = duration.minutes
            meta.durationText = duration.text
            meta.level = level(courseNode["educationalLevel"])
            meta.topics = topics(node: courseNode)
        }

        // 5. Price: isAccessibleForFree, then offers (course → instances → events).
        meta.isFree = boolValue(primary?["isAccessibleForFree"])
        let offerSources: [Any?] = [primary?["offers"]] + instances.map { $0["offers"] } + events.map { $0["offers"] }
        for source in offerSources {
            let offers = ToolReader.offerPricing(from: source)
            guard let pricing = offers.pricing else { continue }
            switch pricing {
            case "free":
                if meta.isFree == nil { meta.isFree = true }
            default:
                meta.price = offers.price
                meta.currency = offers.currency
                if meta.isFree == nil, pricing == "paid" { meta.isFree = false }
            }
            break
        }

        // 6. Next cohort.
        meta.startsAt = startsAt(events: events, instances: instances, now: now)

        // 7. Redirects: canonical whenever the final URL differs from the saved one.
        if let finalURL, finalURL.absoluteString != sourceURL.absoluteString {
            meta.canonicalURL = finalURL.absoluteString
        }

        return CourseExtraction(meta: meta, title: meta.name)
    }

    // MARK: - Guess (on-device job + conservative rule-based fallback)

    /// Whether the readers left a gap the guess may fill (format, length or topics).
    static func needsGuess(_ meta: CourseMeta) -> Bool {
        (meta.format == nil || meta.formatIsGuess)
            || ((meta.durationMinutes == nil && meta.durationText == nil) || meta.durationIsGuess)
            || (meta.topics.isEmpty || meta.topicsAreGuess)
    }

    /// "Self paced" / "on-demand" → self-paced; "cohort-based" / "live" → cohort;
    /// "program(me)" → program; "video course" → video series; "workshop" → workshop; nil
    /// for anything else.
    static func normalizeFormat(_ raw: String?) -> String? {
        guard let lower = ToolReader.clean(raw)?.lowercased() else { return nil }
        let spaced = lower.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let words = Set(spaced.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if words.contains("workshop") || words.contains("workshops") { return "workshop" }
        if words.contains("cohort") || words.contains("cohorts") || words.contains("live") { return "cohort" }
        if spaced.contains("self paced") || spaced.contains("on demand") || spaced.contains("own pace")
            || words.contains("asynchronous") {
            return "self-paced"
        }
        if words.contains("program") || words.contains("programme") || words.contains("programs") { return "program" }
        if words.contains("video") || words.contains("videos") { return "video series" }
        return nil
    }

    /// A short duration phrase with a number ("5 hours", "6 weeks"); nil otherwise.
    static func cleanDurationText(_ raw: String?) -> String? {
        guard let text = ToolReader.clean(raw), text.count <= 30, text.contains(where: \.isNumber) else { return nil }
        return text
    }

    private static let lessonsRegex = try? NSRegularExpression(
        pattern: #"\b(\d{1,4})\+?\s+(?:video\s+|bite-sized\s+|in-depth\s+)?lessons\b"#,
        options: .caseInsensitive
    )

    private static let hoursRegex = try? NSRegularExpression(
        pattern: #"\b(\d{1,3}(?:\.\d)?)\+?\s*(?:hours?|hrs?)\s+of\s+(?:video|content|lessons?|instruction|training|footage)\b"#,
        options: .caseInsensitive
    )

    private static func firstCapture(_ regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// A cheap keyword pass over the page text — conservative: "cohort" / "live sessions" →
    /// cohort, "self-paced" / "at your own pace" → self-paced; "24 lessons" → a lesson count;
    /// "5 hours of video" → "5 hours". No topics. Nil when nothing clear is said.
    static func ruleBasedFacts(text: String?) -> CourseFacts? {
        guard let cleaned = ToolReader.clean(text) else { return nil }
        let lower = cleaned.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        var format: String?
        if words.contains("cohort") || words.contains("cohorts") || lower.contains("live sessions")
            || lower.contains("live session") {
            format = "cohort"
        } else if lower.contains("self-paced") || lower.contains("self paced") || lower.contains("at your own pace") {
            format = "self-paced"
        }

        var lessons: Int? = nil
        if let raw = firstCapture(lessonsRegex, in: cleaned), let count = Int(raw), count > 0 { lessons = count }

        var durationText: String?
        if let hours = firstCapture(hoursRegex, in: cleaned) {
            durationText = hours == "1" ? "1 hour" : "\(hours) hours"
        }

        guard format != nil || lessons != nil || durationText != nil else { return nil }
        return CourseFacts(format: format, durationText: durationText, topics: [], lessons: lessons)
    }

    /// Fills only what the readers left empty (or an earlier guess), setting the flags; read
    /// values are never replaced. A guessed duration is only text — minutes are read values.
    static func applyGuess(_ facts: CourseFacts, to meta: inout CourseMeta) {
        if let format = normalizeFormat(facts.format), meta.format == nil || meta.formatIsGuess {
            meta.format = format
            meta.formatIsGuess = true
        }
        if let duration = cleanDurationText(facts.durationText), meta.durationMinutes == nil,
           meta.durationText == nil || meta.durationIsGuess {
            meta.durationText = duration
            meta.durationIsGuess = true
        }
        let topics = cleanTopics(facts.topics, max: maxGuessedTopics)
        if !topics.isEmpty, meta.topics.isEmpty || meta.topicsAreGuess {
            meta.topics = topics
            meta.topicsAreGuess = true
        }
        if let lessons = facts.lessons, lessons > 0, meta.lessons == nil || meta.lessonsIsGuess {
            meta.lessons = lessons
            meta.lessonsIsGuess = true
        }
    }

    // MARK: - Refresh merge

    /// A refetch that reads less (bot wall, login interstitial) never erases what capture
    /// read; an earlier guess survives only while nothing is read in its place.
    static func merge(fresh: CourseMeta, previous: CourseMeta?) -> CourseMeta {
        guard let previous else { return fresh }
        var meta = fresh
        if meta.name == nil { meta.name = previous.name }
        if meta.provider == nil { meta.provider = previous.provider }
        if meta.instructor == nil { meta.instructor = previous.instructor }
        if meta.format == nil {
            meta.format = previous.format
            meta.formatIsGuess = previous.formatIsGuess
        }
        if meta.lessons == nil {
            meta.lessons = previous.lessons
            meta.lessonsIsGuess = previous.lessonsIsGuess
        }
        if meta.durationMinutes == nil, meta.durationText == nil {
            meta.durationMinutes = previous.durationMinutes
            meta.durationText = previous.durationText
            meta.durationIsGuess = previous.durationIsGuess
        }
        if meta.level == nil { meta.level = previous.level }
        if meta.isFree == nil { meta.isFree = previous.isFree }
        if meta.price == nil {
            meta.price = previous.price
            meta.currency = previous.currency
        }
        if meta.topics.isEmpty {
            meta.topics = previous.topics
            meta.topicsAreGuess = previous.topicsAreGuess
        }
        if meta.startsAt == nil { meta.startsAt = previous.startsAt }
        if meta.canonicalURL == nil { meta.canonicalURL = previous.canonicalURL }
        return meta
    }
}
