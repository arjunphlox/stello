const {
  getAdminClient, normalizeUrl, fetchOGMetadata, downloadImage,
  generateSlug, generateTagsFromMetadata, extractDomain,
} = require('../lib/supabase');
const storage = require('../lib/storage');
const { reprocessItem } = require('./reprocess');
const { enrichItem, getApiKey } = require('./enrich');

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

/**
 * Server-side enrichment drain — heal items stranded at 'text_done' without a
 * babysat browser tab. Mirrors the frontend backfill (reprocess → vision) but
 * runs with the admin client across all users, resolving each owner's API key
 * (user_settings → env.ANTHROPIC_API_KEY). Bounded per invocation: the daily
 * cron passes a small limit (a steady backstop); the guarded manual trigger
 * passes a larger one to clear a backlog in controlled chunks.
 *
 * Sequential on purpose — keeps subrequest count and Anthropic request rate
 * predictable per Worker invocation.
 */
async function drainEnrichment(env, { limit = 25 } = {}) {
  const admin = getAdminClient(env);

  const { data: items, error } = await admin
    .from('items')
    .select('*')
    .eq('enrichment_status', 'text_done')
    .order('added_at', { ascending: true })
    .limit(limit);
  if (error) return { status: 'error', error: error.message };
  if (!items || items.length === 0) return { status: 'nothing to drain', scanned: 0, healed: 0 };

  let healed = 0, errored = 0, stillPending = 0;
  for (const item of items) {
    try {
      const apiKey = await getApiKey(admin, item.user_id, env);
      // Phase 1: reprocess (OG / image / tags / status) — returns the updated item.
      const rp = await reprocessItem(env, admin, item, item.user_id);
      // Phase 2: vision, when the (possibly freshly-downloaded) cover is present
      // and a key is available. enrichItem advances text_done → vision_done.
      if (apiKey && rp.item && rp.item.og_image_path && rp.enrichment_status === 'text_done') {
        await enrichItem(env, admin, rp.item, apiKey, item.user_id);
      }
      // Read the settled status so the count reflects reality, not assumptions.
      const { data: after } = await admin
        .from('items').select('enrichment_status').eq('id', item.id).single();
      const s = after?.enrichment_status;
      if (s === 'vision_done' || s === 'candidates_done') healed++;
      else if (s === 'error') errored++;
      else stillPending++;
    } catch (err) {
      errored++;
      console.warn('drain: item failed', item.slug, err.message);
    }
  }

  return { status: 'drained', scanned: items.length, healed, errored, stillPending };
}

module.exports = { processBatches, captureUrlAdmin, drainEnrichment };
