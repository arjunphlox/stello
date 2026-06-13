const { createClient } = require('@supabase/supabase-js');
const crypto = require('crypto');
const {
  runRuleEnrichment, mineSubjectKeywords, formatTagFor,
  STOP_WORDS_EXT, PLATFORM_NOISE,
} = require('./enrich-rules');
const { ensureWebp } = require('./images');

/**
 * Env is per-request on Workers (no process.env at module scope). Every
 * client factory takes the Worker `env`; handlers reach it via `req.env`
 * (attached by the Hono adapter) or pass it explicitly (cron/scheduled).
 */

/** Admin client (bypasses RLS — for cron jobs and migrations) */
function getAdminClient(env) {
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
}

/** User-scoped client from a request's auth header */
function getUserClient(req) {
  const env = req.env;
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

/** User-scoped client from a raw bearer token (used by enrichCore + waitUntil) */
function userClientFromToken(env, token) {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

/** Extract and verify user from request. Returns { user, error, status, client }. */
async function authenticateRequest(req) {
  const env = req.env;
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  if (!token) {
    return { user: null, error: 'Missing authorization header', status: 401 };
  }
  const client = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: { user }, error } = await client.auth.getUser(token);
  if (error || !user) {
    return { user: null, error: 'Invalid or expired token', status: 401 };
  }
  return { user, error: null, status: 200, client };
}

/** Standard JSON response with CORS headers */
function jsonResponse(res, status, data) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Content-Type', 'application/json');
  return res.status(status).json(data);
}

/** Handle CORS preflight. Returns true if handled. */
function handleCors(req, res) {
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.status(204).end();
    return true;
  }
  return false;
}

/** Generate a URL-safe slug from a title */
function generateSlug(title) {
  let slug = (title || 'untitled').toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .slice(0, 50);
  const hash = crypto.createHash('md5')
    .update(title + Date.now())
    .digest('hex')
    .slice(0, 6);
  return `${slug}-${hash}`;
}

/** Normalize URL for duplicate comparison */
function normalizeUrl(url) {
  return url
    .replace(/\/+$/, '')
    .replace(/\?.*$/, '')
    .replace(/#.*$/, '')
    .replace('http://', 'https://')
    .replace('www.', '')
    .toLowerCase();
}

const NAMED_ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ',
  copy: '©', reg: '®', trade: '™',
  mdash: '—', ndash: '–', hellip: '…',
  ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’',
  middot: '·',
};
function decodeHtmlEntities(str) {
  if (typeof str !== 'string' || !str.includes('&')) return str;
  return str.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, ref) => {
    if (ref[0] === '#') {
      const code = ref[1] === 'x' || ref[1] === 'X'
        ? parseInt(ref.slice(2), 16)
        : parseInt(ref.slice(1), 10);
      if (Number.isFinite(code) && code > 0) {
        try { return String.fromCodePoint(code); } catch { return m; }
      }
      return m;
    }
    const name = ref.toLowerCase();
    return Object.prototype.hasOwnProperty.call(NAMED_ENTITIES, name)
      ? NAMED_ENTITIES[name]
      : m;
  });
}

/** Fetch OG metadata from a URL */
async function fetchOGMetadata(url) {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);

    const resp = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      },
      signal: controller.signal,
      redirect: 'follow',
    });
    clearTimeout(timeout);

    const reader = resp.body.getReader();
    const chunks = [];
    let totalSize = 0;
    while (totalSize < 50000) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      totalSize += value.length;
    }
    reader.cancel();

    const html = Buffer.concat(chunks).toString('utf-8');
    const meta = {};

    const ogPattern1 = /<meta\s+(?:property|name)=["']og:(\w+)["']\s+content=["']([^"']*)["']/gi;
    const ogPattern2 = /<meta\s+content=["']([^"']*)["'].*?(?:property|name)=["']og:(\w+)["']/gi;

    let match;
    while ((match = ogPattern1.exec(html)) !== null) {
      meta[`og:${match[1]}`] = decodeHtmlEntities(match[2]);
    }
    while ((match = ogPattern2.exec(html)) !== null) {
      meta[`og:${match[2]}`] = decodeHtmlEntities(match[1]);
    }

    const titleMatch = html.match(/<title[^>]*>([^<]+)<\/title>/i);
    if (titleMatch) meta.title = decodeHtmlEntities(titleMatch[1].trim());

    const descMatch = html.match(/<meta\s+name=["']description["']\s+content=["']([^"']*)["']/i);
    if (descMatch) meta.description = decodeHtmlEntities(descMatch[1]);

    meta._status = 'fetched';
    return meta;
  } catch (err) {
    console.warn('fetchOGMetadata failed', url, err.message);
    return { _status: 'error', _error: err.message };
  }
}

/**
 * Download an image from `imageUrl` and return `{ buffer, ext, mime, width,
 * height }` as WebP. Every image entering Stello is normalized to WebP at
 * ingest (Images binding) so the bucket is single-format. Caller uploads the
 * returned buffer to R2 via storage.put(). Returns null on any failure.
 */
async function downloadImage(env, imageUrl) {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);

    const resp = await fetch(imageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
        'Accept': 'image/webp,image/*,*/*',
      },
      signal: controller.signal,
      redirect: 'follow',
    });
    clearTimeout(timeout);

    if (!resp.ok) {
      console.warn('downloadImage: non-ok response', imageUrl, resp.status);
      return null;
    }

    const sourceContentType = resp.headers.get('content-type') || null;
    const raw = Buffer.from(await resp.arrayBuffer());
    if (raw.length < 500) {
      console.warn('downloadImage: buffer too small', imageUrl, raw.length);
      return null;
    }

    try {
      // Cap at a sane max width — thumbs are 56px, panel a few hundred.
      // ensureWebp no longer throws on a failed transform; it falls back to
      // the original bytes (carrying transformError) so we never drop a
      // successfully-fetched image.
      return await ensureWebp(env, raw, { maxWidth: 2400, sourceContentType });
    } catch (err) {
      console.warn('downloadImage: webp conversion failed', imageUrl, err.message);
      return null;
    }
  } catch {
    return null;
  }
}

/** Build the capture-time tag set (format + domain + mined subjects + rules). */
function generateTagsFromMetadata({ title, domain, description, sourceUrl }) {
  const tags = [];
  const existingNames = new Set();
  const push = (t) => {
    if (!t || !t.tag || existingNames.has(t.tag)) return;
    existingNames.add(t.tag);
    tags.push(t);
  };

  push(formatTagFor({ sourceUrl, domain }));
  if (domain) {
    push({ tag: domain.replace(/^www\./, ''), category: 'domain', weight: 0.6 });
  }

  for (const kw of mineSubjectKeywords(title, {
    minLen: 3, limit: 5,
    weightStart: 0.8, weightStep: 0.1, weightFloor: 0.5,
    extraStops: new Set(existingNames),
  })) push(kw);

  for (const kw of mineSubjectKeywords(description, {
    minLen: 4, limit: 3,
    weightStart: 0.5, weightStep: 0, weightFloor: 0.5,
    extraStops: new Set([...existingNames, ...STOP_WORDS_EXT, ...PLATFORM_NOISE]),
  })) push(kw);

  const ruleText = [title, description].filter(Boolean).join(' ');
  for (const t of runRuleEnrichment(ruleText, existingNames, { domain })) push(t);

  return tags
    .sort((a, b) => (b.weight || 0) - (a.weight || 0))
    .slice(0, 12);
}

/** Extract domain from URL */
function extractDomain(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return null;
  }
}

module.exports = {
  getAdminClient,
  getUserClient,
  userClientFromToken,
  authenticateRequest,
  jsonResponse,
  handleCors,
  generateSlug,
  normalizeUrl,
  decodeHtmlEntities,
  fetchOGMetadata,
  downloadImage,
  generateTagsFromMetadata,
  extractDomain,
};
