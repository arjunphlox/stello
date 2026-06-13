#!/usr/bin/env node

/**
 * recover-errored-items.js — un-stick items stranded in enrichment_status
 * 'error'.
 *
 * Background: a batch of items errored during vision (transient API failures,
 * a missing key at the time, etc.) and the frontend backfill drip explicitly
 * *gives up* on 'error' (app.js itemNeedsBackfill), so they never retry. Their
 * images are intact in R2 — only the status is stuck.
 *
 * This resets eligible error items to 'text_done' (and clears enrichment_error)
 * so the deployed pipeline re-runs vision on next load:
 *   text_done → reprocess (keeps text_done, has_image) → /api/enrich → vision.
 *
 * The actual vision re-run happens *in the Worker* (it needs the R2 + Images
 * bindings); this script only flips the status that re-arms it. RUN IT AFTER
 * the enrichment fixes are deployed, and PILOT with a small --limit first so
 * the now-persisted enrichment_error tells you why any item re-fails.
 *
 * Usage:
 *   # dry run — report what would change, touch nothing (default)
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/recover-errored-items.js
 *   # pilot: reset 5
 *   node scripts/recover-errored-items.js --apply --limit 5
 *   # full batch
 *   node scripts/recover-errored-items.js --apply --limit 1000
 *
 * Flags:
 *   --apply        actually write (omit = dry run)
 *   --limit N      cap how many items to touch (default 10)
 *   --user <uuid>  restrict to one user_id
 */

const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');

// Friendly: load .env.local (the repo's convention) if the vars aren't set.
(function loadDotEnvLocal() {
  if (process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY) return;
  const p = path.join(__dirname, '..', '.env.local');
  if (!fs.existsSync(p)) return;
  for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
})();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Required env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (or a .env.local with them)');
  process.exit(1);
}

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const limIdx = args.indexOf('--limit');
const LIMIT = limIdx >= 0 ? parseInt(args[limIdx + 1], 10) || 10 : 10;
const userIdx = args.indexOf('--user');
const USER = userIdx >= 0 ? args[userIdx + 1] : null;

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

(async () => {
  // Eligible: stuck in 'error' AND have an image to analyze. (Items with no
  // image can't be healed by re-running vision — leave them for the og/cover
  // fallback paths instead.)
  let q = admin
    .from('items')
    .select('id, slug, og_image_path, enrichment_error, user_id')
    .eq('enrichment_status', 'error')
    .not('og_image_path', 'is', null)
    .order('added_at', { ascending: false })
    .limit(LIMIT);
  if (USER) q = q.eq('user_id', USER);

  const { data: rows, error } = await q;
  if (error) { console.error('query failed:', error.message); process.exit(1); }

  // Total eligible (for context), separate from the capped working set.
  let countQ = admin
    .from('items')
    .select('id', { count: 'exact', head: true })
    .eq('enrichment_status', 'error')
    .not('og_image_path', 'is', null);
  if (USER) countQ = countQ.eq('user_id', USER);
  const { count: totalEligible } = await countQ;

  console.log(`\nEligible errored items with an image: ${totalEligible ?? '?'}`);
  console.log(`${APPLY ? 'APPLYING to' : 'DRY RUN — would reset'} ${rows.length} (limit ${LIMIT})\n`);
  for (const r of rows.slice(0, 20)) {
    console.log(`  ${r.slug}  ${r.enrichment_error ? `(was: ${r.enrichment_error})` : ''}`);
  }
  if (rows.length > 20) console.log(`  …and ${rows.length - 20} more`);

  if (!APPLY) {
    console.log('\nNothing written. Re-run with --apply to reset these to text_done.');
    return;
  }

  const ids = rows.map(r => r.id);
  const { error: upErr } = await admin
    .from('items')
    .update({ enrichment_status: 'text_done', enrichment_error: null })
    .in('id', ids);
  if (upErr) { console.error('update failed:', upErr.message); process.exit(1); }

  console.log(`\n✓ Reset ${ids.length} items to text_done. The deployed Worker's`);
  console.log('  backfill drip will re-run vision on them; check enrichment_error');
  console.log('  afterward for any that re-fail.');
})();
