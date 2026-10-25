import Foundation

/// Pure helpers that keep every fact in the item panel shown once: values are compared after
/// `normalize`, so case, HTML entities, URL scheme / `www.` / trailing `/`, a leading `@`,
/// punctuation and repeated whitespace never make two copies of the same fact look different.
nonisolated enum PanelDedupe {

    /// Lowercased, entities decoded, URL scheme / `www.` / trailing `/` / `@` and punctuation
    /// stripped (punctuation becomes a space), whitespace collapsed and trimmed.
    /// "https://www.X.com/" → "x com", "@nickfloats" → "nickfloats", "a &gt; b" → "a b".
    static func normalize(_ value: String) -> String {
        var s = CaptureService.decodeBasicEntities(value).lowercased()
        s = s.replacingOccurrences(of: #"[a-z][a-z0-9+.\-]*://"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(^|[^a-z0-9])www\."#, with: "$1", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasPrefix("@") { s.removeFirst() }
        let scalars = s.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// True when `value` (normalised) equals, or is contained in, any shown value. Containment
    /// starts on a word; it must also end on a word unless the value is a text of 4+ words (a
    /// cut-off copy of a longer text ends mid-word). Values of 2 characters or fewer only
    /// match by equality.
    static func isRedundant(_ value: String, against shown: [String]) -> Bool {
        let needle = normalize(value)
        guard !needle.isEmpty else { return false }
        let isText = needle.split(separator: " ").count >= 4
        for raw in shown {
            let hay = normalize(raw)
            guard !hay.isEmpty else { continue }
            if hay == needle { return true }
            guard needle.count > 2, hay.count > needle.count else { continue }
            let padded = " \(hay) "
            if padded.contains(" \(needle) ") { return true }
            if isText, padded.contains(" \(needle)") { return true }
        }
        return false
    }

    /// The tags worth showing: drops a tag whose normalised name equals a shown value, or is a
    /// single word (3+ characters) of a shown short value (≤ 4 words — an author name, handle,
    /// host, model, platform, publication…). A host's words cover the host without its TLD
    /// ("dribbble.com" hides "dribbble"); "x.com" hides "x.com" by equality.
    static func filterTags(_ names: [String], shown: [String]) -> [String] {
        var values = Set<String>()
        var words = Set<String>()
        for raw in shown {
            let n = normalize(raw)
            guard !n.isEmpty else { continue }
            values.insert(n)
            let parts = n.split(separator: " ").map(String.init)
            if parts.count <= 4 {
                for word in parts where word.count > 2 { words.insert(word) }
            }
        }
        return names.filter { name in
            let n = normalize(name)
            guard !n.isEmpty else { return false }
            if values.contains(n) { return false }
            if !n.contains(" "), words.contains(n) { return false }
            return true
        }
    }

    /// The first non-empty candidate (trimmed).
    static func primaryText(candidates: [String?]) -> String? {
        candidates.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The first non-empty candidate, plus the later ones that aren't redundant with it or with
    /// each other (in order).
    static func primaryAndRest(candidates: [String?]) -> (primary: String?, rest: [String]) {
        let texts = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let primary = texts.first else { return (nil, []) }
        var kept: [String] = [primary]
        for text in texts.dropFirst() where !isRedundant(text, against: kept) {
            kept.append(text)
        }
        return (primary, Array(kept.dropFirst()))
    }

    /// True when a site-naming value ("X", "Instagram", "Frontend Masters",
    /// "simonwillison.net") names the same site as `host` ("x.com", "frontendmasters.com").
    static func namesSameSite(_ value: String, host: String) -> Bool {
        let v = normalize(value)
        let h = normalize(host)
        guard !v.isEmpty, !h.isEmpty else { return false }
        if v == h { return true }
        let hostParts = h.split(separator: " ").map(String.init)
        let bare = hostParts.count > 1 ? hostParts.dropLast().joined() : h
        let squashed = v.replacingOccurrences(of: " ", with: "")
        return squashed == bare || squashed == h.replacingOccurrences(of: " ", with: "")
    }

    /// True when two URLs point at the same page once normalised.
    static func isSameURL(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        let na = normalize(a)
        return !na.isEmpty && na == normalize(b)
    }
}
