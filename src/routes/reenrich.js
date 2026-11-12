const {
  authenticateRequest, userClient, jsonResponse, handleCors, downloadImage,
} = require('../lib/common');
const storage = require('../lib/storage');
const Anthropic = require('@anthropic-ai/sdk');
const { enrichCore, getApiKey } = require('./enrich');
const { readPage, makeNet, READ_AS_KINDS } = require('../lib/readers/pipeline.js');
const { freshReadFields } = require('../lib/readers/enrich-read.js');
const { fillIns, parseReply } = require('../lib/readers/fill-ins.js');
const { GALLERY_CAP } = require('../lib/readers/product.js');

/** The model that writes the per-kind fill-ins (one call per Enrich, user's own key). */
const FILL_IN_MODEL = 'claude-opus-5-5';
/** Kinds whose read images beyond the cover are kept as a gallery (Mac applyFreshRead). */
const GALLERY_KINDS = new Set(['product', 'post']);

/**
 * Enrich, as on the Mac (EnrichmentService.enrich with force):
 *   1. Re-fetch the page once and run the page readers on it (an already-typed item is
 *      read as its kind). A fresh read is stored over the item's dossier without erasing
 *      what was read before; a missing cover is backfilled. Titles, tags and summaries
 *      the item has are left alone (a post's rule-made title may follow its new text).
 *   2. In the background (waitUntil): a product's or post's other images become its
 *      gallery (when it has none yet); the per-kind fill-ins run (rules first, then one
 *      model call for what is still missing: a tool's pricing, a book's authors, …);
 *      then vision + snippets re-run on the same page. The snippets come from the
 *      reader's text and replace earlier AI picks, never the user's own.
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

  // --- Phase 2: gallery, fill-ins, then vision + candidates via waitUntil ---
  if (req.ctx) {
    req.ctx.waitUntil((async () => {
      const db = userClient(env, user.id);
      const { data: fresh } = await db.from('items').select('*').eq('id', item.id).single();
      if (fresh) {
        const galleryStored = await storeGallery(env, db, user.id, fresh, read).catch(() => false);
        await runFillIns(env, db, user.id, fresh, read).catch((err) => {
          console.warn('reenrich: fill-ins failed', slug, err && err.message);
        });
        await enrichCore(env, user.id, {
          slug, itemId: item.id,
          html: page && page.status < 400 ? page.text : null,
          // Music pages have no prose: like the Mac, no snippets from a platform shell.
          pageText: read ? read.extractedText : null,
          noText: (fresh.kind || item.kind) === 'music',
          replaceAISnippets: true,
          // A gallery already holds the page's images; don't harvest them again.
          noImageCandidates: galleryStored,
        });
      }
    })().catch(() => {}));
  }

  return jsonResponse(res, 200, { slug, status: 'reenriching' });
};

function parseList(v) {
  if (Array.isArray(v)) return v;
  try { const a = JSON.parse(v || '[]'); return Array.isArray(a) ? a : []; } catch { return []; }
}

/**
 * Products and posts keep the read's other images (after the cover) as a gallery, as the
 * Mac's applyFreshRead does: only when the item has no gallery yet, and only when this
 * read's kind is the item's kind. Returns whether gallery images were stored.
 */
async function storeGallery(env, db, userId, item, read) {
  if (!read || !GALLERY_KINDS.has(item.kind) || read.kind !== item.kind) return false;
  const images = parseList(item.images);
  if (images.some((i) => i && i.role === 'gallery')) return false;
  const urls = (read.images?.urls || []).slice(1, GALLERY_CAP);
  if (!urls.length) return false;
  const got = await Promise.all(urls.map(async (url, i) => {
    const img = await downloadImage(env, url);
    if (!img) return null;
    const path = await storage.putSafe(env, `${userId}/${item.slug}/gallery-${i}${img.ext}`, img.buffer, img.mime);
    return path ? {
      path, source: read.images?.source || 'og', is_primary: false, role: 'gallery',
      width: img.width || null, height: img.height || null,
    } : null;
  }));
  const gallery = got.filter(Boolean);
  if (!gallery.length) return false;
  await db.from('items').update({ images: JSON.stringify([...images, ...gallery]) }).eq('id', item.id);
  return true;
}

/** Per-kind fill-ins: rules first, then one model call (the user's key) for the gaps. */
async function runFillIns(env, db, userId, item, read) {
  const apiKey = await getApiKey(db, userId, env);
  const anthropic = apiKey ? new Anthropic({ apiKey }) : null;
  const callModel = anthropic ? async ({ system, schema, user }) => {
    const resp = await anthropic.messages.create({
      model: FILL_IN_MODEL,
      max_tokens: 2000,
      system,
      messages: [{ role: 'user', content: user }],
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
    });
    if (resp.stop_reason === 'refusal') return null;
    const block = (resp.content || []).find((b) => b.type === 'text');
    return block ? parseReply(block.text) : null;
  } : null;
  const fields = await fillIns({ item, text: read ? read.extractedText : null, callModel });
  if (!fields) return;
  const update = {};
  if (fields.metadata) update.metadata = fields.metadata;
  if (fields.title) update.title = String(fields.title).replace(/"/g, "'");
  await db.from('items').update(update).eq('id', item.id);
}
