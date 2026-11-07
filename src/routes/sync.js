/**
 * /api/sync/* — the Apple app's bridge to the web copy. See docs/plans/apple-web-sync.md.
 *
 *   GET  /api/sync/pull?since=N&limit=500   rows with seq > N (tombstones included)
 *   POST /api/sync/push   { changes: [{ id, fields, clock, full? }] }  (≤100)
 *   PUT  /api/sync/image  raw bytes (Content-Type image/*) → { path: "/img/<key>" }
 *   GET  /api/sync/status → { cursor }
 *
 * Mounted with the account helper from step 1:
 *   app.route('/api/sync', syncRoutes({ requireUser }))
 * `requireUser(c)` returns the Stello user id for a web session or a device token,
 * or a Response (401) to send back.
 */
import { Hono } from 'hono';
import { applyChanges, pullChanges, headSeq, SyncError } from '../lib/sync.js';

const MAX_IMAGE_BYTES = 15 * 1024 * 1024;
const IMAGE_TYPES = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/heic': 'heic',
  'image/avif': 'avif',
};

export default function syncRoutes({ requireUser }) {
  const app = new Hono();

  app.use('*', async (c, next) => {
    const user = await requireUser(c);
    if (user instanceof Response) return user;
    if (!user) return c.json({ error: 'unauthorized' }, 401);
    c.set('userId', typeof user === 'string' ? user : user.id);
    await next();
  });

  app.onError((err, c) => {
    if (err instanceof SyncError) return c.json({ error: err.message }, err.status);
    console.error('sync error', err);
    return c.json({ error: 'sync failed' }, 500);
  });

  app.get('/status', async (c) => c.json({ cursor: await headSeq(c.env.DB, c.get('userId')) }));

  app.get('/pull', async (c) => {
    const out = await pullChanges(c.env.DB, c.get('userId'), c.req.query('since'), c.req.query('limit'));
    return c.json(out);
  });

  app.post('/push', async (c) => {
    let body;
    try { body = await c.req.json(); } catch { throw new SyncError(400, 'invalid JSON'); }
    const out = await applyChanges(c.env.DB, c.get('userId'), body?.changes);
    return c.json(out);
  });

  // Content-addressed, so re-sending the same bytes (retries, first link-up from a
  // second device) costs one HEAD and no storage.
  app.put('/image', async (c) => {
    const type = (c.req.header('content-type') || '').split(';')[0].trim().toLowerCase();
    const ext = IMAGE_TYPES[type];
    if (!ext) throw new SyncError(415, 'unsupported image type');
    const bytes = await c.req.arrayBuffer();
    if (!bytes.byteLength) throw new SyncError(400, 'empty body');
    if (bytes.byteLength > MAX_IMAGE_BYTES) throw new SyncError(413, 'image too large');
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
    const key = `${c.get('userId')}/sync/${hex}.${ext}`;
    const existing = await c.env.BUCKET.head(key);
    if (!existing) await c.env.BUCKET.put(key, bytes, { httpMetadata: { contentType: type } });
    return c.json({ path: `/img/${key}`, created: !existing });
  });

  return app;
}
