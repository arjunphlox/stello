import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - Helpers

private func classify(
    _ urlString: String,
    html: String = "<html><head></head><body></body></html>",
    ogType: String? = nil,
    labels: [String] = [],
    title: String = "Some page"
) -> PageClassificationResult {
    let url = URL(string: urlString)!
    return PageClassifier.classify(
        html: html,
        baseURL: url,
        domain: url.host,
        title: title,
        ogDescription: nil,
        ogType: ogType,
        collectionLabels: labels
    )
}

private func jsonLD(_ body: String) -> String {
    """
    <html><head><script type="application/ld+json">
    \(body)
    </script></head><body></body></html>
    """
}

/// `<meta>` tags from (key, content) pairs; `og:` / `book:` / `books:` keys use `property`,
/// the rest `name`.
private func metas(_ pairs: [(String, String)], extraHead: String = "") -> String {
    let tags = pairs.map { pair -> String in
        let (key, content) = pair
        let usesProperty = key.hasPrefix("og:") || key.hasPrefix("book:") || key.hasPrefix("books:")
        let attr = usesProperty ? "property" : "name"
        return #"<meta \#(attr)="\#(key)" content="\#(content)">"#
    }.joined(separator: "\n")
    return "<html><head>\n\(tags)\n\(extraHead)</head><body></body></html>"
}

private func buildBook(
    _ urlString: String,
    finalURL: String? = nil,
    html: String = "",
    ogTitle: String? = nil,
    ogImageURL: String? = nil,
    openLibrary: OpenLibraryBook? = nil
) -> BookExtraction {
    BookReader.build(
        sourceURL: URL(string: urlString)!,
        finalURL: finalURL.flatMap { URL(string: $0) },
        html: html,
        ogTitle: ogTitle,
        ogImageURL: ogImageURL.flatMap { URL(string: $0) },
        openLibrary: openLibrary
    )
}

// MARK: - Fixtures

/// Introduction to Algorithms, 3rd edition — ISBN-10 0262033844 ↔ ISBN-13 9780262033848.
/// Checked by hand: ISBN-10 0·10+2·9+6·8+2·7+0·6+3·5+3·4+8·3+4·2+4·1 = 143 = 11·13 (valid);
/// ISBN-13 body 978026203384 weighted 1,3,1,3… = 9+21+8+0+2+18+2+0+3+9+8+12 = 92 → check
/// digit (10 − 2) % 10 = 8.
private let algorithmsISBN10 = "0262033844"
private let algorithmsISBN13 = "9780262033848"
private let algorithmsAmazonURL = "https://www.amazon.com/Introduction-Algorithms-3rd-MIT-Press/dp/0262033844"
private let algorithmsAmazonTitle = "Introduction to Algorithms, 3rd Edition (The MIT Press): Cormen, Thomas H., Leiserson, Charles E., Rivest, Ronald L., Stein, Clifford: 9780262033848: Amazon.com: Books"

private let goodreadsURL = "https://www.goodreads.com/book/show/40121378-atomic-habits"

private let goodreadsJSONLD = #"""
{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits",
 "bookFormat":"Hardcover","numberOfPages":320,"inLanguage":"English","isbn":"9780735211292",
 "author":[{"@type":"Person","name":"James Clear","url":"https://www.goodreads.com/author/show/7327369.James_Clear"}],
 "aggregateRating":{"@type":"AggregateRating","ratingValue":4.37,"ratingCount":1102345}}
"""#

private let goodreadsHTML = """
<html><head>
<meta property="og:type" content="books.book">
<meta property="og:title" content="Atomic Habits: An Easy &amp; Proven Way to Build Good Habits &amp; Break Bad Ones">
<meta property="books:isbn" content="9780735211292">
<meta property="books:author" content="https://www.goodreads.com/author/show/7327369.James_Clear">
<meta property="books:page_count" content="320">
<script type="application/ld+json">
\(goodreadsJSONLD)
</script>
</head><body></body></html>
"""

private let publisherJSONLD = #"""
{"@context":"https://schema.org","@graph":[
 {"@type":"WebPage","name":"Atomic Habits by James Clear | Penguin Random House"},
 {"@type":"Book","name":"Atomic Habits",
  "author":"James Clear",
  "publisher":{"@type":"Organization","name":"Avery"},
  "datePublished":"2018-10-16","bookFormat":"https://schema.org/Hardcover","inLanguage":"en",
  "numberOfPages":"320","isbn":"978-0-7352-1129-2","genre":["Self-help","Psychology"],
  "image":{"@type":"ImageObject","url":"/covers/atomic-habits.jpg"}}
]}
"""#

/// Open Library `api/books?bibkeys=ISBN:9780262033848&format=json&jscmd=data`, trimmed to the
/// realistic shape (identifiers / classifications / places included, as the API sends them).
private let openLibraryAlgorithmsJSON = #"""
{"ISBN:9780262033848": {
  "url": "https://openlibrary.org/books/OL23167449M/Introduction_to_algorithms",
  "key": "/books/OL23167449M",
  "title": "Introduction to algorithms",
  "subtitle": "third edition",
  "authors": [
    {"url": "https://openlibrary.org/authors/OL1802741A/Thomas_H._Cormen", "name": "Thomas H. Cormen"},
    {"url": "https://openlibrary.org/authors/OL221935A/Charles_E._Leiserson", "name": "Charles E. Leiserson"},
    {"url": "https://openlibrary.org/authors/OL221936A/Ronald_L._Rivest", "name": "Ronald L. Rivest"},
    {"url": "https://openlibrary.org/authors/OL2700926A/Clifford_Stein", "name": "Clifford Stein"}
  ],
  "number_of_pages": 1292,
  "pagination": "xix, 1292 p. :",
  "identifiers": {"isbn_10": ["0262033844"], "isbn_13": ["9780262033848"], "openlibrary": ["OL23167449M"]},
  "classifications": {"lc_classifications": ["QA76.6 .C662 2009"], "dewey_decimal_class": ["005.1"]},
  "publishers": [{"name": "MIT Press"}],
  "publish_places": [{"name": "Cambridge, Mass"}],
  "publish_date": "2009",
  "subjects": [
    {"name": "Computer programming", "url": "https://openlibrary.org/subjects/computer_programming"},
    {"name": "Computer algorithms", "url": "https://openlibrary.org/subjects/computer_algorithms"}
  ],
  "cover": {
    "small": "https://covers.openlibrary.org/b/id/6276478-S.jpg",
    "medium": "https://covers.openlibrary.org/b/id/6276478-M.jpg",
    "large": "https://covers.openlibrary.org/b/id/6276478-L.jpg"
  }
}}
"""#

private func openLibraryAlgorithms() -> OpenLibraryBook {
    BookReader.parseOpenLibrary(data: Data(openLibraryAlgorithmsJSON.utf8), isbn: algorithmsISBN13)!
}

// MARK: - Classification

@Suite("Book classification")
struct BookClassificationTests {

    @Test("Book JSON-LD → book (top level and inside @graph)")
    func bookJSONLD() {
        let top = jsonLD(#"{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits"}"#)
        #expect(classify("https://jamesclear.com/atomic-habits", html: top).kind == .book)
        #expect(classify("https://www.penguinrandomhouse.com/books/543834/atomic-habits", html: jsonLD(publisherJSONLD)).kind == .book)
        #expect(PageClassifier.hasBookNode(html: jsonLD(publisherJSONLD)))
    }

    @Test("og:type book / books.book and book:isbn / books:isbn metas → book")
    func ogTypeAndISBNMeta() {
        #expect(classify("https://example.com/a-book", ogType: "books.book").kind == .book)
        #expect(classify("https://example.com/a-book", ogType: "book").kind == .book)
        #expect(classify("https://example.com/a-book", html: metas([("book:isbn", algorithmsISBN13)])).kind == .book)
        #expect(classify("https://example.com/a-book", html: metas([("books:isbn", algorithmsISBN13)])).kind == .book)
        #expect(classify("https://example.com/a-book", ogType: "article").kind != .book)
    }

    @Test("Amazon /dp/ with a valid ISBN-10 → book (also /gp/product/, /o/ASIN/, amzn, X check digit)")
    func amazonISBN() {
        #expect(classify(algorithmsAmazonURL).kind == .book)
        #expect(classify("https://www.amazon.com/dp/0262033844").kind == .book)
        #expect(classify("https://www.amazon.co.uk/gp/product/0262033844/ref=x").kind == .book)
        #expect(classify("https://www.amazon.in/o/ASIN/0262033844").kind == .book)
        #expect(classify("https://amzn.com/dp/0262033844").kind == .book)
        #expect(classify("https://www.amazon.com/Some-Book/dp/080442957X").kind == .book)
        #expect(classify("https://www.amazon.com/Some-Book/dp/080442957x").kind == .book)
        #expect(PageClassifier.amazonBookISBN10(from: URL(string: "https://www.amazon.com/Some-Book/dp/080442957x")!) == "080442957X")
        #expect(PageClassifier.amazonBookISBN10(from: URL(string: "https://amazon.com.evil.net/dp/0262033844")!) == nil)
    }

    @Test("Amazon /dp/B0… ASIN → not a book (product rules as before)")
    func amazonNonBookASIN() {
        let url = "https://www.amazon.com/Stuffcool-Mag-Dock/dp/B0CHX1W1XY"
        #expect(classify(url).kind == .product)
        #expect(classify(url).productSource == "page")
        #expect(!PageClassifier.isBook(url: URL(string: url)!, ogType: nil, html: ""))
    }

    @Test("A 10-digit ASIN with an invalid ISBN checksum → not a book")
    func invalidChecksum() {
        let url = "https://www.amazon.com/dp/0262033845"
        #expect(!PageClassifier.isValidISBN10("0262033845"))
        #expect(classify(url).kind != .book)
        #expect(classify(url).kind == .product)
    }

    @Test("Known single-book pages: Goodreads, Open Library, Google Books, StoryGraph, Bookshop.org")
    func knownBookPages() {
        #expect(classify(goodreadsURL).kind == .book)
        #expect(classify("https://openlibrary.org/works/OL17930368W/Atomic_Habits").kind == .book)
        #expect(classify("https://openlibrary.org/books/OL26331930M").kind == .book)
        #expect(classify("https://books.google.com/books?id=XfFvDwAAQBAJ").kind == .book)
        #expect(classify("https://books.google.co.in/books?id=XfFvDwAAQBAJ&printsec=frontcover").kind == .book)
        #expect(classify("https://www.google.com/books/edition/Atomic_Habits/XfFvDwAAQBAJ").kind != .book)
        #expect(classify("https://books.google.com/books/edition/Atomic_Habits/XfFvDwAAQBAJ").kind == .book)
        #expect(classify("https://app.thestorygraph.com/books/7b3f3c1e-2d5a-4b8e-9a43-6f1c2e8d9b10").kind == .book)
        #expect(classify("https://bookshop.org/p/books/atomic-habits-james-clear/12345678").kind == .book)

        // Not single books.
        #expect(classify("https://openlibrary.org/authors/OL1A").kind != .book)
        #expect(classify("https://openlibrary.org/works/not-an-id").kind != .book)
        #expect(classify("https://books.google.com/").kind != .book)
        #expect(classify("https://app.thestorygraph.com/browse").kind != .book)
        #expect(classify("https://bookshop.org/lists/best-books-of-2025").kind != .book)
    }

    @Test("Goodreads /list/ and /shelf/ are not books; with the books label a list stays a website")
    func readingLists() {
        let list = "https://www.goodreads.com/list/show/1.Best_Books_Ever"
        #expect(classify(list).kind != .book)
        #expect(classify("https://www.goodreads.com/shelf/show/design").kind != .book)
        #expect(classify(list, labels: ["books"]).kind == .link)
        // A "best books" post: two different Book nodes are a list, not a book.
        let roundup = jsonLD(#"""
        {"@context":"https://schema.org","@graph":[
         {"@type":"Book","name":"Atomic Habits"},{"@type":"Book","name":"Deep Work"}]}
        """#)
        #expect(classify("https://example.com/best-books-2025", html: roundup).kind != .book)
        #expect(classify("https://example.com/best-books-2025", html: roundup, labels: ["books"]).kind == .link)
    }

    @Test("A wishlisted Amazon ISBN link is still a book")
    func wishlistedISBN() {
        #expect(classify(algorithmsAmazonURL, labels: ["wishlist"]).kind == .book)
        #expect(classify(algorithmsAmazonURL, labels: ["wishlist", "books"]).kind == .book)
        // A wishlisted non-book ASIN stays a product.
        #expect(classify("https://www.amazon.com/dp/B0CHX1W1XY", labels: ["wishlist"]).kind == .product)
    }

    @Test("Product JSON-LD with offers + Book JSON-LD → book; product rules skip the Book page")
    func productAndBookNodes() {
        let html = jsonLD(#"""
        {"@context":"https://schema.org","@graph":[
         {"@type":"Product","name":"Atomic Habits (Hardcover)","offers":{"@type":"Offer","price":"18.99","priceCurrency":"USD"}},
         {"@type":"Book","name":"Atomic Habits","isbn":"9780735211292"}]}
        """#)
        let url = "https://shop.example.com/atomic-habits"
        #expect(classify(url, html: html).kind == .book)
        #expect(PageClassifier.productSource(url: URL(string: url)!, ogType: nil, html: html, collectionLabels: []) == nil)
    }

    @Test("Book runs after post and resource; a bare image file is never a book")
    func ordering() {
        #expect(classify("https://x.com/jamesclear/status/1234567890").kind == .post)
        #expect(classify("https://example.com/cover.jpg", ogType: "books.book").kind != .book)
        // A Figma Community file about books stays a resource.
        #expect(classify(
            "https://www.figma.com/community/file/123456/book-mockups",
            html: jsonLD(#"{"@type":"Book","name":"Mockups"}"#)
        ).kind == .resource)
    }

    @Test("isSingleBook (reading-list veto) also knows Google Books and Bookshop.org")
    func singleBookExtended() {
        #expect(PageClassifier.isSingleBook(url: URL(string: "https://books.google.com/books?id=XfFvDwAAQBAJ")!, html: ""))
        #expect(PageClassifier.isSingleBook(url: URL(string: "https://bookshop.org/p/books/atomic-habits/123")!, html: ""))
        #expect(PageClassifier.isSingleBook(
            url: URL(string: "https://example.com/a")!, html: metas([("books:isbn", algorithmsISBN13)])
        ))
        #expect(!PageClassifier.isSingleBook(url: URL(string: "https://www.goodreads.com/list/show/1.Best_Books_Ever")!, html: ""))
    }
}

// MARK: - Readers

@Suite("Book readers")
struct BookReaderTests {

    @Test("ISBN-10 ↔ ISBN-13 conversion and checksums (real ISBNs)")
    func isbnConversion() {
        #expect(BookReader.isbn13(fromISBN10: algorithmsISBN10) == algorithmsISBN13)
        #expect(BookReader.isbn10(fromISBN13: algorithmsISBN13) == algorithmsISBN10)
        #expect(BookReader.isbn13(fromISBN10: "0735211299") == "9780735211292")
        #expect(BookReader.isbn10(fromISBN13: "9780735211292") == "0735211299")
        // X check digit.
        #expect(BookReader.isbn13(fromISBN10: "080442957X") == "9780804429573")
        #expect(BookReader.isbn10(fromISBN13: "9780804429573") == "080442957X")
        // Invalid input / 979 has no ISBN-10.
        #expect(BookReader.isbn13(fromISBN10: "0262033845") == nil)
        #expect(BookReader.isbn10(fromISBN13: "9791032305690") == nil)
        #expect(PageClassifier.isValidISBN13(algorithmsISBN13))
        #expect(!PageClassifier.isValidISBN13("9780262033847"))
        #expect(!PageClassifier.isValidISBN13("1234567890123"))
        #expect(PageClassifier.isValidISBN10("080442957X"))
        #expect(!PageClassifier.isValidISBN10("B0CHX1W1XY"))
    }

    @Test("ISBN normalisation: hyphens, spaces, prefixes, lower-case x; invalid → nil")
    func isbnNormalisation() {
        #expect(BookReader.normalizeISBN("978-0-262-03384-8") == algorithmsISBN13)
        #expect(BookReader.normalizeISBN("ISBN-13: 978 0 262 03384 8") == algorithmsISBN13)
        #expect(BookReader.normalizeISBN("ISBN 0-262-03384-4") == algorithmsISBN10)
        #expect(BookReader.normalizeISBN("0-8044-2957-x") == "080442957X")
        #expect(BookReader.normalizeISBN("978-0-262-03384-9") == nil)
        #expect(BookReader.normalizeISBN("not an isbn") == nil)
        #expect(BookReader.normalizeISBN(nil) == nil)
    }

    @Test("ISBNs from the Amazon ASIN, the books:isbn meta and JSON-LD; each completes the other")
    func isbnSources() {
        let amazon = BookReader.isbns(sourceURL: URL(string: algorithmsAmazonURL)!, finalURL: nil, html: "")
        #expect(amazon == BookISBNs(isbn10: algorithmsISBN10, isbn13: algorithmsISBN13))

        let meta = BookReader.isbns(
            sourceURL: URL(string: "https://example.com/b")!, finalURL: nil,
            html: metas([("books:isbn", "9780735211292")])
        )
        #expect(meta == BookISBNs(isbn10: "0735211299", isbn13: "9780735211292"))

        let ld = BookReader.isbns(sourceURL: URL(string: "https://example.com/b")!, finalURL: nil, html: jsonLD(publisherJSONLD))
        #expect(ld.isbn13 == "9780735211292")
        #expect(ld.isbn10 == "0735211299")

        // workExample editions count when the work node has no isbn.
        let work = jsonLD(#"""
        {"@context":"https://schema.org","@type":"Book","name":"Atomic Habits",
         "workExample":[{"@type":"Book","isbn":"978-0-7352-1129-2","bookFormat":"https://schema.org/EBook","datePublished":"2018"}]}
        """#)
        let fromWork = buildBook("https://example.com/b", html: work).meta
        #expect(fromWork.isbn13 == "9780735211292")
        #expect(fromWork.format == "ebook")
        #expect(fromWork.publishedYear == 2018)
    }

    @Test("JSON-LD author: string, object, array of both; URL-only values and duplicates skipped")
    func authorVariants() {
        let base = URL(string: "https://example.com/")!
        #expect(BookReader.authorRefs("James Clear", base: base).map(\.name) == ["James Clear"])

        let person: [String: Any] = ["@type": "Person", "name": "James Clear", "url": "/authors/james-clear"]
        let object = BookReader.authorRefs(person, base: base)
        #expect(object.map(\.name) == ["James Clear"])
        #expect(object.first?.url == "https://example.com/authors/james-clear")
        #expect(object.first?.kind == ItemKind.individual.rawValue)

        let cormen: [String: Any] = ["@type": "Person", "name": "Thomas H. Cormen"]
        let cormenAgain: [String: Any] = ["@type": "Person", "name": "thomas h. cormen"]
        let mixed: [Any] = [cormen, "Charles E. Leiserson", "https://example.com/authors/rivest", cormenAgain]
        #expect(BookReader.authorRefs(mixed, base: base).map(\.name) == ["Thomas H. Cormen", "Charles E. Leiserson"])
        #expect(BookReader.authorRefs(nil, base: base).isEmpty)
    }

    @Test("bookFormat mapping: schema URLs and words → hardcover / paperback / ebook / audiobook")
    func formatMapping() {
        #expect(BookReader.format(fromBookFormat: "https://schema.org/Hardcover") == "hardcover")
        #expect(BookReader.format(fromBookFormat: "http://schema.org/Paperback") == "paperback")
        #expect(BookReader.format(fromBookFormat: "https://schema.org/EBook") == "ebook")
        #expect(BookReader.format(fromBookFormat: "https://schema.org/AudiobookFormat") == "audiobook")
        #expect(BookReader.format(fromBookFormat: "Hardcover") == "hardcover")
        #expect(BookReader.format(fromBookFormat: "Mass Market Paperback") == "paperback")
        #expect(BookReader.format(fromBookFormat: "Kindle Edition") == "ebook")
        #expect(BookReader.format(fromBookFormat: "Audio CD") == "audiobook")
        #expect(BookReader.format(fromBookFormat: "https://schema.org/GraphicNovel") == nil)
        #expect(BookReader.format(fromBookFormat: nil) == nil)
        // An Audiobook node with no bookFormat.
        let audio = buildBook("https://example.com/b", html: jsonLD(#"{"@type":"Audiobook","name":"Atomic Habits"}"#)).meta
        #expect(audio.format == "audiobook")
    }

    @Test("Goodreads page: JSON-LD + books: metas (author profile URL skipped)")
    func goodreads() {
        let extraction = buildBook(goodreadsURL, html: goodreadsHTML, ogTitle: "Atomic Habits by James Clear | Goodreads")
        let meta = extraction.meta
        #expect(extraction.title == "Atomic Habits")
        #expect(meta.authors.map(\.name) == ["James Clear"])
        #expect(meta.authorsAreGuess == false)
        #expect(meta.format == "hardcover")
        #expect(meta.pages == 320)
        #expect(meta.language == "English")
        #expect(meta.languageLabel == "English")
        #expect(meta.isbn13 == "9780735211292")
        #expect(meta.isbn10 == "0735211299")
        #expect(meta.goodreadsURL == goodreadsURL)
        #expect(meta.amazonURL == nil)
        #expect(meta.publishedYear == nil)
        #expect(meta.canonicalURL == nil)
    }

    @Test("Publisher page: @graph Book, publisher object, datePublished, genre, relative image")
    func publisherPage() {
        let url = "https://www.penguinrandomhouse.com/books/543834/atomic-habits"
        let extraction = buildBook(url, html: jsonLD(publisherJSONLD), ogTitle: "Atomic Habits by James Clear | Penguin Random House")
        let meta = extraction.meta
        #expect(meta.title == "Atomic Habits")
        #expect(meta.authors.map(\.name) == ["James Clear"])
        #expect(meta.publisher == "Avery")
        #expect(meta.publishedYear == 2018)
        #expect(meta.pages == 320)
        #expect(meta.format == "hardcover")
        #expect(meta.language == "en")
        #expect(meta.languageLabel == "English")
        #expect(meta.subjects == ["Self-help", "Psychology"])
        #expect(meta.coverURL == "https://www.penguinrandomhouse.com/covers/atomic-habits.jpg")
        #expect(extraction.coverFallbackURLs.map(\.absoluteString) == ["https://www.penguinrandomhouse.com/covers/atomic-habits.jpg"])
    }

    @Test("book:author / book:release_date metas when there is no JSON-LD")
    func metaOnly() {
        let html = metas([
            ("og:type", "book"),
            ("book:author", "Ursula K. Le Guin"),
            ("book:release_date", "1969-03-01"),
            ("book:isbn", "9780441478125"),
        ])
        let meta = buildBook("https://example.com/left-hand-of-darkness", html: html, ogTitle: "The Left Hand of Darkness").meta
        #expect(meta.title == "The Left Hand of Darkness")
        #expect(meta.authors.map(\.name) == ["Ursula K. Le Guin"])
        #expect(meta.publishedYear == 1969)
        #expect(meta.isbn13 == "9780441478125")
    }

    @Test("Title cleaning: Amazon store parts and the 'Last, First' author part; ' | Site'; ' by <author>'")
    func titleCleaning() {
        #expect(BookReader.cleanTitle(algorithmsAmazonTitle, isAmazon: true, authorNames: [])
            == "Introduction to Algorithms, 3rd Edition (The MIT Press)")
        #expect(BookReader.cleanTitle(
            "Atomic Habits: An Easy & Proven Way to Build Good Habits & Break Bad Ones: Clear, James: 9780735211292: Amazon.com: Books",
            isAmazon: true, authorNames: []
        ) == "Atomic Habits: An Easy & Proven Way to Build Good Habits & Break Bad Ones")
        #expect(BookReader.cleanTitle("Clean Code, A Handbook: Amazon.co.uk: Books", isAmazon: true, authorNames: [])
            == "Clean Code, A Handbook")
        #expect(BookReader.cleanTitle("Atomic Habits by James Clear | Goodreads", isAmazon: false, authorNames: ["James Clear"])
            == "Atomic Habits")
        // " by …" stays when it doesn't name a known author.
        #expect(BookReader.cleanTitle("Stand by Me", isAmazon: false, authorNames: ["James Clear"]) == "Stand by Me")
    }

    @Test("Open Library fixture: title, subtitle, authors, publisher, year, pages, subjects, cover, url")
    func openLibraryParsing() {
        let book = openLibraryAlgorithms()
        #expect(book.title == "Introduction to algorithms")
        #expect(book.subtitle == "third edition")
        #expect(book.authors.map(\.name) == ["Thomas H. Cormen", "Charles E. Leiserson", "Ronald L. Rivest", "Clifford Stein"])
        #expect(book.authors.first?.url == "https://openlibrary.org/authors/OL1802741A/Thomas_H._Cormen")
        #expect(book.publisher == "MIT Press")
        #expect(book.publishedYear == 2009)
        #expect(book.pages == 1292)
        #expect(book.subjects == ["Computer programming", "Computer algorithms"])
        #expect(book.coverURL == "https://covers.openlibrary.org/b/id/6276478-L.jpg")
        #expect(book.url == "https://openlibrary.org/books/OL23167449M/Introduction_to_algorithms")

        // Medium cover when there is no large one; a long publish_date still gives the year.
        let medium = BookReader.parseOpenLibrary(data: Data(#"""
        {"ISBN:0735211299":{"title":"Atomic Habits","publish_date":"Oct 16, 2018",
         "cover":{"medium":"https://covers.openlibrary.org/b/id/1-M.jpg"}}}
        """#.utf8), isbn: "0735211299")
        #expect(medium?.coverURL == "https://covers.openlibrary.org/b/id/1-M.jpg")
        #expect(medium?.publishedYear == 2018)

        // Unknown ISBN ({}), malformed JSON → nil.
        #expect(BookReader.parseOpenLibrary(data: Data("{}".utf8), isbn: "0262033844") == nil)
        #expect(BookReader.parseOpenLibrary(data: Data("<html>".utf8), isbn: "0262033844") == nil)
        #expect(BookReader.openLibraryLookupURL(isbn: "978-0-262-03384-8")?.absoluteString
            == "https://openlibrary.org/api/books?bibkeys=ISBN:9780262033848&format=json&jscmd=data")
    }

    @Test("Amazon page + Open Library: the page wins, Open Library fills the gaps")
    func amazonWithOpenLibrary() {
        let extraction = buildBook(algorithmsAmazonURL, ogTitle: algorithmsAmazonTitle, openLibrary: openLibraryAlgorithms())
        let meta = extraction.meta
        #expect(meta.title == "Introduction to Algorithms, 3rd Edition (The MIT Press)")
        #expect(meta.subtitle == "third edition")
        #expect(meta.authors.count == 4)
        #expect(meta.authorsAreGuess == false)
        #expect(meta.publisher == "MIT Press")
        #expect(meta.publishedYear == 2009)
        #expect(meta.pages == 1292)
        #expect(meta.isbn10 == algorithmsISBN10)
        #expect(meta.isbn13 == algorithmsISBN13)
        #expect(meta.subjects == ["Computer programming", "Computer algorithms"])
        #expect(meta.coverURL == "https://covers.openlibrary.org/b/id/6276478-L.jpg")
        #expect(meta.openLibraryURL == "https://openlibrary.org/books/OL23167449M/Introduction_to_algorithms")
        #expect(meta.amazonURL == "https://www.amazon.com/dp/0262033844")
        #expect(extraction.coverFallbackURLs.map(\.absoluteString) == ["https://covers.openlibrary.org/b/id/6276478-L.jpg"])

        // Page values beat Open Library's.
        let page = jsonLD(#"""
        {"@type":"Book","name":"Introduction to Algorithms","author":"T. Cormen","publisher":"The MIT Press",
         "datePublished":"2009-07-31","numberOfPages":1312}
        """#)
        let mixed = buildBook(algorithmsAmazonURL, html: page, ogTitle: algorithmsAmazonTitle, openLibrary: openLibraryAlgorithms()).meta
        #expect(mixed.title == "Introduction to Algorithms")
        #expect(mixed.authors.map(\.name) == ["T. Cormen"])
        #expect(mixed.publisher == "The MIT Press")
        #expect(mixed.pages == 1312)
        // The subtitle fills in; it is skipped when the title already carries it.
        #expect(mixed.subtitle == "third edition")
        var titled = BookMeta()
        titled.title = "Introduction to Algorithms, Third Edition"
        BookReader.applyOpenLibrary(openLibraryAlgorithms(), to: &titled)
        #expect(titled.subtitle == nil)
    }

    @Test("Kind line variants: 'Author · Year', +N for more authors, either part alone, nil")
    func kindLine() {
        var meta = BookMeta()
        #expect(meta.cardKindLine == nil)
        meta.publishedYear = 2018
        #expect(meta.cardKindLine == "2018")
        meta.authors = [ArticleReader.authorRef("James Clear")]
        #expect(meta.cardKindLine == "James Clear · 2018")
        meta.publishedYear = nil
        #expect(meta.cardKindLine == "James Clear")
        meta.authors = ["Thomas H. Cormen", "Charles E. Leiserson", "Ronald L. Rivest", "Clifford Stein"].map(ArticleReader.authorRef)
        meta.publishedYear = 2009
        #expect(meta.cardKindLine == "Thomas H. Cormen +3 · 2009")
        #expect(meta.authorsLine == "Thomas H. Cormen, Charles E. Leiserson, Ronald L. Rivest, Clifford Stein")
    }

    @Test("Panel lines: ISBN-13 preferred, pages, format label")
    func panelLines() {
        var meta = BookMeta()
        meta.isbn10 = algorithmsISBN10
        #expect(meta.isbnLine == algorithmsISBN10)
        meta.isbn13 = algorithmsISBN13
        #expect(meta.isbnLine == algorithmsISBN13)
        meta.pages = 1292
        #expect(meta.pagesLine == "1292 pages")
        meta.format = "paperback"
        #expect(meta.formatLabel == "Paperback")
    }

    @Test("Canonical URL: set when the final URL differs, else nil")
    func canonical() {
        let redirected = buildBook("https://amzn.com/dp/0262033844", finalURL: "https://www.amazon.com/dp/0262033844").meta
        #expect(redirected.canonicalURL == "https://www.amazon.com/dp/0262033844")
        #expect(buildBook(goodreadsURL, finalURL: goodreadsURL).meta.canonicalURL == nil)
    }

    @Test("Guess fills only empty authors (flagged) and an empty year; read values win")
    func applyGuess() {
        var empty = BookMeta()
        BookReader.applyGuess(BookFacts(authors: ["Thomas H. Cormen", "https://example.com/x", " ", "Clifford Stein"], year: 2009), to: &empty)
        #expect(empty.authors.map(\.name) == ["Thomas H. Cormen", "Clifford Stein"])
        #expect(empty.authorsAreGuess)
        #expect(empty.publishedYear == 2009)
        #expect(BookReader.needsGuess(empty))

        var read = BookMeta()
        read.authors = [ArticleReader.authorRef("James Clear")]
        read.publishedYear = 2018
        #expect(!BookReader.needsGuess(read))
        BookReader.applyGuess(BookFacts(authors: ["Someone Else"], year: 1999), to: &read)
        #expect(read.authors.map(\.name) == ["James Clear"])
        #expect(read.authorsAreGuess == false)
        #expect(read.publishedYear == 2018)

        // Implausible years are dropped.
        var future = BookMeta()
        BookReader.applyGuess(BookFacts(authors: [], year: 3000), to: &future)
        #expect(future.publishedYear == nil)
    }

    @Test("A refetch that reads less never erases what capture read; a guess survives")
    func merge() {
        var previous = buildBook(algorithmsAmazonURL, ogTitle: algorithmsAmazonTitle, openLibrary: openLibraryAlgorithms()).meta
        previous.authorsAreGuess = false
        let fresh = buildBook(algorithmsAmazonURL).meta  // bot wall, lookup failed
        let merged = BookReader.merge(fresh: fresh, previous: previous)
        #expect(merged.title == previous.title)
        #expect(merged.authors.count == 4)
        #expect(merged.publisher == "MIT Press")
        #expect(merged.pages == 1292)
        #expect(merged.openLibraryURL == previous.openLibraryURL)
        #expect(merged.isbn13 == algorithmsISBN13)

        var guessed = BookMeta()
        guessed.authors = [ArticleReader.authorRef("Guessed Author")]
        guessed.authorsAreGuess = true
        let kept = BookReader.merge(fresh: BookMeta(), previous: guessed)
        #expect(kept.authors.map(\.name) == ["Guessed Author"])
        #expect(kept.authorsAreGuess)
    }
}

// MARK: - Item level + refresh

@Suite("Book items")
struct BookItemTests {

    @Test("Item kind line, typed panel, domain pill and search")
    @MainActor
    func itemLevel() {
        let meta = buildBook(algorithmsAmazonURL, ogTitle: algorithmsAmazonTitle, openLibrary: openLibraryAlgorithms()).meta
        let item = Item(title: "Introduction to Algorithms", sourceURL: algorithmsAmazonURL, domain: "amazon.com", kind: ItemKind.book.rawValue)
        item.setMetadata(meta)

        #expect(item.bookMeta() != nil)
        #expect(item.courseMeta() == nil)
        #expect(item.cardKindLine == "Thomas H. Cormen +3 · 2009")
        #expect(item.hasRichTypedPanel)
        #expect(item.displayLink == "amazon.com")
        for query in ["leiserson", "mit press", "computer algorithms", algorithmsISBN13, algorithmsISBN10] {
            #expect(ItemFilter.apply([item], searchText: query, selectedTagNames: []).count == 1, "\(query)")
        }

        // A redirected book shows its canonical host.
        let redirected = Item(title: "Atomic Habits", sourceURL: "https://amzn.com/dp/0735211299", domain: "amzn.com", kind: ItemKind.book.rawValue)
        var redirectedMeta = BookMeta()
        redirectedMeta.canonicalURL = "https://www.amazon.com/dp/0735211299"
        redirected.setMetadata(redirectedMeta)
        #expect(redirected.displayLink == "amazon.com")
    }

    @Test("extractBook without the Open Library lookup reads the page only")
    @MainActor
    func extractWithoutLookup() async {
        let page = PageFetchResult(
            html: goodreadsHTML,
            og: OGResult(title: "Atomic Habits by James Clear | Goodreads", ogType: "books.book"),
            statusCode: 200
        )
        let extraction = await CaptureService.extractBook(
            sourceURL: URL(string: goodreadsURL)!, page: page, lookUpOpenLibrary: false
        )
        #expect(extraction.title == "Atomic Habits")
        #expect(extraction.meta.openLibraryURL == nil)
        #expect(extraction.meta.isbn13 == "9780735211292")
    }

    @Test("Refresh flips a link to book; product and other curated kinds never flip")
    @MainActor
    func refresh() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)

        let link = Item(title: "Atomic Habits", sourceURL: goodreadsURL, kind: ItemKind.link.rawValue)
        let product = Item(title: "Algorithms", sourceURL: algorithmsAmazonURL, kind: ItemKind.product.rawValue)
        let website = Item(title: "Goodreads", sourceURL: goodreadsURL, kind: ItemKind.website.rawValue)
        let unrelated = Item(title: "Blog", sourceURL: "https://example.com/blog/post", kind: ItemKind.link.rawValue)
        for item in [link, product, website, unrelated] { context.insert(item) }
        try context.save()

        // No og:image / JSON-LD image → no cover download during the test.
        let page = PageFetchResult(
            html: goodreadsHTML,
            og: OGResult(title: "Atomic Habits by James Clear | Goodreads", ogType: "books.book"),
            statusCode: 200
        )
        let url = URL(string: goodreadsURL)!
        #expect(await EnrichmentService.refreshBookIfClassified(
            item: link, context: context, url: url, page: page, lookUpOpenLibrary: false
        ))
        #expect(link.kind == ItemKind.book.rawValue)
        #expect(link.bookMeta()?.authors.first?.name == "James Clear")
        #expect(link.bookMeta()?.goodreadsURL == goodreadsURL)

        let amazonPage = PageFetchResult(html: "", og: OGResult(title: algorithmsAmazonTitle), statusCode: 200)
        #expect(await EnrichmentService.refreshBookIfClassified(
            item: product, context: context, url: URL(string: algorithmsAmazonURL)!, page: amazonPage,
            lookUpOpenLibrary: false
        ) == false)
        #expect(product.kind == ItemKind.product.rawValue)

        #expect(await EnrichmentService.refreshBookIfClassified(
            item: website, context: context, url: url, page: page, lookUpOpenLibrary: false
        ) == false)
        #expect(website.kind == ItemKind.website.rawValue)

        let blogPage = PageFetchResult(html: "<html></html>", og: OGResult(title: "A post"), statusCode: 200)
        #expect(await EnrichmentService.refreshBookIfClassified(
            item: unrelated, context: context, url: URL(string: "https://example.com/blog/post")!, page: blogPage,
            lookUpOpenLibrary: false
        ) == false)
        #expect(unrelated.kind == ItemKind.link.rawValue)

        // A refetch that reads less keeps what the first read stored.
        let wall = PageFetchResult(html: "<html></html>", og: OGResult(title: "Robot check"), statusCode: 200)
        #expect(await EnrichmentService.refreshBookIfClassified(
            item: link, context: context, url: url, page: wall, lookUpOpenLibrary: false
        ))
        #expect(link.bookMeta()?.authors.first?.name == "James Clear")
        #expect(link.bookMeta()?.pages == 320)
    }

    @Test("Guess job: Mock / rule-based give nothing — the book keeps no authors")
    @MainActor
    func guessJob() async {
        let item = Item(title: "Some Book", sourceURL: "https://example.com/book", kind: ItemKind.book.rawValue)
        item.setMetadata(BookMeta())
        item.extractedText = "Some Book. By Jane Writer. Published 2020."

        await EnrichmentService.applyBookGuessIfNeeded(item: item, enricher: MockEnricher())
        #expect(item.bookMeta()?.authors.isEmpty == true)
        await EnrichmentService.applyBookGuessIfNeeded(item: item, enricher: RuleBasedFallbackEnricher())
        #expect(item.bookMeta()?.authors.isEmpty == true)
        #expect(item.bookMeta()?.authorsAreGuess == false)
    }
}
