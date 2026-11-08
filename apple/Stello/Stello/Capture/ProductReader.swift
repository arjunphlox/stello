import Foundation

/// A product name/brand guess — what the rule-based fallback and the on-device model both
/// return for Instagram / bare-image products (no structured data to read). Every value is
/// stored on `ProductMeta` with its `…IsGuess` flag set.
nonisolated struct ProductGuess: Sendable, Equatable {
    var productName: String?
    var brand: String?
}

/// On-device helpers for product items: the name / brand guess the on-device job fills gaps with, and
/// the merge a fresh read goes through on Enrich. The page readers themselves live on the
/// Worker (`src/lib/readers/product.js`), the one copy shared with web saves.
nonisolated enum ProductReader {

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

    static func brandRef(_ name: String) -> EntityRef {
        EntityRef(name: name, slug: nil, kind: "brand")
    }

    static func bareHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }

    static func clean(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
