#!/usr/bin/env node

/**
 * restore-collection-labels.js — bring back the user's collection labels
 * (wishlist, digital-tools, midjourney, firms, …) that re-enrichment wiped.
 *
 * Background: the original import stored each item's collection as a
 * `category: 'domain'` tag. `reprocess` / `reenrich` rebuild format/domain/
 * subject tags from page metadata and only preserved intent/color/style/mood,
 * so every rebuilt item lost its collection and got a hostname domain tag
 * instead. The labels survive only in the last committed backup mirror
 * (`index.json` at commit 2462fc0d, Apr 2026).
 *
 * This merges each snapshot item's labels back as `category: 'collection'`
 * tags (weight 0.9), matched by slug, then by source_url, within one user.
 * Existing tags are never removed or reordered; an item that already carries
 * the label is skipped, so re-running is safe. `collection` is now preserved
 * by reprocess/reenrich, so the labels survive future enrichment.
 *
 * Before writing, the current tags of every item it will touch are saved to
 * `_backups/tags-<timestamp>.json` (gitignored).
 *
 * Usage:
 *   # dry run — report what would change, touch nothing (default)
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/restore-collection-labels.js
 *   # pilot, then full
 *   node scripts/restore-collection-labels.js --apply --limit 5
 *   node scripts/restore-collection-labels.js --apply
 *
 * Flags:
 *   --apply            actually write (omit = dry run)
 *   --limit N          cap how many items to update
 *   --snapshot <file>  index.json to read labels from (default: git show 2462fc0d:index.json)
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
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

const SNAPSHOT_COMMIT = '2462fc0d';
const LABEL_WEIGHT = 0.9;

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const limIdx = args.indexOf('--limit');
const LIMIT = limIdx >= 0 ? parseInt(args[limIdx + 1], 10) || Infinity : Infinity;
const snapIdx = args.indexOf('--snapshot');
const SNAPSHOT = snapIdx >= 0 ? args[snapIdx + 1] : null;

const admin = createClient(SUPABASE_URL, SERVICE_KEY);
const parseTags = (t) => (typeof t === 'string' ? JSON.parse(t) : (t || []));

function loadSnapshot() {
  const raw = SNAPSHOT
    ? fs.readFileSync(SNAPSHOT, 'utf8')
    : execFileSync('git', ['show', `${SNAPSHOT_COMMIT}:index.json`], {
      cwd: path.join(__dirname, '..'), maxBuffer: 256 * 1024 * 1024, encoding: 'utf8',
    });
  return JSON.parse(raw).items || [];
}

async function fetchAllItems() {
  const rows = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await admin
      .from('items')
      .select('id, slug, source_url, user_id, tags')
      .order('added_at', { ascending: true })
      .range(from, from + 999);
    if (error) throw new Error(`query failed: ${error.message}`);
    rows.push(...data);
    if (data.length < 1000) return rows;
  }
}

(async () => {
  const snapshot = loadSnapshot();
  const items = await fetchAllItems();
  const bySlug = new Map(items.map(r => [r.slug, r]));
  const byUrl = new Map(items.filter(r => r.source_url).map(r => [r.source_url, r]));

  const plan = [];
  let unmatched = 0, unlabeled = 0, alreadyDone = 0;
  const labelCounts = {};
  for (const s of snapshot) {
    const labels = (s.tags || []).filter(t => t.category === 'domain').map(t => t.tag);
    if (labels.length === 0) { unlabeled++; continue; }
    const row = bySlug.get(s.slug) || (s.source_url && byUrl.get(s.source_url));
    if (!row) { unmatched++; continue; }
    const tags = parseTags(row.tags);
    const have = new Set(tags.filter(t => t.category === 'collection').map(t => t.tag));
    const missing = labels.filter(l => !have.has(l));
    if (missing.length === 0) { alreadyDone++; continue; }
    missing.forEach(l => { labelCounts[l] = (labelCounts[l] || 0) + 1; });
    const next = [...tags, ...missing.map(tag => ({ tag, category: 'collection', weight: LABEL_WEIGHT }))];
    plan.push({ row, before: row.tags, after: JSON.stringify(next), missing });
  }

  const work = plan.slice(0, LIMIT);
  console.log(`\nSnapshot items: ${snapshot.length} · live items: ${items.length}`);
  console.log(`To label: ${plan.length} · already labeled: ${alreadyDone} · no label in snapshot: ${unlabeled} · not in live DB: ${unmatched}`);
  console.log('Labels to add:', Object.entries(labelCounts).sort((a, b) => b[1] - a[1])
    .map(([l, n]) => `${l} ${n}`).join(', ') || '(none)');
  console.log(`${APPLY ? 'APPLYING to' : 'DRY RUN — would update'} ${work.length} items\n`);
  for (const p of work.slice(0, 10)) console.log(`  ${p.row.slug}  + ${p.missing.join(', ')}`);
  if (work.length > 10) console.log(`  …and ${work.length - 10} more`);

  if (!APPLY) {
    console.log('\nNothing written. Re-run with --apply to merge these labels in.');
    return;
  }
  if (work.length === 0) return;

  const dir = path.join(__dirname, '..', '_backups');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `tags-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify(work.map(p => ({ id: p.row.id, slug: p.row.slug, tags: p.before })), null, 1));
  console.log(`Backed up current tags of ${work.length} items → ${path.relative(process.cwd(), file)}`);

  let done = 0, failed = 0;
  for (const p of work) {
    const { error } = await admin.from('items').update({ tags: p.after }).eq('id', p.row.id);
    if (error) {
      failed++;
      console.warn(`  ✗ ${p.row.slug}: ${error.message}`);
    } else done++;
  }
  console.log(`\n✓ Labeled ${done} items${failed ? ` · ${failed} failed (safe to re-run)` : ''}.`);
})().catch((e) => { console.error(e.message); process.exit(1); });
