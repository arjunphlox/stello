const { authenticateRequest, jsonResponse, handleCors } = require('../lib/common');
const { ensureWebp } = require('../lib/images');
const storage = require('../lib/storage');

const { normalize, mergeProfile } = require('../lib/profile');

/**
 * /api/me/profile: the signed-in user's name, designation and photo, as in the Mac's
 * preferences header (UserProfileStore). Shared by the web and the Apple apps (their
 * sync bridge reads and writes it with a device token). Merge rules: src/lib/profile.js.
 *
 *   GET                                       → { name, designation, avatar_path, clock }
 *   PUT    { name?, designation?, clock? }    → the saved profile
 *   POST   <raw image bytes>  [?clock=ms]     → the saved profile with a new avatar_path
 *   DELETE                    [?clock=ms]     → the saved profile with no photo
 *
 * Without a clock a write counts as made now (the web). The apps send when the edit
 * was made, so an older edit never overwrites a newer one from the other side.
 */
module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const current = await readProfile(client, user.id);
  const queryClock = req.query && req.query.clock != null ? Number(req.query.clock) : undefined;

  if (req.method === 'GET') return jsonResponse(res, 200, current);

  if (req.method === 'PUT') {
    const body = req.body || {};
    return write(client, user.id, current, { name: body.name, designation: body.designation }, body.clock, res);
  }

  if (req.method === 'POST') {
    // An older photo than the one on file: keep the newer one, skip the upload.
    const at = Number.isFinite(queryClock) ? queryClock : Date.now();
    if (!mergeProfile(current, { avatar_path: 'x' }, { avatar: at }).changed) return jsonResponse(res, 200, current);
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
    return write(client, user.id, current, { avatar_path: path }, { avatar: at }, res);
  }

  if (req.method === 'DELETE') {
    return write(client, user.id, current, { avatar_path: null }, { avatar: queryClock }, res);
  }

  return jsonResponse(res, 405, { error: 'Method not allowed' });
};

async function write(client, userId, current, patch, clock, res) {
  const { profile, changed } = mergeProfile(current, patch, clock);
  if (!changed) return jsonResponse(res, 200, current);
  return save(client, userId, profile, res);
}

async function readProfile(client, userId) {
  const { data } = await client
    .from('user_settings')
    .select('setting_value')
    .eq('user_id', userId)
    .eq('setting_key', 'profile');
  return normalize(data && data[0] && data[0].setting_value);
}

async function save(client, userId, profile, res) {
  const { error } = await client
    .from('user_settings')
    .upsert({ user_id: userId, setting_key: 'profile', setting_value: profile }, { onConflict: 'user_id,setting_key' });
  if (error) return jsonResponse(res, 500, { error: 'Save failed', detail: error.message });
  return jsonResponse(res, 200, profile);
}
