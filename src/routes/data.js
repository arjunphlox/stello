/**
 * Item reads for the web app, plus admin helpers.
 *
 *   GET  /api/items?offset=0&limit=1000   newest first, the signed-in user's items
 *   GET  /api/item?slug=…                 one item
 *   POST /api/item-dims { slug, images }  image width/height backfill from the grid
 *
 *   POST /api/admin/login-link { email }  → one-time sign-in URL (30 min)
 *   GET  /api/admin/stats                 counts + sign-in diagnostics
 *     Both gated by `Authorization: Bearer <ADMIN_TOKEN>` (a Worker secret;
 *     unset = admin routes are off).
 */
const db = require('../lib/db');
const auth = require('../lib/auth');

async function signedIn(c) {
  return auth.userFromHeaders(c.env, (n) => c.req.header(n));
}

function isAdmin(c) {
  const want = c.env.ADMIN_TOKEN;
  return !!want && c.req.header('authorization') === `Bearer ${want}`;
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
              (SELECT COUNT(*) FROM identities WHERE provider = 'apple') AS apple_links,
              (SELECT COUNT(*) FROM items WHERE deleted_at IS NULL) AS live_items,
              (SELECT COUNT(*) FROM items WHERE updated_at > ?) AS updated_last_15m,
              (SELECT MAX(sync_seq) FROM users) AS max_sync_seq`
    ).bind(Date.now() - 15 * 60 * 1000).first();
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
