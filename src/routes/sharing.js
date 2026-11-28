/**
 * Audience sharing APIs (docs/plans/audience-sharing.md). Shared by the web app and
 * the Apple apps (device token). Rules live in src/lib/sharing.js.
 *
 *   GET    /api/me/sharing                 → { audiences, private_places }
 *   PUT    /api/me/sharing                 { audiences?, private_places? } (per-field clocks) → saved settings
 *   POST   /api/me/sharing/items           { ids: [item uuid], audiences: [audience id], clock? } → sync results
 *
 *   GET    /api/share-links                → { links: [...] }
 *   POST   /api/share-links                { audience_id, label?, filter?, expires_at? } → link
 *   PATCH  /api/share-links/:id            { label?, filter?, expires_at?, rotate?, revoked? } → link
 *   DELETE /api/share-links/:id            → link (revoked)
 *
 * Every link in a reply carries its `url`, recomputed from the token key, so the
 * owner can copy it again at any time. Deleting an audience revokes its links.
 */
import { applyChanges, MAX_PUSH, SyncError } from '../lib/sync.js';
import {
  normalizeSharing, mergeSharing, liveAudiences, cleanFilter, linkToken, hashToken, shareSecret,
} from '../lib/sharing.js';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_LABEL = 120;

export async function readSharing(db, userId) {
  const row = await db
    .prepare("SELECT setting_value FROM user_settings WHERE user_id = ? AND setting_key = 'sharing'")
    .bind(userId)
    .first();
  let value = null;
  try { value = row ? JSON.parse(row.setting_value) : null; } catch { value = null; }
  return normalizeSharing(value);
}

async function saveSharing(db, userId, sharing) {
  await db
    .prepare(
      `INSERT INTO user_settings (user_id, setting_key, setting_value) VALUES (?, 'sharing', ?)
       ON CONFLICT(user_id, setting_key) DO UPDATE SET setting_value = excluded.setting_value`,
    )
    .bind(userId, JSON.stringify(sharing))
    .run();
}

async function linkOut(env, origin, row) {
  const secret = await shareSecret(env);
  const token = await linkToken(secret, row.id, row.token_version);
  let filter = {};
  try { filter = JSON.parse(row.filter || '{}'); } catch { filter = {}; }
  const now = Date.now();
  return {
    id: row.id,
    audience_id: row.audience_id,
    label: row.label,
    filter,
    url: `${origin}/s/${token}`,
    expires_at: row.expires_at,
    revoked_at: row.revoked_at,
    active: row.revoked_at == null && (row.expires_at == null || row.expires_at > now),
    view_count: row.view_count,
    last_viewed_at: row.last_viewed_at,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

const expiry = (v) => (v === null ? null : Number.isFinite(v) && v > 0 ? Math.round(v) : undefined);

export default function mountSharing(app, { requireUser }) {
  const authed = (handler) => async (c) => {
    const userId = await requireUser(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    try {
      return await handler(c, userId);
    } catch (err) {
      if (err instanceof SyncError) return c.json({ error: err.message }, err.status);
      throw err;
    }
  };
  const body = async (c) => {
    try { return (await c.req.json()) || {}; } catch { throw new SyncError(400, 'invalid JSON'); }
  };
  const origin = (c) => new URL(c.req.url).origin;

  // ---- Audiences + private places (synced to the Apple apps like the profile)

  app.get('/api/me/sharing', authed(async (c, userId) => c.json(await readSharing(c.env.DB, userId))));

  app.put('/api/me/sharing', authed(async (c, userId) => {
    const patch = await body(c);
    const current = await readSharing(c.env.DB, userId);
    const { sharing, changed } = mergeSharing(current, patch);
    if (!changed) return c.json(current);
    await saveSharing(c.env.DB, userId, sharing);
    // An audience that is gone takes its links with it, at once.
    const wasLive = new Set(current.audiences.filter((a) => a.deleted_at == null).map((a) => a.id));
    const gone = sharing.audiences.filter((a) => a.deleted_at != null && wasLive.has(a.id)).map((a) => a.id);
    if (gone.length) {
      const now = Date.now();
      await c.env.DB
        .prepare(`UPDATE share_links SET revoked_at = ?, updated_at = ? WHERE user_id = ? AND revoked_at IS NULL AND audience_id IN (${gone.map(() => '?').join(', ')})`)
        .bind(now, now, userId, ...gone)
        .run();
    }
    return c.json(sharing);
  }));

  // Set the audiences of up to 100 items at once (the web's "Share with", single or bulk).
  // Goes through the sync merge, so the Apple apps pull it like any other edit.
  app.post('/api/me/sharing/items', authed(async (c, userId) => {
    const { ids, audiences, clock } = await body(c);
    if (!Array.isArray(ids) || !ids.length || ids.length > MAX_PUSH || !ids.every((id) => typeof id === 'string' && UUID_RE.test(id))) {
      throw new SyncError(400, `ids must be 1 to ${MAX_PUSH} item ids`);
    }
    if (!Array.isArray(audiences)) throw new SyncError(400, 'audiences must be a list');
    const sharing = await readSharing(c.env.DB, userId);
    const live = liveAudiences(sharing);
    const liveIds = new Set(live.map((a) => a.id));
    const wanted = [...new Set(audiences.map((a) => String(a).toLowerCase()))];
    if (!wanted.every((a) => liveIds.has(a))) throw new SyncError(400, 'unknown audience');
    const circles = wanted.filter((a) => live.find((x) => x.id === a).kind === 'circle');
    if (circles.length > 1) throw new SyncError(400, 'an item takes at most one circle');
    const at = Number.isFinite(clock) ? clock : Date.now();
    const out = await applyChanges(c.env.DB, userId, ids.map((id) => ({ id, fields: { audiences: wanted }, clock: at })));
    return c.json(out);
  }));

  // ---- Share links (server only; not synced as rows)

  app.get('/api/share-links', authed(async (c, userId) => {
    const { results } = await c.env.DB
      .prepare('SELECT * FROM share_links WHERE user_id = ? ORDER BY created_at DESC')
      .bind(userId)
      .all();
    const links = [];
    for (const r of results || []) links.push(await linkOut(c.env, origin(c), r));
    return c.json({ links });
  }));

  app.post('/api/share-links', authed(async (c, userId) => {
    const b = await body(c);
    const sharing = await readSharing(c.env.DB, userId);
    const audience = liveAudiences(sharing).find((a) => a.id === String(b.audience_id || '').toLowerCase());
    if (!audience) throw new SyncError(400, 'unknown audience');
    const exp = b.expires_at === undefined ? null : expiry(b.expires_at);
    if (exp === undefined) throw new SyncError(400, 'expires_at must be epoch ms or null');
    const id = crypto.randomUUID();
    const now = Date.now();
    const token = await linkToken(await shareSecret(c.env), id, 1);
    const label = typeof b.label === 'string' && b.label.trim() ? b.label.trim().slice(0, MAX_LABEL) : audience.name;
    await c.env.DB
      .prepare(
        `INSERT INTO share_links (id, user_id, audience_id, label, filter, token_hash, token_version, expires_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?)`,
      )
      .bind(id, userId, audience.id, label, JSON.stringify(cleanFilter(b.filter)), await hashToken(token), exp, now, now)
      .run();
    const row = await c.env.DB.prepare('SELECT * FROM share_links WHERE id = ?').bind(id).first();
    return c.json(await linkOut(c.env, origin(c), row), 201);
  }));

  const loadLink = async (c, userId) => {
    const row = await c.env.DB
      .prepare('SELECT * FROM share_links WHERE id = ? AND user_id = ?')
      .bind(c.req.param('id'), userId)
      .first();
    if (!row) throw new SyncError(404, 'link not found');
    return row;
  };

  app.patch('/api/share-links/:id', authed(async (c, userId) => {
    const row = await loadLink(c, userId);
    const b = await body(c);
    const sets = [];
    const vals = [];
    if (typeof b.label === 'string' && b.label.trim()) { sets.push('label = ?'); vals.push(b.label.trim().slice(0, MAX_LABEL)); }
    if (b.filter !== undefined) { sets.push('filter = ?'); vals.push(JSON.stringify(cleanFilter(b.filter))); }
    if (b.expires_at !== undefined) {
      const exp = expiry(b.expires_at);
      if (exp === undefined) throw new SyncError(400, 'expires_at must be epoch ms or null');
      sets.push('expires_at = ?'); vals.push(exp);
    }
    if (b.revoked === true && row.revoked_at == null) { sets.push('revoked_at = ?'); vals.push(Date.now()); }
    if (b.revoked === false && row.revoked_at != null) { sets.push('revoked_at = NULL'); }
    if (b.rotate === true) {
      const version = row.token_version + 1;
      const token = await linkToken(await shareSecret(c.env), row.id, version);
      sets.push('token_version = ?', 'token_hash = ?');
      vals.push(version, await hashToken(token));
    }
    if (sets.length) {
      sets.push('updated_at = ?');
      vals.push(Date.now());
      await c.env.DB.prepare(`UPDATE share_links SET ${sets.join(', ')} WHERE id = ? AND user_id = ?`).bind(...vals, row.id, userId).run();
    }
    return c.json(await linkOut(c.env, origin(c), await loadLink(c, userId)));
  }));

  app.delete('/api/share-links/:id', authed(async (c, userId) => {
    const row = await loadLink(c, userId);
    if (row.revoked_at == null) {
      const now = Date.now();
      await c.env.DB.prepare('UPDATE share_links SET revoked_at = ?, updated_at = ? WHERE id = ?').bind(now, now, row.id).run();
    }
    return c.json(await linkOut(c.env, origin(c), await loadLink(c, userId)));
  }));
}

/**
 * The live link behind a URL token, or null (unknown, revoked, expired). For the
 * viewer page (phase 2). Counts the view.
 */
export async function resolveLink(env, token, now = Date.now()) {
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{22}$/.test(token)) return null;
  const row = await env.DB.prepare('SELECT * FROM share_links WHERE token_hash = ?').bind(await hashToken(token)).first();
  if (!row || row.revoked_at != null || (row.expires_at != null && row.expires_at <= now)) return null;
  return row;
}
