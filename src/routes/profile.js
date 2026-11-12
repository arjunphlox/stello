const { authenticateRequest, jsonResponse, handleCors } = require('../lib/common');
const { ensureWebp } = require('../lib/images');
const storage = require('../lib/storage');

/**
 * /api/me/profile: the signed-in user's name, designation and photo, as in the Mac's
 * preferences header (UserProfileStore). Stored in user_settings under `profile`; the
 * photo lives in R2 as WebP.
 *
 *   GET                         → { name, designation, avatar_path }
 *   PUT  { name?, designation? } → the saved profile
 *   POST <raw image bytes>      → the saved profile with a new avatar_path
 */
const MAX_TEXT = 80;

module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const current = await readProfile(client, user.id);

  if (req.method === 'GET') return jsonResponse(res, 200, current);

  if (req.method === 'PUT') {
    const body = req.body || {};
    const next = { ...current };
    for (const k of ['name', 'designation']) {
      if (typeof body[k] === 'string') next[k] = body[k].trim().slice(0, MAX_TEXT);
    }
    return save(client, user.id, next, res);
  }

  if (req.method === 'POST') {
    const buffer = await req.arrayBuffer();
    if (!buffer || !buffer.length) return jsonResponse(res, 400, { error: 'No image data received' });
    if (buffer.length > 15 * 1024 * 1024) return jsonResponse(res, 413, { error: 'Image too large' });
    let converted;
    try {
      converted = await ensureWebp(req.env, buffer, { maxWidth: 512 });
    } catch (err) {
      return jsonResponse(res, 400, { error: 'Image conversion failed', detail: err.message });
    }
    // A new key per upload, so browsers and the /img cache never show the old photo.
    const key = `${user.id}/profile/avatar-${Date.now()}${converted.ext}`;
    const path = await storage.putSafe(req.env, key, converted.buffer, converted.mime);
    if (!path) return jsonResponse(res, 500, { error: 'Image upload failed' });
    return save(client, user.id, { ...current, avatar_path: path }, res);
  }

  return jsonResponse(res, 405, { error: 'Method not allowed' });
};

async function readProfile(client, userId) {
  const { data } = await client
    .from('user_settings')
    .select('setting_value')
    .eq('user_id', userId)
    .eq('setting_key', 'profile');
  const v = (data && data[0] && data[0].setting_value) || {};
  return {
    name: typeof v.name === 'string' ? v.name : '',
    designation: typeof v.designation === 'string' ? v.designation : '',
    avatar_path: typeof v.avatar_path === 'string' ? v.avatar_path : null,
  };
}

async function save(client, userId, profile, res) {
  const { error } = await client
    .from('user_settings')
    .upsert({ user_id: userId, setting_key: 'profile', setting_value: profile }, { onConflict: 'user_id,setting_key' });
  if (error) return jsonResponse(res, 500, { error: 'Save failed', detail: error.message });
  return jsonResponse(res, 200, profile);
}
