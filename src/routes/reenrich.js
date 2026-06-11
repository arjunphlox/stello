const {
  authenticateRequest, jsonResponse, handleCors,
  fetchOGMetadata, downloadImage, extractDomain,
  generateTagsFromMetadata,
} = require('../lib/supabase');
const storage = require('../lib/storage');
const { enrichCore } = require('./enrich');

/**
 * Re-run the full enrichment flow for an existing item:
 *   1. Re-fetch OG metadata; backfill title/summary/og_image_path/tags.
 *   2. Reset enrichment_status and re-run vision + candidates (waitUntil).
 *
 * Body: { slug }
 *
 * NOTE (Phase 2): the old Vercel handler also captured 1440/640/360 full-page
 * screenshots via puppeteer + @sparticuz/chromium. That's deferred to a
 * follow-up on Cloudflare Browser Rendering — it was a manual, non-critical
 * enhancement that already degraded to no-screenshots when unavailable.
 */
module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST') return jsonResponse(res, 405, { error: 'Method not allowed' });

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const env = req.env;
  const slug = (req.body && req.body.slug);
  if (!slug) return jsonResponse(res, 400, { error: 'Missing slug' });

  const { data: item, error: fetchErr } = await client
    .from('items')
    .select('*')
    .eq('slug', slug)
    .eq('user_id', user.id)
    .single();
  if (fetchErr || !item) return jsonResponse(res, 404, { error: 'Item not found' });

  const updates = {};

  // --- Phase 1: OG refetch (only if we have a source_url) ---
  if (item.source_url) {
    try {
      const meta = await fetchOGMetadata(item.source_url);
      const title = meta['og:title'] || meta.title || item.title;
      const summary = meta['og:description'] || meta.description || item.summary;
      const ogImageUrl = meta['og:image'] || null;
      const domain = extractDomain(item.source_url);

      if (title && title !== item.title) updates.title = title.replace(/"/g, "'");
      if (summary && summary !== item.summary) updates.summary = (summary || '').slice(0, 200);
      if (domain && domain !== item.domain) updates.domain = domain;

      const existingTags = typeof item.tags === 'string' ? JSON.parse(item.tags) : (item.tags || []);
      const visionAndIntent = existingTags.filter(t =>
        ['color', 'style', 'mood', 'intent'].includes(t.category)
      );
      const freshTags = generateTagsFromMetadata({
        title: updates.title || item.title,
        domain: updates.domain || item.domain,
        description: updates.summary || item.summary,
        sourceUrl: item.source_url,
      });
      const haveNames = new Set(freshTags.map(t => t.tag));
      const merged = [...freshTags];
      for (const t of visionAndIntent) {
        if (!haveNames.has(t.tag)) { merged.push(t); haveNames.add(t.tag); }
      }
      updates.tags = JSON.stringify(merged);

      // Backfill og_image_path if missing.
      if (!item.og_image_path && ogImageUrl) {
        let fullImageUrl = ogImageUrl;
        if (ogImageUrl.startsWith('//')) fullImageUrl = 'https:' + ogImageUrl;
        else if (ogImageUrl.startsWith('/')) {
          try { fullImageUrl = new URL(item.source_url).origin + ogImageUrl; } catch {}
        }
        const img = await downloadImage(env, fullImageUrl);
        if (img) {
          const key = `${user.id}/${slug}/og-image${img.ext}`;
          const path = await storage.putSafe(env, key, img.buffer, img.mime);
          if (path) {
            updates.og_image_path = path;
            const existingImages = (() => {
              try { return typeof item.images === 'string' ? JSON.parse(item.images) : (item.images || []); }
              catch { return []; }
            })();
            if (existingImages.length === 0) {
              updates.images = JSON.stringify([{
                path, source: 'og', is_primary: true,
                width: img.width || null, height: img.height || null,
              }]);
            }
          }
        }
      }
    } catch (err) {
      console.warn('reenrich: OG refetch failed', slug, err.message);
    }
  }

  // Reset enrichment so the downstream vision + candidates re-run.
  updates.enrichment_status = 'text_done';
  updates.enrichment_candidates = JSON.stringify({});

  const { error: updateErr } = await client
    .from('items')
    .update(updates)
    .eq('id', item.id);
  if (updateErr) return jsonResponse(res, 500, { error: 'Update failed', detail: updateErr.message });

  // --- Phase 2: vision + candidates via waitUntil (no self-subrequest) ---
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  if (req.ctx && token) {
    req.ctx.waitUntil(
      enrichCore(env, token, { slug, itemId: item.id }).catch(() => {})
    );
  }

  return jsonResponse(res, 200, { slug, status: 'reenriching' });
};
