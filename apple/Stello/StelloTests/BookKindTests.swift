import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - Fixtures

/// Introduction to Algorithms, 3rd edition — ISBN-10 0262033844 ↔ ISBN-13 9780262033848.
/// Checked by hand: ISBN-10 0·10+2·9+6·8+2·7+0·6+3·5+3·4+8·3+4·2+4·1 = 143 = 11·13 (valid);
/// ISBN-13 body 978026203384 weighted 1,3,1,3… = 9+21+8+0+2+18+2+0+3+9+8+12 = 92 → check
/// digit (10 − 2) % 10 = 8.
private let algorithmsISBN10 = "0262033844"
private let algorithmsISBN13 = "9780262033848"
private let algorithmsAmazonURL = "https://www.amazon.com/Introduction-Algorithms-3rd-MIT-Press/dp/0262033844"

/// What a full read of the book gives (the Worker's book reader + Open Library).
private func algorithmsMeta() -> BookMeta {
    var meta = BookMeta()
    meta.title = "Introduction to Algorithms"
    meta.authors = ["Thomas H. Cormen", "Charles E. Leiserson", "Ronald L. Rivest", "Clifford Stein"]
        .map(ArticleReader.authorRef)
    meta.publisher = "MIT Press"
    meta.publishedYear = 2009
    meta.pages = 1292
    meta.isbn10 = algorithmsISBN10
    meta.isbn13 = algorithmsISBN13
    meta.subjects = ["Computer algorithms"]
    meta.openLibraryURL = "https://openlibrary.org/works/OL1918213W"
    return meta
}

// MARK: - Readers

@Suite("Book readers")
struct BookReaderTests {

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
        let previous = algorithmsMeta()
        var fresh = BookMeta()  // bot wall, lookup failed
        fresh.title = "Introduction to Algorithms"
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
        let item = Item(title: "Introduction to Algorithms", sourceURL: algorithmsAmazonURL, domain: "amazon.com", kind: ItemKind.book.rawValue)
        item.setMetadata(algorithmsMeta())

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
