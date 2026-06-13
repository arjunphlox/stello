const {
  authenticateRequest, userClientFromToken, jsonResponse, handleCors, downloadImage,
} = require('../lib/supabase');
const storage = require('../lib/storage');
const Anthropic = require('@anthropic-ai/sdk');

const SYSTEM_PROMPT = `You analyze images from a design knowledge base. Based on the visual content, provide tags in three categories.

Return ONLY valid JSON with this exact structure:
{
  "color": [{"tag": "name", "weight": 0.0}],
  "style": [{"tag": "name", "weight": 0.0}],
  "mood": [{"tag": "name", "weight": 0.0}]
}

Rules:
- color: 2-4 specific colors visible in the image. Use descriptive names like "burgundy", "teal", "charcoal", "ivory", "coral", "sage", "slate", "amber" — not generic "blue" or "red". Weight = how dominant (0.0-1.0).
- style: 1-3 visual/design styles. Examples: "minimalist", "brutalist", "editorial", "geometric", "organic", "typographic", "illustrated", "photographic", "3d", "hand-drawn", "flat", "retro", "futuristic", "grunge". Weight = how strongly (0.0-1.0).
- mood: 1-2 emotional tones. Examples: "dark", "vibrant", "elegant", "playful", "calm", "energetic", "moody", "warm", "cool", "dramatic", "professional", "whimsical". Weight = confidence (0.0-1.0).

Return ONLY the JSON object, no explanation.`;

const TITLE_PROMPT = `Look at this image and give it a short, descriptive title (3-5 words).
The title should describe what the image shows — e.g., "Geometric Pattern Grid", "Dark Typography Specimen", "Minimalist Watch Design".
Return ONLY the title text, nothing else.`;

const CANDIDATES_PROMPT = `You are curating a designer's personal knowledge base. Given the text of a web page, produce two things the user will choose from:

1. **snippets**: 3–5 short, standalone representative quotes or passages (each ≤ 200 chars) that capture what's interesting about this page for a designer. No ellipses, full sentences when possible.
2. **reasons**: 2–3 short phrases (≤ 4 words each, lowercase kebab-case) suggesting *why* a designer might save this. Examples: "color-palette-inspiration", "grid-system-reference", "typography-pairing", "onboarding-pattern".

Return ONLY valid JSON: {"snippets": ["...", "..."], "reasons": ["...", "..."]}`;

const VISION_CATEGORIES = new Set(['color', 'style', 'mood']);

/** HTTP handler — authenticates then delegates to the shared core. */
module.exports = async function handler(req, res) {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST') return jsonResponse(res, 405, { error: 'Method not allowed' });

  const { user, error, status } = await authenticateRequest(req);
  if (error) return jsonResponse(res, status, { error });

  const { slug, itemId } = req.body || {};
  if (!slug && !itemId) return jsonResponse(res, 400, { error: 'Missing slug or itemId' });

  const token = (req.headers.authorization || '').replace('Bearer ', '');
  const result = await enrichCore(req.env, token, { slug, itemId });
  return jsonResponse(res, 200, result);
};

/**
 * Shared enrichment core — also called fire-and-forget via ctx.waitUntil()
 * from capture / upload-image / reenrich (no self-subrequest). Builds its own
 * user-scoped client from the bearer token.
 */
async function enrichCore(env, accessToken, { slug, itemId }) {
  const client = userClientFromToken(env, accessToken);
  const { data: { user } = {}, error: authErr } = await client.auth.getUser(accessToken);
  if (authErr || !user) return { error: 'unauthorized' };

  // Fetch the item
  let query = client.from('items').select('*');
  if (itemId) query = query.eq('id', itemId);
  else query = query.eq('slug', slug).eq('user_id', user.id);

  const { data: item, error: fetchErr } = await query.single();
  if (fetchErr || !item) return { error: 'Item not found' };

  const apiKey = await getApiKey(client, user.id, env);
  const anthropic = apiKey ? new Anthropic({ apiKey }) : null;
  const result = { slug: item.slug };
  const existingTags = typeof item.tags === 'string' ? JSON.parse(item.tags) : (item.tags || []);
  let currentTags = existingTags;

  // ---- Phase A: Vision tags (requires og_image_path + API key) ----
  if (item.og_image_path && anthropic) {
    try {
      const imgData = await readImageBytes(env, item.og_image_path);
      if (!imgData) throw new Error('Could not fetch image');

      const imgBuffer = imgData.buffer;
      if (imgBuffer.length > 20 * 1024 * 1024) throw new Error('Image too large');

      const contentType = imgData.contentType || 'image/webp';
      const mediaType = contentType.includes('png') ? 'image/png'
        : contentType.includes('webp') ? 'image/webp'
        : contentType.includes('gif') ? 'image/gif' : 'image/jpeg';
      const imageB64 = imgBuffer.toString('base64');

      const contextTags = existingTags
        .filter(t => t.category === 'domain' || t.category === 'subject')
        .map(t => t.tag)
        .slice(0, 6);
      let contextStr = `Item titled "${item.title}"`;
      if (contextTags.length) contextStr += `, tagged with: ${contextTags.join(', ')}`;

      const visionResp = await anthropic.messages.create({
        model: 'claude-sonnet-4-6',
        max_tokens: 300,
        system: SYSTEM_PROMPT,
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageB64 } },
            { type: 'text', text: contextStr },
          ],
        }],
      });

      let raw = visionResp.content[0].text.trim();
      raw = raw.replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '');
      const visionResult = JSON.parse(raw);

      const newTags = mergeNewTags(existingTags, visionResult);
      currentTags = [...existingTags, ...newTags];
      result.tags = currentTags;

      const title = item.title || '';
      if (title.startsWith('Image upload') || title.startsWith('Saved from')) {
        const smartTitle = await generateSmartTitle(anthropic, imageB64, mediaType);
        if (smartTitle) result.title = smartTitle;
      }

      const updates = {
        tags: JSON.stringify(currentTags),
        analyzed_at: new Date().toISOString(),
        enrichment_status: 'vision_done',
        enrichment_error: null,            // clear any prior failure on success
      };
      if (result.title) updates.title = result.title;
      await client.from('items').update(updates).eq('id', item.id);
    } catch (err) {
      result.vision_error = (err.message || '').slice(0, 100);
      // Persist the reason — until now the 'error' status was opaque, leaving
      // no way to tell a missing key from a bad image from an API failure.
      await client.from('items').update({
        enrichment_status: 'error',
        enrichment_error: `vision: ${result.vision_error || 'unknown'}`.slice(0, 200),
      }).eq('id', item.id);
      return result;
    }
  } else if (!item.og_image_path && item.enrichment_status !== 'text_done') {
    await client.from('items').update({ enrichment_status: 'text_done' }).eq('id', item.id);
  }

  // ---- Phase B: Candidates (requires source_url + API key) ----
  if (item.source_url && anthropic) {
    try {
      const html = await fetchPageHtml(item.source_url);
      if (html) {
        // The cover is stored as an R2 "/img/<key>" path, so it can't be
        // compared against external candidate URLs. Re-derive the original
        // og:image source URL from the page and exclude *that* instead.
        const excludeUrl = extractOgImageUrl(html, item.source_url);
        const imageCandidates = await harvestImageCandidates({
          env, html, sourceUrl: item.source_url,
          userId: user.id, slug: item.slug,
          excludeUrl,
        });

        const pageText = extractPageText(html).slice(0, 6000);
        let snippets = [];
        let reasons = [];
        if (pageText.length > 200) {
          try {
            const resp = await anthropic.messages.create({
              model: 'claude-sonnet-4-6',
              max_tokens: 600,
              system: CANDIDATES_PROMPT,
              messages: [{ role: 'user', content: pageText }],
            });
            let raw = resp.content[0].text.trim();
            raw = raw.replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '');
            const parsed = JSON.parse(raw);
            snippets = Array.isArray(parsed.snippets)
              ? parsed.snippets.map(s => String(s).trim()).filter(s => s && s.length <= 400).slice(0, 5)
              : [];
            reasons = Array.isArray(parsed.reasons)
              ? parsed.reasons.map(r => String(r).toLowerCase().trim().replace(/[^a-z0-9\- ]/g, '').replace(/\s+/g, '-')).filter(Boolean).slice(0, 3)
              : [];
          } catch (err) {
            console.warn('candidates prompt failed', item.slug, err.message);
          }
        }

        let imgs = imageCandidates;
        const update = { needs_review: shouldReview(currentTags) };

        // Cover fallback: the page exposed no og:image, but we harvested
        // usable page images — promote the first to the cover so the card
        // isn't a blank tile. Keep status retryable (text_done) so the next
        // pass runs vision on the freshly-promoted cover.
        const existingImages = Array.isArray(item.images)
          ? item.images
          : (() => { try { return JSON.parse(item.images || '[]'); } catch { return []; } })();
        if (!item.og_image_path && existingImages.length === 0 && imgs.length) {
          const [cover, ...rest] = imgs;
          update.og_image_path = cover.path;
          update.images = JSON.stringify([{
            path: cover.path, source: 'extracted', is_primary: true,
            width: cover.width || null, height: cover.height || null,
            label: cover.label || null,
          }]);
          update.enrichment_status = 'text_done';   // vision pending on the new cover
          update.enrichment_error = null;
          imgs = rest;                               // don't also list the cover as a candidate
          result.og_image_path = cover.path;
        } else {
          update.enrichment_status = 'candidates_done';
        }

        const candidates = { images: imgs, snippets, reasons };
        result.enrichment_candidates = candidates;
        update.enrichment_candidates = JSON.stringify(candidates);

        await client.from('items').update(update).eq('id', item.id);
      } else if (item.enrichment_status === 'pending') {
        await client.from('items').update({ enrichment_status: 'vision_done' }).eq('id', item.id);
      }
    } catch (err) {
      console.warn('candidates phase error', item.slug, err.message);
    }
  } else {
    await client.from('items').update({
      needs_review: shouldReview(currentTags),
    }).eq('id', item.id);
  }

  return result;
}

/**
 * Read image bytes for vision. Prefers R2 (the stored path is now a relative
 * "/img/<key>"); falls back to an HTTP fetch for any legacy absolute URL that
 * hasn't been migrated yet.
 */
async function readImageBytes(env, path) {
  try {
    if (/^https?:\/\//i.test(path)) {
      const r = await fetch(path);
      if (!r.ok) return null;
      return { buffer: Buffer.from(await r.arrayBuffer()), contentType: r.headers.get('content-type') || 'image/jpeg' };
    }
    const key = storage.pathToKey(path);
    if (!key) return null;
    const obj = await env.BUCKET.get(key);
    if (!obj) return null;
    return { buffer: Buffer.from(await obj.arrayBuffer()), contentType: obj.httpMetadata?.contentType || 'image/webp' };
  } catch {
    return null;
  }
}

function mergeNewTags(existingTags, visionResult) {
  const existingNames = new Set(existingTags.map(t => t.tag));
  const newTags = [];

  for (const category of VISION_CATEGORIES) {
    const items = visionResult[category] || [];
    for (const item of items) {
      const tagName = (item.tag || '').toLowerCase().trim();
      const weight = Math.min(1.0, Math.max(0.0, parseFloat(item.weight) || 0));
      if (tagName && !existingNames.has(tagName)) {
        newTags.push({
          tag: tagName,
          category,
          weight: Math.round(weight * 100) / 100,
        });
        existingNames.add(tagName);
      }
    }
  }
  return newTags;
}

async function generateSmartTitle(anthropic, imageB64, mediaType) {
  try {
    const resp = await anthropic.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 50,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageB64 } },
          { type: 'text', text: TITLE_PROMPT },
        ],
      }],
    });
    return resp.content[0].text.trim().replace(/^["']|["']$/g, '');
  } catch {
    return null;
  }
}

function shouldReview(tags) {
  if (tags.length < 3) return true;
  if (tags.every(t => (t.weight || 0) < 0.5)) return true;

  const cats = {};
  let highWeight = 0;
  for (const t of tags) {
    cats[t.category] = (cats[t.category] || 0) + 1;
    if ((t.weight || 0) >= 0.6) highWeight++;
  }

  if (tags.length >= 8 && highWeight >= 4 && Object.keys(cats).length >= 3) return false;
  return true;
}

async function getApiKey(client, userId, env) {
  const { data } = await client
    .from('user_settings')
    .select('setting_value')
    .eq('user_id', userId)
    .eq('setting_key', 'anthropic_api_key')
    .single();

  if (data?.setting_value?.key) return data.setting_value.key;
  return env.ANTHROPIC_API_KEY || null;
}

// ---- HTML fetch + extraction helpers ----

async function fetchPageHtml(url) {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    const resp = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      },
      signal: controller.signal,
      redirect: 'follow',
    });
    clearTimeout(timeout);
    if (!resp.ok) return null;

    const reader = resp.body.getReader();
    const chunks = [];
    let total = 0;
    while (total < 500_000) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      total += value.length;
    }
    reader.cancel();
    return Buffer.concat(chunks).toString('utf-8');
  } catch (err) {
    console.warn('fetchPageHtml failed', url, err.message);
    return null;
  }
}

function extractPageText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function extractImageUrls(html, baseUrl) {
  const urls = new Set();
  const out = [];
  const imgRe = /<img\b[^>]*>/gi;
  let match;
  while ((match = imgRe.exec(html)) !== null && out.length < 20) {
    const tag = match[0];
    const srcMatch = tag.match(/\bsrc=["']([^"']+)["']/i);
    const srcsetMatch = tag.match(/\bsrcset=["']([^"']+)["']/i);
    const altMatch = tag.match(/\balt=["']([^"']*)["']/i);
    const widthMatch = tag.match(/\bwidth=["']?(\d+)/i);
    const heightMatch = tag.match(/\bheight=["']?(\d+)/i);
    let src = srcMatch ? srcMatch[1] : null;

    if (!src && srcsetMatch) {
      const entries = srcsetMatch[1].split(',').map(s => s.trim());
      const last = entries[entries.length - 1];
      src = last ? last.split(/\s+/)[0] : null;
    }
    if (!src) continue;
    if (src.startsWith('data:')) continue;

    let abs;
    try { abs = new URL(src, baseUrl).href; } catch { continue; }
    if (!/^https?:/i.test(abs)) continue;

    const w = widthMatch ? parseInt(widthMatch[1]) : null;
    const h = heightMatch ? parseInt(heightMatch[1]) : null;
    if ((w && w < 100) || (h && h < 100)) continue;

    if (/(\bicon\b|\bavatar\b|\bpixel\b|\btracking\b|\bsprite\b|\bbadge\b|\bfavicon\b|\blogo-?small\b|1x1|spacer)/i.test(abs)) continue;

    if (urls.has(abs)) continue;
    urls.add(abs);
    out.push({ url: abs, label: altMatch ? altMatch[1].slice(0, 80) : null });
  }
  return out;
}

/** Pull the og:image URL out of already-fetched HTML, resolved to absolute. */
function extractOgImageUrl(html, baseUrl) {
  const m = html.match(/<meta\s+(?:property|name)=["']og:image["']\s+content=["']([^"']+)["']/i)
    || html.match(/<meta\s+content=["']([^"']+)["']\s+(?:property|name)=["']og:image["']/i);
  if (!m) return null;
  try { return new URL(m[1], baseUrl).href; } catch { return null; }
}

/** Loose URL equality — ignores protocol, query/hash, and a trailing slash. */
function sameImageUrl(a, b) {
  if (!a || !b) return false;
  const strip = (u) => u.replace(/^https?:\/\//i, '').replace(/[?#].*$/, '').replace(/\/+$/, '');
  return strip(a) === strip(b);
}

/**
 * Download up to 5 candidate images and store them in R2.
 * Returns [{ path, label, source: 'extracted', width, height }].
 */
async function harvestImageCandidates({ env, html, sourceUrl, userId, slug, excludeUrl }) {
  const candidates = extractImageUrls(html, sourceUrl);
  const out = [];
  let n = 0;
  for (const cand of candidates) {
    if (out.length >= 5) break;
    if (sameImageUrl(cand.url, excludeUrl)) continue;   // don't re-offer the cover as a candidate

    const img = await downloadImage(env, cand.url);
    if (!img) continue;

    const key = `${userId}/${slug}/candidate-${n}${img.ext}`;
    const path = await storage.putSafe(env, key, img.buffer, img.mime);
    if (path) {
      out.push({
        path, label: cand.label, source: 'extracted',
        width: img.width || null, height: img.height || null,
      });
      n++;
    }
  }
  return out;
}

module.exports.enrichCore = enrichCore;
