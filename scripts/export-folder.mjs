#!/usr/bin/env node
/**
 * Export the Stello library into the folder format, version 2 (src/lib/folder-v2.js).
 * Read-only: it pulls from the live Worker and never writes to D1 or R2.
 *
 *   node scripts/export-folder.mjs --out "<folder>" [options]
 *
 *   --out <dir>        where to write (made if missing). Example for iCloud Drive:
 *                      ~/Library/Mobile Documents/com~apple~CloudDocs/Stello
 *   --base <url>       Worker origin (default https://stello.arjunphlox.workers.dev)
 *   --token <t>        a device token; default: pair now (a code opens in the browser,
 *                      approve it while signed in to Stello). STELLO_TOKEN works too.
 *   --no-images        skip image downloads
 *   --limit <n>        export only the first n live items (for a trial run)
 *   --concurrency <n>  parallel image downloads (default 16)
 *   --keep-token       don't revoke a token this run paired
 *
 * Re-running is safe: unchanged files are left alone and images already on disk
 * are skipped. Deleted (trashed or purged) items are left out.
 * Plan: docs/plans/folder-engine.md.
 */
import { mkdir, writeFile, readFile, readdir, stat, rename } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { execFile } from 'node:child_process';
import {
  FORMAT, FORMAT_VERSION, itemPath, mediaFiles, imageExt, itemToMarkdown, markdownToItem, diffItem,
  canvasToJsonCanvas, safeName,
} from '../src/lib/folder-format.js';
import { FORMAT_VERSION_2, LAYOUT_V2, convertV1, verifyConversion, remapCanvas } from '../src/lib/folder-v2.js';

const args = parseArgs(process.argv.slice(2));
const BASE = (args.base || 'https://stello.arjunphlox.workers.dev').replace(/\/$/, '');
if (!args.out) die('Pass --out "<folder>".');
const OUT = resolve(String(args.out).replace(/^~(?=$|\/)/, homedir()));
const CONC = Math.max(1, Math.min(64, parseInt(args.concurrency || '16', 10) || 16));
const LIMIT = args.limit ? parseInt(args.limit, 10) : 0;
const t0 = Date.now();

main().catch((e) => die(e && e.stack || String(e)));

async function main() {
  // This writes format v2. A v1 folder is converted first (scripts/convert-folder-v2.mjs),
  // so its v1 files are kept in .stello-v1/ instead of sitting beside the new ones.
  let previous = {};
  try {
    previous = JSON.parse(await readFile(join(OUT, 'stello.json'), 'utf8'));
    if (Number(previous.version) < FORMAT_VERSION_2) die(`${OUT} is folder format v${previous.version}. Convert it first: node scripts/convert-folder-v2.mjs --dir "${OUT}" --apply`);
    if (Number(previous.version) > FORMAT_VERSION_2) die(`${OUT} is folder format v${previous.version}; this export writes v${FORMAT_VERSION_2}.`);
  } catch (e) { if (e && e.code !== 'ENOENT' && !(e instanceof SyntaxError)) throw e; }
  let token = args.token || process.env.STELLO_TOKEN || '';
  let paired = false;
  if (!token) { token = await pair(); paired = true; }
  const api = (path, init = {}) => fetchJson(`${BASE}${path}`, { ...init, headers: { authorization: `Bearer ${token}`, ...(init.headers || {}) } });

  try {
    // 1. Items
    log('Reading items…');
    const all = [];
    let since = 0;
    for (;;) {
      const page = await api(`/api/sync/pull?since=${since}&limit=500`);
      all.push(...page.items);
      since = page.cursor;
      if (!page.more) break;
    }
    const live = all.filter((i) => !i.purged && (i.deleted_at === null || i.deleted_at === undefined));
    live.sort((a, b) => String(b.added_at || '').localeCompare(String(a.added_at || '')));
    const items = LIMIT ? live.slice(0, LIMIT) : live;
    log(`${all.length} rows, ${live.length} live, exporting ${items.length}.`);

    // Unique file names (slugs are unique, but cleaned names could collide).
    const paths = new Map();
    const used = new Set();
    for (const it of items) {
      let p = itemPath(it);
      if (used.has(p.toLowerCase())) p = p.replace(/\.md$/, `-${String(it.id).slice(0, 8)}.md`);
      used.add(p.toLowerCase());
      paths.set(it.id, p);
    }
    const slugToPath = new Map(items.map((it) => [it.slug, paths.get(it.id)]));

    // 2. Images
    const plans = new Map(items.map((it) => [it.id, mediaFiles(it, {}, paths.get(it.id))]));
    const jobs = [];
    for (const it of items) {
      for (const f of plans.get(it.id)) if (f.remote && f.file) jobs.push({ it, f });
    }
    const img = { total: jobs.length, done: 0, skipped: 0, failed: [] };
    if (args['no-images']) {
      for (const { f } of jobs) f.file = null;
    } else {
      log(`Downloading ${jobs.length} images, ${CONC} at a time…`);
      let last = 0;
      await pool(jobs, CONC, async ({ it, f }) => {
        const ok = await downloadImage(f);
        if (ok === 'skipped') img.skipped++;
        else if (ok) img.done++;
        else { img.failed.push({ id: it.id, slug: it.slug, path: f.remote }); f.file = null; }
        const n = img.done + img.skipped + img.failed.length;
        if (n - last >= 250 || n === jobs.length) { last = n; log(`  images ${n}/${jobs.length} (${img.failed.length} failed)`); }
      });
    }

    // 3. Item files: v1 text in memory (round-trip checked), then the v2 conversion
    //    (people and places by id; collections folded into kinds/tags; month folders), then write.
    log('Building item files…');
    const report = { written: 0, unchanged: 0, roundTripErrors: [] };
    const v1 = [];
    for (const it of items) {
      const text = itemToMarkdown(it, plans.get(it.id));
      const diff = diffItem(it, markdownToItem(text, { slug: it.slug }));
      if (diff.length) report.roundTripErrors.push({ id: it.id, slug: it.slug, fields: diff });
      v1.push({ path: paths.get(it.id), text });
    }
    const out = convertV1(v1);
    const problems = verifyConversion(v1, out);
    if (problems.length) die(`v2 checks failed, nothing written:\n  ${problems.slice(0, 40).join('\n  ')}`);
    const v2files = [...out.items, ...out.people, ...out.places];
    log(`Writing ${v2files.length} files (${out.items.length} items, ${out.people.length} people, ${out.places.length} places; ${out.report.collections_folded} items had collections folded)…`);
    for (const e of v2files) (await writeIfChanged(join(OUT, e.path), e.text)) ? report.written++ : report.unchanged++;
    // Files from an earlier export that this run didn't produce (a deleted save, a renamed
    // person) are listed, never deleted.
    const produced = new Set(v2files.map((e) => e.path));
    const stale = [];
    // collections/ is listed too: collections were retired, so any file there is stale.
    for (const dir of ['items', 'people', 'places', 'collections']) {
      for (const abs of await walkMd(join(OUT, dir))) { const rel = abs.slice(OUT.length + 1); if (!produced.has(rel)) stale.push(rel); }
    }

    // 4. Canvas docs
    log('Writing canvases…');
    let canvases = 0;
    try {
      const { projects = [] } = await api('/api/projects');
      const ids = new Set(['library', ...projects.map((p) => p.id)]);
      for (const id of ids) {
        const { project } = await api(`/api/projects/${encodeURIComponent(id)}`);
        if (!project) continue;
        const canvas = remapCanvas(canvasToJsonCanvas(project, (slug) => slugToPath.get(slug) || null), out.moves);
        if (id === 'library' && !canvas.nodes.length) continue;
        const name = id === 'library' ? 'Library canvas' : (project.name || id);
        await writeIfChanged(join(OUT, 'projects', `${safeName(name, id)}.canvas`), JSON.stringify(canvas, null, 2) + '\n');
        canvases++;
      }
    } catch (e) {
      log(`  canvases skipped: ${e.message}`);
    }

    // 5. stello.json + report
    const seconds = Math.round((Date.now() - t0) / 1000);
    const info = {
      ...previous,
      format: FORMAT,
      version: FORMAT_VERSION_2,
      exported_at: new Date().toISOString(),
      exported_from: BASE,
      counts: { items: out.items.length, people: out.people.length, places: out.places.length, images: img.total - img.failed.length, canvases },
      layout: LAYOUT_V2,
    };
    await writeIfChanged(join(OUT, 'stello.json'), JSON.stringify(info, null, 2) + '\n');
    const summary = {
      seconds,
      rows: all.length,
      live: live.length,
      exported: items.length,
      files: { written: report.written, unchanged: report.unchanged },
      images: { total: img.total, downloaded: img.done, already_there: img.skipped, failed: img.failed.length },
      canvases,
      round_trip_errors: report.roundTripErrors.length,
      v2: { items: out.items.length, people: out.people.length, places: out.places.length, collections_folded: out.report.collections_folded, merged_urls: out.report.merged_urls },
      stale_files: stale.length,
    };
    await writeFile(join(OUT, 'export-report.json'), JSON.stringify({ ...summary, failed_images: img.failed, round_trip: report.roundTripErrors, stale, merges: out.report.merges || [] }, null, 2) + '\n');
    log(`Done in ${seconds}s.`);
    console.log(JSON.stringify(summary, null, 2));
  } finally {
    if (paired && !args['keep-token']) {
      await fetch(`${BASE}/api/auth/logout`, { method: 'POST', headers: { authorization: `Bearer ${token}` } }).catch(() => {});
    }
  }

  async function downloadImage(f) {
    const base = join(OUT, f.file.replace(/\.[^./]+$/, ''));
    for (const ext of ['webp', 'png', 'jpg', 'gif', 'avif', 'heic', 'img']) {
      if (existsSync(`${base}.${ext}`)) {
        const s = await stat(`${base}.${ext}`);
        if (s.size > 0) { f.file = `${f.file.replace(/\.[^./]+$/, '')}.${ext}`; return 'skipped'; }
      }
    }
    const url = /^https?:/i.test(f.remote) ? f.remote : `${BASE}${f.remote.startsWith('/') ? '' : '/'}${f.remote}`;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const res = await fetch(url, { signal: AbortSignal.timeout(30000) });
        if (res.status === 404) return false;
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const bytes = Buffer.from(await res.arrayBuffer());
        if (!bytes.length) return false;
        f.file = `${f.file.replace(/\.[^./]+$/, '')}.${imageExt(f.remote, res.headers.get('content-type'))}`;
        const dest = join(OUT, f.file);
        await mkdir(dirname(dest), { recursive: true });
        await writeFile(`${dest}.part`, bytes);
        await rename(`${dest}.part`, dest);
        return true;
      } catch {
        await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
      }
    }
    return false;
  }
}

async function pair() {
  const start = await fetchJson(`${BASE}/api/pair/start`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ label: 'Folder export' }),
  });
  log(`Approve this export in Stello: ${start.url}  (code ${start.code})`);
  if (process.platform === 'darwin') execFile('open', [start.url], () => {});
  const until = Date.now() + (start.expires_in || 600) * 1000;
  while (Date.now() < until) {
    await new Promise((r) => setTimeout(r, 2000));
    const res = await fetch(`${BASE}/api/pair/poll`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ code: start.code, poll: start.poll }),
    });
    if (res.status === 410) die('The pairing code expired. Run the export again.');
    const out = await res.json().catch(() => ({}));
    if (out.token) { log('Approved.'); return out.token; }
  }
  die('No approval within 10 minutes. Run the export again.');
}

async function walkMd(dir) {
  if (!existsSync(dir)) return [];
  const found = [];
  for (const ent of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, ent.name);
    if (ent.isDirectory()) found.push(...await walkMd(p));
    else if (ent.name.endsWith('.md')) found.push(p);
  }
  return found;
}

async function writeIfChanged(path, text) {
  try { if ((await readFile(path, 'utf8')) === text) return false; } catch {}
  await mkdir(dirname(path), { recursive: true });
  await writeFile(`${path}.part`, text);
  await rename(`${path}.part`, path);
  return true;
}

async function fetchJson(url, init) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, { ...init, signal: AbortSignal.timeout(60000) }).catch((e) => ({ ok: false, status: 0, e }));
    if (res.ok) return res.json();
    if (res.status === 401) die('Not signed in: the token was refused.');
    if (attempt >= 3 || (res.status && res.status < 500 && res.status !== 429)) {
      throw new Error(`${url.replace(BASE, '')}: HTTP ${res.status || res.e?.message}`);
    }
    await new Promise((r) => setTimeout(r, 1000 * (attempt + 1)));
  }
}

async function pool(list, n, fn) {
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, list.length) }, async () => {
    while (i < list.length) await fn(list[i++]);
  }));
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) out[key] = true;
    else { out[key] = next; i++; }
  }
  return out;
}

function log(msg) { console.error(`[export ${Math.round((Date.now() - t0) / 1000)}s] ${msg}`); }
function die(msg) { console.error(msg); process.exit(1); }
