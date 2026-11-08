/**
 * Stello on Cloudflare Workers — single Worker: static frontend (ASSETS) +
 * all /api/* endpoints + /img/* R2 image serving + daily batch cron.
 *
 * Routing is governed by wrangler.jsonc `assets.run_worker_first`:
 *   /api/*, /img/*  → this Worker first
 *   everything else → static asset, Worker only as a fallback on asset-miss
 *
 * The capture/enrich handlers are Vercel-style (req,res) functions adapted
 * via lib/adapter.js. Data + accounts live in D1 (env.DB, schema applied on
 * first request by lib/schema.js), image bytes in R2 (env.BUCKET).
 */
import { Hono } from 'hono';
import { route } from './lib/adapter.js';

import capture from './routes/capture.js';
import captureBulk from './routes/capture-bulk.js';
import enrich from './routes/enrich.js';
import reenrich from './routes/reenrich.js';
import reprocess from './routes/reprocess.js';
import uploadImage from './routes/upload-image.js';
import itemUpdate from './routes/item-update.js';
import itemDelete from './routes/item-delete.js';
import config from './routes/config.js';
import batchStatus from './routes/batch-status.js';
import mountAuth from './routes/auth.js';
import mountData from './routes/data.js';
import { ensureSchema } from './lib/schema.js';
import auth from './lib/auth.js';
import syncRoutes from './routes/sync.js';
import appleNative from './routes/auth-apple-native.js';
import { runDailySync } from './lib/sync-cron.js';
import { mergeDuplicates } from './lib/dedupe.js';
import processBatchesMod from './routes/process-batches.js';
import classifyRoute from './routes/classify.js';

const app = new Hono();

// Apply the D1 schema once per isolate before any API work.
app.use('/api/*', async (c, next) => {
  await ensureSchema(c.env);
  await next();
});

mountAuth(app);
mountData(app);

// Apple app <-> web copy sync (docs/plans/apple-web-sync.md).
app.post('/api/auth/apple/native', appleNative);
app.route('/api/sync', syncRoutes({ requireUser: auth.requireUser }));

// Page readers for the Apple apps: they send the HTML they fetched, the Worker
// answers with the kind + typed metadata (src/lib/readers/).
app.post('/api/classify', classifyRoute({ requireUser: auth.requireUser }));

// Merge items saved more than once (same link), for the signed-in user only.
//   GET  /api/me/duplicates   → the plan (nothing changes)
//   POST /api/me/duplicates   → apply it (losers are soft-deleted, 30-day restore)
app.get('/api/me/duplicates', async (c) => {
  const userId = await auth.requireUser(c);
  if (!userId) return c.json({ error: 'Not signed in' }, 401);
  return c.json(await mergeDuplicates(c.env.DB, userId));
});
app.post('/api/me/duplicates', async (c) => {
  const userId = await auth.requireUser(c);
  if (!userId) return c.json({ error: 'Not signed in' }, 401);
  return c.json(await mergeDuplicates(c.env.DB, userId, { apply: true }));
});

app.onError((err, c) => {
  console.error('worker error', c.req.path, err && err.stack || err);
  return c.json({ error: 'Server error', detail: String(err && err.message || err) }, 500);
});

// --- API routes (app.all → the handler does its own method + CORS guard) ---
app.all('/api/capture', route(capture));
app.all('/api/capture-bulk', route(captureBulk));
app.all('/api/enrich', route(enrich));
app.all('/api/reenrich', route(reenrich));
app.all('/api/reprocess', route(reprocess));
app.all('/api/upload-image', route(uploadImage));
app.all('/api/item-update', route(itemUpdate));
app.all('/api/item-delete', route(itemDelete));
app.all('/api/config', route(config));
app.all('/api/batch-status', route(batchStatus));
// NOTE: /api/cron/process-batches is intentionally NOT an HTTP route — it
// drains batches with the admin client and runs only via scheduled() below.

// Guarded manual enrichment drain — clears a deep 'text_done' backlog on
// demand instead of waiting days for the daily cron. Gated by ADMIN_TOKEN as
// a bearer (unset = off). `?limit=N` (1–75) bounds how many items one invocation processes.
app.post('/api/cron/drain-enrichment', async (c) => {
  const auth = c.req.header('authorization') || '';
  const want = c.env.ADMIN_TOKEN;
  if (!want || auth !== `Bearer ${want}`) {
    return c.json({ error: 'unauthorized' }, 401);
  }
  const limit = Math.min(Math.max(parseInt(c.req.query('limit') || '25', 10) || 25, 1), 75);
  const result = await processBatchesMod.drainEnrichment(c.env, { limit });
  return c.json(result);
});

// --- Image serving from R2 (zero egress; replaces Supabase public URLs) ---
app.get('/img/*', async (c) => {
  const key = decodeURIComponent(new URL(c.req.url).pathname.slice('/img/'.length));
  if (!key) return c.notFound();
  const obj = await c.env.BUCKET.get(key);
  if (!obj || !obj.body) return c.notFound();
  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set('etag', obj.httpEtag);
  headers.set('cache-control', 'public, max-age=31536000, immutable');
  return new Response(obj.body, { headers });
});

// --- Fallback: anything that reached the Worker but isn't ours → static assets.
// (Only hit for non-asset paths under run_worker_first's fallthrough.)
app.all('*', (c) => c.env.ASSETS.fetch(c.req.raw));

export default {
  fetch: (request, env, ctx) => app.fetch(request, env, ctx),
  async scheduled(event, env, ctx) {
    await ensureSchema(env);
    // 30-day purge of deleted items + daily library snapshot to R2.
    ctx.waitUntil(runDailySync(env));
    ctx.waitUntil(processBatchesMod.processBatches(env));
    // Steady backstop: heal a small batch of stuck-'text_done' items each run
    // so the queue drains server-side even if nobody opens the app.
    ctx.waitUntil(processBatchesMod.drainEnrichment(env, { limit: 20 }));
  },
};
