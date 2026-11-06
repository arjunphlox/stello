/**
 * Stello on Cloudflare Workers — serves the static web app (ASSETS) and the
 * legacy item images in R2 at /img/*.
 *
 * Stello's data lives in the user's private iCloud database (the Mac/iPhone
 * apps' SwiftData + CloudKit store). The web app talks to iCloud directly
 * through CloudKit JS with Apple ID sign-in, so this Worker holds no data,
 * no logins and no API.
 *
 * /img/* stays while the Supabase-era library is imported into iCloud: the
 * export file references images by these paths. Remove it (and the R2
 * binding) once the import is done.
 */
import { Hono } from 'hono';

const app = new Hono();

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

// Anything else that reached the Worker → static assets.
app.all('*', (c) => c.env.ASSETS.fetch(c.req.raw));

export default {
  fetch: (request, env, ctx) => app.fetch(request, env, ctx),
};
