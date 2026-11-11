const {
  authenticateRequest, jsonResponse, handleCors,
  generateSlug, normalizeUrl, fetchOGMetadata,
  downloadImage, generateTagsFromMetadata, extractDomain,
} = require('../lib/common');
const storage = require('../lib/storage');
const { enrichCore } = require('./enrich');
const { sortSavedItem } = require('../lib/readers/sort-item.js');

module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST') return jsonResponse(res, 405, { error: 'Method not allowed' });

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const { type, content, title } = req.body || {};
  if (!type || !content) return jsonResponse(res, 400, { error: 'Missing type or content' });

  if (type === 'url') {
    return handleUrlCapture(req, client, user, content, res);
  }
  if (type === 'text') {
    return handleTextCapture(client, user, content, res, title);
  }

  return jsonResponse(res, 400, { error: 'Unknown type: ' + type });
};

async function handleUrlCapture(req, client, user, url, res) {
  const env = req.env;

  // Duplicate check
  const normalizedUrl = normalizeUrl(url);
  const { data: existing } = await client
    .from('items')
    .select('slug, title, source_url')
    .eq('user_id', user.id)
    .not('source_url', 'is', null);

  if (existing) {
    const dup = existing.find(item =>
      item.source_url && normalizeUrl(item.source_url) === normalizedUrl
    );
    if (dup) {
      return jsonResponse(res, 409, { error: 'Duplicate item', existing: dup });
    }
  }

  // Fetch OG metadata
  const meta = await fetchOGMetadata(url);
  const title = meta['og:title'] || meta.title || extractDomain(url) || 'Untitled';
  const summary = meta['og:description'] || meta.description || '';
  const ogImageUrl = meta['og:image'] || null;
  const domain = extractDomain(url);
  const slug = generateSlug(title);
  const now = new Date().toISOString();

  // Download + store OG image in R2
  let ogImagePath = null;
  let ogImageWidth = null;
  let ogImageHeight = null;
  let hasImage = false;
  let imageError = null;   // why no/degraded image — surfaced via enrichment_error

  if (ogImageUrl) {
    let fullImageUrl = ogImageUrl;
    if (ogImageUrl.startsWith('//')) {
      fullImageUrl = 'https:' + ogImageUrl;
    } else if (ogImageUrl.startsWith('/')) {
      try {
        const base = new URL(url);
        fullImageUrl = base.origin + ogImageUrl;
      } catch { /* keep as-is */ }
    }

    const img = await downloadImage(env, fullImageUrl);
    if (img) {
      const key = `${user.id}/${slug}/og-image${img.ext}`;
      const path = await storage.putSafe(env, key, img.buffer, img.mime);
      if (path) {
        ogImagePath = path;
        ogImageWidth = img.width || null;
        ogImageHeight = img.height || null;
        hasImage = true;
        // Stored, but WebP normalization was skipped — note it (non-fatal).
        if (img.transformError) imageError = `image-webp: ${img.transformError}`.slice(0, 200);
      } else {
        imageError = 'image-store-failed';   // R2 put failed
      }
    } else {
      imageError = 'image-download-failed';  // fetch/decode failed
      console.warn('capture: image download returned null', url, fullImageUrl);
    }
  }

  // Generate tags
  const tags = generateTagsFromMetadata({ title, domain, description: summary, sourceUrl: url });

  const bodyMarkdown = `## Summary\n${summary || ''}`;

  const ogImageEntry = ogImagePath ? [{
    path: ogImagePath,
    source: 'og',
    is_primary: true,
    width: ogImageWidth,
    height: ogImageHeight,
  }] : [];
  const item = {
    user_id: user.id,
    slug,
    title: title.replace(/"/g, "'"),
    source_url: url,
    domain,
    author: null,
    summary: (summary || '').slice(0, 200),
    body_markdown: bodyMarkdown,
    og_image_path: ogImagePath,
    images: JSON.stringify(ogImageEntry),
    status: 'active',
    location: null,
    needs_review: true,
    added_at: now,
    enrichment_status: 'text_done',
    enrichment_error: imageError,
    tags: JSON.stringify(tags),
  };

  const { data: inserted, error: insertErr } = await client
    .from('items')
    .insert(item)
    .select()
    .single();

  if (insertErr) {
    return jsonResponse(res, 500, { error: 'Insert failed', detail: insertErr.message });
  }

  // After the response (waitUntil): sort the item (kind + typed metadata from the
  // page readers), then the background enrichment. Saved first, so a page that runs
  // past the CPU limit costs only the sort; the cron drain still enriches it later.
  if (req.ctx) {
    req.ctx.waitUntil((async () => {
      await sortSavedItem({ client, item: inserted });
      await enrichCore(env, user.id, { slug, itemId: inserted.id });
    })().catch(() => {}));
  }

  return jsonResponse(res, 201, {
    ...inserted,
    has_image: hasImage,
    tags: typeof inserted.tags === 'string' ? JSON.parse(inserted.tags) : inserted.tags,
  });
}

// `fileTitle`: a dropped .md / .txt file's name. Its text is kept whole as the
// body (Mac DropImportService.importFile); a pasted note keeps the old shape.
async function handleTextCapture(client, user, content, res, fileTitle) {
  const words = content.trim().split(/\s+/);
  const given = typeof fileTitle === 'string' ? fileTitle.trim().slice(0, 120) : '';
  const title = given || words.slice(0, 5).join(' ');
  const slug = generateSlug(title);
  const now = new Date().toISOString();
  const summary = content.slice(0, 200);

  const tags = generateTagsFromMetadata({
    title,
    description: content,
    sourceUrl: null,
  });

  const item = {
    user_id: user.id,
    slug,
    title,
    source_url: null,
    domain: null,
    author: null,
    summary,
    body_markdown: given ? content : `## Summary\n${summary}`,
    og_image_path: null,
    status: 'active',
    location: null,
    needs_review: true,
    added_at: now,
    enrichment_status: 'text_done',
    tags: JSON.stringify(tags),
  };

  const { data: inserted, error: insertErr } = await client
    .from('items')
    .insert(item)
    .select()
    .single();

  if (insertErr) {
    return jsonResponse(res, 500, { error: 'Insert failed', detail: insertErr.message });
  }

  return jsonResponse(res, 201, {
    ...inserted,
    has_image: false,
    tags: typeof inserted.tags === 'string' ? JSON.parse(inserted.tags) : inserted.tags,
  });
}
