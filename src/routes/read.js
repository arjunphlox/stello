/**
 * The stateless engine endpoints (docs/plans/folder-engine.md, phase 1).
 * Nothing here reads or writes D1 or R2: the caller keeps the result in its folder.
 *
 *   POST /api/read          { url, html?, status?, finalURL?, collectionLabels? } → engine.read()
 *                           With html the Worker never fetches the page (the app's IP did).
 *   GET  /api/fetch-image?url=<https image>  → the image bytes, for web apps that can't
 *                           fetch cross-origin images into a folder themselves.
 *
 * Signed-in only for now (same device tokens as /api/classify); phase 4 swaps this
 * for a per-install key + rate limit when accounts go.
 */
import { read, MAX_HTML_BYTES } from '../../engine/index.js';

export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_LABELS = 50;

/** Validates a /api/read body; returns engine input or an error string. */
export function readInput(b) {
  if (!b || typeof b !== 'object') return 'body must be an object';
  if (typeof b.url !== 'string' || !/^https?:\/\//i.test(b.url)) return 'url must be an http(s) link';
  if (b.html != null && typeof b.html !== 'string') return 'html must be a string';
  return {
    url: b.url,
    html: b.html != null ? b.html.slice(0, MAX_HTML_BYTES) : null,
    status: Number.isInteger(b.status) ? b.status : null,
    finalURL: typeof b.finalURL === 'string' ? b.finalURL : null,
    collectionLabels: Array.isArray(b.collectionLabels) ? b.collectionLabels.filter((l) => typeof l === 'string').slice(0, MAX_LABELS) : [],
    fetchPage: b.html == null,
  };
}

/** True for URLs the image proxy must not fetch (non-https, local or private hosts). */
export function blockedImageURL(raw) {
  let u;
  try { u = new URL(raw); } catch { return true; }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return true;
  if (u.username || u.password) return true;
  const h = u.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (!h.includes('.') && !h.includes(':')) return true; // localhost, intranet names
  if (/\.(local|localhost|internal|lan|home|arpa)$/.test(h)) return true;
  const v4 = /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(h);
  if (v4) {
    const [a, b] = [+v4[1], +v4[2]];
    if (a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127) || a >= 224) return true;
  }
  if (h.includes(':') && (h === '::1' || h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80') || h === '::')) return true;
  return false;
}

/** Fetch an image for the caller. Returns a Response. */
export async function fetchImage(raw, { fetchImpl = globalThis.fetch } = {}) {
  if (!raw || blockedImageURL(raw)) return json({ error: 'url must be a public http(s) image' }, 400);
  let r;
  try {
    r = await fetchImpl(raw, { redirect: 'follow', headers: { Accept: 'image/avif,image/webp,image/*;q=0.8', 'User-Agent': 'Stello/1.0 (image fetch)' } });
  } catch {
    return json({ error: 'fetch failed' }, 502);
  }
  if (r.url && blockedImageURL(r.url)) return json({ error: 'redirected to a blocked host' }, 400);
  if (!r.ok) return json({ error: `upstream ${r.status}` }, r.status === 404 || r.status === 410 ? 404 : 502);
  const type = (r.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  if (!type.startsWith('image/') || type === 'image/svg+xml') return json({ error: 'not an image' }, 415);
  const len = Number(r.headers.get('content-length') || 0);
  if (len > MAX_IMAGE_BYTES) return json({ error: 'image too large' }, 413);
  const buf = await r.arrayBuffer();
  if (buf.byteLength > MAX_IMAGE_BYTES) return json({ error: 'image too large' }, 413);
  return new Response(buf, { status: 200, headers: { 'content-type': type, 'cache-control': 'private, max-age=86400', 'x-content-type-options': 'nosniff' } });
}

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

/** Mounts both routes (auth injected so tests can run without D1). */
export function mountRead(app, { requireUser }) {
  app.post('/api/read', async (c) => {
    if (!(await requireUser(c))) return c.json({ error: 'Not signed in' }, 401);
    let body;
    try { body = await c.req.json(); } catch { return c.json({ error: 'Body must be JSON' }, 400); }
    const input = readInput(body);
    if (typeof input === 'string') return c.json({ error: input }, 400);
    try {
      return c.json(await read(input));
    } catch (err) {
      return c.json({ url: input.url, error: String(err?.message || err) }, 400);
    }
  });
  app.get('/api/fetch-image', async (c) => {
    if (!(await requireUser(c))) return c.json({ error: 'Not signed in' }, 401);
    return fetchImage(c.req.query('url'));
  });
}
