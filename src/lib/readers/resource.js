/**
 * Resource reader: Figma Community / Framer Marketplace / CodePen pages and
 * `digital-resources`-labelled pages. CreativeWork / Product JSON-LD, og:title, redirects.
 * Port of ResourceReader.swift. No extra network.
 */
import { jsonLDTypedNodes, nodeTypes, typeIs, isDict, resolveURL, toURL, bareHost, wordTokens } from './html.js';
import { figmaCommunityResourceType, framerMarketplaceSegment, isCodePenPenURL } from './classifier.js';
import { string } from './product.js';
import { clean, makerRef as toolMaker, offerPricing, isTrue } from './tool.js';

export const RESOURCE_NODE_TYPES = [
  'CreativeWork', 'SoftwareApplication', 'WebApplication', 'SoftwareSourceCode',
  'Product', 'ProductGroup', 'IndividualProduct', 'DigitalDocument', 'VisualArtwork',
];

const isResourceNodeType = (t) => typeIs(t, ...RESOURCE_NODE_TYPES);

function applyJSONLD(html, base, meta) {
  const node = jsonLDTypedNodes(html).find((n) => nodeTypes(n.dict).some(isResourceNodeType))?.dict;
  if (!node) return;
  if (meta.name == null) setIf(meta, 'name', strippedName(string(node.name)));
  if (meta.maker == null) {
    for (const key of ['creator', 'brand', 'author']) {
      const ref = makerRef(node[key], base);
      if (ref) { meta.maker = ref; break; }
    }
  }
  const offers = offerPricing(node.offers);
  if (meta.pricing == null) {
    if (offers.pricing === 'free') meta.pricing = 'free';
    else if (offers.pricing === 'paid' || offers.pricing === 'freemium') {
      meta.pricing = 'paid';
      setIf(meta, 'price', offers.price);
      setIf(meta, 'currency', offers.currency);
    }
  }
  if (meta.pricing == null && isTrue(node.isAccessibleForFree)) meta.pricing = 'free';
  const counts = interactionCounts(node.interactionStatistic);
  if (meta.users == null) setIf(meta, 'users', counts.users);
  if (meta.likes == null) setIf(meta, 'likes', counts.likes);
}

export function makerRef(value, base) {
  if (typeof value === 'string') {
    const name = clean(value);
    return name ? toolMaker(name) : null;
  }
  if (isDict(value)) {
    const name = string(value.name) ?? string(value.alternateName);
    if (!name) return null;
    const ref = toolMaker(name);
    const raw = string(value.url) ?? string(value.sameAs);
    const resolved = raw ? resolveURL(raw, base?.href ?? base) : null;
    if (resolved) ref.url = resolved;
    return ref;
  }
  if (Array.isArray(value)) {
    for (const el of value) {
      const ref = makerRef(el, base);
      if (ref) return ref;
    }
  }
  return null;
}

const USERS_KEYS = new Set(['useaction', 'downloadaction', 'installaction', 'userdownloads']);
const LIKES_KEYS = new Set(['likeaction', 'userlikes']);

export function interactionCounts(value) {
  let users = null;
  let likes = null;
  const visit = (v) => {
    if (Array.isArray(v)) { v.forEach(visit); return; }
    if (!isDict(v)) return;
    const count = parseCount(v.userInteractionCount);
    if (count == null) return;
    const keys = [interactionKey(v.interactionType), interactionKey(v['@type'])].filter(Boolean);
    if (keys.some((k) => USERS_KEYS.has(k))) users = Math.max(users ?? 0, count);
    else if (keys.some((k) => LIKES_KEYS.has(k))) likes = Math.max(likes ?? 0, count);
  };
  visit(value);
  return { users, likes };
}

function interactionKey(value) {
  const s = string(value);
  if (s) {
    const parts = s.split('/').filter(Boolean);
    return (parts.length ? parts[parts.length - 1] : s).toLowerCase();
  }
  if (isDict(value)) return interactionKey(value['@type']) ?? interactionKey(value['@id']) ?? interactionKey(value.name);
  if (Array.isArray(value)) {
    for (const el of value) {
      const k = interactionKey(el);
      if (k) return k;
    }
  }
  return null;
}

/** 12400 / "12,400" / "12.4k" / "1.2M" → integer; null otherwise or negative. */
export function parseCount(value) {
  if (typeof value === 'number') return Number.isFinite(value) && value >= 0 ? Math.round(value) : null;
  const raw = string(value);
  if (raw == null) return null;
  let text = raw.toLowerCase().replace(/,/g, '').replace(/ /g, '');
  let mult = 1;
  if (text.endsWith('k')) { mult = 1000; text = text.slice(0, -1); }
  else if (text.endsWith('m')) { mult = 1000000; text = text.slice(0, -1); }
  if (!/^[+]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/.test(text)) return null;
  const n = Number(text);
  return n >= 0 ? Math.round(n * mult) : null;
}

const FIXED_NAME_SUFFIXES = [
  ' | figma community', ' | figma', ' - figma community', ' - figma',
  ' | framer marketplace', ' - framer marketplace', ' — framer marketplace', ' – framer marketplace',
  ' | codepen', ' - codepen', ' on codepen',
];

export function strippedName(raw) {
  let text = clean(raw);
  if (!text) return null;
  let changed = true;
  while (changed) {
    changed = false;
    const lower = text.toLowerCase();
    for (const suffix of FIXED_NAME_SUFFIXES) {
      if (lower.endsWith(suffix) && lower.length > suffix.length) {
        text = text.slice(0, text.length - suffix.length).trim();
        changed = true;
        break;
      }
    }
    if (!changed && text.toLowerCase().endsWith(' for framer')) {
      const cut = Math.max(...[' — ', ' – ', ' - ', ' | '].map((s) => text.lastIndexOf(s)));
      if (cut > 0) {
        text = text.slice(0, cut).trim();
        changed = true;
      }
    }
  }
  for (const prefix of ['CodePen - ', 'CodePen — ']) {
    if (text.startsWith(prefix) && text.length > prefix.length) text = text.slice(prefix.length);
  }
  return clean(text);
}

export function titleSaysFree(title) {
  return !!title && wordTokens(title).includes('free');
}

export function pathSubtype(url) {
  const fig = figmaCommunityResourceType(url);
  if (fig) return fig;
  const seg = framerMarketplaceSegment(url);
  if (seg) {
    switch (seg) {
      case 'templates': case 'template': return 'template';
      case 'plugins': case 'plugin': return 'plugin';
      case 'components': case 'component': return 'component';
      default: return null;
    }
  }
  if (isCodePenPenURL(url)) return 'pen';
  return null;
}

export function titleSubtype(title) {
  if (title == null) return null;
  const lower = title.toLowerCase();
  const words = wordTokens(lower);
  if (words.includes('mockup') || words.includes('mockups')) return 'mockup';
  if (words.includes('icons') || words.includes('iconset') || lower.includes('icon set') || lower.includes('icon pack')) return 'icon set';
  if (lower.includes('ui kit') || lower.includes('ui-kit') || words.includes('uikit')) return 'file';
  return null;
}

export function subtype(sourceURL, finalURL, title) {
  const fromPath = pathSubtype(sourceURL) ?? (finalURL ? pathSubtype(finalURL) : null);
  if (fromPath) return fromPath;
  const fromTitle = titleSubtype(title);
  if (fromTitle) return fromTitle;
  const u = toURL(sourceURL);
  if (u && u.pathname.replace(/^\/+|\/+$/g, '') === '' && !u.search) return 'library';
  return null;
}

export function worksWith(url, title) {
  switch (bareHost(url)) {
    case 'figma.com': return (title || '').toLowerCase().includes('figjam') ? ['FigJam'] : ['Figma'];
    case 'framer.com': return ['Framer'];
    case 'codepen.io': return ['CodePen'];
    default: return [];
  }
}

/** @returns {{ meta: object, title: string|null }} */
export function build({ sourceURL, finalURL = null, html = '', ogTitle = null }) {
  const source = toURL(sourceURL);
  const final = toURL(finalURL);
  const meta = { worksWith: [] };
  applyJSONLD(html, final ?? source, meta);
  if (meta.name == null) setIf(meta, 'name', strippedName(ogTitle));
  if (meta.pricing == null && titleSaysFree(ogTitle)) meta.pricing = 'free';
  if (final && final.href !== source.href) meta.canonicalURL = final.href;
  const title = ogTitle ?? meta.name ?? null;
  setIf(meta, 'subtype', subtype(source, final, title));
  meta.worksWith = worksWith(source, title);
  if (!meta.worksWith.length && final) meta.worksWith = worksWith(final, title);
  if (meta.subtype === 'reading list') meta.worksWith = [];
  return { meta, title: meta.name ?? null };
}

export function merge(fresh, previous) {
  if (!previous) return fresh;
  const m = { ...fresh };
  for (const k of ['subtype', 'name', 'maker', 'pricing', 'users', 'likes', 'canonicalURL']) {
    if (m[k] == null && previous[k] != null) m[k] = previous[k];
  }
  if (!m.worksWith?.length) m.worksWith = previous.worksWith ?? [];
  if (m.price == null) { setIf(m, 'price', previous.price); setIf(m, 'currency', previous.currency); }
  return m;
}

function setIf(obj, key, value) {
  if (value != null) obj[key] = value;
}
