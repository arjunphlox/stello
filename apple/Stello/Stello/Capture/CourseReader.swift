import Foundation

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

/// On-device helpers for course items: the format / length / topics guess the on-device job fills gaps with, and
/// the merge a fresh read goes through on Enrich. The page readers themselves live on the
/// Worker (`src/lib/readers/course.js`), the one copy shared with web saves.
nonisolated enum CourseReader {

    /// Most topics kept from the on-device guess.
    static let maxGuessedTopics = 5

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
