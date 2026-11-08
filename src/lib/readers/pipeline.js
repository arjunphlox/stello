/**
 * The page-reader pipeline: one saved link → kind + metadata.
 *
 * Port of `CaptureService.captureURL`'s reading half (everything before the images are
 * downloaded and the item is written). The Worker is the single copy: web saves call it
 * directly, and the Apple apps POST the HTML they already fetched to /api/classify
 * (device IP, so bot walls behave as before) and get the same answer back.
 *
 * Network (the page itself when no HTML is given, plus the per-kind extras: GitHub,
 * Shopify .json, X syndication, Behance / music oEmbeds, Open Library, Deezer) goes
 * through `makeNet`, which caps time and subrequests.
 */
import { parseOG, extractText, clipChars, decodeBasicEntities, domainOf, normalizeURL, toURL } from './html.js';
import { classify } from './classifier.js';
import * as Product from './product.js';
import * as Post from './post.js';
import * as Resource from './resource.js';
import * as Book from './book.js';
import * as Tool from './tool.js';
import * as Course from './course.js';
import * as Article from './article.js';
import { classifyAndExtractMusic } from './music.js';

export const BROWSER_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
  + '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/** Pages are read up to 2 MB (og:image can sit deep in a long page). */
export const MAX_HTML_BYTES = 2_000_000;

/**
 * A small fetch wrapper: per-call timeout, a subrequest budget (the Workers Free plan
 * allows 50 per request), and never throws.
 */
export function makeNet({ fetchImpl = globalThis.fetch, budget = 40 } = {}) {
  let used = 0;
  async function get(url, { timeout = 15000, headers = {} } = {}) {
    if (!url || used >= budget) return null;
    used += 1;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeout);
    try {
      const res = await fetchImpl(url, { headers: { 'User-Agent': BROWSER_UA, ...headers }, redirect: 'follow', signal: ctrl.signal });
      const buf = await readCapped(res, MAX_HTML_BYTES);
      return { status: res.status, text: decodeBody(buf), finalURL: res.url || url };
    } catch {
      return null;
    } finally {
      clearTimeout(timer);
    }
  }
  return {
    get,
    get used() { return used; },
    async json(url, opts = {}) {
      const r = await get(url, { ...opts, headers: { Accept: 'application/json', ...(opts.headers || {}) } });
      if (!r) return null;
      if (opts.okOnly && r.status !== 200) return null;
      try { return JSON.parse(r.text); } catch { return null; }
    },
  };
}

async function readCapped(res, cap) {
  if (!res.body?.getReader) {
    const ab = await res.arrayBuffer();
    return new Uint8Array(ab).subarray(0, cap);
  }
  const reader = res.body.getReader();
  const chunks = [];
  let size = 0;
  while (size < cap) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    size += value.length;
  }
  if (size >= cap) reader.cancel().catch(() => {});
  const out = new Uint8Array(Math.min(size, cap));
  let off = 0;
  for (const c of chunks) {
    const take = Math.min(c.length, out.length - off);
    out.set(c.subarray(0, take), off);
    off += take;
    if (off >= out.length) break;
  }
  return out;
}

function decodeBody(bytes) {
  try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch { /* fall through */ }
  // A slice can cut a multi-byte character; drop up to 3 trailing bytes and retry.
  for (let cut = 1; cut <= 3 && cut < bytes.length; cut++) {
    try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, bytes.length - cut)); } catch { /* next */ }
  }
  return new TextDecoder('latin1').decode(bytes);
}

/**
 * @param {object} input
 * @param {string} input.url                the saved link
 * @param {string} [input.html]             page HTML the caller already fetched (Apple apps)
 * @param {number} [input.status]           HTTP status of that fetch
 * @param {string} [input.finalURL]         URL after redirects
 * @param {string[]} [input.collectionLabels] import / force-Enrich labels (fresh saves: none)
 * @param {object} [input.net]              makeNet() instance
 * @param {Date}   [input.now]
 * @returns {Promise<object>} { kind, title, summary, extractedText, domain, status, metadata,
 *   images: { urls, source, fallbacks }, confidence, signals }
 */
export async function readPage({ url, html = null, status = null, finalURL = null, collectionLabels = [], net = makeNet(), now = new Date(), fetchPage = true }) {
  const source = toURL(url);
  if (!source) throw new Error('readPage: invalid url');

  let page = null;
  if (html != null) {
    page = { html, status, finalURL: toURL(finalURL)?.href ?? null };
  } else if (fetchPage) {
    const r = await net.get(source.href);
    if (r) page = { html: r.text, status: r.status, finalURL: r.finalURL };
  }
  if (page) page.og = parseOG(page.html, page.finalURL ?? source.href);
  const og = page?.og ?? { title: null, description: null, imageURL: null, ogType: null };
  const pageHTML = page?.html ?? '';
  const ogTitle = og.title ?? source.hostname ?? source.href;
  const summary = og.description != null ? [...decodeBasicEntities(og.description)].slice(0, 200).join('') : null;
  const dom = domainOf(source);
  const finalU = page?.finalURL ? toURL(page.finalURL) : null;
  const isGonePage = page?.status === 404 || page?.status === 410;

  const c = classify({ html: pageHTML, baseURL: source, domain: dom, title: ogTitle, ogDescription: og.description, ogType: og.ogType, collectionLabels });
  let kind = c.kind;
  const ogImage = og.imageURL ?? null;
  const common = { sourceURL: source, finalURL: finalU, html: pageHTML, ogTitle: og.title };

  let post = null, product = null, resource = null, book = null, tool = null, course = null, article = null, music = null;

  if (kind === 'post' && c.postPlatform) {
    let syndication = null;
    let oembed = null;
    if (c.postPlatform === 'x') {
      const id = Post.tweetID(source) ?? (finalU ? Post.tweetID(finalU) : null);
      if (id) {
        const r = await net.get(Post.syndicationURL(id), { headers: { Accept: 'application/json' } });
        syndication = r ? Post.parseSyndication(r.text, r.status) : { kind: 'unavailable' };
      }
    } else if (c.postPlatform === 'behance') {
      const o = await net.json(Post.behanceOEmbedURL(source));
      if (o) oembed = { title: o.title ?? null, authorName: o.author_name ?? null, authorURL: o.author_url ?? null, thumbnailURL: o.thumbnail_url ?? null };
    }
    post = Post.build({ ...common, platform: c.postPlatform, ogDescription: og.description, ogImageURL: ogImage, ogType: og.ogType, syndication, oembed });
    Post.applyAIArt(post.meta, collectionLabels, []);
  }

  if (kind === 'product' && c.productSource) {
    let shopify = null;
    if (c.productSource === 'page') {
      const jsonURL = Product.shopifyJSONURL(finalU ?? source) ?? Product.shopifyJSONURL(source);
      if (jsonURL) shopify = Product.parseShopifyProduct(await net.json(jsonURL, { okOnly: true }));
    }
    product = Product.build({ ...common, source: c.productSource, ogDescription: og.description, ogImageURL: ogImage, shopify, now });
  }

  if (kind === 'resource') resource = Resource.build(common);

  if (kind === 'book') {
    const ids = Book.isbns({ sourceURL: source, finalURL: finalU, html: pageHTML });
    const isbn = ids.isbn13 ?? ids.isbn10;
    let openLibrary = null;
    if (isbn) {
      const body = await net.json(Book.openLibraryLookupURL(isbn), { timeout: 10000, okOnly: true, headers: { 'User-Agent': 'Stello/1.0 (book lookup)' } });
      openLibrary = body ? Book.parseOpenLibrary(body, isbn) : null;
    }
    book = Book.build({ ...common, ogImageURL: ogImage, openLibrary });
  }

  if (kind === 'tool') {
    const api = Tool.githubAPIURL(source) ?? (finalU ? Tool.githubAPIURL(finalU) : null);
    let github = null;
    if (api) {
      const r = await net.get(api, { timeout: 10000, headers: { 'User-Agent': 'Stello/1.0', Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' } });
      github = r ? Tool.parseGitHubRepo(r.text, r.status) : null;
    }
    tool = Tool.build({ ...common, ogDescription: og.description, github });
  }

  if (kind === 'course') course = Course.build({ ...common, now });

  // Articles need the full text (reading time); extract it once and clip it for the AI slice.
  const fullText = kind === 'article' ? extractText(pageHTML, null) : undefined;
  if (kind === 'article') article = Article.build({ ...common, pageText: fullText });

  if (kind === 'link') {
    music = await classifyAndExtractMusic({ sourceURL: source, domain: dom, title: ogTitle, ogType: og.ogType, page, net });
    if (music) kind = 'music';
  }

  const firstTitle = [post?.title, product?.title, resource?.title, book?.title, tool?.title, course?.title, music?.rawTitle]
    .map((t) => (typeof t === 'string' ? t.trim() : '')).find(Boolean);
  const title = firstTitle || ogTitle;

  let extractedText;
  if (post) extractedText = post.meta.text ?? null;
  else if (music) extractedText = null;
  else if (product && product.meta.source !== 'page') extractedText = product.meta.caption ?? null;
  else extractedText = fullText !== undefined ? clipChars(fullText, 4000) : extractText(pageHTML);

  // Images: product gallery / post media (cover first), else music cover, else og:image;
  // books add their JSON-LD / Open Library covers as fallbacks.
  const images = { urls: [], source: 'og', fallbacks: [] };
  if (product || post) {
    images.urls = (product ?? post).imageURLs;
    images.source = product ? 'product' : 'post';
    if (ogImage) images.fallbacks.push(ogImage);
  } else if (music) {
    if (music.coverImageURL) images.urls.push(music.coverImageURL);
    if (music.coverFallbackURL) images.fallbacks.push(music.coverFallbackURL);
  } else if (ogImage) {
    images.urls.push(ogImage);
  }
  if (book?.coverFallbackURLs?.length) images.fallbacks.push(...book.coverFallbackURLs);

  let displayDomain = dom;
  const canonical = tool?.meta.canonicalURL ?? resource?.meta.canonicalURL ?? book?.meta.canonicalURL
    ?? course?.meta.canonicalURL ?? article?.canonicalURL ?? null;
  if (product) displayDomain = (finalU ? domainOf(finalU) : null) ?? dom;
  else if (canonical) displayDomain = domainOf(canonical) ?? dom;

  const metadata = c.individualMeta ?? music?.meta ?? product?.meta ?? post?.meta ?? tool?.meta
    ?? resource?.meta ?? book?.meta ?? course?.meta ?? article ?? null;

  return {
    kind,
    title,
    summary,
    extractedText,
    domain: displayDomain,
    sourceURL: normalizeURL(source),
    status: isGonePage || post?.isGone ? 'gone' : 'active',
    metadata,
    images,
    fetched: page != null,
    ...confidenceFor(kind, page, metadata),
  };
}

/**
 * How sure the rules are, 0 to 1, with the signal that decided it. A plain `link` that
 * the page could not be read for (bot wall, timeout) is the least sure — those are the
 * cases a second opinion (Jev) or Needs review is for.
 */
export function confidenceFor(kind, page, metadata) {
  if (!page) return { confidence: kind === 'link' ? 0.2 : 0.7, signal: 'url-only' };
  if (page.status && page.status >= 400 && page.status !== 404 && page.status !== 410) {
    return { confidence: kind === 'link' ? 0.25 : 0.7, signal: `http-${page.status}` };
  }
  if (kind === 'link') return { confidence: 0.5, signal: 'no-rule-matched' };
  const filled = metadata ? Object.values(metadata).filter((v) => v != null && v !== false && !(Array.isArray(v) && !v.length)).length : 0;
  return { confidence: filled >= 3 ? 0.95 : 0.85, signal: 'rules' };
}
