const {
  authenticateRequest, jsonResponse, handleCors, generateSlug, normalizeUrl,
  fetchOGMetadata, downloadImage, generateTagsFromMetadata, extractDomain,
} = require('../lib/supabase');
const storage = require('../lib/storage');

module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST') return jsonResponse(res, 405, { error: 'Method not allowed' });

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const env = req.env;
  const { urls } = req.body || {};
  if (!urls || !urls.length) {
    return jsonResponse(res, 400, { error: 'No URLs provided' });
  }

  const { data: batch, error: batchErr } = await client
    .from('batch_jobs')
    .insert({
      user_id: user.id,
      status: 'processing',
      total_items: urls.length,
      completed_items: 0,
      failed_items: 0,
      urls: JSON.stringify(urls),
      results: JSON.stringify([]),
    })
    .select()
    .single();

  if (batchErr) {
    return jsonResponse(res, 500, { error: 'Failed to create batch', detail: batchErr.message });
  }

  // Process up to 5 items inline; the daily cron drains the rest.
  const inlineLimit = Math.min(urls.length, 5);
  const results = [];

  for (let i = 0; i < inlineLimit; i++) {
    try {
      const item = await captureUrl(env, client, user, urls[i]);
      results.push({ index: i, url: urls[i], item, error: null });
    } catch (err) {
      results.push({ index: i, url: urls[i], item: null, error: err.message });
    }
  }

  const completed = results.filter(r => r.item).length;
  const failed = results.filter(r => r.error).length;
  const batchStatus = inlineLimit >= urls.length ? 'completed' : 'processing';

  await client
    .from('batch_jobs')
    .update({
      status: batchStatus,
      completed_items: completed,
      failed_items: failed,
      results: JSON.stringify(results),
    })
    .eq('id', batch.id);

  return jsonResponse(res, 202, {
    batchId: batch.id,
    total: urls.length,
    completed,
    failed,
    status: batchStatus,
  });
};

async function captureUrl(env, client, user, url) {
  const normalizedUrl = normalizeUrl(url);
  const { data: existing } = await client
    .from('items')
    .select('slug, source_url')
    .eq('user_id', user.id)
    .not('source_url', 'is', null);

  if (existing) {
    const dup = existing.find(item =>
      item.source_url && normalizeUrl(item.source_url) === normalizedUrl
    );
    if (dup) return { ...dup, is_duplicate: true };
  }

  const meta = await fetchOGMetadata(url);
  const title = meta['og:title'] || meta.title || extractDomain(url) || 'Untitled';
  const summary = meta['og:description'] || meta.description || '';
  const ogImageUrl = meta['og:image'] || null;
  const domain = extractDomain(url);
  const slug = generateSlug(title);
  const now = new Date().toISOString();

  let ogImagePath = null;
  let ogImageWidth = null;
  let ogImageHeight = null;
  let imageError = null;
  if (ogImageUrl) {
    let fullImageUrl = ogImageUrl;
    if (ogImageUrl.startsWith('//')) fullImageUrl = 'https:' + ogImageUrl;
    else if (ogImageUrl.startsWith('/')) {
      try { fullImageUrl = new URL(url).origin + ogImageUrl; } catch {}
    }

    const img = await downloadImage(env, fullImageUrl);
    if (img) {
      const key = `${user.id}/${slug}/og-image${img.ext}`;
      const path = await storage.putSafe(env, key, img.buffer, img.mime);
      if (path) {
        ogImagePath = path;
        ogImageWidth = img.width || null;
        ogImageHeight = img.height || null;
        if (img.transformError) imageError = `image-webp: ${img.transformError}`.slice(0, 200);
      } else {
        imageError = 'image-store-failed';
      }
    } else {
      imageError = 'image-download-failed';
      console.warn('capture-bulk: image download returned null', url, fullImageUrl);
    }
  }

  const tags = generateTagsFromMetadata({ title, domain, description: summary, sourceUrl: url });

  const ogImageEntry = ogImagePath ? [{
    path: ogImagePath, source: 'og', is_primary: true,
    width: ogImageWidth, height: ogImageHeight,
  }] : [];

  const { data: inserted, error: insertErr } = await client
    .from('items')
    .insert({
      user_id: user.id, slug, title: title.replace(/"/g, "'"),
      source_url: url, domain, author: null,
      summary: (summary || '').slice(0, 200),
      body_markdown: `## Summary\n${summary || ''}`,
      og_image_path: ogImagePath,
      images: JSON.stringify(ogImageEntry),
      status: 'active',
      location: null, needs_review: true,
      added_at: now, enrichment_status: 'text_done',
      enrichment_error: imageError,
      tags: JSON.stringify(tags),
    })
    .select()
    .single();

  if (insertErr) throw new Error(insertErr.message);
  return inserted;
}

module.exports.captureUrl = captureUrl;
