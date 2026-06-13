const {
  authenticateRequest, jsonResponse, handleCors,
  fetchOGMetadata, downloadImage, generateTagsFromMetadata,
  extractDomain, decodeHtmlEntities,
} = require('../lib/supabase');
const storage = require('../lib/storage');

/**
 * Re-run capture-time processing for an existing item (login backfill):
 * re-decode title/summary, regenerate tags with the current rule tables,
 * download a missing OG image. Preserves intent + vision tags.
 */
module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST') return jsonResponse(res, 405, { error: 'Method not allowed' });

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const env = req.env;
  const { slug, itemId } = req.body || {};
  if (!slug && !itemId) return jsonResponse(res, 400, { error: 'Missing slug or itemId' });

  const baseQuery = client.from('items').select('*').eq('user_id', user.id);
  const { data: item, error: fetchErr } = await (
    itemId ? baseQuery.eq('id', itemId) : baseQuery.eq('slug', slug)
  ).single();
  if (fetchErr || !item) return jsonResponse(res, 404, { error: 'Item not found' });

  const existingTags = typeof item.tags === 'string'
    ? JSON.parse(item.tags) : (item.tags || []);

  const PRESERVED_CATS = new Set(['intent', 'color', 'style', 'mood']);
  const preserved = existingTags.filter(t => PRESERVED_CATS.has(t.category));

  const cleanedTitle = decodeHtmlEntities(item.title || '');
  const cleanedSummary = decodeHtmlEntities(item.summary || '');

  // Text-only items: nothing to refetch, just normalize and return.
  if (!item.source_url) {
    const updates = {};
    if (cleanedTitle !== item.title) updates.title = cleanedTitle.replace(/"/g, "'");
    if (cleanedSummary !== item.summary) updates.summary = cleanedSummary;
    if (item.enrichment_status !== 'vision_done') {
      updates.enrichment_status = 'vision_done';
    }
    if (Object.keys(updates).length > 0) {
      await client.from('items').update(updates).eq('id', item.id);
    }
    return jsonResponse(res, 200, {
      status: 'text_only_cleaned',
      enrichment_status: updates.enrichment_status || item.enrichment_status,
    });
  }

  const meta = await fetchOGMetadata(item.source_url);
  const ogFailed = meta._status === 'error';

  const title = ogFailed
    ? cleanedTitle || extractDomain(item.source_url) || 'Untitled'
    : (meta['og:title'] || meta.title || cleanedTitle || extractDomain(item.source_url) || 'Untitled');

  const summary = ogFailed
    ? cleanedSummary
    : (meta['og:description'] || meta.description || cleanedSummary || '');

  const ogImageUrl = ogFailed ? null : (meta['og:image'] || null);
  const domain = extractDomain(item.source_url);

  const updates = {
    title: title.replace(/"/g, "'"),
    summary: (summary || '').slice(0, 200),
    body_markdown: `## Summary\n${summary || ''}`,
    domain,
  };

  let ogImagePath = item.og_image_path;
  let imageUploadRetryable = false;
  if (!ogImagePath && ogImageUrl) {
    let fullImageUrl = ogImageUrl;
    if (ogImageUrl.startsWith('//')) fullImageUrl = 'https:' + ogImageUrl;
    else if (ogImageUrl.startsWith('/')) {
      try { fullImageUrl = new URL(item.source_url).origin + ogImageUrl; } catch { /* keep */ }
    }

    const img = await downloadImage(env, fullImageUrl);
    if (img) {
      const key = `${user.id}/${item.slug}/og-image${img.ext}`;
      const path = await storage.putSafe(env, key, img.buffer, img.mime);
      if (!path) {
        // Transient R2 issue — worth another shot on the next backfill.
        imageUploadRetryable = true;
        updates.enrichment_error = 'image-store-failed';
      } else {
        ogImagePath = path;
        updates.og_image_path = ogImagePath;
        // Recovered the image — clear any prior failure (or note a skipped
        // WebP normalization, which is non-fatal).
        updates.enrichment_error = img.transformError
          ? `image-webp: ${img.transformError}`.slice(0, 200) : null;
        const existingImages = (() => {
          try { return typeof item.images === 'string' ? JSON.parse(item.images) : (item.images || []); }
          catch { return []; }
        })();
        if (existingImages.length === 0) {
          updates.images = JSON.stringify([{
            path: ogImagePath, source: 'og', is_primary: true,
            width: img.width || null, height: img.height || null,
          }]);
        }
      }
    } else {
      updates.enrichment_error = 'image-download-failed';
      console.warn('reprocess: image download returned null', item.source_url, fullImageUrl);
    }
  }

  const freshTags = generateTagsFromMetadata({
    title, domain, description: summary, sourceUrl: item.source_url,
  });

  const seen = new Set();
  const merged = [];
  for (const t of [...freshTags, ...preserved]) {
    if (seen.has(t.tag)) continue;
    seen.add(t.tag);
    merged.push(t);
  }
  merged.sort((a, b) => (b.weight || 0) - (a.weight || 0));
  updates.tags = JSON.stringify(merged.slice(0, 16));

  const hasVisionTags = preserved.some(t => t.category === 'color'
    || t.category === 'style' || t.category === 'mood');
  // Status must reflect what's actually left to do — never mark an item
  // "done" just to stop the backfill drip. Crucially, an item whose page
  // advertises an og:image we *failed to store* stays retryable (text_done)
  // so a later pass (or the download-hardening fix) can recover the image,
  // rather than being masked as vision_done forever.
  if (ogImagePath && hasVisionTags) {
    updates.enrichment_status = 'vision_done';        // image + vision both present
  } else if (ogImagePath) {
    updates.enrichment_status = 'text_done';          // have image, vision still pending
  } else if (ogImageUrl || imageUploadRetryable || ogFailed) {
    // page HAS an og:image we couldn't store, OR the OG fetch errored
    // transiently — keep retrying rather than masking as done.
    updates.enrichment_status = 'text_done';
  } else {
    updates.enrichment_status = 'candidates_done';    // OG fetched OK, page has no image → terminal, not "vision_done"
  }

  await client.from('items').update(updates).eq('id', item.id);

  return jsonResponse(res, 200, {
    status: 'reprocessed',
    has_image: !!ogImagePath,
    tags_count: merged.length,
    enrichment_status: updates.enrichment_status,
    og_failed: ogFailed,
  });
};
