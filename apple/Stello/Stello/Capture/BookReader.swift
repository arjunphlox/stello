import Foundation

// MARK: - Types

/// Authors / year guessed from page text by the on-device job when the readers found no
/// author. Stored on `BookMeta` with `authorsAreGuess` set.
nonisolated struct BookFacts: Sendable, Equatable {
    var authors: [String] = []
    var year: Int? = nil
}

/// The fields Stello reads from Open Library's
/// `api/books?bibkeys=ISBN:<isbn>&format=json&jscmd=data` response.
nonisolated struct OpenLibraryBook: Sendable, Equatable {
    var title: String?
    var subtitle: String?
    var authors: [EntityRef] = []
    var publisher: String?
    var publishedYear: Int?
    var pages: Int?
    var subjects: [String] = []
    /// `cover.large`, else `cover.medium`.
    var coverURL: String?
    /// The Open Library book page (`url`).
    var url: String?
}

/// Result of the book readers: metadata, the title the item should carry (nil = keep the page
/// title) and the cover URLs to try when the page gave no usable image (page JSON-LD image,
/// then the Open Library cover).
nonisolated struct BookExtraction: Sendable {
    var meta: BookMeta
    var title: String?
    var coverFallbackURLs: [URL] = []
}

/// The ISBNs a page names, checksum-valid and hyphen-free; each derived from the other when
/// only one is read.
nonisolated struct BookISBNs: Sendable, Equatable {
    var isbn10: String?
    var isbn13: String?
}

// MARK: - BookReader

/// Pure, network-free book readers: the ISBN (Amazon ASIN, `book:isbn` / `books:isbn` meta,
/// JSON-LD `isbn`), the Book JSON-LD node (name, author, publisher, datePublished,
/// numberOfPages, bookFormat, inLanguage, image, genre / about, plus its first
/// `workExample` edition), og / book meta tags, and the parsing of Open Library's books API.
/// The Open Library fetch itself lives in `CaptureService.extractBook`; page data wins over
/// Open Library, which only fills gaps.
nonisolated enum BookReader {

    /// The stored format vocabulary.
    static let formats: [String] = ["hardcover", "paperback", "ebook", "audiobook"]

    /// Most subjects kept.
    static let maxSubjects = 8

    /// Most authors kept from the on-device guess.
    static let maxGuessedAuthors = 4

    // MARK: - ISBN

    /// Strips an "ISBN" / "ISBN-13:" prefix, hyphens and spaces, upper-cases a trailing x;
    /// returns the value only when it is a checksum-valid ISBN-10 or ISBN-13.
    static func normalizeISBN(_ raw: String?) -> String? {
        guard var text = ToolReader.clean(raw)?.uppercased() else { return nil }
        for prefix in ["ISBN-13", "ISBN-10", "ISBN13", "ISBN10", "ISBN"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        text = String(text.filter { !$0.isWhitespace && $0 != "-" && $0 != ":" && $0 != "\u{2010}" && $0 != "\u{2011}" })
        if PageClassifier.isValidISBN10(text) || PageClassifier.isValidISBN13(text) { return text }
        return nil
    }

    /// ISBN-10 → ISBN-13: "978" + the first nine digits + the mod-10 check digit
    /// (`0262033844` → `9780262033848`). Nil for an invalid ISBN-10.
    static func isbn13(fromISBN10 isbn10: String) -> String? {
        let value = isbn10.uppercased()
        guard PageClassifier.isValidISBN10(value) else { return nil }
        let body = "978" + String(value.prefix(9))
        var sum = 0
        for (index, ch) in body.enumerated() {
            sum += (ch.wholeNumberValue ?? 0) * (index % 2 == 0 ? 1 : 3)
        }
        let check = (10 - sum % 10) % 10
        return body + String(check)
    }

    /// ISBN-13 → ISBN-10, only for the 978 prefix (979 has no ISBN-10): the nine digits after
    /// 978 + the mod-11 check digit (`9780262033848` → `0262033844`). Nil otherwise.
    static func isbn10(fromISBN13 isbn13: String) -> String? {
        guard PageClassifier.isValidISBN13(isbn13), isbn13.hasPrefix("978") else { return nil }
        let body = String(isbn13.dropFirst(3).prefix(9))
        var sum = 0
        for (index, ch) in body.enumerated() {
            sum += (ch.wholeNumberValue ?? 0) * (10 - index)
        }
        let check = (11 - sum % 11) % 11
        return body + (check == 10 ? "X" : String(check))
    }

    /// Fills the missing half from the other one.
    static func completed(_ isbns: BookISBNs) -> BookISBNs {
        var result = isbns
        if result.isbn13 == nil, let ten = result.isbn10 { result.isbn13 = isbn13(fromISBN10: ten) }
        if result.isbn10 == nil, let thirteen = result.isbn13 { result.isbn10 = isbn10(fromISBN13: thirteen) }
        return result
    }

    /// The page's ISBNs: `book:isbn` / `books:isbn` meta, the Book JSON-LD `isbn` (and its
    /// first `workExample`), then the Amazon ASIN (saved URL, then the redirect target). The
    /// first valid ISBN-10 and the first valid ISBN-13 are kept, then completed from each other.
    static func isbns(sourceURL: URL, finalURL: URL?, html: String) -> BookISBNs {
        let tags = pageTags(html: html)
        let node = bookNode(html: html)
        return isbns(sourceURL: sourceURL, finalURL: finalURL, tags: tags, node: node)
    }

    static func isbns(sourceURL: URL, finalURL: URL?, tags: PageTags, node: [String: Any]?) -> BookISBNs {
        var candidates: [String] = tags.isbns
        if let node {
            candidates += CourseReader.strings(node["isbn"])
            for example in CourseReader.dicts(node["workExample"]) {
                candidates += CourseReader.strings(example["isbn"])
            }
        }
        if let asin = PageClassifier.amazonBookISBN10(from: sourceURL) { candidates.append(asin) }
        if let asin = finalURL.flatMap({ PageClassifier.amazonBookISBN10(from: $0) }) { candidates.append(asin) }

        var result = BookISBNs()
        for candidate in candidates {
            guard let isbn = normalizeISBN(candidate) else { continue }
            if isbn.count == 10, result.isbn10 == nil { result.isbn10 = isbn }
            if isbn.count == 13, result.isbn13 == nil { result.isbn13 = isbn }
        }
        // A pair that disagrees (two different books named on the page): keep the ISBN-13 and
        // derive the ISBN-10 from it.
        if let ten = result.isbn10, let thirteen = result.isbn13, isbn13(fromISBN10: ten) != thirteen {
            result.isbn10 = isbn10(fromISBN13: thirteen)
        }
        return completed(result)
    }

    // MARK: - Meta tags

    nonisolated struct PageTags: Sendable {
        var siteName: String?
        var ogImage: String?
        /// `book:isbn` / `books:isbn` contents, in page order.
        var isbns: [String] = []
        /// `book:author` / `books:author` contents that are names (profile URLs are skipped).
        var authors: [String] = []
        /// `book:release_date` / `books:release_date`.
        var releaseDate: String?
        /// `books:page_count` / `book:page_count`.
        var pageCount: String?
    }

    static func pageTags(html: String) -> PageTags {
        var tags = PageTags()
        guard !html.isEmpty else { return tags }
        for attrs in CaptureService.metaTagAttributes(in: html) {
            guard let content = ToolReader.clean(attrs["content"]) else { continue }
            let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            switch key {
            case "og:site_name": if tags.siteName == nil { tags.siteName = content }
            case "og:image": if tags.ogImage == nil { tags.ogImage = content }
            case "book:isbn", "books:isbn": tags.isbns.append(content)
            case "book:author", "books:author":
                if !ArticleReader.looksLikeURL(content) { tags.authors.append(content) }
            case "book:release_date", "books:release_date":
                if tags.releaseDate == nil { tags.releaseDate = content }
            case "book:page_count", "books:page_count":
                if tags.pageCount == nil { tags.pageCount = content }
            default: break
            }
        }
        return tags
    }

    // MARK: - JSON-LD

    /// The first Book (or Audiobook) JSON-LD node on the page, @graph included.
    static func bookNode(html: String) -> [String: Any]? {
        guard !html.isEmpty else { return nil }
        return PageClassifier.jsonLDNodes(from: html)
            .first(where: { $0.types.contains(where: PageClassifier.isBookType) })?.dict
    }

    /// JSON-LD `author`: a string, a `{name, url}` object or an array of either → individual
    /// refs (an object keeps its `url`). URL-only values are skipped; duplicates dropped.
    static func authorRefs(_ value: Any?, base: URL) -> [EntityRef] {
        var refs: [EntityRef] = []
        var seen: Set<String> = []
        func add(_ ref: EntityRef) {
            guard !ArticleReader.looksLikeURL(ref.name), seen.insert(ref.name.lowercased()).inserted else { return }
            refs.append(ref)
        }
        func visit(_ element: Any?) {
            if let raw = element as? String, let name = ToolReader.clean(raw) {
                add(ArticleReader.authorRef(name))
            } else if element is [String: Any] {
                if var ref = ResourceReader.makerRef(from: element, base: base) {
                    ref.kind = ItemKind.individual.rawValue
                    add(ref)
                }
            } else if let array = element as? [Any] {
                array.forEach(visit)
            }
        }
        visit(value)
        return refs
    }

    /// Trimmed, de-duplicated (case-insensitive) author names as individual refs.
    static func authorRefs(names: [String]) -> [EntityRef] {
        cleanAuthorNames(names, max: Int.max).map(ArticleReader.authorRef)
    }

    /// `bookFormat` (a schema.org URL or a word) → `hardcover` | `paperback` | `ebook` |
    /// `audiobook`; nil for anything else (GraphicNovel, …).
    static func format(fromBookFormat value: Any?) -> String? {
        for raw in CourseReader.strings(value) {
            var text = raw
            if ArticleReader.looksLikeURL(text), let last = text.split(separator: "/").last { text = String(last) }
            let lower = text.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
            if lower.contains("hardcover") || lower.contains("hardback") { return "hardcover" }
            if lower.contains("paperback") || lower.contains("softcover") { return "paperback" }
            if lower.contains("ebook") || lower.contains("kindle") || lower.contains("epub") { return "ebook" }
            if lower.contains("audiobook") || lower.contains("audible") || lower.contains("audiocd") { return "audiobook" }
        }
        return nil
    }

    /// A string, `{url}` / `{contentUrl}` object or an array (first) → an absolute URL string.
    static func imageURL(_ value: Any?, base: URL) -> String? {
        var candidate: String?
        if let s = ProductReader.string(value) {
            candidate = s
        } else if let dict = value as? [String: Any] {
            candidate = ProductReader.string(dict["url"]) ?? ProductReader.string(dict["contentUrl"])
        } else if let array = value as? [Any] {
            for element in array {
                if let url = imageURL(element, base: base) { return url }
            }
        }
        guard let raw = candidate, let url = URL(string: raw, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url.absoluteString
    }

    private static let yearRegex = try? NSRegularExpression(pattern: #"(?<!\d)(1[4-9]\d{2}|20\d{2}|2100)(?!\d)"#)

    /// The first plausible four-digit year in a date ("2009-07-31", "July 31, 2009",
    /// "c2009"); nil when there is none.
    static func year(from raw: String?) -> Int? {
        guard let text = ToolReader.clean(raw), let regex = yearRegex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return plausibleYear(Int(text[range]))
    }

    /// A year between 1450 and two years from now; nil otherwise.
    static func plausibleYear(_ year: Int?) -> Int? {
        guard let year else { return nil }
        let current = Calendar(identifier: .gregorian).component(.year, from: .now)
        return (1450...(current + 2)).contains(year) ? year : nil
    }

    /// Trimmed, at most 60 characters, de-duplicated (case-insensitive), at most `max`.
    static func cleanSubjects(_ values: [String], max: Int = maxSubjects) -> [String] {
        CourseReader.cleanTopics(values, max: max)
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

    // MARK: - Title

    /// The book title: a trailing " | Site" part dropped; on Amazon the store parts
    /// (": Amazon.com: Books", the ISBN) and the "Last, First" author part dropped; a trailing
    /// " by <author>" dropped when it names a known author.
    static func cleanTitle(_ raw: String?, isAmazon: Bool, authorNames: [String]) -> String? {
        guard var text = ToolReader.clean(raw) else { return nil }

        if isAmazon {
            var parts = text.components(separatedBy: ": ").compactMap { ToolReader.clean($0) }
            parts.removeAll { part in
                let lower = part.lowercased()
                return lower.contains("amazon") || lower == "books" || lower == "kindle store"
                    || normalizeISBN(part) != nil
            }
            if parts.count > 1, let last = parts.last, last.contains(",") { parts.removeLast() }
            if !parts.isEmpty { text = parts.joined(separator: ": ") }
        }

        if let range = text.range(of: " | ", options: .backwards) {
            let head = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = text[range.upperBound...]
            if !head.isEmpty, tail.count <= 40 { text = head }
        }

        if let range = text.range(of: " by ", options: [.backwards, .caseInsensitive]) {
            let head = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = CourseReader.normalizedKey(String(text[range.upperBound...]))
            let keys = authorNames.map(CourseReader.normalizedKey).filter { !$0.isEmpty }
            if !head.isEmpty, keys.contains(where: { $0 == tail || tail.hasPrefix($0) }) { text = head }
        }
        return ToolReader.clean(text)
    }

    // MARK: - Open Library

    /// `https://openlibrary.org/api/books?bibkeys=ISBN:<isbn>&format=json&jscmd=data`.
    static func openLibraryLookupURL(isbn: String) -> URL? {
        guard let isbn = normalizeISBN(isbn) else { return nil }
        var components = URLComponents(string: "https://openlibrary.org/api/books")
        components?.queryItems = [
            URLQueryItem(name: "bibkeys", value: "ISBN:\(isbn)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "jscmd", value: "data"),
        ]
        return components?.url
    }

    /// Parses the books API response: the entry for `ISBN:<isbn>` (else the only entry).
    /// Nil for an empty object (unknown ISBN), malformed JSON or an entry with nothing usable.
    static func parseOpenLibrary(data: Data, isbn: String?) -> OpenLibraryBook? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], !root.isEmpty else {
            return nil
        }
        let entry: [String: Any]?
        if let isbn, let match = root["ISBN:\(isbn)"] as? [String: Any] {
            entry = match
        } else {
            entry = root.values.compactMap { $0 as? [String: Any] }.first
        }
        guard let entry else { return nil }

        var book = OpenLibraryBook()
        book.title = ProductReader.string(entry["title"])
        book.subtitle = ProductReader.string(entry["subtitle"])
        book.authors = CourseReader.dicts(entry["authors"]).compactMap { author in
            guard let name = ProductReader.string(author["name"]) else { return nil }
            var ref = ArticleReader.authorRef(name)
            ref.url = ProductReader.string(author["url"])
            return ref
        }
        book.publisher = CourseReader.dicts(entry["publishers"]).compactMap { ProductReader.string($0["name"]) }.first
            ?? CourseReader.strings(entry["publishers"]).first
        book.publishedYear = year(from: ProductReader.string(entry["publish_date"]))
        if let pages = ResourceReader.parseCount(entry["number_of_pages"]), pages > 0 { book.pages = pages }
        book.subjects = cleanSubjects(CourseReader.names(entry["subjects"]))
        if let cover = entry["cover"] as? [String: Any] {
            book.coverURL = ProductReader.string(cover["large"]) ?? ProductReader.string(cover["medium"])
        }
        book.url = ProductReader.string(entry["url"])

        guard book.title != nil || !book.authors.isEmpty || book.url != nil else { return nil }
        return book
    }

    /// Fills only what the page left empty; page values are never replaced. The subtitle is
    /// skipped when the page title already carries it.
    static func applyOpenLibrary(_ book: OpenLibraryBook, to meta: inout BookMeta) {
        if meta.title == nil { meta.title = ToolReader.clean(book.title) }
        if meta.subtitle == nil, let subtitle = ToolReader.clean(book.subtitle),
           !(meta.title?.lowercased().contains(subtitle.lowercased()) ?? false) {
            meta.subtitle = subtitle
        }
        if meta.authors.isEmpty, !book.authors.isEmpty {
            meta.authors = book.authors
            meta.authorsAreGuess = false
        }
        if meta.publisher == nil { meta.publisher = ToolReader.clean(book.publisher) }
        if meta.publishedYear == nil { meta.publishedYear = book.publishedYear }
        if meta.pages == nil { meta.pages = book.pages }
        if meta.subjects.isEmpty { meta.subjects = cleanSubjects(book.subjects) }
        if meta.coverURL == nil { meta.coverURL = book.coverURL }
        if meta.openLibraryURL == nil { meta.openLibraryURL = book.url }
    }

    // MARK: - Links

    /// Whether the URL is on Amazon (`amazon.<tld>` / `amzn.*`).
    static func isAmazonURL(_ url: URL) -> Bool {
        guard let host = ProductReader.bareHost(url) else { return false }
        let labels = host.split(separator: ".")
        return labels.contains("amazon") || labels.first == "amzn"
    }

    // MARK: - Build

    /// Assembles `BookMeta` for one book page. `ogTitle` / `ogImageURL` are the page's
    /// og:title (or `<title>`) and og:image; `openLibrary` is the books-API lookup for the
    /// page's ISBN (nil when there was no ISBN or the lookup failed).
    static func build(
        sourceURL: URL,
        finalURL: URL?,
        html: String,
        ogTitle: String?,
        ogImageURL: URL? = nil,
        openLibrary: OpenLibraryBook? = nil
    ) -> BookExtraction {
        var meta = BookMeta()
        let base = finalURL ?? sourceURL
        let tags = pageTags(html: html)
        let node = bookNode(html: html)
        let edition = node.flatMap { CourseReader.dicts($0["workExample"]).first }

        // 1. ISBN.
        let ids = isbns(sourceURL: sourceURL, finalURL: finalURL, tags: tags, node: node)
        meta.isbn10 = ids.isbn10
        meta.isbn13 = ids.isbn13

        // 2. Authors: JSON-LD, then the book:author metas.
        meta.authors = authorRefs(node?["author"], base: base)
        if meta.authors.isEmpty { meta.authors = authorRefs(edition?["author"], base: base) }
        if meta.authors.isEmpty { meta.authors = authorRefs(names: tags.authors) }

        // 3. Title.
        let isAmazon = isAmazonURL(sourceURL) || (finalURL.map(isAmazonURL) ?? false)
        let authorNames = meta.authors.map(\.name)
        meta.title = cleanTitle(ProductReader.string(node?["name"]), isAmazon: false, authorNames: authorNames)
            ?? cleanTitle(ogTitle, isAmazon: isAmazon, authorNames: authorNames)

        // 4. Book facts (the node, then its first edition).
        func value(_ key: String) -> Any? { node?[key] ?? edition?[key] }
        meta.publisher = ProductReader.brandName(from: value("publisher"))
        meta.publishedYear = year(from: ProductReader.string(value("datePublished"))) ?? year(from: tags.releaseDate)
        if let pages = ResourceReader.parseCount(value("numberOfPages")) ?? ResourceReader.parseCount(tags.pageCount),
           pages > 0 {
            meta.pages = pages
        }
        meta.format = format(fromBookFormat: value("bookFormat"))
        if meta.format == nil, let node,
           CourseReader.typeNames(node["@type"]).contains(where: { $0.caseInsensitiveCompare("Audiobook") == .orderedSame }) {
            meta.format = "audiobook"
        }
        meta.language = ProductReader.brandName(from: value("inLanguage"))
        if let node {
            var subjects = CourseReader.names(node["genre"])
            subjects += CourseReader.names(node["about"])
            meta.subjects = cleanSubjects(subjects)
        }

        // 5. Cover: JSON-LD image, else og:image.
        let pageImage = imageURL(node?["image"], base: base)
        meta.coverURL = pageImage ?? ogImageURL?.absoluteString ?? imageURL(tags.ogImage, base: base)

        // 6. Links from the saved URL.
        for url in [sourceURL, finalURL].compactMap({ $0 }) {
            if meta.goodreadsURL == nil, let host = ProductReader.bareHost(url),
               host == "goodreads.com" || host.hasSuffix(".goodreads.com"), PageClassifier.isKnownBookPageURL(url) {
                meta.goodreadsURL = url.absoluteString
            }
            if meta.openLibraryURL == nil, ProductReader.bareHost(url) == "openlibrary.org",
               PageClassifier.isKnownBookPageURL(url) {
                meta.openLibraryURL = url.absoluteString
            }
            if meta.amazonURL == nil, isAmazonURL(url), let isbn = PageClassifier.amazonBookISBN10(from: url),
               let host = url.host {
                meta.amazonURL = "https://\(host)/dp/\(isbn)"
            }
        }

        // 7. Open Library fills the gaps.
        if let openLibrary { applyOpenLibrary(openLibrary, to: &meta) }

        // 8. Redirects: canonical whenever the final URL differs from the saved one.
        if let finalURL, finalURL.absoluteString != sourceURL.absoluteString {
            meta.canonicalURL = finalURL.absoluteString
        }

        // Covers to try when og:image is missing or fails: the page's JSON-LD image, then
        // Open Library's.
        var fallbacks: [URL] = []
        for candidate in [pageImage, openLibrary?.coverURL] {
            guard let candidate, let url = URL(string: candidate), url != ogImageURL,
                  !fallbacks.contains(url) else { continue }
            fallbacks.append(url)
        }

        return BookExtraction(meta: meta, title: meta.title, coverFallbackURLs: fallbacks)
    }

    // MARK: - Guess (on-device job only)

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

    // MARK: - Refresh merge

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
