/**
 * Image storage on R2 (env.BUCKET), replacing Supabase Storage.
 *
 * Object keys keep the prior layout: `<user_id>/<slug>/<file>`. Bytes are
 * served back through the Worker at `GET /img/<key>` (see src/index.js) so
 * there's no custom domain and **zero egress** — the cost lever the whole
 * migration is justified by.
 *
 * The DB persists the app-relative serve path ("/img/<key>") in
 * items.images[].path / og_image_path instead of a Supabase public URL.
 */

const PREFIX = '/img/';

/** Store bytes under `key`, return the app-relative serve path. */
async function put(env, key, buffer, contentType) {
  await env.BUCKET.put(key, buffer, {
    httpMetadata: { contentType: contentType || 'application/octet-stream' },
  });
  return PREFIX + key;
}

/**
 * put() that never throws — returns the serve path or null (logging on
 * failure). Mirrors the capture handlers' "don't fail the whole capture
 * over one bad image" tolerance.
 */
async function putSafe(env, key, buffer, contentType) {
  try {
    return await put(env, key, buffer, contentType);
  } catch (err) {
    console.warn('storage.put failed', key, err.message);
    return null;
  }
}

/**
 * Translate a stored value back to an R2 object key. Accepts, in order:
 *   - our own "/img/<key>" serve paths
 *   - legacy Supabase public URLs (".../object/public/item-images/<key>") so
 *     cleanup keeps working during the transition before the migration runs
 *   - bare R2 keys ("<user>/<slug>/<file>", e.g. from list())
 * Returns null for external http(s) URLs we don't own (never delete those).
 */
function pathToKey(p) {
  if (typeof p !== 'string') return null;
  const img = p.indexOf(PREFIX);
  if (img >= 0) return decodeURIComponent(p.slice(img + PREFIX.length).split('?')[0]);
  const sb = '/storage/v1/object/public/item-images/';
  const j = p.indexOf(sb);
  if (j >= 0) return decodeURIComponent(p.slice(j + sb.length).split('?')[0]);
  // External URL we don't own — skip.
  if (/^https?:\/\//i.test(p)) return null;
  // Already a bare relative key.
  return p.replace(/^\/+/, '').split('?')[0] || null;
}

/** Best-effort delete of one or many paths/keys. Never throws. */
async function remove(env, paths) {
  const keys = (Array.isArray(paths) ? paths : [paths]).map(pathToKey).filter(Boolean);
  if (!keys.length) return;
  try {
    await env.BUCKET.delete(keys);
  } catch (err) {
    console.warn('storage.remove failed', err.message);
  }
}

/** List object keys under a `<user_id>/<slug>` prefix. */
async function list(env, prefix) {
  const out = await env.BUCKET.list({ prefix });
  return (out.objects || []).map(o => o.key);
}

module.exports = { put, putSafe, remove, list, pathToKey, PREFIX };
