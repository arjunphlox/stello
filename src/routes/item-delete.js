const { authenticateRequest, jsonResponse, handleCors } = require('../lib/common');

/**
 * Delete an item (soft delete, restorable for 30 days).
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

  // Soft delete (db.js turns delete() on items into deleted_at = now). The
  // row and its R2 images stay for 30 days so a delete can be restored and
  // the Apple apps learn about it through sync; the daily purge clears them.
  const { error: deleteErr } = await client
    .from('items')
    .delete()
    .eq('id', item.id);
  if (deleteErr) return jsonResponse(res, 500, { error: 'Delete failed', detail: deleteErr.message });

  return jsonResponse(res, 200, { slug, deleted: true });
};
