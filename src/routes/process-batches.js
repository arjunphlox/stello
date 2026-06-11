const {
  getAdminClient, normalizeUrl, fetchOGMetadata, downloadImage,
  generateSlug, generateTagsFromMetadata, extractDomain,
} = require('../lib/supabase');
const storage = require('../lib/storage');

/**
 * Daily batch drain — pick up incomplete batch jobs and process pending URLs.
 * Invoked by the Worker's scheduled() handler (Cron Trigger "0 0 * * *").
 * No HTTP surface and no CRON_SECRET: the platform invokes scheduled()
 * directly, so there's nothing to authenticate.
 */
async function processBatches(env) {
  const admin = getAdminClient(env);

  const { data: batches } = await admin
    .from('batch_jobs')
    .select('*')
    .eq('status', 'processing')
    .order('created_at', { ascending: true })
    .limit(3);

  if (!batches || batches.length === 0) {
    return { status: 'no pending batches' };
  }

  let totalProcessed = 0;

  for (const batch of batches) {
    const urls = typeof batch.urls === 'string' ? JSON.parse(batch.urls) : (batch.urls || []);
    const results = typeof batch.results === 'string' ? JSON.parse(batch.results) : (batch.results || []);
    const processedIndices = new Set(results.map(r => r.index));

    const pending = [];
    for (let i = 0; i < urls.length; i++) {
      if (!processedIndices.has(i)) pending.push({ index: i, url: urls[i] });
    }

    if (pending.length === 0) {
      await admin.from('batch_jobs').update({ status: 'completed' }).eq('id', batch.id);
      continue;
    }

    const toProcess = pending.slice(0, 5);
    for (const { index, url } of toProcess) {
      try {
        const item = await captureUrlAdmin(env, admin, batch.user_id, url);
        results.push({ index, url, item, error: null });
      } catch (err) {
        results.push({ index, url, item: null, error: err.message });
      }
      totalProcessed++;
    }

    const completed = results.filter(r => r.item).length;
    const failed = results.filter(r => r.error).length;
    const allDone = results.length >= urls.length;

    await admin
      .from('batch_jobs')
      .update({
        status: allDone ? 'completed' : 'processing',
        completed_items: completed,
        failed_items: failed,
        results: JSON.stringify(results),
      })
      .eq('id', batch.id);
  }

  return { status: 'processed', count: totalProcessed };
}

async function captureUrlAdmin(env, admin, userId, url) {
  const normalizedUrl = normalizeUrl(url);
  const { data: existing } = await admin
    .from('items')
    .select('slug, source_url')
    .eq('user_id', userId)
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
  if (ogImageUrl) {
    let fullImageUrl = ogImageUrl;
    if (ogImageUrl.startsWith('//')) fullImageUrl = 'https:' + ogImageUrl;
    else if (ogImageUrl.startsWith('/')) {
      try { fullImageUrl = new URL(url).origin + ogImageUrl; } catch {}
    }
    const img = await downloadImage(env, fullImageUrl);
    if (img) {
      const key = `${userId}/${slug}/og-image${img.ext}`;
      const path = await storage.putSafe(env, key, img.buffer, img.mime);
      if (path) ogImagePath = path;
    } else {
      console.warn('cron: image download returned null', url, fullImageUrl);
    }
  }

  const tags = generateTagsFromMetadata({ title, domain, description: summary, sourceUrl: url });

  const ogImageEntry = ogImagePath ? [{
    path: ogImagePath, source: 'og', is_primary: true,
  }] : [];

  const { data: inserted, error: insertErr } = await admin
    .from('items')
    .insert({
      user_id: userId, slug, title: title.replace(/"/g, "'"),
      source_url: url, domain, author: null,
      summary: (summary || '').slice(0, 200),
      body_markdown: `## Summary\n${summary || ''}`,
      og_image_path: ogImagePath,
      images: JSON.stringify(ogImageEntry),
      status: 'active',
      location: null, needs_review: true,
      added_at: now, enrichment_status: 'text_done',
      tags: JSON.stringify(tags),
    })
    .select()
    .single();

  if (insertErr) throw new Error(insertErr.message);
  return inserted;
}

module.exports = { processBatches, captureUrlAdmin };
