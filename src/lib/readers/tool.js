/**
 * Tool reader: SoftwareApplication JSON-LD, og / meta tags, GitHub REST JSON, redirects.
 * Port of ToolReader.swift. The GitHub fetch lives in pipeline.js.
 */
import { jsonLDTypedNodes, nodeTypes, typeIs, metaTagAttributes, appleDate, parseISODate, isDict, bareHost, toURL, pathParts, urlPath } from './html.js';
import { githubRepo, isAppStoreAppURL, isMacAppStoreURL } from './classifier.js';
import { string, brandName } from './product.js';

export function clean(v) {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t || null;
}

export function makerRef(name) {
  return { name, kind: 'maker' };
}

/** Swift's ToolMeta always encodes these. */
export function emptyToolMeta() {
  return { platforms: [], platformsAreGuess: false, pricingIsGuess: false, topics: [] };
}

// ─── GitHub ─────────────────────────────────────────────────────────────

export function githubAPIURL(url) {
  const repo = githubRepo(url);
  return repo ? `https://api.github.com/repos/${repo.owner}/${repo.repo}` : null;
}

export function parseGitHubRepo(body, statusCode) {
  if (body == null) return null;
  if (statusCode != null && statusCode !== 200) return null;
  let repo = body;
  if (typeof body === 'string') {
    try { repo = JSON.parse(body); } catch { return null; }
  }
  if (!isDict(repo) || (repo.full_name == null && repo.name == null)) return null;
  return repo;
}

export function licenseLabel(license) {
  const id = clean(license?.spdx_id);
  if (id && id.toUpperCase() !== 'NOASSERTION') return id;
  return clean(license?.name);
}

function applyGitHub(repo, meta) {
  const full = clean(repo.full_name) ?? clean(repo.name);
  if (full) meta.name = full;
  const description = clean(repo.description);
  if (description) meta.tagline = description;
  const login = clean(repo.owner?.login);
  if (login) meta.maker = makerRef(login);
  setOrDelete(meta, 'stars', Number.isInteger(repo.stargazers_count) ? repo.stargazers_count : null);
  setOrDelete(meta, 'language', clean(repo.language));
  setOrDelete(meta, 'license', licenseLabel(repo.license));
  setOrDelete(meta, 'lastPushedAt', appleDate(parseISODate(repo.pushed_at)));
  meta.topics = (Array.isArray(repo.topics) ? repo.topics : []).map(clean).filter(Boolean);
  setOrDelete(meta, 'homepageURL', clean(repo.homepage));
  const html = clean(repo.html_url);
  if (html) meta.repoURL = html;
  if (meta.license != null) meta.pricing = 'open source';
}

export function cleanGitHubDescription(raw) {
  let text = clean(raw);
  if (!text) return null;
  const i = text.lastIndexOf('Contribute to ');
  if (i >= 0 && text.slice(i).endsWith('on GitHub.')) text = text.slice(0, i);
  text = text.trim();
  if (text.endsWith(' -')) text = text.slice(0, -2);
  return clean(text);
}

// ─── SoftwareApplication JSON-LD ────────────────────────────────────────

export function isSoftwareTypeName(t) {
  return typeIs(t, 'SoftwareApplication', 'WebApplication', 'MobileApplication');
}

function applyJSONLD(html, meta) {
  const node = jsonLDTypedNodes(html).find((n) => nodeTypes(n.dict).some(isSoftwareTypeName));
  if (!node) return [];
  const app = node.dict;
  if (meta.name == null) setIf(meta, 'name', string(app.name));
  if (!meta.platforms.length) meta.platforms = platforms(app.operatingSystem);
  if (meta.category == null) setIf(meta, 'category', cleanCategory(app.applicationCategory));
  const offers = offerPricing(app.offers);
  if (meta.pricing == null) setIf(meta, 'pricing', offers.pricing);
  if (meta.price == null && offers.price != null) {
    meta.price = offers.price;
    setIf(meta, 'currency', offers.currency);
  }
  if (meta.pricing == null && isTrue(app.isAccessibleForFree)) meta.pricing = 'free';
  if (meta.maker == null) {
    for (const key of ['author', 'creator', 'publisher']) {
      const name = brandName(app[key]);
      if (name) { meta.maker = makerRef(name); break; }
    }
  }
  return nodeTypes(app);
}

export function isTrue(v) {
  if (typeof v === 'boolean') return v;
  return string(v)?.toLowerCase() === 'true';
}

export function platforms(value) {
  const raw = typeof value === 'string' ? [value] : Array.isArray(value) ? value.filter((v) => typeof v === 'string') : [];
  const out = [];
  for (const entry of raw) {
    for (const piece of entry.split(/[,;]/)) {
      const name = normalizePlatform(piece);
      if (name && !out.includes(name)) out.push(name);
    }
  }
  return out;
}

export function normalizePlatform(raw) {
  const trimmed = clean(raw);
  if (!trimmed) return null;
  const lower = trimmed.toLowerCase();
  const words = lower.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  const has = (w) => words.includes(w);
  if (lower.includes('watchos') || has('watch')) return 'watchOS';
  if (lower.includes('visionos') || lower.includes('vision pro')) return 'visionOS';
  if (lower.includes('tvos') || lower.includes('apple tv')) return 'tvOS';
  if (lower.includes('ipados') || has('ipad')) return 'iPadOS';
  if (has('ios') || has('iphone')) return 'iOS';
  if (lower.includes('macos') || lower.includes('mac os') || has('osx') || lower.includes('os x') || has('mac') || has('macintosh')) return 'macOS';
  if (lower.startsWith('win') || has('windows')) return 'Windows';
  if (has('linux') || has('ubuntu') || has('debian') || has('fedora')) return 'Linux';
  if (has('android')) return 'Android';
  if (has('web') || has('browser') || has('online') || has('chrome') || has('firefox') || has('safari')) return 'Web';
  if (['any', 'all', 'cross-platform', 'multi-platform', 'n/a'].includes(lower)) return null;
  return [...trimmed].length <= 24 ? trimmed : null;
}

export function cleanCategory(value) {
  let raw = string(value);
  if (raw == null && Array.isArray(value)) raw = value.map(string).find(Boolean) ?? null;
  if (raw == null) return null;
  let text = raw;
  if (text.includes('/')) {
    const parts = text.split('/').filter(Boolean);
    if (parts.length) text = parts[parts.length - 1];
  }
  if (text.endsWith('Application') && text.length > 'Application'.length) text = text.slice(0, -'Application'.length);
  let spaced = '';
  let prev = null;
  for (const ch of text) {
    if (isUpper(ch) && prev != null && isLower(prev)) spaced += ' ';
    spaced += ch;
    prev = ch;
  }
  return clean(spaced);
}

const isUpper = (c) => c !== c.toLowerCase() && c === c.toUpperCase();
const isLower = (c) => c !== c.toUpperCase() && c === c.toLowerCase();

/** Offer | AggregateOffer | arrays: 0 → free; 0 + positive → freemium; positive → paid (lowest). */
export function offerPricing(value) {
  const prices = [];
  let currency = null;
  const record = (any) => {
    const raw = string(any);
    if (raw == null) return;
    const compact = raw.replace(/,/g, '');
    const first = compact.search(/\d/);
    if (first >= 0) {
      let kept = compact.slice(first).replace(/[^\d.]/g, '');
      if (kept.endsWith('.')) kept = kept.slice(0, -1);
      if (/^\d*\.?\d+$/.test(kept)) prices.push([Number(kept), kept]);
    } else if (raw.toLowerCase() === 'free') {
      prices.push([0, '0']);
    }
  };
  const visit = (v) => {
    if (Array.isArray(v)) { v.forEach(visit); return; }
    if (!isDict(v)) return;
    if (currency == null) currency = string(v.priceCurrency)?.toUpperCase() ?? null;
    record(v.price);
    record(v.lowPrice);
    record(v.highPrice);
    if (v.priceSpecification != null) {
      const specs = Array.isArray(v.priceSpecification) ? v.priceSpecification : [v.priceSpecification];
      for (const s of specs) {
        if (!isDict(s)) continue;
        record(s.price);
        if (currency == null) currency = string(s.priceCurrency)?.toUpperCase() ?? null;
      }
    }
    if (v.offers != null) visit(v.offers);
  };
  visit(value);
  if (!prices.length) return { pricing: null, price: null, currency: null };
  const hasFree = prices.some((p) => p[0] === 0);
  let paid = null;
  for (const p of prices) if (p[0] > 0 && (paid == null || p[0] < paid[0])) paid = p;
  if (hasFree && !paid) return { pricing: 'free', price: null, currency: null };
  if (hasFree && paid) return { pricing: 'freemium', price: paid[1], currency };
  if (paid) return { pricing: 'paid', price: paid[1], currency };
  return { pricing: null, price: null, currency: null };
}

// ─── og / meta ──────────────────────────────────────────────────────────

export function pageTags(html) {
  const tags = { siteName: null, metaDescription: null };
  for (const a of metaTagAttributes(html)) {
    const content = clean(a.content);
    if (!content) continue;
    if ((a.property ?? '').toLowerCase() === 'og:site_name' && tags.siteName == null) tags.siteName = content;
    if ((a.name ?? '').toLowerCase() === 'description' && tags.metaDescription == null) tags.metaDescription = content;
  }
  return tags;
}

const STORE_SITE_NAMES = new Set([
  'app store', 'mac app store', 'github', 'chrome web store', 'firefox add-ons',
  'microsoft edge add-ons', 'hugging face', 'google play', 'product hunt',
]);

const APP_STORE_LINK_RE = /href\s*=\s*["']((?:https?:)?\/\/(?:apps|itunes)\.apple\.com\/[^"'\s>]+)["']/gi;

export function firstAppStoreLink(html) {
  for (const m of (html || '').matchAll(APP_STORE_LINK_RE)) {
    let link = m[1].replace(/&amp;/g, '&');
    if (link.startsWith('//')) link = 'https:' + link;
    if (toURL(link) && isAppStoreAppURL(link)) return link;
  }
  return null;
}

// ─── Subtype ────────────────────────────────────────────────────────────

const HF_NON_MODEL = new Set([
  'spaces', 'datasets', 'docs', 'blog', 'models', 'papers', 'learn', 'pricing', 'posts',
  'collections', 'organizations', 'settings', 'login', 'join', 'tasks', 'enterprise',
]);

export function subtype(url, jsonLDTypes, meta, siteName) {
  if (githubRepo(url)) return 'library';
  if (isAppStoreAppURL(url)) return 'app';
  const host = bareHost(url) ?? '';
  const path = urlPath(url).toLowerCase();
  if (host === 'chromewebstore.google.com' || (host === 'chrome.google.com' && path.startsWith('/webstore'))
    || host === 'addons.mozilla.org' || (host === 'microsoftedge.microsoft.com' && path.startsWith('/addons'))
    || (siteName || '').toLowerCase() === 'chrome web store'
    || (meta.category || '').toLowerCase().includes('extension')) return 'extension';
  if (host === 'huggingface.co') {
    const parts = pathParts(url, true);
    if (parts.length >= 2 && !HF_NON_MODEL.has(parts[0])) return 'AI model';
  }
  if (jsonLDTypes.some((t) => typeIs(t, 'MobileApplication'))) return 'app';
  if (jsonLDTypes.some((t) => typeIs(t, 'WebApplication'))) return 'web app';
  const native = meta.platforms.filter((p) => p !== 'Web');
  if (native.length && !meta.platforms.includes('Web')) return 'app';
  return 'web app';
}

// ─── Build ──────────────────────────────────────────────────────────────

/** @returns {{ meta: object, title: string|null }} */
export function build({ sourceURL, finalURL = null, html = '', ogDescription = null, github = null }) {
  const source = toURL(sourceURL);
  const final = toURL(finalURL);
  const meta = emptyToolMeta();
  const tags = pageTags(html);
  const repoRef = githubRepo(source) ?? (final ? githubRepo(final) : null);

  if (github) applyGitHub(github, meta);
  if (repoRef) {
    if (meta.repoURL == null) meta.repoURL = `https://github.com/${repoRef.owner}/${repoRef.repo}`;
    if (meta.name == null) meta.name = `${repoRef.owner}/${repoRef.repo}`;
    if (meta.maker == null) meta.maker = makerRef(repoRef.owner);
  }
  const types = applyJSONLD(html, meta);
  if (meta.tagline == null) {
    const description = ogDescription ?? tags.metaDescription;
    setIf(meta, 'tagline', repoRef ? cleanGitHubDescription(description) : clean(description));
  }
  if (meta.maker == null && tags.siteName && !STORE_SITE_NAMES.has(tags.siteName.toLowerCase())) {
    meta.maker = makerRef(tags.siteName);
  }
  if (isAppStoreAppURL(source)) {
    meta.appStoreURL = source.href;
    if (!meta.platforms.length && isMacAppStoreURL(source)) meta.platforms = ['macOS'];
  } else {
    setIf(meta, 'appStoreURL', firstAppStoreLink(html));
  }
  if (final) {
    const landed = bareHost(final);
    if (landed && landed !== bareHost(source)) meta.canonicalURL = final.href;
  }
  meta.subtype = subtype(source, types, meta, tags.siteName);
  if (meta.pricing == null && meta.price != null) meta.pricing = 'paid';
  return { meta, title: meta.name ?? null };
}

// ─── Guess ──────────────────────────────────────────────────────────────

export function needsGuess(meta) {
  return (!meta.platforms?.length || meta.platformsAreGuess) || (meta.pricing == null || meta.pricingIsGuess);
}

export function ruleBasedFacts(text) {
  const lower = clean(text)?.toLowerCase();
  if (!lower) return null;
  const plats = [];
  const add = (n) => { if (!plats.includes(n)) plats.push(n); };
  if (lower.includes('download for mac') || lower.includes('download for macos') || lower.includes('mac app store')) add('macOS');
  if (lower.includes('download for windows')) add('Windows');
  if (lower.includes('download for linux')) add('Linux');
  if (lower.includes('download on the app store')) add('iOS');
  if (lower.includes('get it on google play')) add('Android');
  let pricing = null;
  const freePlan = lower.includes('free plan') || lower.includes('free tier') || lower.includes('free forever');
  const paid = lower.includes('per month') || lower.includes('/month') || lower.includes('/mo')
    || lower.includes('pro plan') || lower.includes('upgrade to pro');
  if (freePlan && paid) pricing = 'freemium';
  else if (lower.includes('100% free') || lower.includes('completely free')) pricing = 'free';
  if (!plats.length && pricing == null) return null;
  return { platforms: plats, pricing };
}

export function normalizePricing(raw) {
  const key = clean(raw)?.toLowerCase().replace(/-/g, ' ');
  switch (key) {
    case 'free': return 'free';
    case 'paid': case 'subscription': case 'one time purchase': return 'paid';
    case 'freemium': case 'free trial': case 'free with in app purchases': case 'free with paid plans': return 'freemium';
    case 'open source': case 'oss': return 'open source';
    default: return null;
  }
}

export function applyGuess(facts, meta) {
  const plats = [];
  for (const raw of facts.platforms || []) {
    const n = normalizePlatform(raw);
    if (n && !plats.includes(n)) plats.push(n);
  }
  if (plats.length && (!meta.platforms?.length || meta.platformsAreGuess)) {
    meta.platforms = plats;
    meta.platformsAreGuess = true;
  }
  const pricing = normalizePricing(facts.pricing);
  if (pricing && (meta.pricing == null || meta.pricingIsGuess)) {
    meta.pricing = pricing;
    meta.pricingIsGuess = true;
  }
}

/** A refetch that reads less never erases what capture read. */
export function merge(fresh, previous) {
  if (!previous) return fresh;
  const m = { ...fresh };
  for (const k of ['subtype', 'name', 'tagline', 'category', 'maker', 'repoURL', 'stars', 'language', 'license', 'lastPushedAt', 'homepageURL', 'appStoreURL', 'canonicalURL']) {
    if (m[k] == null && previous[k] != null) m[k] = previous[k];
  }
  if (!m.platforms?.length) { m.platforms = previous.platforms ?? []; m.platformsAreGuess = !!previous.platformsAreGuess; }
  if (m.pricing == null) { setIf(m, 'pricing', previous.pricing); m.pricingIsGuess = !!previous.pricingIsGuess; }
  if (m.price == null) { setIf(m, 'price', previous.price); setIf(m, 'currency', previous.currency); }
  if (!m.topics?.length) m.topics = previous.topics ?? [];
  return m;
}

function setIf(obj, key, value) {
  if (value != null) obj[key] = value;
}

function setOrDelete(obj, key, value) {
  if (value != null) obj[key] = value; else delete obj[key];
}
