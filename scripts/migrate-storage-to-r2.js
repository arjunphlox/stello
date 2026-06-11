#!/usr/bin/env node
/**
 * One-time migration: copy existing item images from Supabase Storage into
 * R2, then rewrite items.images[].path + og_image_path from Supabase public
 * URLs to the Worker's "/img/<key>" serve paths.
 *
 *   node scripts/migrate-storage-to-r2.js --dry-run   # report only
 *   node scripts/migrate-storage-to-r2.js             # copy + rewrite
 *
 * Requirements:
 *   - .env.local with SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
 *   - wrangler authed (uploads via `wrangler r2 object put`) and R2 enabled
 *   - the stello-item-images bucket created
 *
 * Idempotent: paths already starting with "/img/" are left untouched, and
 * each object key is uploaded at most once per run. Safe to re-run.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { createClient } = require('@supabase/supabase-js');

const BUCKET = 'stello-item-images';
const SB_MARKER = '/storage/v1/object/public/item-images/';
const DRY = process.argv.includes('--dry-run');

// --- env ---
(() => {
  const envFile = path.join(__dirname, '..', '.env.local');
  if (!fs.existsSync(envFile)) return;
  for (const line of fs.readFileSync(envFile, 'utf8').split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq < 0) continue;
    const k = t.slice(0, eq).trim();
    if (!(k in process.env)) process.env[k] = t.slice(eq + 1).trim();
  }
})();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in .env.local');
  process.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

/** Supabase public URL (or already-/img path) → bare R2 key, or null. */
function toKey(p) {
  if (typeof p !== 'string') return null;
  if (p.startsWith('/img/')) return null;               // already migrated
  const i = p.indexOf(SB_MARKER);
  if (i >= 0) return decodeURIComponent(p.slice(i + SB_MARKER.length).split('?')[0]);
  return null;                                            // external / unknown — leave as-is
}

function ctForKey(key) {
  if (key.endsWith('.png')) return 'image/png';
  if (key.endsWith('.jpg') || key.endsWith('.jpeg')) return 'image/jpeg';
  if (key.endsWith('.gif')) return 'image/gif';
  return 'image/webp';
}

const uploaded = new Set();

async function copyToR2(key, sourceUrl) {
  if (uploaded.has(key)) return true;
  // Download bytes from the Supabase public URL.
  const resp = await fetch(sourceUrl);
  if (!resp.ok) { console.warn('  ! download failed', resp.status, sourceUrl); return false; }
  const buf = Buffer.from(await resp.arrayBuffer());
  if (DRY) { console.log(`  [dry] would put ${key} (${buf.length}b)`); uploaded.add(key); return true; }

  const tmp = path.join(os.tmpdir(), 'stello-mig-' + key.replace(/[^a-z0-9.]/gi, '_'));
  fs.writeFileSync(tmp, buf);
  try {
    execFileSync('npx', [
      'wrangler', 'r2', 'object', 'put',
      `${BUCKET}/${key}`,
      '--file', tmp,
      '--content-type', ctForKey(key),
      '--remote',
    ], { stdio: ['ignore', 'ignore', 'inherit'] });
    uploaded.add(key);
    return true;
  } catch (err) {
    console.warn('  ! wrangler put failed', key, err.message);
    return false;
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

function rewritePath(p) {
  const key = toKey(p);
  return key ? '/img/' + key : p;
}

async function main() {
  console.log(`migrate-storage-to-r2 ${DRY ? '(dry run)' : ''}`);
  const { data: items, error } = await admin
    .from('items')
    .select('id, slug, images, og_image_path');
  if (error) { console.error('fetch items failed', error.message); process.exit(1); }

  let rows = 0, copied = 0, rewritten = 0;
  for (const item of items) {
    let images = item.images;
    if (typeof images === 'string') { try { images = JSON.parse(images); } catch { images = []; } }
    images = Array.isArray(images) ? images : [];

    let changed = false;

    for (const img of images) {
      const key = toKey(img.path);
      if (!key) continue;
      const ok = await copyToR2(key, img.path);
      if (ok) { copied++; img.path = '/img/' + key; changed = true; }
    }

    let ogPath = item.og_image_path;
    const ogKey = toKey(ogPath);
    if (ogKey) {
      const ok = await copyToR2(ogKey, ogPath);
      if (ok) { ogPath = '/img/' + ogKey; changed = true; }
    }

    if (changed) {
      rewritten++;
      if (!DRY) {
        const { error: upErr } = await admin
          .from('items')
          .update({ images: JSON.stringify(images), og_image_path: ogPath })
          .eq('id', item.id);
        if (upErr) console.warn('  ! row update failed', item.slug, upErr.message);
      }
      console.log(`  ${DRY ? '[dry] ' : ''}${item.slug} — rewritten`);
    }
    rows++;
  }

  console.log(`\nDone: ${rows} items scanned, ${copied} objects copied, ${rewritten} rows rewritten.`);
}

main().catch(err => { console.error(err); process.exit(1); });
