const {
  authenticateRequest, jsonResponse, handleCors, downloadImage,
} = require('../lib/common');
const storage = require('../lib/storage');
const { enrichCore } = require('./enrich');
const { readPage, makeNet, READ_AS_KINDS } = require('../lib/readers/pipeline.js');
const { freshReadFields } = require('../lib/readers/enrich-read.js');

/**
 * Enrich, as on the Mac (EnrichmentService.enrich with force):
 *   1. Re-fetch the page once and run the page readers on it (an already-typed item is
 *      read as its kind). A fresh read is stored over the item's dossier without erasing
 *      what was read before; a missing cover is backfilled. Titles, tags and summaries
 *      the item has are left alone (a post's rule-made title may follow its new text).
 *   2. Reset enrichment and re-run vision + snippets (waitUntil) on the same page: the
 *      snippets come from the reader's text and replace earlier AI picks, never the
 *      user's own.
 *
 * Body: { slug }
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
  let page = null;
  let read = null;

  // --- Phase 1: one page fetch + the page readers (only with a source_url) ---
  if (item.source_url) {
    try {
      const net = makeNet();
      const got = await net.get(item.source_url);
      if (got) page = got;
      const tags = Array.isArray(item.tags) ? item.tags
        : (() => { try { return JSON.parse(item.tags || '[]'); } catch { return []; } })();
      // Without the page the URL and labels still decide (music reads its oEmbed).
      read = await readPage({
        url: item.source_url,
        html: page ? page.text : '',
        status: page ? page.status : null,
        finalURL: page ? page.finalURL : null,
        collectionLabels: tags.filter(t => t && t.category === 'collection').map(t => t.tag),
        asKind: READ_AS_KINDS.has(item.kind) ? item.kind : null,
        net,
      });
      Object.assign(updates, freshReadFields(read, item) || {});
      if (!item.summary && read.summary) updates.summary = String(read.summary).slice(0, 200);
      if (!item.domain && read.domain) updates.domain = read.domain;

      // Backfill a missing cover from what the readers found.
      const images = Array.isArray(item.images) ? item.images
        : (() => { try { return JSON.parse(item.images || '[]'); } catch { return []; } })();
      if (!item.og_image_path && images.length === 0) {
        const urls = [...(read.images?.urls || []).slice(0, 1), ...(read.images?.fallbacks || []).slice(0, 1)];
        for (const url of urls) {
          const img = await downloadImage(env, url);
          if (!img) continue;
          const path = await storage.putSafe(env, `${user.id}/${slug}/og-image${img.ext}`, img.buffer, img.mime);
          if (!path) continue;
          updates.og_image_path = path;
          updates.images = JSON.stringify([{
            path, source: read.images?.source || 'og', is_primary: true,
            width: img.width || null, height: img.height || null,
          }]);
          break;
        }
      }
    } catch (err) {
      console.warn('reenrich: page read failed', slug, err.message);
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
  if (req.ctx) {
    req.ctx.waitUntil(
      enrichCore(env, user.id, {
        slug, itemId: item.id,
        html: page && page.status < 400 ? page.text : null,
        // Music pages have no prose: like the Mac, no snippets from a platform shell.
        pageText: read ? read.extractedText : null,
        noText: (updates.kind || item.kind) === 'music',
        replaceAISnippets: true,
      }).catch(() => {})
    );
  }

  return jsonResponse(res, 200, { slug, status: 'reenriching' });
};
