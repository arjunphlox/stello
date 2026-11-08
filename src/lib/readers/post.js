/**
 * Post reader: X syndication JSON, Instagram / Behance / Dribbble / Pinterest og tags,
 * Behance oEmbed, the Post title rule and the AI-art rules. Port of PostReader.swift.
 * The network steps (syndication, oEmbed) live in pipeline.js.
 */
import { metaTagAttributes, decodeBasicEntities, appleDate, resolveURL, toURL, pathParts, isDict } from './html.js';
import { parseInstagramOG, cleanCaption } from './product.js';

export const MEDIA_CAP = 8;
export const TITLE_WORD_COUNT = 8;

function clean(v) {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t || null;
}

// ─── X ──────────────────────────────────────────────────────────────────

export function tweetID(url) {
  const parts = pathParts(url);
  const i = parts.findIndex((p) => ['status', 'statuses'].includes(p.toLowerCase()));
  if (i < 0 || i + 1 >= parts.length) return null;
  const id = parts[i + 1];
  return /^[0-9]+$/.test(id) ? id : null;
}

export function handleFromXURL(url) {
  const parts = pathParts(url);
  const i = parts.findIndex((p) => p.toLowerCase() === 'status');
  if (i <= 0) return null;
  const handle = parts[i - 1];
  if (['i', 'web'].includes(handle.toLowerCase())) return null;
  return handle || null;
}

/** The embed widget's token: `((id / 1e15) * π).toString(36)` without `0` and `.`. */
export function syndicationToken(id) {
  const n = Number(id);
  if (!Number.isFinite(n) || n <= 0) return 'a';
  const token = ((n / 1e15) * Math.PI).toString(36).replace(/[0.]/g, '');
  return token || 'a';
}

export function syndicationURL(id) {
  return `https://cdn.syndication.twimg.com/tweet-result?id=${id}&lang=en&token=${syndicationToken(id)}`;
}

/** @returns {{ kind: 'tweet', tweet: object } | { kind: 'gone' } | { kind: 'unavailable' }} */
export function parseSyndication(body, statusCode) {
  if (statusCode === 404 || statusCode === 410) return { kind: 'gone' };
  if (body == null) return { kind: 'unavailable' };
  if (statusCode != null && statusCode !== 200) return { kind: 'unavailable' };
  const text = String(body).trim();
  if (!text || text === '{}') return { kind: 'gone' };
  let obj;
  try { obj = JSON.parse(text); } catch { return { kind: 'unavailable' }; }
  if (!isDict(obj)) return { kind: 'unavailable' };
  if (obj.__typename === 'TweetTombstone' || obj.tombstone != null) return { kind: 'gone' };
  const media = Array.isArray(obj.mediaDetails) ? obj.mediaDetails : [];
  if (clean(obj.text) == null && obj.user == null && !media.length) return { kind: 'gone' };
  return { kind: 'tweet', tweet: obj };
}

export function tweetMedia(tweet) {
  const details = Array.isArray(tweet.mediaDetails) ? tweet.mediaDetails : [];
  let urls = details.map((d) => clean(d?.media_url_https)).filter(Boolean);
  let types = details.map((d) => (typeof d?.type === 'string' ? d.type.toLowerCase() : null)).filter(Boolean);
  if (!urls.length) {
    urls = (Array.isArray(tweet.photos) ? tweet.photos : []).map((p) => clean(p?.url)).filter(Boolean);
    types = urls.map(() => 'photo');
  }
  const poster = clean(tweet.video?.poster);
  if (!urls.length && poster) {
    urls = [poster];
    types = ['video'];
  }
  const count = Math.max(details.length, urls.length);
  return { urls, mediaType: mediaTypeLabel(types, count), count };
}

export function mediaTypeLabel(types, count) {
  if (count <= 0) return null;
  if (count > 1) return 'carousel';
  switch (types[0]) {
    case 'video': return 'video';
    case 'animated_gif': case 'gif': return 'gif';
    default: return 'image';
  }
}

const LEGACY_MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };

export function parseTweetDate(raw) {
  const s = clean(raw);
  if (!s) return null;
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/.test(s)) {
    const d = new Date(s);
    return isNaN(d) ? null : d;
  }
  const m = /^[A-Za-z]{3} ([A-Za-z]{3}) (\d{2}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2}) (\d{4})$/.exec(s);
  if (!m) return null;
  const month = LEGACY_MONTHS[m[1].toLowerCase()];
  if (month == null) return null;
  const offset = (m[6] === '-' ? -1 : 1) * (+m[7] * 60 + +m[8]);
  return new Date(Date.UTC(+m[9], month, +m[2], +m[3], +m[4], +m[5]) - offset * 60000);
}

export function cleanTweetText(raw) {
  if (raw == null) return null;
  const text = String(raw).replace(/(\s*https?:\/\/t\.co\/[A-Za-z0-9]+)+\s*$/, '');
  return clean(decodeBasicEntities(text));
}

const X_TITLE_HANDLE_RE = /^([\s\S]+?)\s+\(@([A-Za-z0-9_]+)\)\s+on\s+(?:X|Twitter)\s*(?::\s*([\s\S]*))?$/;
const X_TITLE_TEXT_RE = /^([\s\S]+?)\s+on\s+(?:X|Twitter)\s*:\s*([\s\S]*)$/;

export function parseXOG(title, description) {
  let name = null, handle = null, text = null;
  const t = clean(title);
  if (t) {
    let m = X_TITLE_HANDLE_RE.exec(t);
    if (m) {
      name = clean(m[1]);
      handle = m[2];
      if (m[3] != null) text = cleanCaption(m[3]);
    } else if ((m = X_TITLE_TEXT_RE.exec(t))) {
      name = clean(m[1]);
      text = cleanCaption(m[2]);
    }
  }
  if (text == null && description != null) text = cleanCaption(description);
  return { name, handle, text };
}

export function ogExtras(html) {
  const extras = { url: null, hasVideo: false };
  for (const a of metaTagAttributes(html)) {
    const key = (a.property ?? a.name ?? '').toLowerCase();
    const content = clean(a.content);
    if (!content) continue;
    if (key === 'og:url') { if (extras.url == null) extras.url = content; }
    else if (key === 'og:video' || key === 'og:video:url' || key === 'og:video:secure_url') extras.hasVideo = true;
  }
  return extras;
}

// ─── Behance / Dribbble / Pinterest ─────────────────────────────────────

export function behanceOEmbedURL(url) {
  const u = toURL(url);
  if (!u?.host) return null;
  let path;
  try { path = decodeURIComponent(u.pathname); } catch { path = u.pathname; }
  const post = `https://${u.host}${path}`;
  const encoded = [...new TextEncoder().encode(post)].map((b) => {
    const c = String.fromCharCode(b);
    return /[A-Za-z0-9\-._~]/.test(c) ? c : '%' + b.toString(16).toUpperCase().padStart(2, '0');
  }).join('');
  return `https://www.behance.net/services/oembed?url=${encoded}`;
}

const DRIBBBLE_TITLE_RE = /^([\s\S]+?)\s+by\s+([\s\S]+?)\s+(?:on|\|)\s+Dribbble$/i;
const PINTEREST_DISCOVERED_RE = /^This Pin was discovered by\s+([^.]+?)\./i;

export function parseDribbbleTitle(title) {
  const t = clean(title);
  const m = t ? DRIBBBLE_TITLE_RE.exec(t) : null;
  if (!m) return { work: null, author: null };
  return { work: clean(m[1]), author: clean(m[2]) };
}

export function parsePinterestDescription(description) {
  const d = clean(description);
  if (!d) return { author: null, text: null };
  const m = PINTEREST_DISCOVERED_RE.exec(d);
  if (m) return { author: clean(m[1]), text: null };
  if (d.toLowerCase().startsWith('discover recipes, home ideas')) return { author: null, text: null };
  return { author: null, text: d };
}

// ─── Title rule ─────────────────────────────────────────────────────────

const BARE_GENERIC_TITLES = new Set([
  'x', 'twitter', 'instagram', 'behance', 'dribbble', 'pinterest',
  'x.com', 'twitter.com', 'mobile.twitter.com', 'instagram.com', 'www.instagram.com',
  'behance.net', 'www.behance.net', 'dribbble.com', 'pinterest.com', 'www.pinterest.com',
]);

export function isGenericPostTitle(title) {
  const t = clean(title);
  if (!t) return true;
  const l = t.toLowerCase();
  if (BARE_GENERIC_TITLES.has(l)) return true;
  if (l.startsWith('javascript is not available')) return true;
  if (l.endsWith(' on x') || l.endsWith(' on twitter') || l.includes(' on x:') || l.includes(' on twitter:')
    || l.endsWith(' / x') || l.endsWith(' / twitter')) return true;
  if (l.includes(' on instagram:') || l.endsWith(' on instagram') || l.includes('• instagram') || l.endsWith('| instagram')) return true;
  if (l.startsWith('behance ::') || l.startsWith('dribbble -') || l.startsWith('dribbble |')) return true;
  if (l.startsWith('pin on ') || l.startsWith('pin by ')) return true;
  return false;
}

const WORK_TITLE_SUFFIXES = [
  ' on Behance', ' :: Behance', ' | Behance', ' - Behance',
  ' on Dribbble', ' | Dribbble', ' - Dribbble',
  ' | Pinterest', ' - Pinterest',
];

export function strippedWorkTitle(title) {
  const work = parseDribbbleTitle(title).work;
  if (work) return work;
  for (const suffix of WORK_TITLE_SUFFIXES) {
    if (title.toLowerCase().endsWith(suffix.toLowerCase())) {
      const stripped = title.slice(0, title.length - suffix.length).trim();
      return stripped || title;
    }
  }
  return title;
}

export function postTitle({ currentTitle, handle, authorName, text }) {
  const current = clean(currentTitle);
  if (current && !isGenericPostTitle(current)) return strippedWorkTitle(current);
  const excerpt = textExcerpt(text);
  if (!excerpt) return current;
  const h = clean(handle);
  const prefix = h ? `@${h}` : clean(authorName);
  return prefix ? `${prefix}: ${excerpt}` : excerpt;
}

export function textExcerpt(text) {
  const t = clean(text);
  if (!t) return null;
  const words = t.replace(/https?:\/\/\S+/g, ' ').split(/\s+/).filter(Boolean);
  if (!words.length) return null;
  if (words.length <= TITLE_WORD_COUNT) return words.join(' ');
  let head = words.slice(0, TITLE_WORD_COUNT).join(' ');
  while (head && ',;:-–—'.includes(head.at(-1))) head = head.slice(0, -1);
  return head + '…';
}

// ─── AI art ─────────────────────────────────────────────────────────────

export const AI_ART_LABELS = new Set(['midjourney', 'gen-ai', 'ai-art', 'stable-diffusion', 'dall-e', 'nijijourney']);
const MJ_PARAM_RE = /(?:^|\s)(?:--|—)(?:ar|v|style|sref|niji|chaos|stylize)(?=[ \t]+[^\s\-—]|[ \t]*$)/im;

export function normalizedLabel(label) {
  return String(label).trim().toLowerCase().replace(/ /g, '-').replace(/_/g, '-');
}

export function hasMidjourneyParams(text) {
  return !!text && MJ_PARAM_RE.test(text);
}

function modelName(key) {
  switch (key) {
    case 'midjourney': case 'nijijourney': return 'Midjourney';
    case 'stable-diffusion': return 'Stable Diffusion';
    case 'dall-e': return 'DALL·E';
    default: return null;
  }
}

export function aiArtSignal(labels = [], tags = [], text = null) {
  let isAIArt = false;
  let model = null;
  for (const name of [...labels, ...tags]) {
    const key = normalizedLabel(name);
    if (!AI_ART_LABELS.has(key)) continue;
    isAIArt = true;
    if (model == null) model = modelName(key);
  }
  if (hasMidjourneyParams(text)) {
    isAIArt = true;
    if (model == null) model = 'Midjourney';
  }
  if (!isAIArt) return { isAIArt: false, model: null };
  if (model == null && text) {
    const l = text.toLowerCase();
    if (l.includes('midjourney') || l.includes('nijijourney') || l.includes('niji')) model = 'Midjourney';
    else if (l.includes('stable diffusion') || l.includes('stable-diffusion')) model = 'Stable Diffusion';
    else if (l.includes('dall-e') || l.includes('dall·e') || l.includes('dalle')) model = 'DALL·E';
  }
  return { isAIArt: true, model };
}

const PROMPT_LABEL_RE = /\bprompt\s*(?::|—|–|-)+\s*(.+)$/im;

export function extractPrompt(text) {
  const t = clean(text);
  if (!t) return null;
  const m = PROMPT_LABEL_RE.exec(t);
  if (m) {
    const p = cleanPrompt(m[1]);
    if (p) return p;
  }
  return paramsSentence(t);
}

function paramsSentence(text) {
  for (const line of text.split(/\r?\n|\r/).filter(Boolean)) {
    const pm = MJ_PARAM_RE.exec(line);
    if (!pm) continue;
    // The match may start with the whitespace before `--`; Swift's range starts there too.
    const head = line.slice(0, pm.index);
    let start = 0;
    for (const b of head.matchAll(/[.!?]\s+/g)) start = b.index + b[0].length;
    const p = cleanPrompt(line.slice(start));
    if (p) return p;
  }
  return null;
}

export function cleanPrompt(raw) {
  const r = clean(raw);
  return r ? cleanCaption(r) : null;
}

/** Recomputes the AI-art flag / model and rule-reads the prompt (only for Post items). */
export function applyAIArt(meta, labels = [], tags = []) {
  const s = aiArtSignal(labels, tags, meta.text ?? null);
  meta.isAIArt = s.isAIArt;
  if (s.model) meta.aiModel = s.model; else delete meta.aiModel;
  if (!s.isAIArt) return;
  if (meta.prompt == null || meta.promptIsGuess) {
    const read = extractPrompt(meta.text);
    if (read) { meta.prompt = read; meta.promptIsGuess = false; }
  }
}

// ─── Build ──────────────────────────────────────────────────────────────

const individual = (name) => ({ name, kind: 'individual' });

/**
 * @param syndication  parseSyndication() outcome, X only
 * @param oembed       { title, authorName, authorURL, thumbnailURL }, Behance only
 * @returns {{ meta: object, imageURLs: string[], title: string|null, isGone: boolean }}
 */
export function build({ sourceURL, finalURL = null, platform, html = '', ogTitle = null, ogDescription = null, ogImageURL = null, ogType = null, syndication = null, oembed = null }) {
  const source = toURL(sourceURL);
  const landing = toURL(finalURL) ?? source;
  const extras = ogExtras(html);
  const ogVideo = extras.hasVideo || (ogType || '').toLowerCase().startsWith('video');
  const meta = { platform, canonicalURL: extras.url ?? landing.href, isAIArt: false, promptIsGuess: false };
  let imageStrings = [];
  let mediaFromReader = false;
  let isGone = false;
  let titleSource = ogTitle;
  const ogImage = ogImageURL ? String(ogImageURL) : null;

  switch (platform) {
    case 'x': {
      const id = tweetID(source) ?? tweetID(landing);
      if (syndication?.kind === 'tweet') {
        const tweet = syndication.tweet;
        set(meta, 'text', cleanTweetText(tweet.text));
        set(meta, 'authorHandle', clean(tweet.user?.screen_name));
        const name = clean(tweet.user?.name);
        if (name) meta.author = individual(name);
        set(meta, 'postedAt', appleDate(parseTweetDate(tweet.created_at)));
        const media = tweetMedia(tweet);
        imageStrings = media.urls;
        set(meta, 'mediaType', media.mediaType);
        if (media.count > 0) meta.mediaCount = media.count;
        mediaFromReader = true;
      } else {
        if (syndication?.kind === 'gone') isGone = true;
        const og = parseXOG(ogTitle, ogDescription);
        set(meta, 'text', og.text);
        set(meta, 'authorHandle', og.handle);
        if (og.name) meta.author = individual(og.name);
      }
      if (meta.authorHandle == null) set(meta, 'authorHandle', handleFromXURL(source));
      if (id) {
        meta.canonicalURL = `https://x.com/${meta.authorHandle ?? 'i'}/status/${id}`;
        meta.embedURL = `https://platform.twitter.com/embed/Tweet.html?id=${id}`;
      }
      break;
    }
    case 'instagram': {
      const info = parseInstagramOG(ogTitle, ogDescription);
      set(meta, 'authorHandle', info.handle);
      const name = info.displayName ?? (info.handle ? `@${info.handle}` : null);
      if (name) meta.author = individual(name);
      set(meta, 'text', info.caption);
      set(meta, 'postedAt', appleDate(info.postedAt));
      const segments = pathParts(source);
      const lowered = segments.map((s) => s.toLowerCase());
      const isReel = lowered.some((s) => ['reel', 'reels', 'tv'].includes(s));
      const i = lowered.findIndex((s) => ['p', 'reel', 'reels', 'tv'].includes(s));
      if (i >= 0 && i + 1 < segments.length) meta.embedURL = `https://www.instagram.com/p/${segments[i + 1]}/embed`;
      if (ogImage) imageStrings = [ogImage];
      if (imageStrings.length) {
        meta.mediaType = ogVideo || isReel ? 'video' : 'image';
        meta.mediaCount = imageStrings.length;
        mediaFromReader = true;
      }
      break;
    }
    case 'behance': {
      const name = clean(oembed?.authorName);
      if (name) meta.author = individual(name);
      const authorURL = toURL(clean(oembed?.authorURL));
      const handle = authorURL ? pathParts(authorURL)[0] : null;
      if (handle) meta.authorHandle = handle;
      set(meta, 'text', cleanCaption(ogDescription ?? ''));
      if (titleSource == null) titleSource = oembed?.title ?? null;
      if (ogImage) imageStrings = [ogImage];
      else if (clean(oembed?.thumbnailURL)) imageStrings = [clean(oembed.thumbnailURL)];
      break;
    }
    case 'dribbble': {
      const author = parseDribbbleTitle(ogTitle).author;
      if (author) meta.author = individual(author);
      set(meta, 'text', cleanCaption(ogDescription ?? ''));
      if (ogImage) imageStrings = [ogImage];
      break;
    }
    default: {
      const pin = parsePinterestDescription(ogDescription);
      if (pin.author) meta.author = individual(pin.author);
      set(meta, 'text', pin.text);
      if (ogImage) imageStrings = [ogImage];
    }
  }

  if (meta.text != null) meta.text = decodeBasicEntities(meta.text);

  let images = [];
  const seen = new Set();
  for (const raw of imageStrings) {
    let s = String(raw).trim();
    if (s.startsWith('//')) s = 'https:' + s;
    const u = resolveURL(s, landing.href);
    if (!u || seen.has(u)) continue;
    seen.add(u);
    images.push(u);
  }
  if (!images.length && !mediaFromReader && ogImage) images = [ogImage];
  images = images.slice(0, MEDIA_CAP);
  if (!mediaFromReader && images.length) {
    meta.mediaType = ogVideo ? 'video' : 'image';
    meta.mediaCount = images.length;
  }

  const title = postTitle({ currentTitle: titleSource, handle: meta.authorHandle, authorName: meta.author?.name, text: meta.text });
  return { meta, imageURLs: images, title, isGone };
}

function set(obj, key, value) {
  if (value != null) obj[key] = value;
}
