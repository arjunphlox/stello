const { authenticateRequest, jsonResponse, handleCors } = require('../lib/supabase');
const { ensureWebp } = require('../lib/images');
const storage = require('../lib/storage');

/**
 * Unified curation endpoint. The panel posts deltas here as the user picks
 * images, adds/removes snippets, toggles why-saved reasons, or uploads a
 * custom image. Each field is optional; only changed fields are sent.
 */
module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST') return jsonResponse(res, 405, { error: 'Method not allowed' });

  const { user, error, status, client } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const env = req.env;
  const body = req.body || {};
  const slug = body.slug;
  if (!slug) return jsonResponse(res, 400, { error: 'Missing slug' });

  const { data: item, error: fetchErr } = await client
    .from('items')
    .select('*')
    .eq('slug', slug)
    .eq('user_id', user.id)
    .single();
  if (fetchErr || !item) return jsonResponse(res, 404, { error: 'Item not found' });

  const existingTags = parseJsonField(item.tags, []);
  const existingImages = parseJsonField(item.images, []);
  const existingSnippets = parseJsonField(item.snippets, []);
  const candidates = parseJsonField(item.enrichment_candidates, {});

  let images = existingImages.slice();
  let snippets = existingSnippets.slice();
  let tags = existingTags.slice();

  if (images.length === 0 && item.og_image_path) {
    images.push({ path: item.og_image_path, source: 'og', is_primary: true });
  }

  // --- Manual image upload -> WebP (Images binding) -> R2 -> images[] ---
  if (body.manual_image_upload && body.manual_image_upload.base64) {
    try {
      const rawBuffer = Buffer.from(body.manual_image_upload.base64, 'base64');
      const converted = await ensureWebp(env, rawBuffer, { maxWidth: 2400 });
      const n = images.length;
      const key = `${user.id}/${slug}/manual-${Date.now()}-${n}${converted.ext}`;
      const path = await storage.putSafe(env, key, converted.buffer, converted.mime);
      if (path) {
        images.push({
          path,
          label: body.manual_image_upload.label || null,
          source: 'manual',
          is_primary: images.length === 0,
          width: converted.width || null,
          height: converted.height || null,
        });
      }
    } catch (err) {
      console.warn('item-update: manual image conversion failed', slug, err.message);
    }
  }

  // --- Add candidate image paths into images[] ---
  if (Array.isArray(body.add_image_paths)) {
    const have = new Set(images.map(i => i.path));
    for (const path of body.add_image_paths) {
      if (!path || have.has(path)) continue;
      const candMatch = Array.isArray(candidates.images)
        ? candidates.images.find(c => c.path === path || c.url === path)
        : null;
      images.push({
        path,
        label: candMatch?.label || null,
        source: candMatch ? (candMatch.source || 'extracted') : 'extracted',
        is_primary: images.length === 0,
        width: candMatch?.width || null,
        height: candMatch?.height || null,
      });
      have.add(path);
    }
  }

  // --- Remove image paths ---
  if (Array.isArray(body.remove_image_paths) && body.remove_image_paths.length) {
    const drop = new Set(body.remove_image_paths);
    images = images.filter(i => !drop.has(i.path));
    if (!images.some(i => i.is_primary) && images.length) {
      images[0].is_primary = true;
    }
    // Best-effort R2 cleanup — never blocks the DB update.
    await storage.remove(env, body.remove_image_paths);
  }

  // --- Primary image ---
  if (body.primary_image_path) {
    let found = false;
    images = images.map(i => {
      const match = i.path === body.primary_image_path;
      if (match) found = true;
      return { ...i, is_primary: match };
    });
    if (!found) {
      const candMatch = Array.isArray(candidates.images)
        ? candidates.images.find(c => c.path === body.primary_image_path || c.url === body.primary_image_path)
        : null;
      images = images.map(i => ({ ...i, is_primary: false }));
      images.push({
        path: body.primary_image_path,
        label: candMatch?.label || null,
        source: candMatch ? (candMatch.source || 'extracted') : 'extracted',
        is_primary: true,
        width: candMatch?.width || null,
        height: candMatch?.height || null,
      });
    }
  }

  // --- Snippet mutations ---
  if (Array.isArray(body.removed_snippet_ids) && body.removed_snippet_ids.length) {
    const drop = new Set(body.removed_snippet_ids.map(Number));
    snippets = snippets.filter((_, i) => !drop.has(i));
  }
  if (Array.isArray(body.new_snippets)) {
    const now = new Date().toISOString();
    for (const text of body.new_snippets) {
      const clean = String(text || '').trim();
      if (!clean) continue;
      if (snippets.some(s => s.text === clean)) continue;
      const fromCandidate = Array.isArray(candidates.snippets) && candidates.snippets.includes(clean);
      snippets.push({
        text: clean,
        source: fromCandidate ? 'extracted' : 'manual',
        added_at: now,
      });
    }
  }

  // --- why_saved -> intent tags (append only new ones) ---
  if (Array.isArray(body.why_saved)) {
    const existingIntents = new Set(
      tags.filter(t => t.category === 'intent').map(t => t.tag)
    );
    tags = tags.filter(t => t.category !== 'intent' || body.why_saved.includes(t.tag));
    for (const raw of body.why_saved) {
      const reason = String(raw || '').toLowerCase().trim().replace(/\s+/g, '-');
      if (!reason || existingIntents.has(reason)) continue;
      tags.push({ tag: reason, category: 'intent', weight: 0.9 });
      existingIntents.add(reason);
    }
  }

  // --- body_markdown: rebuild Key Snippets + What Makes It Work sections ---
  let bodyMarkdown = stripSections(item.body_markdown || '', [
    'Key Snippets', 'What Makes It Work',
  ]);
  if (snippets.length) {
    const lines = snippets.map(s => `> ${s.text}`).join('\n\n');
    bodyMarkdown = bodyMarkdown.replace(/\s+$/, '') + `\n\n## Key Snippets\n${lines}`;
  }
  if (typeof body.what_works === 'string' && body.what_works.trim()) {
    bodyMarkdown = bodyMarkdown.replace(/\s+$/, '') + `\n\n## What Makes It Work\n${body.what_works.trim()}`;
  }

  // --- Mirror primary image back to legacy og_image_path for grid card ---
  const primary = images.find(i => i.is_primary);
  const ogImagePath = primary ? primary.path : (images[0]?.path || null);

  // --- Resolve candidates (remove ones the user already promoted) ---
  let nextCandidates = candidates;
  if (Array.isArray(candidates.images) && Array.isArray(body.add_image_paths) && body.add_image_paths.length) {
    const promoted = new Set(body.add_image_paths);
    nextCandidates = {
      ...candidates,
      images: candidates.images.filter(c => !promoted.has(c.path || c.url)),
    };
  }
  if (Array.isArray(candidates.snippets) && Array.isArray(body.new_snippets) && body.new_snippets.length) {
    const added = new Set(body.new_snippets.map(t => String(t).trim()));
    nextCandidates = {
      ...nextCandidates,
      snippets: (nextCandidates.snippets || candidates.snippets).filter(s => !added.has(s)),
    };
  }
  if (body.resolve_candidates) {
    nextCandidates = {};
  }

  const updates = {
    images: JSON.stringify(images),
    snippets: JSON.stringify(snippets),
    tags: JSON.stringify(tags),
    body_markdown: bodyMarkdown,
    og_image_path: ogImagePath,
    enrichment_candidates: JSON.stringify(nextCandidates),
  };
  let needsReview = item.needs_review;
  if (Array.isArray(body.why_saved)) {
    needsReview = false;
    updates.needs_review = false;
  }

  const { error: updateErr } = await client
    .from('items')
    .update(updates)
    .eq('id', item.id);
  if (updateErr) return jsonResponse(res, 500, { error: 'Update failed', detail: updateErr.message });

  return jsonResponse(res, 200, {
    slug,
    images,
    snippets,
    tags,
    og_image_path: ogImagePath,
    body_markdown: bodyMarkdown,
    enrichment_candidates: nextCandidates,
    needs_review: needsReview,
  });
};

function parseJsonField(v, fallback) {
  if (v == null) return fallback;
  if (typeof v === 'string') {
    try { return JSON.parse(v); } catch { return fallback; }
  }
  return v;
}

/**
 * Remove any `## Heading` section (and its contents up to the next `## `)
 * from a markdown string so the panel can rewrite its own sections.
 */
function stripSections(md, headings) {
  if (!md) return '';
  let out = md;
  for (const h of headings) {
    const re = new RegExp(
      `(^|\\n)##\\s+${h.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\$&')}\\b[\\s\\S]*?(?=\\n##\\s|$)`,
      'g'
    );
    out = out.replace(re, '');
  }
  return out.replace(/\n{3,}/g, '\n\n').trim();
}
