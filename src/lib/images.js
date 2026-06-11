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

  // .output() resolves to an ImageTransformationResult; .response() on it
  // yields the encoded HTTP Response. (output() is awaited before response().)
  const result = await env.IMAGES
    .input(toStream(raw))
    .transform(transform)
    // anim: true preserves animated GIF/WebP as animated WebP.
    .output({ format: 'image/webp', quality, anim: true });

  const buffer = Buffer.from(await result.response().arrayBuffer());
  return { buffer, ext: '.webp', mime: 'image/webp', width: outW, height: outH };
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
