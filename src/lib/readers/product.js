/**
 * Product reader: Shopify `.json`, Product JSON-LD, og price tags, Instagram og
 * caption / creator, bare-image filename. Port of ProductReader.swift.
 * The only network step (the Shopify `.json`) lives in pipeline.js.
 */
import { jsonLDTypedNodes, nodeHasType, metaTagAttributes, isDict, appleDate, resolveURL, toURL, bareHost } from './html.js';
import { shopifyHandle } from './classifier.js';

export const GALLERY_CAP = 8;

export function clean(v) {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t || null;
}

export function string(v) {
  if (typeof v === 'string') return clean(v);
  if (typeof v === 'number' && Number.isFinite(v)) return String(v);
  return null;
}

// ─── Shopify ────────────────────────────────────────────────────────────

export function shopifyJSONURL(url) {
  const u = toURL(url);
  const handle = shopifyHandle(u);
  if (!handle || !u?.host) return null;
  return `${u.protocol}//${u.host}/products/${encodeURIComponent(handle).replace(/%2F/g, '/')}.json`;
}

/** The `.json` envelope only — the `.js` endpoint prices in cents. */
export function parseShopifyProduct(json) {
  let data = json;
  if (typeof json === 'string') {
    try { data = JSON.parse(json); } catch { return null; }
  }
  const p = data?.product;
  return isDict(p) ? p : null;
}

function applyShopify(product, meta, images, base) {
  const title = clean(product.title);
  if (title) { meta.productName = title; delete meta.productNameIsGuess; }
  const vendor = clean(product.vendor);
  if (vendor) { meta.brand = brandRef(vendor); delete meta.brandIsGuess; }
  if (meta.category == null) setIf(meta, 'category', clean(product.product_type));

  const prices = (Array.isArray(product.variants) ? product.variants : [])
    .map((v) => normalizePrice(lenient(v?.price))).filter(Boolean);
  if (prices.length) {
    meta.price = prices[0];
    const nums = prices.map(Number);
    const lo = Math.min(...nums);
    const hi = Math.max(...nums);
    if (lo !== hi) {
      meta.priceMin = prices.find((p) => Number(p) === lo);
      meta.priceMax = prices.find((p) => Number(p) === hi);
    }
  }
  let srcs = (Array.isArray(product.images) ? product.images : []).map((i) => i?.src).filter((s) => typeof s === 'string');
  if (!srcs.length && typeof product.image?.src === 'string') srcs = [product.image.src];
  appendImages(srcs, base, images);
}

function lenient(v) {
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return String(v);
  return null;
}

// ─── JSON-LD ────────────────────────────────────────────────────────────

function applyJSONLD(html, meta, images, base) {
  const product = jsonLDTypedNodes(html).find((n) => nodeHasType(n.dict, 'Product', 'ProductGroup'))?.dict;
  if (!product) return;
  if (meta.productName == null) setIf(meta, 'productName', string(product.name));
  if (meta.brand == null) {
    const b = brandName(product.brand);
    if (b) meta.brand = brandRef(b);
  }
  if (meta.category == null) setIf(meta, 'category', string(product.category));

  let offers = offerSummary(product.offers);
  if (offers.price == null && offers.low == null && Array.isArray(product.hasVariant)) {
    for (const variant of product.hasVariant) {
      if (!isDict(variant)) continue;
      const s = offerSummary(variant.offers);
      if (s.price != null || s.low != null) { offers = s; break; }
    }
  }
  if (meta.price == null) {
    setIf(meta, 'price', offers.price ?? offers.low);
    if (offers.low != null && offers.high != null && offers.low !== offers.high) {
      meta.priceMin = offers.low;
      meta.priceMax = offers.high;
    }
  }
  if (offers.currency != null) meta.currency = offers.currency;
  if (meta.availability == null && offers.availability != null) meta.availability = availabilityLabel(offers.availability);
  if (!images.length) appendImages(imageStrings(product.image), base, images);
}

export function offerSummary(value) {
  const s = { price: null, low: null, high: null, currency: null, availability: null };
  const visit = (v) => {
    if (Array.isArray(v)) { v.forEach(visit); return; }
    if (!isDict(v)) return;
    if (s.currency == null) s.currency = string(v.priceCurrency)?.toUpperCase() ?? null;
    if (s.availability == null) s.availability = string(v.availability);
    const low = normalizePrice(string(v.lowPrice));
    if (low && s.low == null) s.low = low;
    const high = normalizePrice(string(v.highPrice));
    if (high && s.high == null) s.high = high;
    if (s.price == null) s.price = normalizePrice(string(v.price));
    if (v.priceSpecification != null) {
      const specs = Array.isArray(v.priceSpecification) ? v.priceSpecification : [v.priceSpecification];
      for (const sp of specs) {
        if (!isDict(sp)) continue;
        if (s.price == null) s.price = normalizePrice(string(sp.price));
        if (s.currency == null) s.currency = string(sp.priceCurrency)?.toUpperCase() ?? null;
      }
    }
    if (v.offers != null) visit(v.offers);
  };
  visit(value);
  return s;
}

export function brandName(value) {
  const s = string(value);
  if (s) return s;
  if (isDict(value)) return string(value.name);
  if (Array.isArray(value)) {
    for (const el of value) {
      const n = brandName(el);
      if (n) return n;
    }
  }
  return null;
}

export function imageStrings(value) {
  const s = string(value);
  if (s) return [s];
  if (isDict(value)) return [string(value.url) ?? string(value.contentUrl)].filter(Boolean);
  if (Array.isArray(value)) return value.flatMap(imageStrings);
  return [];
}

// ─── og tags ────────────────────────────────────────────────────────────

function applyOGTags(html, meta) {
  let amount = null, currency = null, siteName = null, availability = null, brand = null;
  for (const a of metaTagAttributes(html)) {
    const key = (a.property ?? a.name ?? '').toLowerCase();
    const content = clean(a.content);
    if (!content) continue;
    switch (key) {
      case 'product:price:amount': case 'og:price:amount': if (amount == null) amount = normalizePrice(content); break;
      case 'product:price:currency': case 'og:price:currency': if (currency == null) currency = content.toUpperCase(); break;
      case 'og:site_name': if (siteName == null) siteName = content; break;
      case 'product:availability': case 'og:availability': if (availability == null) availability = content; break;
      case 'product:brand': case 'og:brand': if (brand == null) brand = content; break;
      default: break;
    }
  }
  if (meta.price == null) setIf(meta, 'price', amount);
  if (meta.currency == null) setIf(meta, 'currency', currency);
  if (meta.shop == null) setIf(meta, 'shop', siteName);
  if (meta.availability == null && availability) meta.availability = availabilityLabel(availability);
  if (meta.brand == null && brand) meta.brand = brandRef(brand);
}

// ─── Instagram ──────────────────────────────────────────────────────────

const IG_DESC_RE = /^\s*[\d.,]+[KkMm]?\s+likes?(?:,\s*[\d.,]+[KkMm]?\s+comments?)?\s*-\s*([A-Za-z0-9._]+)\s+on\s+([^:]+?):\s*([\s\S]*)$/;
const IG_TITLE_RE = /^([\s\S]+?)\s+on\s+Instagram:\s*([\s\S]*)$/;
const HANDLE_IN_PARENS_RE = /\(@([A-Za-z0-9._]+)\)/;

export function parseInstagramOG(title, description) {
  const info = { handle: null, displayName: null, caption: null, postedAt: null };
  const d = description ? IG_DESC_RE.exec(description) : null;
  if (d) {
    info.handle = d[1];
    info.postedAt = instagramDate(d[2]);
    info.caption = cleanCaption(d[3]);
  }
  const t = title ? IG_TITLE_RE.exec(title) : null;
  if (t) {
    let name = t[1].trim();
    const hm = HANDLE_IN_PARENS_RE.exec(name);
    if (hm) {
      if (info.handle == null) info.handle = hm[1];
      name = (name.slice(0, hm.index) + name.slice(hm.index + hm[0].length)).trim();
    }
    info.displayName = name || null;
    if (info.caption == null) info.caption = cleanCaption(t[2]);
  }
  return info;
}

const MONTH_NAMES = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];

/** "March 3, 2025" → that day at 00:00 UTC. */
export function instagramDate(raw) {
  const m = /^([A-Za-z]+) (\d{1,2}), (\d{4})$/.exec(String(raw).trim());
  if (!m) return null;
  const month = MONTH_NAMES.indexOf(m[1].toLowerCase());
  if (month < 0) return null;
  const day = +m[2];
  const d = new Date(Date.UTC(+m[3], month, day));
  return d.getUTCDate() === day ? d : null;
}

export function cleanCaption(raw) {
  let s = String(raw).trim();
  if (s.endsWith('.') && (s.slice(0, -1).endsWith('"') || s.slice(0, -1).endsWith('”'))) s = s.slice(0, -1);
  const chars = [...s];
  if (chars.length >= 2 && (chars[0] === '"' || chars[0] === '“') && (chars.at(-1) === '"' || chars.at(-1) === '”')) {
    s = chars.slice(1, -1).join('');
  }
  s = s.trim();
  return s || null;
}

// ─── Bare image filename ────────────────────────────────────────────────

const GENERIC_FILENAME_WORDS = new Set(['img', 'image', 'images', 'photo', 'pic', 'dsc', 'screenshot', 'file', 'untitled', 'copy', 'final']);

export function titleFromImageFilename(url) {
  const u = toURL(url);
  const raw = u ? u.pathname.split('/').filter(Boolean).pop() || '' : String(url).split('/').pop();
  const noExt = raw.includes('.') ? raw.slice(0, raw.lastIndexOf('.')) : raw;
  let decoded;
  try { decoded = decodeURIComponent(noExt); } catch { decoded = noExt; }
  const tokens = decoded.split(/[-_ +.@]+/).filter(Boolean).map((t) => t.toLowerCase()).filter((t) => !isNoiseToken(t));
  while (tokens.length && /^\d+$/.test(tokens.at(-1))) tokens.pop();
  if (!tokens.length || !tokens.some((t) => !GENERIC_FILENAME_WORDS.has(t) && !/^\d+$/.test(t))) return null;
  const sentence = tokens.join(' ');
  return sentence.charAt(0).toUpperCase() + sentence.slice(1);
}

function isNoiseToken(t) {
  if (/^\d*x\d*$/.test(t) && t !== 'x') return true;
  if (t.length >= 8 && /\d/.test(t) && /^[0-9a-f]+$/i.test(t)) return true;
  return false;
}

// ─── Build ──────────────────────────────────────────────────────────────

/** @returns {{ meta: object, imageURLs: string[], title: string|null }} */
export function build({ sourceURL, finalURL = null, source, html = '', ogTitle = null, ogDescription = null, ogImageURL = null, shopify = null, now = new Date() }) {
  const landing = toURL(finalURL) ?? toURL(sourceURL);
  const meta = { source, canonicalURL: landing.href };
  let images = [];
  let title = null;

  switch (source) {
    case 'instagram': {
      const info = parseInstagramOG(ogTitle, ogDescription);
      setIf(meta, 'creatorHandle', info.handle);
      const name = info.displayName ?? (info.handle ? `@${info.handle}` : null);
      if (name) meta.creator = { name, kind: 'individual' };
      setIf(meta, 'caption', info.caption);
      meta.originalPostURL = toURL(sourceURL).href;
      if (ogImageURL) images = [String(ogImageURL)];
      title = info.caption ? shortTitle(info.caption) : null;
      break;
    }
    case 'image': {
      setIf(meta, 'shop', bareHost(landing));
      const name = titleFromImageFilename(sourceURL);
      if (name) { meta.productName = name; meta.productNameIsGuess = true; }
      images = [toURL(sourceURL).href];
      title = meta.productName ?? null;
      break;
    }
    default: {
      if (shopify) applyShopify(shopify, meta, images, landing);
      applyJSONLD(html, meta, images, landing);
      applyOGTags(html, meta);
      if (meta.productName == null) setIf(meta, 'productName', clean(ogTitle));
      if (meta.shop == null) setIf(meta, 'shop', bareHost(landing));
      meta.buyURL = landing.href;
      if (!images.length && ogImageURL) images = [String(ogImageURL)];
      title = meta.productName ?? null;
    }
  }

  if (meta.price != null) meta.pricedAt = appleDate(now);
  if (meta.priceMin != null && meta.priceMin === meta.priceMax) {
    delete meta.priceMin;
    delete meta.priceMax;
  }
  const seen = new Set();
  images = images.filter((u) => !seen.has(u) && seen.add(u));
  return { meta, imageURLs: images.slice(0, GALLERY_CAP), title };
}

// ─── Helpers ────────────────────────────────────────────────────────────

/** "Rs. 2,699.00" → "2699.00"; null without digits or when zero. */
export function normalizePrice(raw) {
  if (raw == null) return null;
  const s = String(raw);
  const first = s.search(/\d/);
  if (first < 0) return null;
  let kept = s.slice(first).replace(/[^\d.]/g, '');
  if (kept.endsWith('.')) kept = kept.slice(0, -1);
  if (!kept || !/^\d*\.?\d+$/.test(kept) || !(Number(kept) > 0)) return null;
  return kept;
}

export function availabilityLabel(raw) {
  const parts = String(raw).split('/').filter(Boolean);
  const last = parts.length ? parts[parts.length - 1] : String(raw);
  const key = last.toLowerCase().replace(/ /g, '').replace(/_/g, '');
  switch (key) {
    case 'instock': case 'in-stock': return 'in stock';
    case 'outofstock': case 'out-of-stock': case 'oos': return 'out of stock';
    case 'soldout': return 'sold out';
    case 'preorder': case 'pre-order': return 'pre-order';
    case 'presale': return 'pre-sale';
    case 'backorder': return 'backorder';
    case 'discontinued': return 'discontinued';
    case 'limitedavailability': return 'limited';
    case 'onlineonly': return 'online only';
    case 'instoreonly': return 'in store only';
    default: return last.toLowerCase();
  }
}

export function brandRef(name) {
  return { name, kind: 'brand' };
}

export function shortTitle(caption) {
  const firstLine = String(caption).split(/\r?\n|\r/).find((l) => l.length) ?? String(caption);
  const trimmed = firstLine.trim();
  const chars = [...trimmed];
  if (chars.length <= 80) return trimmed;
  return chars.slice(0, 79).join('').trim() + '…';
}

function appendImages(srcs, base, images) {
  for (const src of srcs) {
    let s = String(src).trim();
    if (s.startsWith('//')) s = 'https:' + s;
    const u = resolveURL(s, base.href ?? base);
    if (u) images.push(u);
  }
}

function setIf(obj, key, value) {
  if (value != null) obj[key] = value;
}
