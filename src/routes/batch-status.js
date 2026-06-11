const { authenticateRequest, jsonResponse, handleCors } = require('../lib/supabase');

module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'GET') return jsonResponse(res, 405, { error: 'Method not allowed' });

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const batchId = req.query.id;
  if (!batchId) return jsonResponse(res, 400, { error: 'Missing batch id' });

  const { data: batch, error: fetchErr } = await client
    .from('batch_jobs')
    .select('*')
    .eq('id', batchId)
    .eq('user_id', user.id)
    .single();

  if (fetchErr || !batch) {
    return jsonResponse(res, 404, { error: 'Batch not found' });
  }

  const results = typeof batch.results === 'string'
    ? JSON.parse(batch.results) : (batch.results || []);

  return jsonResponse(res, 200, {
    batchId: batch.id,
    status: batch.status,
    total: batch.total_items,
    completed: batch.completed_items,
    failed: batch.failed_items,
    results,
  });
};
