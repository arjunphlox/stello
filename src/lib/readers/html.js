/**
 * Shared HTML / URL helpers for the page readers.
 *
 * Port of the parsing helpers in the Mac app's CaptureService.swift and the private
 * helpers of PageClassifier.swift. The Worker is the single copy of the readers; the
 * Apple apps send it the HTML they fetched and get the kind + metadata back.
 *
 * Pure functions, no network.
 */

// ─── Attribute / meta parsing ───────────────────────────────────────────

const META_TAG_RE = /<meta\s+([^>]*)>/gi;
const ATTR_RE = /([\w:.-]+)\s*=\s*(?:"([^"]*?)"|'([^']*?)'|([^\s>]+))/gi;

/** `key="v" key2='v' key3=v` → lowercase-keyed object (last one wins). */
export function parseAttributes(attrsStr) {
  const attrs = {};
  for (const m of String(attrsStr || '').matchAll(ATTR_RE)) {
    attrs[m[1].toLowerCase()] = m[2] ?? m[3] ?? m[4] ?? '';
  }
  return attrs;
}

/** Every `<meta …>` tag in the page as an attribute object (last page cached). */
let metaCache = { html: null, value: [] };
export function metaTagAttributes(html) {
  if (!html) return [];
  if (metaCache.html === html) return metaCache.value;
  const out = [];
  for (const m of html.matchAll(META_TAG_RE)) out.push(parseAttributes(m[1]));
  metaCache = { html, value: out };
  return out;
}

/** Content of the first non-empty `<meta property|name=key>` (key lowercase). */
export function metaContent(html, key) {
  for (const attrs of metaTagAttributes(html)) {
    const name = (attrs.property ?? attrs.name ?? '').toLowerCase();
    if (name === key) {
      const c = (attrs.content ?? '').trim();
      if (c) return c;
    }
  }
  return null;
}

/** og:title / og:description / og:image / og:type, order-independent (CaptureService.parseOG). */
export function parseOG(html, baseURL) {
  const r = { title: null, description: null, imageURL: null, ogType: null };
  for (const a of metaTagAttributes(html)) {
    const property = a.property ?? '';
    const name = a.name ?? '';
    const content = a.content ?? '';
    switch (property) {
      case 'og:title': if (r.title == null) r.title = content; break;
      case 'og:description': if (r.description == null) r.description = content; break;
      case 'og:image': if (r.imageURL == null) r.imageURL = resolveURL(content, baseURL); break;
      case 'og:type': if (r.ogType == null) r.ogType = content; break;
      case 'twitter:image': if (r.imageURL == null) r.imageURL = resolveURL(content, baseURL); break;
      default: break;
    }
    switch (name) {
      case 'description': if (r.description == null) r.description = content; break;
      case 'twitter:image': if (r.imageURL == null) r.imageURL = resolveURL(content, baseURL); break;
      default: break;
    }
  }
  if (r.title == null) {
    const m = /<title[^>]*>([^<]+)<\/title>/i.exec(html || '');
    if (m) r.title = m[1].trim();
  }
  return r;
}

// ─── Text ───────────────────────────────────────────────────────────────

const BASIC_ENTITIES = [
  ['&nbsp;', ' '], ['&amp;', '&'], ['&lt;', '<'], ['&gt;', '>'],
  ['&quot;', '"'], ['&#39;', "'"], ['&apos;', "'"],
  ['&mdash;', '—'], ['&ndash;', '–'],
  ['&rsquo;', '’'], ['&lsquo;', '‘'], ['&rdquo;', '”'], ['&ldquo;', '“'],
];

const ENTITY_MAP = Object.fromEntries(BASIC_ENTITIES);
const LATER_ENTITIES_RE = /&(?:lt|gt|quot|#39|apos|mdash|ndash|rsquo|lsquo|rdquo|ldquo);/g;

/**
 * Same result as replacing each entity in table order (so `&amp;lt;` → `<` but
 * `&amp;nbsp;` → `&nbsp;`, as in Swift), in three passes instead of thirteen.
 */
export function decodeBasicEntities(s) {
  let out = String(s ?? '');
  if (!out.includes('&')) return out;
  out = out.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
  return out.replace(LATER_ENTITIES_RE, (e) => ENTITY_MAP[e]);
}

/**
 * Readability-lite plain text (CaptureService.extractText). `limit: null` returns all of it.
 */
export function extractText(html, limit = 4000) {
  if (!html) return null;
  const body = html.search(/<body/i);
  const page = body >= 0 ? html.slice(body) : html;
  // The page's own prose lives in <article>, else <main>: reading only that keeps site
  // menus, sign-in prompts and sidebars ("You must be signed in to star a repository")
  // out of the text the snippets are picked from. A region with too little prose (a
  // card on a home page) falls back to the whole body.
  for (const region of [between(page, 'article'), between(page, 'main')]) {
    if (region == null) continue;
    const text = proseText(region);
    if (text && wordCount(text) >= MIN_REGION_WORDS) return limit == null ? text : clipChars(text, limit);
  }
  const text = proseText(page);
  if (!text) return null;
  return limit == null ? text : clipChars(text, limit);
}

/** A region under this many words isn't the page's prose. */
export const MIN_REGION_WORDS = 60;

/** Blocks whose content is never prose. An unterminated one (a page cut at 2 MB) runs to the end. */
const CODE_TAGS = ['script', 'style', 'noscript', 'svg', 'template'];
/** Page chrome: menus, headers and footers, sidebars, forms, buttons. Only whole elements go. */
const CHROME_TAGS = ['nav', 'header', 'footer', 'aside', 'form', 'button', 'dialog', 'select'];

/** From the first `<tag` to the last `</tag>` (spans nested and sibling elements). */
function between(html, tag) {
  const start = html.search(new RegExp(`<${tag}[\\s>]`, 'i'));
  if (start < 0) return null;
  const end = Math.max(html.lastIndexOf(`</${tag}>`), html.lastIndexOf(`</${tag.toUpperCase()}>`));
  return end > start ? html.slice(start, end) : null;
}

function wordCount(text) {
  let n = 1;
  for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 32) n++;
  return n;
}

function proseText(html) {
  let text = html;
  for (const tag of CODE_TAGS) {
    text = text.replace(new RegExp(`<${tag}[^>]*>[\\s\\S]*?(</${tag}>|$)`, 'gi'), ' ');
  }
  for (const tag of CHROME_TAGS) {
    text = text.replace(new RegExp(`<${tag}[\\s>][\\s\\S]*?</${tag}>`, 'gi'), ' ');
  }
  text = text.replace(/<!--[\s\S]*?-->/g, ' ');
  text = text.replace(/<[^>]+>/g, ' ');
  text = decodeBasicEntities(text);
  text = text.replace(/--[A-Za-z0-9_-]+\s*:[^;{}]{0,120};?/g, ' ');
  const words = text.trim().split(/\s+/).filter((w) =>
    (w.length <= 40 || [...w].length <= 40) && !CODE_CHARS_RE.test(w) && !w.startsWith('--'));
  return words.join(' ') || null;
}

/** The first `limit` characters (code points, as Swift's `prefix`). */
export function clipChars(text, limit) {
  if (text == null || text.length <= limit) return text;
  // 2×limit UTF-16 units always hold at least `limit` code points.
  return [...text.slice(0, limit * 2)].slice(0, limit).join('');
}

const CODE_CHARS_RE = /[{};=]/;

// ─── JSON-LD ────────────────────────────────────────────────────────────

const JSONLD_RE = /<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;

/**
 * Typed JSON-LD nodes: `{ dict, topLevel }`. `@graph` members are not top level
 * (Yoast puts every author Person there).
 */
let nodeCache = { html: null, value: [] };
export function jsonLDTypedNodes(html) {
  if (!html) return [];
  if (nodeCache.html === html) return nodeCache.value;
  const nodes = [];
  for (const m of html.matchAll(JSONLD_RE)) {
    const body = m[1].trim();
    let json;
    try { json = JSON.parse(body); } catch { continue; }
    collectTypedNodes(json, true, nodes);
  }
  nodeCache = { html, value: nodes };
  return nodes;
}

function collectTypedNodes(value, topLevel, out) {
  if (Array.isArray(value)) {
    for (const v of value) collectTypedNodes(v, topLevel, out);
  } else if (isDict(value)) {
    if (value['@type'] != null) out.push({ dict: value, topLevel });
    if (value['@graph'] != null) collectTypedNodes(value['@graph'], false, out);
  }
}

export function isDict(v) {
  return v != null && typeof v === 'object' && !Array.isArray(v);
}

/** `"https://schema.org/Product"` → `"Product"`. */
export function normalizeSchemaType(raw) {
  const parts = String(raw).split('/').filter(Boolean);
  const last = parts[parts.length - 1];
  return last || String(raw);
}

export function typeNames(value) {
  if (typeof value === 'string') return [normalizeSchemaType(value)];
  if (Array.isArray(value)) return value.filter((v) => typeof v === 'string').map(normalizeSchemaType);
  return [];
}

export function nodeTypes(dict) {
  return typeNames(dict?.['@type']);
}

export function typeIs(type, ...names) {
  const t = String(type).toLowerCase();
  return names.some((n) => n.toLowerCase() === t);
}

export function nodeHasType(dict, ...names) {
  return nodeTypes(dict).some((t) => typeIs(t, ...names));
}

/** Trimmed non-empty string, else null. */
export function str(v) {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t ? t : null;
}

export function nonBlank(v) {
  return str(v);
}

// ─── URL helpers ────────────────────────────────────────────────────────

export function toURL(u) {
  if (u instanceof URL) return u;
  try { return new URL(String(u)); } catch { return null; }
}

export function resolveURL(href, base) {
  if (href == null) return null;
  const s = String(href).trim();
  // An absolute link is kept as written (Swift's absoluteString adds no trailing slash).
  try { new URL(s); return s; } catch { /* relative */ }
  try { return new URL(s, base ? String(base) : undefined).href; } catch { return null; }
}

/** Lowercased host without a leading `www.`; null when there is none. */
export function bareHost(url) {
  const u = toURL(url);
  let host = (u?.hostname || '').toLowerCase();
  if (!host) return null;
  if (host.startsWith('www.')) host = host.slice(4);
  return host;
}

/** Percent-decoded path (Swift `URL.path`), never empty-string-safe. */
export function urlPath(url) {
  const u = toURL(url);
  if (!u) return '';
  try { return decodeURIComponent(u.pathname); } catch { return u.pathname; }
}

/** Non-empty path segments (Swift `url.path.split(separator: "/")`). */
export function pathParts(url, lower = false) {
  const parts = urlPath(url).split('/').filter(Boolean);
  return lower ? parts.map((p) => p.toLowerCase()) : parts;
}

/** Lowercased extension of the last path segment (Swift `pathExtension`). */
export function pathExtension(url) {
  const parts = pathParts(url);
  const last = parts[parts.length - 1] || '';
  const dot = last.lastIndexOf('.');
  return dot > 0 ? last.slice(dot + 1).toLowerCase() : '';
}

export function queryValue(url, name) {
  const u = toURL(url);
  return u ? u.searchParams.get(name) : null;
}

/** `brand.tld` / `brand.co.tld` / `sub.brand.tld` — the brand is the registrable label. */
export function hostIsBrand(host, brand) {
  const labels = String(host || '').split('.');
  const index = labels.lastIndexOf(brand);
  if (index < 0) return false;
  const suffix = labels.slice(index + 1);
  return suffix.length >= 1 && suffix.length <= 2 && suffix.every((l) => l.length >= 2 && l.length <= 3);
}

export function hostMatches(host, root) {
  return host === root || (host || '').endsWith('.' + root);
}

/** www-stripped host as shown on the card (CaptureService.domain). */
export function domainOf(url) {
  const u = toURL(url);
  let host = u?.hostname || '';
  if (host.startsWith('www.')) host = host.slice(4);
  return host || null;
}

/** Lowercase scheme + host, drop one trailing slash (CaptureService.normalizeURL). */
export function normalizeURL(url) {
  const u = toURL(url);
  if (!u) return String(url);
  const copy = new URL(u.href);
  if (copy.pathname.length > 1 && copy.pathname.endsWith('/')) copy.pathname = copy.pathname.slice(0, -1);
  return copy.href;
}

/** "Hello World!" → "hello-world" (ASCII letters, digits and dashes). */
export function slugify(text) {
  return String(text).toLowerCase().replace(/ /g, '-').replace(/[^a-z0-9-]/g, '');
}

/** Whole-word tokens (letters + digits, Unicode). */
export function wordTokens(text) {
  return String(text || '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}

export function isAllDigits(s) {
  return /^[0-9]+$/.test(s);
}

// ─── Dates ──────────────────────────────────────────────────────────────

/** Seconds between 1970 and 2001-01-01: Swift's JSONEncoder writes `Date` as seconds since 2001. */
export const APPLE_EPOCH = 978307200;

/** JS Date (or ms) → the number a Swift `Date` decodes from. */
export function appleDate(d) {
  if (d == null) return null;
  const ms = d instanceof Date ? d.getTime() : Number(d);
  if (!Number.isFinite(ms)) return null;
  return ms / 1000 - APPLE_EPOCH;
}

/**
 * ISO-8601 date / date-time strings the readers meet in JSON-LD and meta tags
 * (`2025-03-11`, `2025-03-11T10:00:00Z`, `…+05:30`, fractional seconds). Date-only
 * strings are midnight UTC, like Swift's ISO8601DateFormatter with `.withFullDate`.
 */
export function parseISODate(s) {
  const t = str(s);
  if (!t) return null;
  let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(t);
  if (m) return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$/.exec(t);
  if (!m) return null;
  const d = new Date(t.replace(' ', 'T') + (m[7] ? '' : 'Z'));
  return isNaN(d) ? null : d;
}
