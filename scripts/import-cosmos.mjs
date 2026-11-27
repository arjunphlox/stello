#!/usr/bin/env node
/**
 * Bring the Cosmos notes (the old cosmos/ topic notes, now iCloud Drive/Stello/Cosmos)
 * into the Stello library, with no duplicates.
 *
 *   node scripts/import-cosmos.mjs --dir "<Cosmos folder>"            plan only (default): prints counts, writes nothing
 *   node scripts/import-cosmos.mjs --dir "<Cosmos folder>" --apply    import
 *
 *   --base <url>      Worker origin (default https://stello.arjunphlox.workers.dev)
 *   --token <t>       device token (or STELLO_TOKEN); default: pair now
 *   --no-covers       skip fetching og:image covers for new links
 *   --concurrency <n> parallel cover fetches and uploads (default 20)
 *
 * What it does:
 *   - Reads every note: table notes ("| Item | Source URL |"), card notes ("## 1. Title"
 *     with image, caption, tags, source) and "[View Image](images/x)" rows.
 *   - Each note's name becomes a `collection` tag (same slug style as the library's).
 *   - A link already in the library (normalised URL) only gains the collection tag.
 *     A new link becomes a plain link item (the Mac app gives it a kind, from its own
 *     IP, as for any web save). A note image with no link becomes an image item; the
 *     same image file in two notes is one item.
 *   - New items get their note image as cover, or else the page's og:image, fetched in
 *     parallel from this machine. No AI and no serial page reads (import speed rule).
 *   - Writes go through /api/sync/push (100 per request), so every app pulls them as
 *     normal edits. Images go to /api/sync/image (content-addressed).
 * Re-running is safe: items it made are found by URL or image hash and left alone.
 */
import { readFile, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, resolve, dirname, extname, basename } from 'node:path';
import { homedir, tmpdir } from 'node:os';
import { execFile } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { normaliseUrl } from '../src/lib/folder-v2.js';
import { parseNote, collectionSlug } from '../src/lib/cosmos.js';
import { ruleTags } from '../engine/index.js';

const args = parseArgs(process.argv.slice(2));
if (!args.dir) die('Pass --dir "<Cosmos folder>".');
const DIR = resolve(String(args.dir).replace(/^~(?=$|\/)/, homedir()));
const BASE = (args.base || 'https://stello.arjunphlox.workers.dev').replace(/\/$/, '');
const APPLY = !!args.apply;
const CONC = Math.max(1, Math.min(48, parseInt(args.concurrency || '20', 10) || 20));
const t0 = Date.now();

main().catch((e) => die(e && e.stack || String(e)));

async function main() {
  // 1. Notes → entries.
  const notes = (await walk(DIR)).filter((p) => p.endsWith('.md'));
  const entries = [];
  for (const abs of notes) {
    const text = await readFile(abs, 'utf8');
    const name = basename(abs, '.md');
    for (const e of parseNote(text, name)) {
      if (e.image) e.imageAbs = resolve(dirname(abs), decodeURI(e.image));
      entries.push(e);
    }
  }
  // Unreferenced images in a note's folder (e.g. Quotes/images/*.heic) become image items too.
  const referenced = new Set(entries.filter((e) => e.imageAbs).map((e) => e.imageAbs));
  for (const abs of notes) {
    const imgDir = join(dirname(abs), 'images');
    if (!existsSync(imgDir)) continue;
    const note = basename(abs, '.md');
    for (const f of await readdir(imgDir)) {
      const p = join(imgDir, f);
      if (!/\.(webp|jpe?g|png|gif|heic)$/i.test(f) || referenced.has(p)) continue;
      referenced.add(p);
      entries.push({ collection: note, title: `${note} image`, url: null, imageAbs: p, caption: null, tags: [] });
    }
  }
  log(`${notes.length} notes, ${entries.length} entries.`);

  // 2. One record per link (normalised) or per image file (content hash).
  const byKey = new Map();
  for (const e of entries) {
    let key;
    if (e.url) key = 'u:' + normaliseUrl(e.url);
    else if (e.imageAbs && existsSync(e.imageAbs)) key = 'h:' + createHash('sha256').update(await readFile(e.imageAbs)).digest('hex');
    else continue; // a bare card with neither link nor image
    const r = byKey.get(key) || { key, url: e.url, title: null, caption: null, tags: new Set(), collections: new Set(), imageAbs: null };
    r.title ||= e.title; r.caption ||= e.caption; r.imageAbs ||= e.imageAbs && existsSync(e.imageAbs) ? e.imageAbs : null;
    e.tags.forEach((t) => r.tags.add(t));
    r.collections.add(collectionSlug(e.collection));
    byKey.set(key, r);
  }
  const records = [...byKey.values()];

  // 3. The library as it is now.
  let token = args.token || process.env.STELLO_TOKEN || '';
  let paired = false;
  if (!token) { token = await pair(); paired = true; }
  const api = (path, init = {}) => fetchJson(`${BASE}${path}`, { ...init, headers: { authorization: `Bearer ${token}`, ...(init.headers || {}) } });
  try {
    const live = [];
    let since = 0;
    for (;;) {
      const page = await api(`/api/sync/pull?since=${since}&limit=500`);
      live.push(...page.items.filter((i) => !i.purged && i.deleted_at == null));
      since = page.cursor;
      if (!page.more) break;
    }
    const byUrl = new Map(live.filter((i) => i.source_url).map((i) => [normaliseUrl(i.source_url), i]));
    const byImage = new Map();
    for (const i of live) for (const img of i.images || []) { const m = /\/sync\/([0-9a-f]{64})\./.exec(img.path || ''); if (m) byImage.set(m[1], i); }

    const updates = [];
    const fresh = [];
    for (const r of records) {
      const hit = r.key.startsWith('u:') ? byUrl.get(r.key.slice(2)) : byImage.get(r.key.slice(2));
      if (!hit) { fresh.push(r); continue; }
      const tags = Array.isArray(hit.tags) ? hit.tags : [];
      const have = new Set(tags.filter((t) => t.category === 'collection').map((t) => t.tag));
      const add = [...r.collections].filter((c) => !have.has(c));
      if (add.length) updates.push({ item: hit, tags: [...tags, ...add.map((tag) => ({ tag, category: 'collection', weight: 0.9 }))] });
    }
    const summary = {
      notes: notes.length, entries: entries.length, distinct: records.length,
      already_in_library: records.length - fresh.length, gain_collection_tag: updates.length,
      new_items: fresh.length, new_links: fresh.filter((r) => r.url).length, new_images: fresh.filter((r) => !r.url).length,
    };
    log(JSON.stringify(summary));
    if (!APPLY) { log('Plan only. Re-run with --apply to import.'); return; }

    // 4. Covers: the note's image, else the page's og:image (parallel, short timeout).
    let covers = 0, coverMiss = 0;
    await pool(fresh, CONC, async (r) => {
      let bytes = null, type = null;
      if (r.imageAbs) ({ bytes, type } = await localImage(r.imageAbs));
      else if (r.url && !args['no-covers']) ({ bytes, type } = await ogImage(r.url));
      if (!bytes) { coverMiss++; return; }
      try {
        const up = await fetchJson(`${BASE}/api/sync/image`, { method: 'PUT', headers: { authorization: `Bearer ${token}`, 'content-type': type }, body: bytes });
        r.image = { path: up.path, source: r.imageAbs ? 'manual' : 'og', is_primary: true };
        covers++;
      } catch { coverMiss++; }
    }, (n) => n % 250 === 0 && log(`  covers ${n}/${fresh.length}`));
    log(`Covers: ${covers} stored, ${coverMiss} without one.`);

    // 5. Push.
    const now = Date.now();
    const iso = new Date(now).toISOString();
    const changes = [
      ...updates.map((u) => ({ id: u.item.id, fields: { tags: u.tags }, clock: now })),
      ...fresh.map((r) => newItem(r, iso, now)),
    ];
    let applied = 0;
    for (let i = 0; i < changes.length; i += 100) {
      const out = await api('/api/sync/push', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ changes: changes.slice(i, i + 100) }) });
      applied += (out.results || []).filter((x) => x.status === 'applied').length;
      if ((i / 100) % 10 === 0) log(`  pushed ${Math.min(i + 100, changes.length)}/${changes.length}`);
    }
    log(`Done in ${Math.round((Date.now() - t0) / 1000)}s: ${applied} of ${changes.length} changes applied.`);
    console.log(JSON.stringify({ ...summary, covers, applied, seconds: Math.round((Date.now() - t0) / 1000) }, null, 2));
  } finally {
    if (paired) await fetch(`${BASE}/api/auth/logout`, { method: 'POST', headers: { authorization: `Bearer ${token}` } }).catch(() => {});
  }
}

function newItem(r, iso, now) {
  const id = randomUUID();
  let domain = null;
  try { domain = r.url ? new URL(r.url).hostname.replace(/^www\./, '') : null; } catch { /* keep null */ }
  const title = (r.title || domain || 'Cosmos image').slice(0, 300);
  const summary = r.caption ? r.caption.slice(0, 200) : null;
  const tags = [
    ...[...r.collections].map((tag) => ({ tag, category: 'collection', weight: 0.9 })),
    ...[...r.tags].slice(0, 8).map((tag) => ({ tag: tag.toLowerCase(), category: 'subject', weight: 0.6 })),
  ];
  if (!r.url) tags.push({ tag: 'image-upload', category: 'format', weight: 0.4 });
  const seen = new Set(tags.map((t) => t.tag));
  for (const t of ruleTags({ title, domain, description: summary || '', url: r.url })) if (!seen.has(t.tag)) { seen.add(t.tag); tags.push(t); }
  return {
    id,
    full: true,
    clock: now,
    fields: {
      slug: `${slugify(title)}-${id.slice(0, 6)}`,
      title,
      source_url: r.url || null,
      domain,
      summary,
      body_markdown: null,
      status: 'active',
      needs_review: false,
      kind: r.url ? 'link' : null,
      // No AI on the import path: links wait for the Mac's rules (as any web save),
      // images are done.
      enrichment_status: r.url ? 'awaiting_classify' : 'candidates_done',
      added_at: iso,
      tags,
      images: r.image ? [r.image] : [],
      snippets: [],
      metadata: null,
    },
  };
}

function slugify(s) { return collectionSlug(s).slice(0, 60) || 'item'; }

const TYPES = { webp: 'image/webp', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif' };
async function localImage(abs) {
  let ext = extname(abs).slice(1).toLowerCase();
  let path = abs;
  if (ext === 'heic') {
    // HEIC isn't accepted by the Worker; macOS converts it (sips ships with the OS).
    path = join(tmpdir(), `cosmos-${createHash('md5').update(abs).digest('hex')}.jpg`);
    const ok = await new Promise((res) => execFile('sips', ['-s', 'format', 'jpeg', abs, '--out', path], (err) => res(!err)));
    if (!ok) return { bytes: null };
    ext = 'jpg';
  }
  const type = TYPES[ext];
  if (!type) return { bytes: null };
  const bytes = await readFile(path);
  return bytes.length > 15 * 1024 * 1024 ? { bytes: null } : { bytes, type };
}

async function ogImage(url) {
  try {
    const page = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(8000), headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Version/18.0 Safari/605.1.15', Accept: 'text/html' } });
    if (!page.ok || !/html/i.test(page.headers.get('content-type') || '')) return { bytes: null };
    const html = (await page.text()).slice(0, 400_000);
    const m = /<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)(?::src)?["'][^>]*content=["']([^"']+)["']/i.exec(html)
      || /<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["'](?:og:image|twitter:image)["']/i.exec(html);
    if (!m) return { bytes: null };
    const src = new URL(m[1].replace(/&amp;/g, '&'), page.url).href;
    const img = await fetch(src, { signal: AbortSignal.timeout(8000) });
    const type = (img.headers.get('content-type') || '').split(';')[0].toLowerCase();
    if (!img.ok || !Object.values(TYPES).includes(type)) return { bytes: null };
    const bytes = Buffer.from(await img.arrayBuffer());
    return bytes.length && bytes.length <= 15 * 1024 * 1024 ? { bytes, type } : { bytes: null };
  } catch { return { bytes: null }; }
}

async function pool(list, n, fn, tick = () => {}) {
  let i = 0, done = 0;
  await Promise.all(Array.from({ length: Math.min(n, list.length) }, async () => {
    while (i < list.length) { const it = list[i++]; await fn(it); tick(++done); }
  }));
}
async function walk(dir) {
  const out = [];
  for (const ent of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, ent.name);
    if (ent.isDirectory()) out.push(...await walk(p)); else out.push(p);
  }
  return out;
}
async function pair() {
  const start = await fetchJson(`${BASE}/api/pair/start`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ label: 'Cosmos import' }) });
  log(`Approve this in Stello: ${start.url}  (code ${start.code})`);
  if (process.platform === 'darwin') execFile('open', [start.url], () => {});
  const until = Date.now() + (start.expires_in || 600) * 1000;
  while (Date.now() < until) {
    await new Promise((r) => setTimeout(r, 2000));
    const res = await fetch(`${BASE}/api/pair/poll`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ code: start.code, poll: start.poll }) });
    if (res.status === 410) die('The pairing code expired. Run it again.');
    const out = await res.json().catch(() => ({}));
    if (out.token) { log('Approved.'); return out.token; }
  }
  die('No approval within 10 minutes. Run it again.');
}
async function fetchJson(url, init) {
  const r = await fetch(url, init);
  const text = await r.text();
  if (!r.ok) throw new Error(`${init?.method || 'GET'} ${url}: ${r.status} ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : {};
}
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) out[a.slice(2)] = true; else { out[a.slice(2)] = next; i++; }
  }
  return out;
}
function log(s) { console.log(`[cosmos ${((Date.now() - t0) / 1000).toFixed(0)}s] ${s}`); }
function die(s) { console.error(s); process.exit(1); }
