/**
 * Image → WebP via the Cloudflare Images binding (env.IMAGES).
 *
 * Drop-in replacement for the old sharp-based _lib/webp.js. Preserves the
 * exact return contract so every caller is unchanged:
 *   { buffer, ext, mime, width, height }
 * width/height are the OUTPUT dimensions (post-resize) so the frontend can
 * reserve the exact aspect-ratio slot and the masonry never reflows.
 *
 * sharp is native C++ and cannot run on Workers; the Images binding does the
 * decode + resize + WebP encode in-platform. Each input()/info() call counts
 * as one transformation — we read input dims once and compute the output
 * dims arithmetically to avoid a second billable op.
 *
 * NOTE: the Images binding does not run in plain `wrangler dev` — exercise
 * image conversion locally with `wrangler dev --remote` (or in deploy).
 */

/** Wrap raw bytes in a fresh ReadableStream (input()/info() consume a stream). */
function toStream(bytes) {
  return new Blob([bytes]).stream();
}

/** RIFF....WEBP byte sniff — lets us skip a transform for already-WebP input. */
function isWebp(bytes) {
  if (!bytes || bytes.length < 12) return false;
  return (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  );
}

/** Magic-byte sniff → { ext, mime } for the formats og images come in as. */
function sniffImageType(bytes) {
  if (!bytes || bytes.length < 12) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return { ext: '.jpg', mime: 'image/jpeg' };
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return { ext: '.png', mime: 'image/png' };
  if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) return { ext: '.gif', mime: 'image/gif' };
  if (isWebp(bytes)) return { ext: '.webp', mime: 'image/webp' };
  // AVIF/HEIC: ISO-BMFF 'ftyp' box at offset 4, brand at 8.
  if (bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70) {
    const brand = String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]);
    if (brand === 'avif' || brand === 'avis') return { ext: '.avif', mime: 'image/avif' };
  }
  return null;
}

function extFromMime(mime) {
  if (!mime) return '.jpg';
  if (mime.includes('png')) return '.png';
  if (mime.includes('gif')) return '.gif';
  if (mime.includes('webp')) return '.webp';
  if (mime.includes('avif')) return '.avif';
  return '.jpg';
}

/**
 * Store the input bytes unchanged. The WebP-normalized bucket is the ideal,
 * but a non-WebP original is *vastly* better than a dropped image — this is
 * the fallback when the Images binding can't process an input (unsupported
 * source, transform error, binding absent in plain `wrangler dev`). Carries
 * `transformError` so callers can record why normalization was skipped.
 */
function passthrough(bytes, opts = {}, transformError = null) {
  const raw = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const sniff = sniffImageType(raw);
  const mime = (sniff && sniff.mime) || opts.sourceContentType || 'image/jpeg';
  const ext = (sniff && sniff.ext) || extFromMime(opts.sourceContentType);
  return { buffer: Buffer.from(raw), ext, mime, width: null, height: null, transformError };
}

/**
 * Convert arbitrary image bytes to WebP. Optionally clamp width to maxWidth
 * (never enlarges). Returns { buffer, ext, mime, width, height }.
 */
async function toWebp(env, input, opts = {}) {
  const { maxWidth, quality = 82 } = opts;
  const raw = input instanceof Uint8Array ? input : new Uint8Array(input);

  // Input dimensions (one transformation) — drives the resize decision and
  // lets us compute output dims without a second info() pass.
  let inW = null, inH = null;
  try {
    const info = await env.IMAGES.info(toStream(raw));
    inW = info.width || null;
    inH = info.height || null;
  } catch { /* dims optional — frontend falls back to aspect-ratio: auto */ }

  const transform = {};
  let outW = inW, outH = inH;
  if (maxWidth && inW && inW > maxWidth) {
    transform.width = maxWidth;
    outW = maxWidth;
    outH = inH ? Math.round(inH * (maxWidth / inW)) : null;
  }

  try {
    // .output() resolves to an ImageTransformationResult; .response() on it
    // yields the encoded HTTP Response. (output() is awaited before response().)
    const result = await env.IMAGES
      .input(toStream(raw))
      .transform(transform)
      // anim: true preserves animated GIF/WebP as animated WebP.
      .output({ format: 'image/webp', quality, anim: true });

    const buffer = Buffer.from(await result.response().arrayBuffer());
    return { buffer, ext: '.webp', mime: 'image/webp', width: outW, height: outH };
  } catch (err) {
    // Images binding choked (unsupported input, transform error, quota) or is
    // absent (plain `wrangler dev`). Keep the original bytes rather than
    // returning null and losing the image — the silent failure that left ~47%
    // of items with a valid og:image but nothing stored.
    const reason = ((err && err.message) || 'images-transform-failed').slice(0, 120);
    console.warn('toWebp: Images transform failed, storing original bytes', reason);
    return passthrough(raw, opts, reason);
  }
}

/**
 * If already WebP (and within maxWidth), return bytes unchanged — just read
 * dims. Otherwise convert. Mirrors the old ensureWebp shortcut for manual
 * uploads the user already pre-converted.
 */
async function ensureWebp(env, input, opts = {}) {
  const raw = input instanceof Uint8Array ? input : new Uint8Array(input);
  if (isWebp(raw)) {
    let width = null, height = null;
    try {
      const info = await env.IMAGES.info(toStream(raw));
      width = info.width || null;
      height = info.height || null;
    } catch { /* dims optional */ }
    // Respect maxWidth even for WebP input — if oversized, fall through to resize.
    if (!(opts.maxWidth && width && width > opts.maxWidth)) {
      return { buffer: Buffer.from(raw), ext: '.webp', mime: 'image/webp', width, height };
    }
  }
  return toWebp(env, raw, opts);
}

module.exports = { toWebp, ensureWebp, isWebp };
