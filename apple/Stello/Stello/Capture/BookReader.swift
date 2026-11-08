import Foundation

/// Authors / year guessed from page text by the on-device job when the readers found no
/// author. Stored on `BookMeta` with `authorsAreGuess` set.
nonisolated struct BookFacts: Sendable, Equatable {
    var authors: [String] = []
    var year: Int? = nil
}

/// On-device helpers for book items: the author guess the on-device job fills gaps with, and
/// the merge a fresh read goes through on Enrich. The page readers themselves live on the
/// Worker (`src/lib/readers/book.js`), the one copy shared with web saves.
nonisolated enum BookReader {

    /// Most authors kept from the on-device guess.
    static let maxGuessedAuthors = 4

    /// A year between 1450 and two years from now; nil otherwise.
    static func plausibleYear(_ year: Int?) -> Int? {
        guard let year else { return nil }
        let current = Calendar(identifier: .gregorian).component(.year, from: .now)
        return (1450...(current + 2)).contains(year) ? year : nil
    }

    /// Trimmed, at most 80 characters, never a URL, de-duplicated (case-insensitive), at most
    /// `max`.
    static func cleanAuthorNames(_ values: [String], max: Int) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in values {
            guard result.count < max else { break }
            guard let name = ToolReader.clean(value), name.count <= 80, !ArticleReader.looksLikeURL(name) else { continue }
            if seen.insert(name.lowercased()).inserted { result.append(name) }
        }
        return result
    }

    /// Whether the URL is on Amazon (`amazon.<tld>` / `amzn.*`).
    static func isAmazonURL(_ url: URL) -> Bool {
        guard let host = ProductReader.bareHost(url) else { return false }
        let labels = host.split(separator: ".")
        return labels.contains("amazon") || labels.first == "amzn"
    }

    /// Whether the readers left no author (or only an earlier guess).
    static func needsGuess(_ meta: BookMeta) -> Bool {
        meta.authors.isEmpty || meta.authorsAreGuess
    }

    /// Fills the authors only when none were read (or replaces an earlier guess), setting
    /// `authorsAreGuess`; fills an empty year. Read values are never replaced.
    static func applyGuess(_ facts: BookFacts, to meta: inout BookMeta) {
        let authors = cleanAuthorNames(facts.authors, max: maxGuessedAuthors)
        if !authors.isEmpty, meta.authors.isEmpty || meta.authorsAreGuess {
            meta.authors = authors.map(ArticleReader.authorRef)
            meta.authorsAreGuess = true
        }
        if meta.publishedYear == nil, let year = plausibleYear(facts.year) {
            meta.publishedYear = year
        }
    }

    /// A refetch that reads less (bot wall, failed lookup) never erases what capture read; an
    /// earlier guessed author list survives only while nothing is read in its place.
    static func merge(fresh: BookMeta, previous: BookMeta?) -> BookMeta {
        guard let previous else { return fresh }
        var meta = fresh
        if meta.title == nil { meta.title = previous.title }
        if meta.subtitle == nil { meta.subtitle = previous.subtitle }
        if meta.authors.isEmpty {
            meta.authors = previous.authors
            meta.authorsAreGuess = previous.authorsAreGuess
        }
        if meta.publisher == nil { meta.publisher = previous.publisher }
        if meta.publishedYear == nil { meta.publishedYear = previous.publishedYear }
        if meta.pages == nil { meta.pages = previous.pages }
        if meta.isbn10 == nil { meta.isbn10 = previous.isbn10 }
        if meta.isbn13 == nil { meta.isbn13 = previous.isbn13 }
        if meta.language == nil { meta.language = previous.language }
        if meta.subjects.isEmpty { meta.subjects = previous.subjects }
        if meta.format == nil { meta.format = previous.format }
        if meta.coverURL == nil { meta.coverURL = previous.coverURL }
        if meta.openLibraryURL == nil { meta.openLibraryURL = previous.openLibraryURL }
        if meta.goodreadsURL == nil { meta.goodreadsURL = previous.goodreadsURL }
        if meta.amazonURL == nil { meta.amazonURL = previous.amazonURL }
        if meta.canonicalURL == nil { meta.canonicalURL = previous.canonicalURL }
        return meta
    }
}
