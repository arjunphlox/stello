/**
 * Item reads for the web app (the browser used to query Supabase directly)
 * and the one-off Supabase → D1 import.
 *
 *   GET  /api/items?offset=0&limit=1000   newest first, the signed-in user's items
 *   GET  /api/item?slug=…                 one item
 *   POST /api/item-dims { slug, images }  image width/height backfill from the grid
 *
 *   POST /api/admin/import-supabase?table=items&offset=0&limit=250
 *   POST /api/admin/login-link { email }  → one-time sign-in URL (30 min)
 *     Both gated by `Authorization: Bearer <ADMIN_TOKEN>` (falls back to the
 *     Supabase service-role key while Supabase still exists).
 */
const db = require('../lib/db');
const auth = require('../lib/auth');

async function signedIn(c) {
  return auth.userFromHeaders(c.env, (n) => c.req.header(n));
}

function isAdmin(c) {
  const want = c.env.ADMIN_TOKEN || c.env.SUPABASE_SERVICE_ROLE_KEY;
  return !!want && c.req.header('authorization') === `Bearer ${want}`;
}

// ------------------------------------------------------------ Supabase import

function toMs(v) {
  const t = v ? Date.parse(v) : NaN;
  return Number.isFinite(t) ? t : Date.now();
}

async function supa(env, path) {
  const base = String(env.SUPABASE_URL || '').replace(/\/rest\/v1\/?$/, '').replace(/\/$/, '');
  const r = await fetch(`${base}${path}`, {
    headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
  });
  if (!r.ok) throw new Error(`Supabase ${path} → ${r.status} ${await r.text()}`);
  return r.json();
}

const ITEM_COLS = [
  'id', 'user_id', 'slug', 'title', 'source_url', 'domain', 'author', 'summary', 'body_markdown',
  'og_image_path', 'status', 'location', 'needs_review', 'link_last_checked', 'added_at',
  'analyzed_at', 'enrichment_status', 'tags', 'images', 'snippets', 'enrichment_candidates',
  'enrichment_error',
];

/**
 * Users first (only those who own items), then items page by page. Upserts by
 * id, so a re-run refreshes rows and never duplicates. Item ids, user ids,
 * slugs and /img/ paths are kept as-is, so R2 images keep working.
 */
async function importSupabase(env, { table, offset, limit }) {
  const raw = db.admin(env, { raw: true, includeDeleted: true });

  if (table === 'users') {
    const owners = new Set();
    for (let from = 0; ; from += 1000) {
      const page = await supa(env, `/rest/v1/items?select=user_id&order=id&offset=${from}&limit=1000`);
      page.forEach(r => owners.add(r.user_id));
      if (page.length < 1000) break;
    }
    const { users = [] } = await supa(env, '/auth/v1/admin/users?per_page=1000');
    const profiles = await supa(env, '/rest/v1/profiles?select=id,display_name');
    const names = Object.fromEntries(profiles.map(p => [p.id, p.display_name]));
    const done = [];
    for (const u of users.filter(u => owners.has(u.id))) {
      const email = u.email ? u.email.toLowerCase() : null;
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO users (id, email, display_name, created_at) VALUES (?, ?, ?, ?)
           ON CONFLICT (id) DO UPDATE SET email = excluded.email, display_name = COALESCE(users.display_name, excluded.display_name)`
        ).bind(u.id, email, names[u.id] || email, toMs(u.created_at)),
        ...(email ? [env.DB.prepare(
          'INSERT OR IGNORE INTO identities (provider, subject, user_id, email, created_at) VALUES (?, ?, ?, ?, ?)'
        ).bind('email', email, u.id, email, Date.now())] : []),
      ]);
      done.push({ id: u.id, email });
    }
    const settings = await supa(env, '/rest/v1/user_settings?select=user_id,setting_key,setting_value');
    const kept = settings.filter(s => owners.has(s.user_id));
    if (kept.length) {
      const { error } = await raw.from('user_settings').upsert(kept, { onConflict: 'user_id,setting_key' });
      if (error) throw new Error(error.message);
    }
    return { table, users: done, settings: kept.length };
  }

  if (table === 'items') {
    const rows = await supa(env,
      `/rest/v1/items?select=${ITEM_COLS.join(',')},updated_at&order=added_at.asc,id.asc&offset=${offset}&limit=${limit}`);
    const prepared = rows.map(r => {
      const out = {};
      for (const c of ITEM_COLS) out[c] = r[c];
      const updated = toMs(r.updated_at);
      out.added_at = r.added_at || new Date(updated).toISOString();
      out.title = r.title || '';
      out.status = r.status || 'active';
      out.enrichment_status = r.enrichment_status || 'pending';
      out.needs_review = r.needs_review !== false;
      out.tags = r.tags ?? [];
      out.images = r.images ?? [];
      out.snippets = r.snippets ?? [];
      out.enrichment_candidates = r.enrichment_candidates ?? {};
      out.updated_at = updated;
      out.seq = 0;   // set below
      out.field_clock = Object.fromEntries(ITEM_COLS.filter(c => !['id', 'user_id'].includes(c)).map(c => [c, updated]));
      return out;
    });
    // One seq bump per page per user; every row of the page gets that seq.
    const byUser = {};
    for (const r of prepared) (byUser[r.user_id] ||= []).push(r);
    let written = 0;
    for (const [uid, list] of Object.entries(byUser)) {
      const row = await env.DB.prepare('UPDATE users SET sync_seq = sync_seq + 1 WHERE id = ? RETURNING sync_seq').bind(uid).first();
      if (!row) throw new Error(`items for unknown user ${uid}: run table=users first`);
      list.forEach(r => { r.seq = row.sync_seq; });
      for (let i = 0; i < list.length; i += 50) {
        const { error } = await raw.from('items').upsert(list.slice(i, i + 50), { onConflict: 'id' });
        if (error) throw new Error(error.message);
        written += Math.min(50, list.length - i);
      }
    }
    return { table, offset, fetched: rows.length, written, done: rows.length < limit };
  }

  throw new Error('table must be users or items');
}

module.exports = function mountData(app) {
  app.get('/api/items', async (c) => {
    const user = await signedIn(c);
    if (!user) return c.json({ error: 'Not signed in' }, 401);
    const offset = Math.max(0, parseInt(c.req.query('offset') || '0', 10) || 0);
    const limit = Math.min(Math.max(parseInt(c.req.query('limit') || '1000', 10) || 1000, 1), 2000);
    const { data, error } = await db.forUser(c.env, user.id).from('items').select('*')
      .order('added_at', { ascending: false }).order('id', { ascending: true }).range(offset, offset + limit - 1);
    if (error) return c.json({ error: error.message }, 500);
    return c.json({ items: data });
  });

  app.get('/api/item', async (c) => {
    const user = await signedIn(c);
    if (!user) return c.json({ error: 'Not signed in' }, 401);
    const slug = c.req.query('slug');
    if (!slug) return c.json({ error: 'Missing slug' }, 400);
    const { data } = await db.forUser(c.env, user.id).from('items').select('*').eq('slug', slug).maybeSingle();
    if (!data) return c.json({ error: 'Item not found' }, 404);
    return c.json({ item: data });
  });

  app.post('/api/item-dims', async (c) => {
    const user = await signedIn(c);
    if (!user) return c.json({ error: 'Not signed in' }, 401);
    const { slug, images } = await c.req.json().catch(() => ({}));
    if (!slug || !Array.isArray(images)) return c.json({ error: 'Missing slug or images' }, 400);
    const { error } = await db.forUser(c.env, user.id).from('items').update({ images }).eq('slug', slug);
    if (error) return c.json({ error: error.message }, 500);
    return c.json({ ok: true });
  });

  app.post('/api/admin/import-supabase', async (c) => {
    if (!isAdmin(c)) return c.json({ error: 'unauthorized' }, 401);
    const table = c.req.query('table') || 'items';
    const offset = Math.max(0, parseInt(c.req.query('offset') || '0', 10) || 0);
    const limit = Math.min(Math.max(parseInt(c.req.query('limit') || '250', 10) || 250, 1), 1000);
    try {
      return c.json(await importSupabase(c.env, { table, offset, limit }));
    } catch (err) {
      return c.json({ error: err.message }, 500);
    }
  });

  app.post('/api/admin/login-link', async (c) => {
    if (!isAdmin(c)) return c.json({ error: 'unauthorized' }, 401);
    const { email } = await c.req.json().catch(() => ({}));
    const user = await auth.findUserByEmail(c.env, email);
    if (!user) return c.json({ error: 'no such user' }, 404);
    const token = auth.randomToken();
    await c.env.DB.prepare(
      "INSERT INTO auth_states (state, nonce, mode, user_id, created_at) VALUES (?, '', 'magic', ?, ?)"
    ).bind(await auth.sha256(token), user.id, Date.now()).run();
    return c.json({ url: `${new URL(c.req.url).origin}/api/auth/magic?token=${token}`, expires_in_min: 30 });
  });

  app.get('/api/admin/stats', async (c) => {
    if (!isAdmin(c)) return c.json({ error: 'unauthorized' }, 401);
    const r = await c.env.DB.prepare(
      `SELECT (SELECT COUNT(*) FROM users) AS users,
              (SELECT COUNT(*) FROM items) AS items,
              (SELECT COUNT(*) FROM items WHERE deleted_at IS NOT NULL) AS deleted,
              (SELECT COUNT(*) FROM identities WHERE provider = 'apple') AS apple_links`
    ).first();
    // Sign-in diagnostics: unfinished Apple sign-ins (callback never arrived),
    // recent sessions and identity links, newest first. No tokens returned.
    const [{ results: pending }, { results: sessions }, { results: links }] = await c.env.DB.batch([
      c.env.DB.prepare("SELECT mode, created_at FROM auth_states WHERE mode != 'magic' ORDER BY created_at DESC LIMIT 10"),
      c.env.DB.prepare('SELECT kind, created_at FROM sessions ORDER BY created_at DESC LIMIT 10'),
      c.env.DB.prepare('SELECT provider, created_at FROM identities ORDER BY created_at DESC LIMIT 10'),
    ]);
    const iso = (rows) => rows.map(x => ({ ...x, created_at: new Date(x.created_at).toISOString() }));
    return c.json({ ...r, pending_apple_states: iso(pending), recent_sessions: iso(sessions), identities: iso(links) });
  });
};
