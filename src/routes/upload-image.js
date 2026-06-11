const {
  authenticateRequest, jsonResponse, handleCors, generateSlug,
} = require('../lib/supabase');
const { ensureWebp } = require('../lib/images');
const storage = require('../lib/storage');
const { enrichCore } = require('./enrich');

module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST') return jsonResponse(res, 405, { error: 'Method not allowed' });

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const env = req.env;

  // Raw image bytes (the client POSTs the binary directly).
  const buffer = await req.arrayBuffer();
  if (!buffer || !buffer.length) {
    return jsonResponse(res, 400, { error: 'No image data received' });
  }

  // Convert to WebP via the Images binding — also returns output dims.
  let converted;
  try {
    converted = await ensureWebp(env, buffer, { maxWidth: 2400 });
  } catch (err) {
    return jsonResponse(res, 400, { error: 'Image conversion failed', detail: err.message });
  }

  const now = new Date();
  const dateStr = now.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  const title = `Image upload — ${dateStr}`;
  const slug = generateSlug(title);
  const isoNow = now.toISOString();

  const key = `${user.id}/${slug}/og-image${converted.ext}`;
  const path = await storage.putSafe(env, key, converted.buffer, converted.mime);
  if (!path) {
    return jsonResponse(res, 500, { error: 'Image upload failed' });
  }

  const tags = [{ tag: 'image-upload', category: 'format', weight: 0.4 }];

  const imagesEntry = [{
    path, source: 'og', is_primary: true,
    width: converted.width || null, height: converted.height || null,
  }];

  const item = {
    user_id: user.id,
    slug,
    title,
    source_url: null,
    domain: null,
    author: null,
    summary: 'Image pasted from clipboard',
    body_markdown: '## Summary\nImage pasted from clipboard',
    og_image_path: path,
    images: JSON.stringify(imagesEntry),
    status: 'active',
    location: null,
    needs_review: true,
    added_at: isoNow,
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

  // Background enrichment via waitUntil.
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  if (req.ctx && token) {
    req.ctx.waitUntil(
      enrichCore(env, token, { slug, itemId: inserted.id }).catch(() => {})
    );
  }

  return jsonResponse(res, 201, {
    ...inserted,
    has_image: true,
    tags: typeof inserted.tags === 'string' ? JSON.parse(inserted.tags) : inserted.tags,
  });
};
