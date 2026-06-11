const { authenticateRequest, jsonResponse, handleCors } = require('../lib/supabase');
const storage = require('../lib/storage');

/**
 * Delete an item and the R2 objects it owns.
 * Body: { slug }
 */
module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST' && req.method !== 'DELETE') {
    return jsonResponse(res, 405, { error: 'Method not allowed' });
  }

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const slug = (req.body && req.body.slug) || req.query.slug;
  if (!slug) return jsonResponse(res, 400, { error: 'Missing slug' });

  const { data: item, error: fetchErr } = await client
    .from('items')
    .select('id, user_id, slug')
    .eq('slug', slug)
    .eq('user_id', user.id)
    .single();
  if (fetchErr || !item) return jsonResponse(res, 404, { error: 'Item not found' });

  // Best-effort storage cleanup: everything under {user_id}/{slug}/.
  // A remove failure doesn't block the row delete (orphaned objects can be
  // GC'd later; an undeletable row is worse).
  try {
    const keys = await storage.list(req.env, `${user.id}/${slug}/`);
    if (keys.length) await storage.remove(req.env, keys);
  } catch (err) {
    console.warn('item-delete: storage cleanup threw', slug, err.message);
  }

  const { error: deleteErr } = await client
    .from('items')
    .delete()
    .eq('id', item.id);
  if (deleteErr) return jsonResponse(res, 500, { error: 'Delete failed', detail: deleteErr.message });

  return jsonResponse(res, 200, { slug, deleted: true });
};
