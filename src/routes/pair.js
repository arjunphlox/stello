/**
 * Pair a plugin with a Stello account, no password typed into the plugin.
 *
 *   POST /api/pair/start  { label? }       → { code, poll, url, expires_in }   (no sign-in)
 *   GET  /api/pair/info?code=              → { label }                         (signed in)
 *   POST /api/pair/approve  { code }       → { ok }                            (signed in)
 *   POST /api/pair/poll  { code, poll }    → { pending } | { token } | 410
 *
 * The plugin shows the code and opens /pair.html?code=…; the signed-in user
 * approves it there; the plugin's next poll receives a device token (the same
 * kind the Apple apps hold, 1 year) exactly once. Codes live 10 minutes.
 */
import auth from '../lib/auth.js';

const TTL_MS = 10 * 60 * 1000;
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

function makeCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const chars = [...bytes].map((b) => ALPHABET[b % ALPHABET.length]).join('');
  return `${chars.slice(0, 4)}-${chars.slice(4)}`;
}
const cleanCode = (v) => String(v || '').toUpperCase().replace(/[^A-Z0-9]/g, '').replace(/^(.{4})(.{4})$/, '$1-$2');
const cleanLabel = (v) => (String(v || '').trim().slice(0, 60) || 'Figma plugin');

export default function mountPair(app) {
  app.post('/api/pair/start', async (c) => {
    const { label } = await c.req.json().catch(() => ({}));
    const now = Date.now();
    const poll = auth.randomToken(24);
    const code = makeCode();
    await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM device_pairings WHERE created_at < ?').bind(now - TTL_MS),
      c.env.DB.prepare('INSERT INTO device_pairings (code, poll_hash, label, created_at) VALUES (?, ?, ?, ?)')
        .bind(code, await auth.sha256(poll), cleanLabel(label), now),
    ]);
    const url = new URL(`/pair.html?code=${code}`, new URL(c.req.url).origin).toString();
    return c.json({ code, poll, url, expires_in: TTL_MS / 1000 });
  });

  app.get('/api/pair/info', async (c) => {
    const userId = await auth.requireUser(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const row = await c.env.DB.prepare('SELECT label, created_at, approved_at FROM device_pairings WHERE code = ?')
      .bind(cleanCode(c.req.query('code'))).first();
    if (!row || Date.now() - row.created_at > TTL_MS) return c.json({ error: 'That code has expired. Start again in the plugin.' }, 404);
    return c.json({ label: row.label, approved: !!row.approved_at });
  });

  app.post('/api/pair/approve', async (c) => {
    const userId = await auth.requireUser(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const { code } = await c.req.json().catch(() => ({}));
    const row = await c.env.DB.prepare('SELECT * FROM device_pairings WHERE code = ?').bind(cleanCode(code)).first();
    if (!row || Date.now() - row.created_at > TTL_MS) return c.json({ error: 'That code has expired. Start again in the plugin.' }, 404);
    if (row.approved_at) return c.json({ ok: true });
    const { token } = await auth.createSession(c.env, userId, { kind: 'device', label: row.label });
    const r = await c.env.DB.prepare(
      'UPDATE device_pairings SET user_id = ?, token = ?, approved_at = ? WHERE code = ? AND approved_at IS NULL'
    ).bind(userId, token, Date.now(), row.code).run();
    if (!r.meta || !r.meta.changes) await auth.revokeSession(c.env, token);
    return c.json({ ok: true });
  });

  app.post('/api/pair/poll', async (c) => {
    const { code, poll } = await c.req.json().catch(() => ({}));
    const row = await c.env.DB.prepare('SELECT * FROM device_pairings WHERE code = ?').bind(cleanCode(code)).first();
    if (!row || Date.now() - row.created_at > TTL_MS) return c.json({ error: 'expired' }, 410);
    if (!poll || (await auth.sha256(String(poll))) !== row.poll_hash) return c.json({ error: 'expired' }, 410);
    if (!row.approved_at || !row.token) return c.json({ pending: true });
    await c.env.DB.prepare('DELETE FROM device_pairings WHERE code = ?').bind(row.code).run();
    return c.json({ token: row.token });
  });
}
