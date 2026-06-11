/**
 * Stello on Cloudflare Workers — single Worker: static frontend (ASSETS) +
 * all /api/* endpoints + /img/* R2 image serving + daily batch cron.
 *
 * Routing is governed by wrangler.jsonc `assets.run_worker_first`:
 *   /api/*, /img/*  → this Worker first
 *   everything else → static asset, Worker only as a fallback on asset-miss
 *
 * The /api/* handlers are Vercel-style (req,res) functions adapted via
 * lib/adapter.js. Supabase stays the DB + auth; only compute + image bytes
 * moved off Vercel.
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
import authCallback from './routes/auth-callback.js';
import processBatchesMod from './routes/process-batches.js';

const app = new Hono();

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
app.all('/api/auth-callback', route(authCallback));
// NOTE: /api/cron/process-batches is intentionally NOT an HTTP route — it
// drains batches with the admin client and runs only via scheduled() below.

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
    ctx.waitUntil(processBatchesMod.processBatches(env));
  },
};
