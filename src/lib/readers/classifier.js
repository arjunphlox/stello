/**
 * Deterministic page kind from the fetched HTML + URL. No AI.
 *
 * Line-for-line port of the Mac app's PageClassifier.swift (the Swift copy is retired
 * once the Apple apps call the Worker). Kind order: gone (status, set by the caller) →
 * post → resource → book → product → tool → course → article → individual / foundry →
 * link. Music runs after, in the reader pipeline, only when this returns `link`.
 */
import {
  jsonLDTypedNodes, nodeTypes, typeIs, nodeHasType, str, isDict, metaTagAttributes, metaContent,
  parseAttributes, resolveURL, toURL, bareHost, hostIsBrand, hostMatches, pathParts, pathExtension,
  queryValue, slugify, wordTokens, isAllDigits,
} from './html.js';

/**
 * @returns {{ kind: string, individualMeta?: object|null, productSource?: string|null, postPlatform?: string|null }}
 */
export function classify({ html = '', baseURL, domain = null, title = null, ogDescription = null, ogType = null, collectionLabels = [] }) {
  const url = toURL(baseURL);
  if (!url) return { kind: 'link', individualMeta: null };
  const nodes = jsonLDTypedNodes(html);

  const platform = postPlatform(url, collectionLabels);
  if (platform) return { kind: 'post', individualMeta: null, postPlatform: platform };
  if (isResourceNodes(url, ogType, nodes, html, collectionLabels)) return { kind: 'resource', individualMeta: null };
  if (isBookNodes(url, ogType, nodes, html)) return { kind: 'book', individualMeta: null };
  const source = productSourceNodes(url, ogType, nodes, html, collectionLabels);
  if (source) return { kind: 'product', individualMeta: null, productSource: source };
  if (isToolNodes(url, ogType, nodes, collectionLabels)) return { kind: 'tool', individualMeta: null };
  if (isCourseNodes(url, ogType, nodes, title, collectionLabels)) return { kind: 'course', individualMeta: null };
  if (isArticleNodes(url, ogType, nodes, html, collectionLabels)) return { kind: 'article', individualMeta: null };

  const individual = hasIndividualSignals(nodes, ogType);
  const foundry = hasFoundrySignals(nodes, domain, title);
  if (individual && foundry) return { kind: 'link', individualMeta: null };
  if (individual) {
    return { kind: 'individual', individualMeta: extractIndividualMeta(nodes, html, url, ogDescription) };
  }
  if (foundry) return { kind: 'foundry', individualMeta: null };
  return { kind: 'link', individualMeta: null };
}

// ─── Individual / foundry ───────────────────────────────────────────────

const FOUNDRY_STRONG = new Set(['foundry', 'typefoundry']);

function hasIndividualSignals(nodes, ogType) {
  if ((ogType || '').toLowerCase() === 'profile') return true;
  return primaryPerson(nodes) != null;
}

function hasFoundrySignals(nodes, domain, title) {
  const hasOrg = nodes.some((n) => nodeHasType(n.dict, 'Organization'));
  if (!hasOrg) return false;
  if (title && strongFoundryWordMatch(title)) return true;
  if (domain) {
    if (strongFoundryWordMatch(domain)) return true;
    if (domain.toLowerCase().split('.').includes('fonts')) return true;
  }
  return false;
}

function strongFoundryWordMatch(text) {
  return wordTokens(text).some((t) => FOUNDRY_STRONG.has(t));
}

function primaryPerson(nodes) {
  const top = nodes.find((n) => n.topLevel && nodeHasType(n.dict, 'Person'));
  if (top) return top.dict;
  for (const node of nodes) {
    for (const key of ['mainEntity', 'about']) {
      const ref = node.dict[key];
      if (ref == null) continue;
      if (isDict(ref)) {
        if (nodeHasType(ref, 'Person')) return ref;
        if (typeof ref['@id'] === 'string') {
          const resolved = personWithID(ref['@id'], nodes);
          if (resolved) return resolved;
        }
      } else if (typeof ref === 'string') {
        const resolved = personWithID(ref, nodes);
        if (resolved) return resolved;
      }
    }
  }
  return null;
}

function personWithID(id, nodes) {
  return nodes.find((n) => n.dict['@id'] === id && nodeHasType(n.dict, 'Person'))?.dict ?? null;
}

function extractIndividualMeta(nodes, html, baseURL, ogDescription) {
  const meta = {};
  const bio = (ogDescription || '').trim();
  if (bio) meta.bio = bio;
  const person = primaryPerson(nodes);
  if (person) {
    const role = str(person.jobTitle);
    if (role) meta.currentRole = role;
    const location = postalAddressString(person.address);
    if (location) meta.location = { name: location, slug: slugify(location), kind: 'place' };
  }
  applySocialLinks(html, baseURL, meta);
  return Object.keys(meta).length ? withIndividualDefaults(meta) : null;
}

/** Swift's IndividualMeta encodes its empty arrays; keep the JSON shape the same. */
function withIndividualDefaults(meta) {
  return { professions: [], traits: [], typefaces: [], typeFoundries: [], ...meta };
}

function postalAddressString(value) {
  const s = str(value);
  if (s) return s;
  if (!isDict(value)) return null;
  const parts = [str(value.addressLocality), str(value.addressRegion), str(value.addressCountry)].filter(Boolean);
  return parts.length ? parts.join(', ') : null;
}

// Social links: rel=me wins over body anchors; share / intent widgets are skipped.
const SOCIAL_SLOT = { x: 'xURL', instagram: 'instagramURL', linkedIn: 'linkedInURL', behance: 'behanceURL', bluesky: 'bluesky', mastodon: 'mastodon', threads: 'threads' };

function applySocialLinks(html, baseURL, meta) {
  const claimed = new Set();
  const links = anchorAndLinkTags(html);
  for (const relMePass of [true, false]) {
    for (const link of links) {
      if (link.isRelMe !== relMePass || !link.href) continue;
      const resolved = resolveURL(link.href, baseURL.href);
      const u = toURL(resolved);
      if (!u || isShareOrIntentLink(u)) continue;
      const platform = socialPlatform(u);
      if (!platform) continue;
      if (relMePass) claimed.add(platform);
      else if (claimed.has(platform)) continue;
      const slot = SOCIAL_SLOT[platform];
      if (meta[slot] == null) meta[slot] = u.href;
    }
  }
}

function isShareOrIntentLink(u) {
  const path = decodeURIComponentSafe(u.pathname).toLowerCase();
  return path.includes('/intent') || path.includes('/share');
}

function decodeURIComponentSafe(s) {
  try { return decodeURIComponent(s); } catch { return s; }
}

function socialPlatform(u) {
  let host = (u.hostname || '').toLowerCase();
  if (!host) return null;
  if (host.startsWith('www.')) host = host.slice(4);
  const m = (root) => hostMatches(host, root);
  if (m('x.com') || m('twitter.com')) return 'x';
  if (m('instagram.com')) return 'instagram';
  if (m('linkedin.com')) return 'linkedIn';
  if (m('behance.net')) return 'behance';
  if (m('bsky.app')) return 'bluesky';
  if (m('threads.net') || m('threads.com')) return 'threads';
  if (m('mastodon.social') || m('mastodon.online')) return 'mastodon';
  return null;
}

function anchorAndLinkTags(html) {
  const out = [];
  for (const re of [/<a\s+([^>]*)>/gi, /<link\s+([^>]*)>/gi]) {
    for (const m of (html || '').matchAll(re)) {
      const attrs = parseAttributes(m[1]);
      const rel = (attrs.rel || '').toLowerCase();
      out.push({ href: attrs.href ?? null, isRelMe: rel.split(/[\s,]+/).includes('me') });
    }
  }
  return out;
}

// ─── Music (host / og:type rules; extraction lives in music.js) ────────

export function musicPlatform(host) {
  const h = String(host || '').toLowerCase();
  const m = (root) => hostMatches(h, root);
  if (m('open.spotify.com')) return 'spotify';
  if (m('music.apple.com')) return 'apple-music';
  if (m('bandcamp.com')) return 'bandcamp';
  if (m('soundcloud.com')) return 'soundcloud';
  if (m('music.youtube.com')) return 'youtube-music';
  if (m('tidal.com')) return 'tidal';
  if (m('mixcloud.com')) return 'mixcloud';
  if (m('deezer.com')) return 'deezer';
  return null;
}

export function isPlainYouTubeHost(host) {
  const h = String(host || '').toLowerCase();
  return h === 'youtube.com' || (h.endsWith('.youtube.com') && h !== 'music.youtube.com') || h === 'youtu.be';
}

const MUSIC_OG_TYPES = new Set(['music.album', 'music.song', 'music.playlist', 'music.musician']);
export function isMusicOGType(ogType) {
  return ogType != null && MUSIC_OG_TYPES.has(String(ogType).toLowerCase());
}

export function isMusicYouTubeSignal(authorName, title) {
  if (authorName) {
    const a = authorName.toLowerCase();
    if (a.endsWith(' - topic') || a.includes('vevo')) return true;
  }
  if (title) {
    const t = title.toLowerCase();
    if (t.includes('official music video') || t.includes('official audio') || t.includes('video song')) return true;
  }
  return false;
}

export function musicSubtype(url, ogType, platform) {
  if (platform === 'mixcloud') return 'mix';
  switch ((ogType || '').toLowerCase()) {
    case 'music.playlist': return 'playlist';
    case 'music.musician': return 'artist';
    case 'music.album': return 'album';
    case 'music.song': return 'track';
    default: break;
  }
  const u = toURL(url);
  const path = decodeURIComponentSafe(u?.pathname || '').toLowerCase();
  const query = (u?.search || '').replace(/^\?/, '').toLowerCase();
  if (path.includes('/playlist/') || path.includes('pl.u-') || path.includes('/sets/')) return 'playlist';
  if (path.includes('/artist/')) return 'artist';
  if (path.includes('/album/')) return query.includes('i=') ? 'track' : 'album';
  if (path.includes('/track/')) return 'track';
  return 'track';
}

// ─── Post ───────────────────────────────────────────────────────────────

export const WISHLIST_LABEL = 'wishlist';

export function hasWishlistLabel(labels = []) {
  return labels.some((l) => String(l).trim().toLowerCase() === WISHLIST_LABEL);
}

export function postPlatform(url, collectionLabels = []) {
  if (hasWishlistLabel(collectionLabels)) return null;
  return socialPostHost(url);
}

// ─── Product ────────────────────────────────────────────────────────────

export function productSource(url, ogType, html, collectionLabels = []) {
  return productSourceNodes(toURL(url), ogType, jsonLDTypedNodes(html), html, collectionLabels);
}

function productSourceNodes(url, ogType, nodes, html, collectionLabels) {
  const wishlisted = hasWishlistLabel(collectionLabels);
  const postHost = socialPostHost(url);
  if (postHost) {
    if (!wishlisted) return null;
    return postHost === 'instagram' ? 'instagram' : 'page';
  }
  const type = ogTypeKey(ogType);
  if (isProductOGType(type)) return 'page';

  const isArticle = type === 'article' || nodes.some((n) => nodeTypes(n.dict).some(isArticleType));
  const isSoftware = nodes.some((n) => nodeTypes(n.dict).some(isSoftwareType));
  const isCourse = nodes.some((n) => nodeTypes(n.dict).some(isCourseType));
  const isBook = nodes.some((n) => nodeTypes(n.dict).some(isBookType));

  if (!isArticle && !isSoftware && !isCourse && !isBook) {
    if (nodes.some((n) => nodeTypes(n.dict).some(isProductType) && n.dict.offers != null)) return 'page';
    if (isShopifyProductURL(url) && (!html || hasShopifyMarker(html) || isMyShopifyHost(url))) return 'page';
  }
  if (isAmazonProductURL(url) || isKickstarterProjectURL(url)) return 'page';
  if (wishlisted && isBareImageURL(url)) return 'image';
  return null;
}

function ogTypeKey(ogType) {
  return ogType == null ? null : String(ogType).trim().toLowerCase();
}

export function isProductOGType(ogType) {
  const t = ogTypeKey(ogType);
  if (!t) return false;
  return t === 'product' || t === 'og:product' || t.startsWith('product.');
}

function isProductType(t) { return typeIs(t, 'Product', 'ProductGroup', 'IndividualProduct'); }
function isSoftwareType(t) { return typeIs(t, 'SoftwareApplication', 'WebApplication', 'MobileApplication'); }

export const ARTICLE_TYPE_NAMES = ['Article', 'BlogPosting', 'NewsArticle', 'TechArticle', 'Report', 'ScholarlyArticle'];
export function isArticleType(t) { return typeIs(t, ...ARTICLE_TYPE_NAMES); }
export function isBookType(t) { return typeIs(t, 'Book', 'Audiobook'); }
export function isCourseType(t) { return typeIs(t, 'Course'); }
export function isEducationEventType(t) { return typeIs(t, 'EducationEvent'); }

// ─── Resource ───────────────────────────────────────────────────────────

export const DIGITAL_RESOURCES_LABEL = 'digital-resources';
export const BOOKS_LABEL = 'books';

export function normalizedLabelKey(label) {
  return String(label).trim().toLowerCase().replace(/ /g, '-').replace(/_/g, '-');
}

export function hasLabel(key, labels = []) {
  return labels.some((l) => normalizedLabelKey(l) === key);
}

export function isResource(url, ogType, html, collectionLabels = []) {
  return isResourceNodes(toURL(url), ogType, jsonLDTypedNodes(html), html, collectionLabels);
}

function isResourceNodes(url, ogType, nodes, html, collectionLabels) {
  if (figmaCommunityResourceType(url) || framerMarketplaceSegment(url) || isCodePenPenURL(url)) return true;
  if (hasWishlistLabel(collectionLabels) || isBareImageURL(url)) return false;
  if (hasLabel(DIGITAL_RESOURCES_LABEL, collectionLabels)) {
    const type = ogTypeKey(ogType);
    const isArticle = type === 'article' || nodes.some((n) => nodeTypes(n.dict).some(isArticleType));
    if (!isArticle) return true;
  }
  return false;
}

const FIGMA_RESOURCE_SEGMENTS = new Set(['plugin', 'widget', 'file']);

export function figmaCommunityResourceType(url) {
  if (bareHost(url) !== 'figma.com') return null;
  const parts = pathParts(url, true);
  if (parts.length < 3) return null;
  if (!(parts[0] === 'community' || (parts[0].startsWith('@') && parts[0].length > 1))) return null;
  const type = parts[1];
  if (!FIGMA_RESOURCE_SEGMENTS.has(type) || !parts[2]) return null;
  return type;
}

const FRAMER_RESERVED = new Set([
  'creators', 'creator', 'profile', 'search', 'category', 'categories', 'collections',
  'sell', 'submit', 'become-a-creator', 'blog', 'about', 'faq', 'help',
]);
const FRAMER_LISTING = new Set([
  'category', 'categories', 'search', 'page', 'tag', 'tags', 'free', 'paid', 'popular',
  'new', 'newest', 'featured', 'trending', 'best', 'all',
]);

export function framerMarketplaceSegment(url) {
  if (bareHost(url) !== 'framer.com') return null;
  const parts = pathParts(url, true);
  if (parts.length < 3 || parts[0] !== 'marketplace') return null;
  const [, type, slug] = parts;
  if (FRAMER_RESERVED.has(type) || FRAMER_LISTING.has(slug) || !slug) return null;
  return type;
}

export function isCodePenPenURL(url) {
  if (bareHost(url) !== 'codepen.io') return false;
  const parts = pathParts(url, true);
  if (parts.length < 3) return false;
  return ['pen', 'full', 'details'].includes(parts[1]) && !!parts[2];
}

// ─── Book ───────────────────────────────────────────────────────────────

export function isSingleBook(url, html) {
  const u = toURL(url);
  const nodes = jsonLDTypedNodes(html);
  const host = bareHost(u);
  if (host) {
    const parts = pathParts(u, true);
    const after = (marker) => {
      const i = parts.indexOf(marker);
      return i >= 0 && i + 1 < parts.length ? parts[i + 1] : null;
    };
    if (hostIsBrand(host, 'amazon')) {
      let id = after('dp');
      if (id == null) {
        const i = parts.indexOf('gp');
        if (i >= 0 && i + 2 < parts.length && parts[i + 1] === 'product') id = parts[i + 2];
      }
      if (id && isISBN10(id)) return true;
    }
    if (hostMatches(host, 'thestorygraph.com') && after('books') != null) return true;
    if (hostMatches(host, 'goodreads.com') && parts.length >= 3 && parts[0] === 'book' && parts[1] === 'show') return true;
    if (host === 'openlibrary.org' && parts.length >= 2 && (parts[0] === 'books' || parts[0] === 'works')) return true;
  }
  if (isKnownBookPageURL(u)) return true;
  if (hasSingleBookNode(nodes)) return true;
  return hasBookISBNMeta(html);
}

export function isISBN10(id) {
  return /^[0-9]{9}[0-9xX]$/.test(String(id));
}

export function isBookOGType(ogType) {
  const t = ogTypeKey(ogType);
  return t === 'book' || t === 'books.book';
}

export function isBook(url, ogType, html) {
  return isBookNodes(toURL(url), ogType, jsonLDTypedNodes(html), html);
}

function isBookNodes(url, ogType, nodes, html) {
  if (isBareImageURL(url)) return false;
  if (hasSingleBookNode(nodes)) return true;
  if (isBookOGType(ogType) || hasBookISBNMeta(html)) return true;
  if (amazonBookISBN10(url) != null) return true;
  return isKnownBookPageURL(url);
}

function hasSingleBookNode(nodes) {
  const names = nodes
    .filter((n) => nodeTypes(n.dict).some(isBookType))
    .map((n) => (typeof n.dict.name === 'string' ? n.dict.name : '').trim().toLowerCase());
  return names.length > 0 && new Set(names.filter(Boolean)).size <= 1;
}

export function hasBookNode(html) {
  return jsonLDTypedNodes(html).some((n) => nodeTypes(n.dict).some(isBookType));
}

export function hasBookISBNMeta(html) {
  if (!html) return false;
  return metaTagAttributes(html).some((a) => {
    const key = (a.property ?? a.name ?? '').toLowerCase();
    if (key !== 'book:isbn' && key !== 'books:isbn') return false;
    return !!(a.content ?? '').trim();
  });
}

export function amazonBookISBN10(url) {
  const host = bareHost(url);
  if (!host || !(hostIsBrand(host, 'amazon') || hostIsBrand(host, 'amzn'))) return null;
  const parts = pathParts(url);
  const lower = parts.map((p) => p.toLowerCase());
  const candidates = [];
  lower.forEach((part, i) => {
    if (part === 'dp' && i + 1 < parts.length) candidates.push(parts[i + 1]);
    if (part === 'gp' && i + 2 < parts.length && lower[i + 1] === 'product') candidates.push(parts[i + 2]);
    if (part === 'gp' && i + 3 < parts.length && lower[i + 1] === 'aw' && lower[i + 2] === 'd') candidates.push(parts[i + 3]);
    if (part === 'o' && i + 2 < parts.length && lower[i + 1] === 'asin') candidates.push(parts[i + 2]);
  });
  for (const c of candidates) if (isValidISBN10(c)) return c.toUpperCase();
  return null;
}

export function isValidISBN10(value) {
  if (!isISBN10(value)) return false;
  let sum = 0;
  [...String(value).toUpperCase()].forEach((ch, i) => {
    sum += (ch === 'X' ? 10 : Number(ch)) * (10 - i);
  });
  return sum % 11 === 0;
}

export function isValidISBN13(value) {
  const v = String(value);
  if (!/^[0-9]{13}$/.test(v) || !(v.startsWith('978') || v.startsWith('979'))) return false;
  let sum = 0;
  [...v].forEach((ch, i) => { sum += Number(ch) * (i % 2 === 0 ? 1 : 3); });
  return sum % 10 === 0;
}

export function isKnownBookPageURL(url) {
  const host = bareHost(url);
  if (!host) return false;
  const m = (root) => hostMatches(host, root);
  const parts = pathParts(url, true);
  if (m('goodreads.com')) return parts.length >= 3 && parts[0] === 'book' && parts[1] === 'show' && !!parts[2];
  if (m('openlibrary.org')) {
    if (parts.length < 2) return false;
    const id = parts[1];
    const isOLID = (suffix) => id.length > 3 && id.startsWith('ol') && id.endsWith(suffix) && isAllDigits(id.slice(2, -1));
    return (parts[0] === 'works' && isOLID('w')) || (parts[0] === 'books' && isOLID('m'));
  }
  if (host.startsWith('books.google.') && hostIsBrand(host, 'google')) {
    if (queryValue(url, 'id')) return true;
    const i = parts.indexOf('books');
    return i >= 0 && i + 2 < parts.length && parts[i + 1] === 'edition';
  }
  if (m('thestorygraph.com')) {
    if (parts.length < 2 || parts[0] !== 'books') return false;
    return parts[1].length >= 8 && /^[-0-9a-f]+$/.test(parts[1]);
  }
  if (m('bookshop.org')) return parts.length >= 3 && parts[0] === 'p' && parts[1] === 'books' && !!parts[2];
  return false;
}

// ─── Tool ───────────────────────────────────────────────────────────────

export const TOOL_LABELS = new Set(['digital-tools', 'digital-productivity', 'gen-ai']);
export const AI_ART_ONLY_LABELS = new Set(['midjourney', 'nijijourney', 'ai-art', 'stable-diffusion', 'dall-e']);

export function hasToolLabel(labels = []) {
  const keys = labels.map(normalizedLabelKey);
  if (keys.some((k) => AI_ART_ONLY_LABELS.has(k))) return false;
  return keys.some((k) => TOOL_LABELS.has(k));
}

export function isTool(url, ogType, html, collectionLabels = []) {
  return isToolNodes(toURL(url), ogType, jsonLDTypedNodes(html), collectionLabels);
}

function isToolNodes(url, ogType, nodes, collectionLabels) {
  if (githubRepo(url) || isAppStoreAppURL(url)) return true;
  const type = ogTypeKey(ogType);
  const isArticle = type === 'article' || nodes.some((n) => nodeTypes(n.dict).some(isArticleType));
  if (isArticle) return false;
  if (nodes.some((n) => nodeTypes(n.dict).some(isSoftwareType))) return true;
  if (hasToolLabel(collectionLabels) && !isBareImageURL(url) && !isArticleShapedURL(url)) return true;
  return false;
}

const GITHUB_RESERVED = new Set([
  'orgs', 'topics', 'features', 'marketplace', 'settings', 'about', 'pricing', 'collections',
  'sponsors', 'explore', 'trending', 'login', 'logout', 'join', 'signup', 'search', 'new',
  'notifications', 'issues', 'pulls', 'dashboard', 'organizations', 'enterprise', 'enterprises',
  'security', 'site', 'team', 'customer-stories', 'readme', 'apps', 'codespaces', 'users',
  'events', 'contact', 'home', 'nonprofit', 'premium-support', 'resources', 'solutions',
  'sitemap', 'watching', 'stars', 'account', 'copilot', 'mobile', 'education', 'partners',
  'github-copilot', 'community', 'discussions', 'advisories', 'blog', 'changelog',
]);

export function githubRepo(url) {
  if (bareHost(url) !== 'github.com') return null;
  const parts = pathParts(url);
  if (parts.length < 2) return null;
  const owner = parts[0];
  let repo = parts[1];
  if (repo.toLowerCase().endsWith('.git')) repo = repo.slice(0, -4);
  if (GITHUB_RESERVED.has(owner.toLowerCase()) || !owner || !repo) return null;
  const ok = /^[A-Za-z0-9._-]+$/;
  if (!ok.test(owner) || !ok.test(repo)) return null;
  return { owner, repo };
}

export function isAppStoreAppURL(url) {
  const u = toURL(url);
  if (!u) return false;
  const scheme = u.protocol.replace(/:$/, '').toLowerCase();
  if (['macappstore', 'itms-apps', 'itms-appss'].includes(scheme)) return true;
  const host = bareHost(u);
  if (host !== 'apps.apple.com' && host !== 'itunes.apple.com') return false;
  const parts = pathParts(u, true);
  const i = parts.indexOf('app');
  return i >= 0 && i + 1 < parts.length;
}

export function isMacAppStoreURL(url) {
  const u = toURL(url);
  if (!u) return false;
  if (u.protocol.toLowerCase() === 'macappstore:') return true;
  if (!isAppStoreAppURL(u)) return false;
  return u.searchParams.getAll('mt').includes('12');
}

// ─── Course ─────────────────────────────────────────────────────────────

export const EDUCATION_LABEL = 'education';

export const MULTI_PURPOSE_COURSE_HOSTS = new Set([
  'frontendmasters.com', 'maven.com', 'udemy.com', 'coursera.org', 'domestika.org',
  'skillshare.com', 'egghead.io', 'university.webflow.com',
]);
export const SINGLE_PURPOSE_COURSE_HOSTS = new Set([
  'motiondesign.school', 'superhi.com', 'shiftnudge.com', 'thebasics.dev', 'designcourse.com',
]);
const COURSE_HOST_PATH_SEGMENTS = new Set(['course', 'courses', 'learn', 'classes']);
const MAVEN_RESERVED = new Set([
  'blog', 'about', 'pricing', 'login', 'signup', 'sign-up', 'search', 'categories', 'category',
  'topics', 'teach', 'business', 'for-business', 'careers', 'jobs', 'terms', 'privacy', 'help',
  'resources', 'p', 'u', 'settings', 'explore', 'creators', 'courses', 'lightning-lessons',
  'guides', 'articles', 'events',
]);
export const COURSE_PATH_SEGMENTS = new Set(['course', 'courses', 'program', 'programs', 'masterclass', 'bootcamp', 'workshop']);
const COURSE_TITLE_WORDS = new Set([
  'course', 'courses', 'masterclass', 'masterclasses', 'bootcamp', 'bootcamps', 'workshop',
  'workshops', 'academy', 'learn', 'master',
]);

export function isCourse(url, ogType, html, title, collectionLabels = []) {
  return isCourseNodes(toURL(url), ogType, jsonLDTypedNodes(html), title, collectionLabels);
}

function isCourseNodes(url, ogType, nodes, title, collectionLabels) {
  if (isBareImageURL(url)) return false;
  if (nodes.some((n) => nodeTypes(n.dict).some(isCourseType))) return true;
  if (isCourseHostURL(url) || hasCoursePathSegment(url)) return true;
  const titleWord = titleHasCourseWord(title);
  const educationLabelled = hasLabel(EDUCATION_LABEL, collectionLabels);
  if ((titleWord || educationLabelled) && nodes.some((n) => nodeTypes(n.dict).some(isEducationEventType))) return true;
  if (educationLabelled && titleWord && !hasStrongArticleSignal(url, nodes)) return true;
  return false;
}

export function hasCourseNode(html) {
  return jsonLDTypedNodes(html).some((n) => nodeTypes(n.dict).some(isCourseType));
}

function hasStrongArticleSignal(url, nodes) {
  return nodes.some((n) => nodeTypes(n.dict).some(isArticleType)) || isArticleShapedURL(url);
}

export function isArticleShapedURL(url) {
  return urlPathDate(url) != null || hasArticlePathSlug(url)
    || isMediumPost(url) || isSubstackPost(url) || isCodropsArticle(url);
}

export function courseHost(url) {
  const host = bareHost(url);
  if (!host) return null;
  const roots = [...MULTI_PURPOSE_COURSE_HOSTS, ...SINGLE_PURPOSE_COURSE_HOSTS, 'joshwcomeau.com'].sort();
  return roots.find((root) => hostMatches(host, root)) ?? null;
}

export function isCourseHostURL(url) {
  const root = courseHost(url);
  const host = bareHost(url);
  if (!root || !host) return false;
  const parts = pathParts(url, true);
  if (root === 'joshwcomeau.com') return parts.includes('courses');
  if (SINGLE_PURPOSE_COURSE_HOSTS.has(root)) {
    if (host.startsWith('blog.')) return false;
    if (parts.includes('blog') || isArticleShapedURL(url)) return false;
    return true;
  }
  for (let i = 0; i < parts.length; i++) {
    if (COURSE_HOST_PATH_SEGMENTS.has(parts[i]) && i + 1 < parts.length) {
      const slug = parts[i + 1];
      if (slug && !ARTICLE_LISTING_SLUGS.has(slug)) return true;
    }
  }
  if (root === 'maven.com' && host === 'maven.com' && parts.length >= 2 && !MAVEN_RESERVED.has(parts[0])) return true;
  return false;
}

export function hasCoursePathSegment(url) {
  const parts = pathParts(url, true);
  if (parts.includes('blog') || isArticleShapedURL(url)) return false;
  for (let i = 0; i < parts.length; i++) {
    if (!COURSE_PATH_SEGMENTS.has(parts[i])) continue;
    if (i + 1 < parts.length) {
      const slug = parts[i + 1];
      if (slug && !ARTICLE_LISTING_SLUGS.has(slug)) return true;
    } else if (i > 0) {
      return true;
    }
  }
  return false;
}

export function coursePathFormat(url) {
  if (!hasCoursePathSegment(url)) return null;
  const parts = pathParts(url, true);
  if (parts.includes('program') || parts.includes('programs')) return 'program';
  if (parts.includes('workshop')) return 'workshop';
  return null;
}

export function titleHasCourseWord(title) {
  if (!title) return false;
  return wordTokens(title).some((t) => COURSE_TITLE_WORDS.has(t));
}

// ─── Article ────────────────────────────────────────────────────────────

export const NEWS_LABEL = 'news';
export const ARTICLE_PATH_SEGMENTS = new Set(['blog', 'article', 'articles', 'post', 'posts', 'news', 'essays', 'writing']);
const ARTICLE_LISTING_SLUGS = new Set([
  'page', 'tag', 'tags', 'category', 'categories', 'author', 'authors', 'archive', 'archives',
  'feed', 'rss', 'atom', 'search', 'topic', 'topics',
]);
const MEDIUM_RESERVED = new Set([
  'tag', 'tags', 'topic', 'topics', 'me', 'm', 'search', 'membership', 'about', 'plans',
  'creators', 'policy', 'jobs', 'signin', 'login', 'new-story', 'followers', 'following',
]);

export function isArticle(url, ogType, html, collectionLabels = []) {
  return isArticleNodes(toURL(url), ogType, jsonLDTypedNodes(html), html, collectionLabels);
}

function isArticleNodes(url, ogType, nodes, html, collectionLabels) {
  if (isBareImageURL(url)) return false;
  if (nodes.some((n) => nodeTypes(n.dict).some(isArticleType))) return true;
  const meta = (key) => (html ? metaContent(html, key) : null);
  if (meta('article:published_time') != null) return true;
  if (urlPathDate(url) != null) return true;
  if (hasArticlePathSlug(url) || isMediumPost(url) || isSubstackPost(url) || isCodropsArticle(url)) return true;
  if (ogTypeKey(ogType) !== 'article') return false;
  if (hasLabel(NEWS_LABEL, collectionLabels)) return true;
  const hasAuthor = meta('author') != null || meta('article:author') != null
    || (meta('twitter:label1') || '').toLowerCase() === 'written by'
    || nodes.some((n) => n.dict.author != null);
  const hasDate = meta('article:modified_time') != null || nodes.some((n) => n.dict.datePublished != null);
  return hasAuthor || hasDate;
}

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** `/YYYY/MM/<slug>`, `/YYYY/Mon/<slug>`, `/YYYY/MM/DD/<slug>` → { year, month, day }. */
export function urlPathDate(url) {
  const parts = pathParts(url);
  if (parts.length < 3) return null;
  for (let i = 0; i < parts.length - 2; i++) {
    const year = pathYear(parts[i]);
    const month = pathMonth(parts[i + 1]);
    if (year == null || month == null) continue;
    let day = null;
    let next = i + 2;
    const seg = parts[next];
    if (seg.length <= 2 && isAllDigits(seg) && +seg >= 1 && +seg <= 31) {
      day = +seg;
      next += 1;
    }
    if (next >= parts.length || !parts[next]) continue;
    return { year, month, day };
  }
  return null;
}

function pathYear(seg) {
  if (seg.length !== 4 || !isAllDigits(seg) || !(seg.startsWith('19') || seg.startsWith('20'))) return null;
  return +seg;
}

function pathMonth(seg) {
  if (seg.length >= 1 && seg.length <= 2 && isAllDigits(seg)) {
    const m = +seg;
    return m >= 1 && m <= 12 ? m : null;
  }
  if (seg.length === 3) {
    const i = MONTHS.indexOf(seg.toLowerCase());
    if (i >= 0) return i + 1;
  }
  return null;
}

export function hasArticlePathSlug(url) {
  const parts = pathParts(url, true);
  for (let i = 0; i < parts.length; i++) {
    if (!ARTICLE_PATH_SEGMENTS.has(parts[i]) || i + 1 >= parts.length) continue;
    const slug = parts[i + 1];
    if (!slug || ARTICLE_LISTING_SLUGS.has(slug) || slug.endsWith('.xml')) continue;
    return true;
  }
  return false;
}

export function isMediumPost(url) {
  const host = bareHost(url);
  if (!host) return false;
  const parts = pathParts(url, true);
  const first = parts[0];
  if (first == null || MEDIUM_RESERVED.has(first)) return false;
  if (host === 'medium.com') return parts.length >= 2;
  if (host.endsWith('.medium.com')) return parts.length > 0 && !first.startsWith('@');
  return false;
}

export function isSubstackPost(url) {
  const host = bareHost(url);
  if (!host || !host.endsWith('.substack.com')) return false;
  const parts = pathParts(url);
  return parts.length >= 2 && parts[0].toLowerCase() === 'p' && !!parts[1];
}

export function isCodropsArticle(url) {
  if (bareHost(url) !== 'tympanus.net') return false;
  const parts = pathParts(url, true);
  return parts.length >= 3 && parts[0] === 'codrops' && pathYear(parts[1]) != null;
}

// ─── Product host / path rules ──────────────────────────────────────────

export function socialPostHost(url) {
  const host = bareHost(url);
  if (!host) return null;
  const m = (root) => hostMatches(host, root);
  const parts = pathParts(url, true);
  const followed = (marker) => {
    const i = parts.indexOf(marker);
    return i >= 0 && i + 1 < parts.length;
  };
  if (m('instagram.com')) {
    const i = parts.findIndex((p) => ['p', 'reel', 'reels', 'tv'].includes(p));
    return i >= 0 && i + 1 < parts.length ? 'instagram' : null;
  }
  if (m('x.com') || m('twitter.com')) return followed('status') ? 'x' : null;
  if (m('behance.net')) return followed('gallery') ? 'behance' : null;
  if (m('dribbble.com')) return followed('shots') ? 'dribbble' : null;
  if (hostIsBrand(host, 'pinterest') || host === 'pin.it') {
    if (host === 'pin.it') return parts.length ? 'pinterest' : null;
    return followed('pin') ? 'pinterest' : null;
  }
  return null;
}

export function isShopifyProductURL(url) {
  return shopifyHandle(url) != null;
}

export function shopifyHandle(url) {
  const parts = pathParts(url);
  let i = -1;
  parts.forEach((p, j) => { if (p.toLowerCase() === 'products') i = j; });
  if (i < 0 || i + 1 >= parts.length) return null;
  let handle = parts[i + 1];
  for (const ext of ['.json', '.js', '.oembed', '.xml']) {
    if (handle.toLowerCase().endsWith(ext)) handle = handle.slice(0, -ext.length);
  }
  return handle || null;
}

function isMyShopifyHost(url) {
  const host = bareHost(url);
  return !!host && hostMatches(host, 'myshopify.com');
}

function hasShopifyMarker(html) {
  return html.includes('cdn.shopify.com') || html.includes('/cdn/shop/')
    || html.includes('Shopify.shop') || html.includes('shopify-digital-wallet');
}

export function isAmazonProductURL(url) {
  const host = bareHost(url);
  if (!host) return false;
  if (['amzn.to', 'amzn.in', 'amzn.eu', 'a.co'].includes(host)) return true;
  if (!hostIsBrand(host, 'amazon')) return false;
  const path = decodeURIComponentSafe(toURL(url).pathname).toLowerCase();
  return path.includes('/dp/') || path.includes('/gp/product/') || path.includes('/gp/aw/d/');
}

export function isKickstarterProjectURL(url) {
  const host = bareHost(url);
  if (!host || !hostMatches(host, 'kickstarter.com')) return false;
  const parts = pathParts(url, true);
  return parts[0] === 'projects' && parts.length >= 3;
}

export const BARE_IMAGE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'webp', 'gif', 'avif']);

export function isBareImageURL(url) {
  return BARE_IMAGE_EXTENSIONS.has(pathExtension(url));
}
