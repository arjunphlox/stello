/**
 * Article reader: Article-family JSON-LD, meta tags, the URL path date, reading time.
 * Port of ArticleReader.swift. No extra network.
 */
import { jsonLDTypedNodes, nodeTypes, metaTagAttributes, parseISODate, appleDate, toURL, bareHost, pathParts } from './html.js';
import { isArticleType, urlPathDate } from './classifier.js';
import { string, brandName } from './product.js';
import { clean } from './tool.js';
import { makerRef } from './resource.js';

export const WORDS_PER_MINUTE = 230;
export const MAX_TECH_STACK = 5;

export function pageTags(html) {
  const t = { siteName: null, author: null, articleAuthor: null, publishedTime: null, twitterLabel1: null, twitterData1: null };
  if (!html) return t;
  for (const a of metaTagAttributes(html)) {
    const content = clean(a.content);
    if (!content) continue;
    switch ((a.property ?? a.name ?? '').toLowerCase()) {
      case 'og:site_name': t.siteName ??= content; break;
      case 'author': t.author ??= content; break;
      case 'article:author': t.articleAuthor ??= content; break;
      case 'article:published_time': t.publishedTime ??= content; break;
      case 'twitter:label1': t.twitterLabel1 ??= content; break;
      case 'twitter:data1': t.twitterData1 ??= content; break;
      default: break;
    }
  }
  return t;
}

export function articleNode(html) {
  if (!html) return null;
  const nodes = jsonLDTypedNodes(html);
  const a = nodes.find((n) => nodeTypes(n.dict).some(isArticleType));
  if (a) return a.dict;
  return nodes.find((n) => n.dict.author != null || n.dict.datePublished != null || n.dict.publisher != null)?.dict ?? null;
}

export function authorRef(name) {
  return { name, kind: 'individual' };
}

export function looksLikeURL(value) {
  const l = String(value).toLowerCase();
  return l.startsWith('http://') || l.startsWith('https://') || l.startsWith('www.');
}

export function author(node, tags, base) {
  if (node) {
    const ref = makerRef(node.author, base);
    if (ref && !looksLikeURL(ref.name)) return { ...ref, kind: 'individual' };
  }
  for (const c of [tags.author, tags.articleAuthor]) {
    if (c && !looksLikeURL(c)) return authorRef(c);
  }
  if ((tags.twitterLabel1 || '').toLowerCase() === 'written by' && tags.twitterData1 && !looksLikeURL(tags.twitterData1)) {
    return authorRef(tags.twitterData1);
  }
  return null;
}

export function publication(node, tags, url) {
  if (tags.siteName) return tags.siteName;
  if (node) {
    const name = brandName(node.publisher);
    if (name) return name;
  }
  return bareHost(url);
}

/** ISO 8601 (zone optional — none reads as UTC), a bare date, or a longer string's date part. */
export function parseDate(raw) {
  const s = clean(raw);
  if (!s) return null;
  const d = parseISODate(s);
  if (d) return d;
  if (s.length > 10) return parseISODate(s.slice(0, 10));
  return null;
}

/** The URL path date at 12:00 UTC (the 1st when there is no day). */
export function urlDate(url) {
  const p = urlPathDate(url);
  if (!p) return null;
  return new Date(Date.UTC(p.year, p.month - 1, p.day ?? 1, 12));
}

export function publishedAt(node, tags, url) {
  if (node) {
    const d = parseDate(string(node.datePublished));
    if (d) return d;
  }
  return parseDate(tags.publishedTime) ?? urlDate(url);
}

export function readingMinutes(text) {
  if (text == null) return null;
  const words = String(text).split(/\s+/).filter(Boolean).length;
  if (!words) return null;
  return Math.max(1, Math.ceil(words / WORDS_PER_MINUTE));
}

export function isTutorial(url, title) {
  if (bareHost(url) === 'tympanus.net') return true;
  const parts = pathParts(url, true);
  if (parts.includes('tutorial') || parts.includes('tutorials')) return true;
  const l = clean(title)?.toLowerCase();
  return !!l && (l.startsWith('how to') || l.startsWith('tutorial'));
}

export const KNOWN_TECH_STACK = [
  ['three.js', ['three.js', 'threejs'], false],
  ['GSAP', ['gsap'], false],
  ['React', ['React', 'React.js', 'ReactJS'], true],
  ['WebGL', ['webgl'], false],
  ['GLSL', ['glsl'], false],
  ['CSS', ['css'], false],
  ['Swift', ['Swift'], true],
  ['SwiftUI', ['swiftui'], false],
  ['Rive', ['Rive'], true],
  ['Framer', ['Framer'], true],
  ['Figma', ['figma'], false],
  ['Next.js', ['next.js', 'nextjs'], false],
  ['Svelte', ['svelte'], false],
  ['Vue', ['Vue', 'vue.js', 'vuejs'], true],
  ['Tailwind', ['tailwind', 'tailwindcss'], false],
];

export function ruleBasedTechStack(text) {
  const c = clean(text);
  if (!c) return [];
  const tokens = new Set(c.split(/[^\p{L}\p{N}.]+/u).map((t) => t.replace(/^\.+|\.+$/g, '')).filter(Boolean));
  const lower = new Set([...tokens].map((t) => t.toLowerCase()));
  const out = [];
  for (const [name, spellings, exactCase] of KNOWN_TECH_STACK) {
    const found = spellings.some((s) => (exactCase && !s.includes('.') ? tokens.has(s) : lower.has(s.toLowerCase())));
    if (!found) continue;
    out.push(name);
    if (out.length === MAX_TECH_STACK) break;
  }
  return out;
}

export function cleanTechStack(names = []) {
  const out = [];
  const seen = new Set();
  for (const raw of names) {
    const n = clean(raw);
    if (!n || [...n].length > 40) continue;
    if (!seen.has(n.toLowerCase())) { seen.add(n.toLowerCase()); out.push(n); }
    if (out.length === MAX_TECH_STACK) break;
  }
  return out;
}

/** Swift's ArticleMeta always encodes these. */
export function emptyArticleMeta() {
  return { summaryIsGuess: false, isTutorial: false, techStack: [] };
}

export function build({ sourceURL, finalURL = null, html = '', ogTitle = null, pageText = null }) {
  const source = toURL(sourceURL);
  const final = toURL(finalURL);
  const url = final ?? source;
  const meta = emptyArticleMeta();
  const tags = pageTags(html);
  const node = articleNode(html);
  setIf(meta, 'publication', publication(node, tags, source));
  setIf(meta, 'author', author(node, tags, url));
  const pub = publishedAt(node, tags, source) ?? (final ? urlDate(final) : null);
  setIf(meta, 'publishedAt', appleDate(pub));
  setIf(meta, 'readingMinutes', readingMinutes(pageText));
  meta.isTutorial = isTutorial(source, ogTitle) || (final ? isTutorial(final, null) : false);
  if (final && final.href !== source.href) meta.canonicalURL = final.href;
  return meta;
}

export function needsDigest(meta) {
  return meta.summary == null || (meta.isTutorial && !meta.techStack?.length);
}

export function applyDigest(facts, text, meta) {
  const summary = clean(facts?.summary);
  if (meta.summary == null && summary) {
    meta.summary = summary;
    meta.summaryIsGuess = true;
  }
  if (!meta.isTutorial || meta.techStack?.length) return;
  const fromModel = cleanTechStack(facts?.techStack ?? []);
  meta.techStack = fromModel.length ? fromModel : ruleBasedTechStack(text);
}

export function merge(fresh, previous) {
  if (!previous) return fresh;
  const m = { ...fresh };
  for (const k of ['publication', 'author', 'publishedAt', 'readingMinutes', 'canonicalURL']) {
    if (m[k] == null && previous[k] != null) m[k] = previous[k];
  }
  m.isTutorial = !!(m.isTutorial || previous.isTutorial);
  if (previous.summary != null) m.summary = previous.summary; else delete m.summary;
  m.summaryIsGuess = !!previous.summaryIsGuess;
  m.techStack = previous.techStack ?? [];
  return m;
}

function setIf(obj, key, value) {
  if (value != null) obj[key] = value;
}
