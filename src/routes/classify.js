/**
 * POST /api/classify: the one copy of the page readers, for the Apple apps.
 *
 * The apps fetch the page on the device (device IP, so bot walls behave as before)
 * and send the HTML; the Worker answers with the kind and typed metadata, so the
 * Swift readers can go. Web saves use the same pipeline through capture.
 *
 * Body: one page `{ url, html?, status?, finalURL?, collectionLabels?, asKind?, kindOnly? }`, or
 * `{ pages: [...] }` up to CLASSIFY_BATCH_MAX (default 1: on the Workers Free plan a
 * request has 10 ms of CPU, and a long page alone can use most of it).
 * Answer: the readPage result, or `{ results: [...] }` for `pages`. A page that fails
 * comes back as `{ url, error }` so the app keeps its own fallback.
 *
 * `html: ""` means the app couldn't read the page: the URL and labels decide, and the
 * Worker never fetches it itself. `asKind` reads an already-typed item as that kind
 * (Enrich), `kindOnly` skips the readers (import). The apps send the body raw-deflated
 * with `X-Stello-Encoding: deflate-raw`, which cuts an import's upload several times over.
 */
import { readPage, makeNet, MAX_HTML_BYTES, READ_AS_KINDS } from '../lib/readers/pipeline.js';

export const MAX_LABELS = 50;

export function batchMax(env) {
  const n = parseInt(env?.CLASSIFY_BATCH_MAX ?? '1', 10);
  return Number.isFinite(n) && n >= 1 ? Math.min(n, 20) : 1;
}

/** Validates one page from the request body; returns readPage input or an error string. */
export function pageInput(p) {
  if (!p || typeof p !== 'object') return 'page must be an object';
  if (typeof p.url !== 'string' || !/^https?:\/\//i.test(p.url)) return 'url must be an http(s) link';
  if (p.html != null && typeof p.html !== 'string') return 'html must be a string';
  const labels = Array.isArray(p.collectionLabels) ? p.collectionLabels.filter((l) => typeof l === 'string').slice(0, MAX_LABELS) : [];
  return {
    url: p.url,
    html: p.html ? p.html.slice(0, MAX_HTML_BYTES) : null,
    status: Number.isInteger(p.status) ? p.status : null,
    finalURL: typeof p.finalURL === 'string' ? p.finalURL : null,
    collectionLabels: labels,
    // HTML (or "" for an unreadable page) from the app: never refetch the page from
    // Cloudflare's IP.
    fetchPage: p.html == null,
    asKind: READ_AS_KINDS.has(p.asKind) ? p.asKind : null,
    kindOnly: p.kindOnly === true,
  };
}

export async function classifyPages(body, env, { net = makeNet(), now = new Date() } = {}) {
  const many = Array.isArray(body?.pages);
  const pages = many ? body.pages : [body];
  if (!pages.length) return { status: 400, body: { error: 'No pages' } };
  const max = batchMax(env);
  if (pages.length > max) return { status: 413, body: { error: `At most ${max} page(s) per request`, max } };

  const results = [];
  for (const p of pages) {
    const input = pageInput(p);
    if (typeof input === 'string') { results.push({ url: p?.url ?? null, error: input }); continue; }
    try {
      results.push(await readPage({ ...input, net, now }));
    } catch (err) {
      results.push({ url: input.url, error: String(err?.message || err) });
    }
  }
  if (many) return { status: 200, body: { results } };
  const [one] = results;
  return { status: one.error ? 400 : 200, body: one };
}

/** JSON body, raw-deflated when the app says so (`X-Stello-Encoding: deflate-raw`). */
export async function readBody(request) {
  if (request.headers.get('X-Stello-Encoding') === 'deflate-raw') {
    const stream = request.body.pipeThrough(new DecompressionStream('deflate-raw'));
    return JSON.parse(await new Response(stream).text());
  }
  return request.json();
}

/** Hono handler factory (auth injected so tests can run without D1). */
export default function classifyRoute({ requireUser }) {
  return async (c) => {
    const userId = await requireUser(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    let body;
    try { body = await readBody(c.req.raw); } catch { return c.json({ error: 'Body must be JSON' }, 400); }
    const out = await classifyPages(body, c.env);
    return c.json(out.body, out.status);
  };
}
