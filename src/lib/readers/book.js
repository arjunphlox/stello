/**
 * Book reader: ISBNs, Book JSON-LD (+ first workExample edition), og / book meta tags,
 * Open Library's books API. Port of BookReader.swift. The Open Library fetch lives in
 * pipeline.js; page data wins, Open Library fills gaps.
 */
import { jsonLDTypedNodes, nodeTypes, typeIs, metaTagAttributes, isDict, resolveURL, toURL, bareHost, hostMatches } from './html.js';
import { isBookType, isValidISBN10, isValidISBN13, amazonBookISBN10, isKnownBookPageURL } from './classifier.js';
import { string, brandName } from './product.js';
import { clean } from './tool.js';
import { makerRef, parseCount } from './resource.js';
import { looksLikeURL, authorRef } from './article.js';
import { dicts, strings, names, cleanTopics, normalizedKey, typeNames } from './course.js';

export const FORMATS = ['hardcover', 'paperback', 'ebook', 'audiobook'];
export const MAX_SUBJECTS = 8;
export const MAX_GUESSED_AUTHORS = 4;

// ─── ISBN ───────────────────────────────────────────────────────────────

export function normalizeISBN(raw) {
  let text = clean(raw)?.toUpperCase();
  if (!text) return null;
  for (const prefix of ['ISBN-13', 'ISBN-10', 'ISBN13', 'ISBN10', 'ISBN']) {
    if (text.startsWith(prefix)) { text = text.slice(prefix.length); break; }
  }
  text = text.replace(/[\s\-:‐‑]/g, '');
  return isValidISBN10(text) || isValidISBN13(text) ? text : null;
}

export function isbn13FromISBN10(isbn10) {
  const v = String(isbn10).toUpperCase();
  if (!isValidISBN10(v)) return null;
  const body = '978' + v.slice(0, 9);
  let sum = 0;
  [...body].forEach((ch, i) => { sum += Number(ch) * (i % 2 === 0 ? 1 : 3); });
  return body + String((10 - (sum % 10)) % 10);
}

export function isbn10FromISBN13(isbn13) {
  if (!isValidISBN13(isbn13) || !isbn13.startsWith('978')) return null;
  const body = isbn13.slice(3, 12);
  let sum = 0;
  [...body].forEach((ch, i) => { sum += Number(ch) * (10 - i); });
  const check = (11 - (sum % 11)) % 11;
  return body + (check === 10 ? 'X' : String(check));
}

export function completed(ids) {
  const r = { ...ids };
  if (r.isbn13 == null && r.isbn10) r.isbn13 = isbn13FromISBN10(r.isbn10);
  if (r.isbn10 == null && r.isbn13) r.isbn10 = isbn10FromISBN13(r.isbn13);
  return r;
}

export function isbns({ sourceURL, finalURL = null, html = '', tags = null, node = undefined }) {
  const t = tags ?? pageTags(html);
  const n = node === undefined ? bookNode(html) : node;
  let candidates = [...t.isbns];
  if (n) {
    candidates = candidates.concat(strings(n.isbn));
    for (const ex of dicts(n.workExample)) candidates = candidates.concat(strings(ex.isbn));
  }
  const a = amazonBookISBN10(sourceURL);
  if (a) candidates.push(a);
  const b = finalURL ? amazonBookISBN10(finalURL) : null;
  if (b) candidates.push(b);
  const result = { isbn10: null, isbn13: null };
  for (const c of candidates) {
    const isbn = normalizeISBN(c);
    if (!isbn) continue;
    if (isbn.length === 10 && result.isbn10 == null) result.isbn10 = isbn;
    if (isbn.length === 13 && result.isbn13 == null) result.isbn13 = isbn;
  }
  if (result.isbn10 && result.isbn13 && isbn13FromISBN10(result.isbn10) !== result.isbn13) {
    result.isbn10 = isbn10FromISBN13(result.isbn13);
  }
  return completed(result);
}

// ─── Meta / JSON-LD ─────────────────────────────────────────────────────

export function pageTags(html) {
  const t = { siteName: null, ogImage: null, isbns: [], authors: [], releaseDate: null, pageCount: null };
  if (!html) return t;
  for (const a of metaTagAttributes(html)) {
    const content = clean(a.content);
    if (!content) continue;
    switch ((a.property ?? a.name ?? '').toLowerCase()) {
      case 'og:site_name': t.siteName ??= content; break;
      case 'og:image': t.ogImage ??= content; break;
      case 'book:isbn': case 'books:isbn': t.isbns.push(content); break;
      case 'book:author': case 'books:author': if (!looksLikeURL(content)) t.authors.push(content); break;
      case 'book:release_date': case 'books:release_date': t.releaseDate ??= content; break;
      case 'book:page_count': case 'books:page_count': t.pageCount ??= content; break;
      default: break;
    }
  }
  return t;
}

export function bookNode(html) {
  if (!html) return null;
  return jsonLDTypedNodes(html).find((n) => nodeTypes(n.dict).some(isBookType))?.dict ?? null;
}

export function authorRefs(value, base) {
  const refs = [];
  const seen = new Set();
  const add = (ref) => {
    if (looksLikeURL(ref.name) || seen.has(ref.name.toLowerCase())) return;
    seen.add(ref.name.toLowerCase());
    refs.push(ref);
  };
  const visit = (el) => {
    if (typeof el === 'string') {
      const n = clean(el);
      if (n) add(authorRef(n));
    } else if (isDict(el)) {
      const ref = makerRef(el, base);
      if (ref) add({ ...ref, kind: 'individual' });
    } else if (Array.isArray(el)) {
      el.forEach(visit);
    }
  };
  visit(value);
  return refs;
}

export function authorRefsFromNames(list) {
  return cleanAuthorNames(list, Infinity).map(authorRef);
}

export function formatFromBookFormat(value) {
  for (const raw of strings(value)) {
    let text = raw;
    if (looksLikeURL(text)) {
      const parts = text.split('/').filter(Boolean);
      if (parts.length) text = parts[parts.length - 1];
    }
    const l = text.toLowerCase().replace(/[- ]/g, '');
    if (l.includes('hardcover') || l.includes('hardback')) return 'hardcover';
    if (l.includes('paperback') || l.includes('softcover')) return 'paperback';
    if (l.includes('ebook') || l.includes('kindle') || l.includes('epub')) return 'ebook';
    if (l.includes('audiobook') || l.includes('audible') || l.includes('audiocd')) return 'audiobook';
  }
  return null;
}

export function imageURL(value, base) {
  let candidate = string(value);
  if (candidate == null && isDict(value)) candidate = string(value.url) ?? string(value.contentUrl);
  if (candidate == null && Array.isArray(value)) {
    for (const el of value) {
      const u = imageURL(el, base);
      if (u) return u;
    }
    return null;
  }
  if (candidate == null) return null;
  const resolved = toURL(resolveURL(candidate, base?.href ?? base));
  if (!resolved || !['http:', 'https:'].includes(resolved.protocol)) return null;
  return resolved.href;
}

const YEAR_RE = /(?<!\d)(1[4-9]\d{2}|20\d{2}|2100)(?!\d)/;

export function year(raw) {
  const t = clean(raw);
  const m = t ? YEAR_RE.exec(t) : null;
  return m ? plausibleYear(+m[1]) : null;
}

export function plausibleYear(y) {
  if (y == null) return null;
  const current = new Date().getUTCFullYear();
  return y >= 1450 && y <= current + 2 ? y : null;
}

export function cleanSubjects(values, max = MAX_SUBJECTS) {
  return cleanTopics(values, max);
}

export function cleanAuthorNames(values, max) {
  const out = [];
  const seen = new Set();
  for (const v of values) {
    if (out.length >= max) break;
    const n = clean(v);
    if (!n || [...n].length > 80 || looksLikeURL(n)) continue;
    if (!seen.has(n.toLowerCase())) { seen.add(n.toLowerCase()); out.push(n); }
  }
  return out;
}

// ─── Title ──────────────────────────────────────────────────────────────

export function cleanTitle(raw, isAmazon, authorNames) {
  let text = clean(raw);
  if (!text) return null;
  if (isAmazon) {
    let parts = text.split(': ').map(clean).filter(Boolean);
    parts = parts.filter((p) => {
      const l = p.toLowerCase();
      return !(l.includes('amazon') || l === 'books' || l === 'kindle store' || normalizeISBN(p) != null);
    });
    if (parts.length > 1 && parts[parts.length - 1].includes(',')) parts.pop();
    if (parts.length) text = parts.join(': ');
  }
  const bar = text.lastIndexOf(' | ');
  if (bar >= 0) {
    const head = text.slice(0, bar).trim();
    const tail = text.slice(bar + 3);
    if (head && [...tail].length <= 40) text = head;
  }
  const by = text.toLowerCase().lastIndexOf(' by ');
  if (by >= 0) {
    const head = text.slice(0, by).trim();
    const tail = normalizedKey(text.slice(by + 4));
    const keys = authorNames.map(normalizedKey).filter(Boolean);
    if (head && keys.some((k) => k === tail || tail.startsWith(k))) text = head;
  }
  return clean(text);
}

// ─── Open Library ───────────────────────────────────────────────────────

export function openLibraryLookupURL(isbn) {
  const n = normalizeISBN(isbn);
  return n ? `https://openlibrary.org/api/books?bibkeys=ISBN:${n}&format=json&jscmd=data` : null;
}

export function parseOpenLibrary(body, isbn) {
  let root = body;
  if (typeof body === 'string') {
    try { root = JSON.parse(body); } catch { return null; }
  }
  if (!isDict(root) || !Object.keys(root).length) return null;
  const entry = (isbn && isDict(root[`ISBN:${isbn}`])) ? root[`ISBN:${isbn}`] : Object.values(root).find(isDict);
  if (!entry) return null;
  const book = {
    title: string(entry.title),
    subtitle: string(entry.subtitle),
    authors: dicts(entry.authors).map((a) => {
      const name = string(a.name);
      if (!name) return null;
      const ref = authorRef(name);
      const url = string(a.url);
      if (url) ref.url = url;
      return ref;
    }).filter(Boolean),
    publisher: dicts(entry.publishers).map((p) => string(p.name)).find(Boolean) ?? strings(entry.publishers)[0] ?? null,
    publishedYear: year(string(entry.publish_date)),
    pages: null,
    subjects: cleanSubjects(names(entry.subjects)),
    coverURL: isDict(entry.cover) ? (string(entry.cover.large) ?? string(entry.cover.medium)) : null,
    url: string(entry.url),
  };
  const pages = parseCount(entry.number_of_pages);
  if (pages > 0) book.pages = pages;
  if (book.title == null && !book.authors.length && book.url == null) return null;
  return book;
}

export function applyOpenLibrary(book, meta) {
  if (meta.title == null) setIf(meta, 'title', clean(book.title));
  const subtitle = clean(book.subtitle);
  if (meta.subtitle == null && subtitle && !(meta.title || '').toLowerCase().includes(subtitle.toLowerCase())) meta.subtitle = subtitle;
  if (!meta.authors.length && book.authors?.length) {
    meta.authors = book.authors;
    meta.authorsAreGuess = false;
  }
  if (meta.publisher == null) setIf(meta, 'publisher', clean(book.publisher));
  if (meta.publishedYear == null) setIf(meta, 'publishedYear', book.publishedYear);
  if (meta.pages == null) setIf(meta, 'pages', book.pages);
  if (!meta.subjects.length) meta.subjects = cleanSubjects(book.subjects || []);
  if (meta.coverURL == null) setIf(meta, 'coverURL', book.coverURL);
  if (meta.openLibraryURL == null) setIf(meta, 'openLibraryURL', book.url);
}

export function isAmazonURL(url) {
  const host = bareHost(url);
  if (!host) return false;
  const labels = host.split('.');
  return labels.includes('amazon') || labels[0] === 'amzn';
}

/** Swift's BookMeta always encodes these. */
export function emptyBookMeta() {
  return { authors: [], subjects: [], authorsAreGuess: false };
}

/** @returns {{ meta: object, title: string|null, coverFallbackURLs: string[] }} */
export function build({ sourceURL, finalURL = null, html = '', ogTitle = null, ogImageURL = null, openLibrary = null }) {
  const source = toURL(sourceURL);
  const final = toURL(finalURL);
  const meta = emptyBookMeta();
  const base = final ?? source;
  const tags = pageTags(html);
  const node = bookNode(html);
  const edition = node ? dicts(node.workExample)[0] ?? null : null;

  const ids = isbns({ sourceURL: source, finalURL: final, tags, node });
  setIf(meta, 'isbn10', ids.isbn10);
  setIf(meta, 'isbn13', ids.isbn13);

  meta.authors = authorRefs(node?.author, base);
  if (!meta.authors.length) meta.authors = authorRefs(edition?.author, base);
  if (!meta.authors.length) meta.authors = authorRefsFromNames(tags.authors);

  const amazon = isAmazonURL(source) || (final ? isAmazonURL(final) : false);
  const authorNames = meta.authors.map((a) => a.name);
  setIf(meta, 'title', cleanTitle(string(node?.name), false, authorNames) ?? cleanTitle(ogTitle, amazon, authorNames));

  const value = (k) => node?.[k] ?? edition?.[k];
  setIf(meta, 'publisher', brandName(value('publisher')));
  setIf(meta, 'publishedYear', year(string(value('datePublished'))) ?? year(tags.releaseDate));
  const pages = parseCount(value('numberOfPages')) ?? parseCount(tags.pageCount);
  if (pages > 0) meta.pages = pages;
  setIf(meta, 'format', formatFromBookFormat(value('bookFormat')));
  if (meta.format == null && node && typeNames(node['@type']).some((t) => typeIs(t, 'Audiobook'))) meta.format = 'audiobook';
  setIf(meta, 'language', brandName(value('inLanguage')));
  if (node) meta.subjects = cleanSubjects([...names(node.genre), ...names(node.about)]);

  const pageImage = imageURL(node?.image, base);
  setIf(meta, 'coverURL', pageImage ?? (ogImageURL ? String(ogImageURL) : null) ?? imageURL(tags.ogImage, base));

  for (const url of [source, final].filter(Boolean)) {
    const host = bareHost(url);
    if (meta.goodreadsURL == null && host && hostMatches(host, 'goodreads.com') && isKnownBookPageURL(url)) meta.goodreadsURL = url.href;
    if (meta.openLibraryURL == null && host === 'openlibrary.org' && isKnownBookPageURL(url)) meta.openLibraryURL = url.href;
    const asin = isAmazonURL(url) ? amazonBookISBN10(url) : null;
    if (meta.amazonURL == null && asin && url.host) meta.amazonURL = `https://${url.host}/dp/${asin}`;
  }

  if (openLibrary) applyOpenLibrary(openLibrary, meta);
  if (final && final.href !== source.href) meta.canonicalURL = final.href;

  const fallbacks = [];
  const og = ogImageURL ? String(ogImageURL) : null;
  for (const c of [pageImage, openLibrary?.coverURL]) {
    const u = c ? toURL(c)?.href : null;
    if (!u || u === og || fallbacks.includes(u)) continue;
    fallbacks.push(u);
  }
  return { meta, title: meta.title ?? null, coverFallbackURLs: fallbacks };
}

// ─── Guess / merge ──────────────────────────────────────────────────────

export function needsGuess(meta) {
  return !meta.authors?.length || meta.authorsAreGuess;
}

export function applyGuess(facts, meta) {
  const authors = cleanAuthorNames(facts.authors || [], MAX_GUESSED_AUTHORS);
  if (authors.length && (!meta.authors?.length || meta.authorsAreGuess)) {
    meta.authors = authors.map(authorRef);
    meta.authorsAreGuess = true;
  }
  const y = plausibleYear(facts.year ?? null);
  if (meta.publishedYear == null && y) meta.publishedYear = y;
}

export function merge(fresh, previous) {
  if (!previous) return fresh;
  const m = { ...fresh };
  for (const k of ['title', 'subtitle', 'publisher', 'publishedYear', 'pages', 'isbn10', 'isbn13', 'language', 'format', 'coverURL', 'openLibraryURL', 'goodreadsURL', 'amazonURL', 'canonicalURL']) {
    if (m[k] == null && previous[k] != null) m[k] = previous[k];
  }
  if (!m.authors?.length) { m.authors = previous.authors ?? []; m.authorsAreGuess = !!previous.authorsAreGuess; }
  if (!m.subjects?.length) m.subjects = previous.subjects ?? [];
  return m;
}

function setIf(obj, key, value) {
  if (value != null) obj[key] = value;
}
