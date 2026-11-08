// Port of StelloTests/BookKindTests.swift (kind-line, panel-line, SwiftData item, refresh
// and enricher-job tests stay with the Apple app).
import { test } from 'node:test';
import { eq, classify } from './readers-helpers.js';
import * as B from '../src/lib/readers/book.js';
import * as C from '../src/lib/readers/classifier.js';

const jsonLD = (body) => `<html><head><script type="application/ld+json">\n${body}\n</script></head><body></body></html>`;
const metas = (pairs) => `<html><head>\n${pairs.map(([k, c]) => `<meta ${/^(og|book|books):/.test(k) ? 'property' : 'name'}="${k}" content="${c}">`).join('\n')}\n</head><body></body></html>`;
const buildBook = (url, { finalURL = null, html = '', ogTitle = null, ogImageURL = null, openLibrary = null } = {}) =>
  B.build({ sourceURL: new URL(url), finalURL: finalURL ? new URL(finalURL) : null, html, ogTitle, ogImageURL, openLibrary });
const names = (refs) => (refs || []).map((r) => r.name);
const fallbacks = (x) => x.coverFallbackURLs.map(String);

const algorithmsISBN10 = '0262033844';
const algorithmsISBN13 = '9780262033848';
const algorithmsAmazonURL = 'https://www.amazon.com/Introduction-Algorithms-3rd-MIT-Press/dp/0262033844';
const algorithmsAmazonTitle = 'Introduction to Algorithms, 3rd Edition (The MIT Press): Cormen, Thomas H., Leiserson, Charles E., Rivest, Ronald L., Stein, Clifford: 9780262033848: Amazon.com: Books';
const goodreadsURL = 'https://www.goodreads.com/book/show/40121378-atomic-habits';
const goodreadsJSONLD = `{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits",
 "bookFormat":"Hardcover","numberOfPages":320,"inLanguage":"English","isbn":"9780735211292",
 "author":[{"@type":"Person","name":"James Clear","url":"https://www.goodreads.com/author/show/7327369.James_Clear"}],
 "aggregateRating":{"@type":"AggregateRating","ratingValue":4.37,"ratingCount":1102345}}`;
const goodreadsHTML = `<html><head>
<meta property="og:type" content="books.book">
<meta property="og:title" content="Atomic Habits: An Easy &amp; Proven Way to Build Good Habits &amp; Break Bad Ones">
<meta property="books:isbn" content="9780735211292">
<meta property="books:author" content="https://www.goodreads.com/author/show/7327369.James_Clear">
<meta property="books:page_count" content="320">
<script type="application/ld+json">
${goodreadsJSONLD}
</script>
</head><body></body></html>`;
const publisherJSONLD = `{"@context":"https://schema.org","@graph":[
 {"@type":"WebPage","name":"Atomic Habits by James Clear | Penguin Random House"},
 {"@type":"Book","name":"Atomic Habits",
  "author":"James Clear",
  "publisher":{"@type":"Organization","name":"Avery"},
  "datePublished":"2018-10-16","bookFormat":"https://schema.org/Hardcover","inLanguage":"en",
  "numberOfPages":"320","isbn":"978-0-7352-1129-2","genre":["Self-help","Psychology"],
  "image":{"@type":"ImageObject","url":"/covers/atomic-habits.jpg"}}
]}`;
const openLibraryAlgorithmsJSON = `{"ISBN:9780262033848": {
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
}}`;
const openLibraryAlgorithms = () => B.parseOpenLibrary(openLibraryAlgorithmsJSON, algorithmsISBN13);

// Classification

test('Book JSON-LD → book (top level and inside @graph)', () => {
  eq(classify('https://jamesclear.com/atomic-habits', { html: jsonLD('{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits"}') }).kind, 'book');
  eq(classify('https://www.penguinrandomhouse.com/books/543834/atomic-habits', { html: jsonLD(publisherJSONLD) }).kind, 'book');
  eq(C.hasBookNode(jsonLD(publisherJSONLD)), true);
});

test('og:type book / books.book and book:isbn / books:isbn metas → book', () => {
  eq(classify('https://example.com/a-book', { ogType: 'books.book' }).kind, 'book');
  eq(classify('https://example.com/a-book', { ogType: 'book' }).kind, 'book');
  eq(classify('https://example.com/a-book', { html: metas([['book:isbn', algorithmsISBN13]]) }).kind, 'book');
  eq(classify('https://example.com/a-book', { html: metas([['books:isbn', algorithmsISBN13]]) }).kind, 'book');
  eq(classify('https://example.com/a-book', { ogType: 'article' }).kind !== 'book', true);
});

test('Amazon /dp/ with a valid ISBN-10 → book', () => {
  for (const url of [algorithmsAmazonURL, 'https://www.amazon.com/dp/0262033844', 'https://www.amazon.co.uk/gp/product/0262033844/ref=x',
    'https://www.amazon.in/o/ASIN/0262033844', 'https://amzn.com/dp/0262033844', 'https://www.amazon.com/Some-Book/dp/080442957X',
    'https://www.amazon.com/Some-Book/dp/080442957x']) eq(classify(url).kind, 'book', url);
  eq(C.amazonBookISBN10(new URL('https://www.amazon.com/Some-Book/dp/080442957x')), '080442957X');
  eq(C.amazonBookISBN10(new URL('https://amazon.com.evil.net/dp/0262033844')), null);
});

test('Amazon /dp/B0… ASIN → not a book', () => {
  const url = 'https://www.amazon.com/Stuffcool-Mag-Dock/dp/B0CHX1W1XY';
  eq(classify(url).kind, 'product');
  eq(classify(url).productSource, 'page');
  eq(C.isBook(new URL(url), null, ''), false);
});

test('A 10-digit ASIN with an invalid ISBN checksum → not a book', () => {
  eq(C.isValidISBN10('0262033845'), false);
  eq(classify('https://www.amazon.com/dp/0262033845').kind, 'product');
});

test('Known single-book pages: Goodreads, Open Library, Google Books, StoryGraph, Bookshop.org', () => {
  for (const url of [goodreadsURL, 'https://openlibrary.org/works/OL17930368W/Atomic_Habits', 'https://openlibrary.org/books/OL26331930M',
    'https://books.google.com/books?id=XfFvDwAAQBAJ', 'https://books.google.co.in/books?id=XfFvDwAAQBAJ&printsec=frontcover',
    'https://books.google.com/books/edition/Atomic_Habits/XfFvDwAAQBAJ', 'https://app.thestorygraph.com/books/7b3f3c1e-2d5a-4b8e-9a43-6f1c2e8d9b10',
    'https://bookshop.org/p/books/atomic-habits-james-clear/12345678']) eq(classify(url).kind, 'book', url);
  for (const url of ['https://www.google.com/books/edition/Atomic_Habits/XfFvDwAAQBAJ', 'https://openlibrary.org/authors/OL1A',
    'https://openlibrary.org/works/not-an-id', 'https://books.google.com/', 'https://app.thestorygraph.com/browse',
    'https://bookshop.org/lists/best-books-of-2025']) eq(classify(url).kind !== 'book', true, url);
});

test('Goodreads /list/ and /shelf/ are not books; with the books label a list stays a website', () => {
  const list = 'https://www.goodreads.com/list/show/1.Best_Books_Ever';
  eq(classify(list).kind !== 'book', true);
  eq(classify('https://www.goodreads.com/shelf/show/design').kind !== 'book', true);
  eq(classify(list, { labels: ['books'] }).kind, 'link');
  const roundup = jsonLD('{"@context":"https://schema.org","@graph":[{"@type":"Book","name":"Atomic Habits"},{"@type":"Book","name":"Deep Work"}]}');
  eq(classify('https://example.com/best-books-2025', { html: roundup }).kind !== 'book', true);
  eq(classify('https://example.com/best-books-2025', { html: roundup, labels: ['books'] }).kind, 'link');
});

test('A wishlisted Amazon ISBN link is still a book', () => {
  eq(classify(algorithmsAmazonURL, { labels: ['wishlist'] }).kind, 'book');
  eq(classify(algorithmsAmazonURL, { labels: ['wishlist', 'books'] }).kind, 'book');
  eq(classify('https://www.amazon.com/dp/B0CHX1W1XY', { labels: ['wishlist'] }).kind, 'product');
});

test('Product JSON-LD with offers + Book JSON-LD → book; product rules skip the Book page', () => {
  const html = jsonLD(`{"@context":"https://schema.org","@graph":[
   {"@type":"Product","name":"Atomic Habits (Hardcover)","offers":{"@type":"Offer","price":"18.99","priceCurrency":"USD"}},
   {"@type":"Book","name":"Atomic Habits","isbn":"9780735211292"}]}`);
  const url = 'https://shop.example.com/atomic-habits';
  eq(classify(url, { html }).kind, 'book');
  eq(C.productSource(new URL(url), null, html, []), null);
});

test('Book runs after post and resource; a bare image file is never a book', () => {
  eq(classify('https://x.com/jamesclear/status/1234567890').kind, 'post');
  eq(classify('https://example.com/cover.jpg', { ogType: 'books.book' }).kind !== 'book', true);
  eq(classify('https://www.figma.com/community/file/123456/book-mockups', { html: jsonLD('{"@type":"Book","name":"Mockups"}') }).kind, 'resource');
});

test('isSingleBook also knows Google Books and Bookshop.org', () => {
  eq(C.isSingleBook(new URL('https://books.google.com/books?id=XfFvDwAAQBAJ'), ''), true);
  eq(C.isSingleBook(new URL('https://bookshop.org/p/books/atomic-habits/123'), ''), true);
  eq(C.isSingleBook(new URL('https://example.com/a'), metas([['books:isbn', algorithmsISBN13]])), true);
  eq(C.isSingleBook(new URL('https://www.goodreads.com/list/show/1.Best_Books_Ever'), ''), false);
});

// Readers

test('ISBN-10 ↔ ISBN-13 conversion and checksums', () => {
  eq(B.isbn13FromISBN10(algorithmsISBN10), algorithmsISBN13);
  eq(B.isbn10FromISBN13(algorithmsISBN13), algorithmsISBN10);
  eq(B.isbn13FromISBN10('0735211299'), '9780735211292');
  eq(B.isbn10FromISBN13('9780735211292'), '0735211299');
  eq(B.isbn13FromISBN10('080442957X'), '9780804429573');
  eq(B.isbn10FromISBN13('9780804429573'), '080442957X');
  eq(B.isbn13FromISBN10('0262033845'), null);
  eq(B.isbn10FromISBN13('9791032305690'), null);
  eq(C.isValidISBN13(algorithmsISBN13), true);
  eq(C.isValidISBN13('9780262033847'), false);
  eq(C.isValidISBN13('1234567890123'), false);
  eq(C.isValidISBN10('080442957X'), true);
  eq(C.isValidISBN10('B0CHX1W1XY'), false);
});

test('ISBN normalisation: hyphens, spaces, prefixes, lower-case x; invalid → nil', () => {
  eq(B.normalizeISBN('978-0-262-03384-8'), algorithmsISBN13);
  eq(B.normalizeISBN('ISBN-13: 978 0 262 03384 8'), algorithmsISBN13);
  eq(B.normalizeISBN('ISBN 0-262-03384-4'), algorithmsISBN10);
  eq(B.normalizeISBN('0-8044-2957-x'), '080442957X');
  eq(B.normalizeISBN('978-0-262-03384-9'), null);
  eq(B.normalizeISBN('not an isbn'), null);
  eq(B.normalizeISBN(null), null);
});

test('ISBNs from the Amazon ASIN, the books:isbn meta and JSON-LD; each completes the other', () => {
  const pick = (r) => ({ isbn10: r.isbn10 ?? null, isbn13: r.isbn13 ?? null });
  eq(pick(B.isbns({ sourceURL: new URL(algorithmsAmazonURL), html: '' })), { isbn10: algorithmsISBN10, isbn13: algorithmsISBN13 });
  eq(pick(B.isbns({ sourceURL: new URL('https://example.com/b'), html: metas([['books:isbn', '9780735211292']]) })), { isbn10: '0735211299', isbn13: '9780735211292' });
  eq(pick(B.isbns({ sourceURL: new URL('https://example.com/b'), html: jsonLD(publisherJSONLD) })), { isbn10: '0735211299', isbn13: '9780735211292' });
  const work = jsonLD(`{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits",
   "workExample":[{"@type":"Book","isbn":"978-0-7352-1129-2","bookFormat":"https://schema.org/EBook","datePublished":"2018"}]}`);
  const m = buildBook('https://example.com/b', { html: work }).meta;
  eq(m.isbn13, '9780735211292');
  eq(m.format, 'ebook');
  eq(m.publishedYear, 2018);
});

test('JSON-LD author: string, object, array of both; URL-only values and duplicates skipped', () => {
  const base = new URL('https://example.com/');
  eq(names(B.authorRefs('James Clear', base)), ['James Clear']);
  const o = B.authorRefs({ '@type': 'Person', name: 'James Clear', url: '/authors/james-clear' }, base);
  eq(names(o), ['James Clear']);
  eq(o[0]?.url, 'https://example.com/authors/james-clear');
  eq(o[0]?.kind, 'individual');
  const mixed = [{ '@type': 'Person', name: 'Thomas H. Cormen' }, 'Charles E. Leiserson', 'https://example.com/authors/rivest', { '@type': 'Person', name: 'thomas h. cormen' }];
  eq(names(B.authorRefs(mixed, base)), ['Thomas H. Cormen', 'Charles E. Leiserson']);
  eq(B.authorRefs(null, base), []);
});

test('bookFormat mapping', () => {
  const f = B.formatFromBookFormat;
  eq(f('https://schema.org/Hardcover'), 'hardcover');
  eq(f('http://schema.org/Paperback'), 'paperback');
  eq(f('https://schema.org/EBook'), 'ebook');
  eq(f('https://schema.org/AudiobookFormat'), 'audiobook');
  eq(f('Hardcover'), 'hardcover');
  eq(f('Mass Market Paperback'), 'paperback');
  eq(f('Kindle Edition'), 'ebook');
  eq(f('Audio CD'), 'audiobook');
  eq(f('https://schema.org/GraphicNovel'), null);
  eq(f(null), null);
  eq(buildBook('https://example.com/b', { html: jsonLD('{"@type":"Audiobook","name":"Atomic Habits"}') }).meta.format, 'audiobook');
});

test('Goodreads page: JSON-LD + books: metas (author profile URL skipped)', () => {
  const x = buildBook(goodreadsURL, { html: goodreadsHTML, ogTitle: 'Atomic Habits by James Clear | Goodreads' });
  const m = x.meta;
  eq(x.title, 'Atomic Habits');
  eq(names(m.authors), ['James Clear']);
  eq(m.authorsAreGuess, false);
  eq(m.format, 'hardcover');
  eq(m.pages, 320);
  eq(m.language, 'English');
  eq(m.isbn13, '9780735211292');
  eq(m.isbn10, '0735211299');
  eq(m.goodreadsURL, goodreadsURL);
  eq(m.amazonURL, null);
  eq(m.publishedYear, null);
  eq(m.canonicalURL, null);
});

test('Publisher page: @graph Book, publisher object, datePublished, genre, relative image', () => {
  const x = buildBook('https://www.penguinrandomhouse.com/books/543834/atomic-habits', { html: jsonLD(publisherJSONLD), ogTitle: 'Atomic Habits by James Clear | Penguin Random House' });
  const m = x.meta;
  eq(m.title, 'Atomic Habits');
  eq(names(m.authors), ['James Clear']);
  eq(m.publisher, 'Avery');
  eq(m.publishedYear, 2018);
  eq(m.pages, 320);
  eq(m.format, 'hardcover');
  eq(m.language, 'en');
  eq(m.subjects, ['Self-help', 'Psychology']);
  eq(m.coverURL, 'https://www.penguinrandomhouse.com/covers/atomic-habits.jpg');
  eq(fallbacks(x), ['https://www.penguinrandomhouse.com/covers/atomic-habits.jpg']);
});

test('book:author / book:release_date metas when there is no JSON-LD', () => {
  const html = metas([['og:type', 'book'], ['book:author', 'Ursula K. Le Guin'], ['book:release_date', '1969-03-01'], ['book:isbn', '9780441478125']]);
  const m = buildBook('https://example.com/left-hand-of-darkness', { html, ogTitle: 'The Left Hand of Darkness' }).meta;
  eq(m.title, 'The Left Hand of Darkness');
  eq(names(m.authors), ['Ursula K. Le Guin']);
  eq(m.publishedYear, 1969);
  eq(m.isbn13, '9780441478125');
});

test("Title cleaning: Amazon store parts and the 'Last, First' author part; ' | Site'; ' by <author>'", () => {
  eq(B.cleanTitle(algorithmsAmazonTitle, true, []), 'Introduction to Algorithms, 3rd Edition (The MIT Press)');
  eq(B.cleanTitle('Atomic Habits: An Easy & Proven Way to Build Good Habits & Break Bad Ones: Clear, James: 9780735211292: Amazon.com: Books', true, []),
    'Atomic Habits: An Easy & Proven Way to Build Good Habits & Break Bad Ones');
  eq(B.cleanTitle('Clean Code, A Handbook: Amazon.co.uk: Books', true, []), 'Clean Code, A Handbook');
  eq(B.cleanTitle('Atomic Habits by James Clear | Goodreads', false, ['James Clear']), 'Atomic Habits');
  eq(B.cleanTitle('Stand by Me', false, ['James Clear']), 'Stand by Me');
});

test('Open Library fixture: title, subtitle, authors, publisher, year, pages, subjects, cover, url', () => {
  const b = openLibraryAlgorithms();
  eq(b.title, 'Introduction to algorithms');
  eq(b.subtitle, 'third edition');
  eq(names(b.authors), ['Thomas H. Cormen', 'Charles E. Leiserson', 'Ronald L. Rivest', 'Clifford Stein']);
  eq(b.authors[0]?.url, 'https://openlibrary.org/authors/OL1802741A/Thomas_H._Cormen');
  eq(b.publisher, 'MIT Press');
  eq(b.publishedYear, 2009);
  eq(b.pages, 1292);
  eq(b.subjects, ['Computer programming', 'Computer algorithms']);
  eq(b.coverURL, 'https://covers.openlibrary.org/b/id/6276478-L.jpg');
  eq(b.url, 'https://openlibrary.org/books/OL23167449M/Introduction_to_algorithms');
  const medium = B.parseOpenLibrary('{"ISBN:0735211299":{"title":"Atomic Habits","publish_date":"Oct 16, 2018","cover":{"medium":"https://covers.openlibrary.org/b/id/1-M.jpg"}}}', '0735211299');
  eq(medium?.coverURL, 'https://covers.openlibrary.org/b/id/1-M.jpg');
  eq(medium?.publishedYear, 2018);
  eq(B.parseOpenLibrary('{}', '0262033844'), null);
  eq(B.parseOpenLibrary('<html>', '0262033844'), null);
  eq(B.openLibraryLookupURL('978-0-262-03384-8'), 'https://openlibrary.org/api/books?bibkeys=ISBN:9780262033848&format=json&jscmd=data');
});

test('Amazon page + Open Library: the page wins, Open Library fills the gaps', () => {
  const x = buildBook(algorithmsAmazonURL, { ogTitle: algorithmsAmazonTitle, openLibrary: openLibraryAlgorithms() });
  const m = x.meta;
  eq(m.title, 'Introduction to Algorithms, 3rd Edition (The MIT Press)');
  eq(m.subtitle, 'third edition');
  eq(m.authors.length, 4);
  eq(m.authorsAreGuess, false);
  eq(m.publisher, 'MIT Press');
  eq(m.publishedYear, 2009);
  eq(m.pages, 1292);
  eq(m.isbn10, algorithmsISBN10);
  eq(m.isbn13, algorithmsISBN13);
  eq(m.subjects, ['Computer programming', 'Computer algorithms']);
  eq(m.coverURL, 'https://covers.openlibrary.org/b/id/6276478-L.jpg');
  eq(m.openLibraryURL, 'https://openlibrary.org/books/OL23167449M/Introduction_to_algorithms');
  eq(m.amazonURL, 'https://www.amazon.com/dp/0262033844');
  eq(fallbacks(x), ['https://covers.openlibrary.org/b/id/6276478-L.jpg']);
  const page = jsonLD('{"@type":"Book","name":"Introduction to Algorithms","author":"T. Cormen","publisher":"The MIT Press","datePublished":"2009-07-31","numberOfPages":1312}');
  const mixed = buildBook(algorithmsAmazonURL, { html: page, ogTitle: algorithmsAmazonTitle, openLibrary: openLibraryAlgorithms() }).meta;
  eq(mixed.title, 'Introduction to Algorithms');
  eq(names(mixed.authors), ['T. Cormen']);
  eq(mixed.publisher, 'The MIT Press');
  eq(mixed.pages, 1312);
  eq(mixed.subtitle, 'third edition');
  const titled = { ...B.emptyBookMeta(), title: 'Introduction to Algorithms, Third Edition' };
  B.applyOpenLibrary(openLibraryAlgorithms(), titled);
  eq(titled.subtitle, null);
});

test('Canonical URL: set when the final URL differs, else nil', () => {
  eq(buildBook('https://amzn.com/dp/0262033844', { finalURL: 'https://www.amazon.com/dp/0262033844' }).meta.canonicalURL, 'https://www.amazon.com/dp/0262033844');
  eq(buildBook(goodreadsURL, { finalURL: goodreadsURL }).meta.canonicalURL, null);
});

test('Guess fills only empty authors (flagged) and an empty year; read values win', () => {
  const empty = B.emptyBookMeta();
  B.applyGuess({ authors: ['Thomas H. Cormen', 'https://example.com/x', ' ', 'Clifford Stein'], year: 2009 }, empty);
  eq(names(empty.authors), ['Thomas H. Cormen', 'Clifford Stein']);
  eq(empty.authorsAreGuess, true);
  eq(empty.publishedYear, 2009);
  eq(B.needsGuess(empty), true);
  const read = { ...B.emptyBookMeta(), authors: [{ name: 'James Clear', kind: 'individual' }], publishedYear: 2018 };
  eq(B.needsGuess(read), false);
  B.applyGuess({ authors: ['Someone Else'], year: 1999 }, read);
  eq(names(read.authors), ['James Clear']);
  eq(read.authorsAreGuess, false);
  eq(read.publishedYear, 2018);
  const future = B.emptyBookMeta();
  B.applyGuess({ authors: [], year: 3000 }, future);
  eq(future.publishedYear, null);
});

test('A refetch that reads less never erases what capture read; a guess survives', () => {
  const previous = buildBook(algorithmsAmazonURL, { ogTitle: algorithmsAmazonTitle, openLibrary: openLibraryAlgorithms() }).meta;
  const m = B.merge(buildBook(algorithmsAmazonURL).meta, previous);
  eq(m.title, previous.title);
  eq(m.authors.length, 4);
  eq(m.publisher, 'MIT Press');
  eq(m.pages, 1292);
  eq(m.openLibraryURL, previous.openLibraryURL);
  eq(m.isbn13, algorithmsISBN13);
  const guessed = { ...B.emptyBookMeta(), authors: [{ name: 'Guessed Author', kind: 'individual' }], authorsAreGuess: true };
  const kept = B.merge(B.emptyBookMeta(), guessed);
  eq(names(kept.authors), ['Guessed Author']);
  eq(kept.authorsAreGuess, true);
});
