#!/usr/bin/env node
/**
 * One-time conversion of a v1 Stello folder to format v2 (src/lib/folder-v2.js).
 *
 *   node scripts/convert-folder-v2.mjs --dir "<folder>"            trial: writes to a temp folder, changes nothing
 *   node scripts/convert-folder-v2.mjs --dir "<folder>" --out <d>  trial into <d>
 *   node scripts/convert-folder-v2.mjs --dir "<folder>" --apply    convert the folder in place
 *
 * --apply moves the v1 item files and canvases into <folder>/.stello-v1/ (a backup,
 * nothing is deleted), writes items/<YYYY>/<MM>/, people/, places/, collections/,
 * rewrites canvases to the new paths and sets stello.json to version 2.
 * media/ is not touched: image paths are rewritten, the files stay where they are.
 * It refuses to run if any check fails, or if the folder is already v2.
 */
import { readFile, writeFile, mkdir, readdir, rename } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { homedir, tmpdir } from 'node:os';
import { convertV1, verifyConversion, remapCanvas, FORMAT_VERSION_2 } from '../src/lib/folder-v2.js';

const args = parseArgs(process.argv.slice(2));
if (!args.dir) die('Pass --dir "<folder>".');
const DIR = resolve(String(args.dir).replace(/^~(?=$|\/)/, homedir()));
const APPLY = !!args.apply;
const OUT = APPLY ? DIR : resolve(String(args.out || join(tmpdir(), `stello-v2-trial-${Date.now()}`)).replace(/^~(?=$|\/)/, homedir()));
const t0 = Date.now();

main().catch((e) => die(e && e.stack || String(e)));

async function main() {
  const infoPath = join(DIR, 'stello.json');
  const info = existsSync(infoPath) ? JSON.parse(await readFile(infoPath, 'utf8')) : {};
  if (Number(info.version) >= FORMAT_VERSION_2) die(`${DIR} is already format v${info.version}.`);

  const paths = (await walk(join(DIR, 'items'))).filter((p) => p.endsWith('.md'));
  log(`Reading ${paths.length} item files…`);
  const files = await Promise.all(paths.map(async (abs) => ({ path: abs.slice(DIR.length + 1), text: await readFile(abs, 'utf8') })));

  const out = convertV1(files);
  const problems = verifyConversion(files, out);
  log(JSON.stringify({ ...out.report, challenge_titles: out.report.challenge_titles.length }));
  if (problems.length) {
    log(`${problems.length} problems:\n  ` + problems.slice(0, 40).join('\n  '));
    die('Stopped: fix the problems first. Nothing was changed.');
  }

  // Media sanity: every referenced file exists (only reported; v1 left failed downloads as null).
  let missingMedia = 0;
  for (const e of [...out.items, ...out.people]) {
    for (const img of e.header.images || []) {
      if (!img || !img.file) continue;
      const abs = resolve(join(DIR, dirname(e.path)), img.file);
      if (!existsSync(abs)) missingMedia++;
    }
  }
  log(`Media references with no file on disk: ${missingMedia}`);

  const canvases = existsSync(join(DIR, 'projects')) ? (await readdir(join(DIR, 'projects'))).filter((n) => n.endsWith('.canvas')) : [];

  if (APPLY) {
    // 1. Back up v1 item files and canvases (move, so nothing is stored twice in the live tree).
    const backup = join(DIR, '.stello-v1');
    for (const { path } of files) await move(join(DIR, path), join(backup, path));
    for (const n of canvases) await move(join(DIR, 'projects', n), join(backup, 'projects', n));
    if (existsSync(infoPath)) await move(infoPath, join(backup, 'stello.json'));
  }

  // 2. Write v2 files.
  const all = [...out.items, ...out.people, ...out.places, ...out.collections];
  for (const e of all) await put(join(OUT, e.path), e.text);
  const src = APPLY ? join(DIR, '.stello-v1', 'projects') : join(DIR, 'projects');
  for (const n of canvases) {
    const canvas = JSON.parse(await readFile(join(src, n), 'utf8'));
    await put(join(OUT, 'projects', n), JSON.stringify(remapCanvas(canvas, out.moves), null, 2) + '\n');
  }
  const next = {
    ...info,
    format: info.format || 'stello-folder',
    version: FORMAT_VERSION_2,
    converted_from_v1_at: new Date().toISOString(),
    counts: { items: out.items.length, people: out.people.length, places: out.places.length, collections: out.collections.length, canvases: canvases.length },
  };
  await put(join(OUT, 'stello.json'), JSON.stringify(next, null, 2) + '\n');
  await put(join(OUT, 'conversion-report.json'), JSON.stringify({ ...out.report, missing_media: missingMedia, moves: out.moves }, null, 2) + '\n');

  // 3. Read back what was written.
  let bad = 0;
  for (const e of all) if ((await readFile(join(OUT, e.path), 'utf8')) !== e.text) bad++;
  log(`${all.length} files written to ${OUT}, ${bad} read-back mismatches, ${((Date.now() - t0) / 1000).toFixed(1)} s.`);
  if (!APPLY) log('Trial only: the folder was not changed. Re-run with --apply to convert it.');
  if (bad) process.exit(1);
}

async function walk(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const ent of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, ent.name);
    if (ent.isDirectory()) out.push(...await walk(p));
    else out.push(p);
  }
  return out;
}
async function put(path, text) { await mkdir(dirname(path), { recursive: true }); await writeFile(path, text); }
async function move(from, to) { await mkdir(dirname(to), { recursive: true }); await rename(from, to); }
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) out[key] = true; else { out[key] = next; i++; }
  }
  return out;
}
function log(s) { console.log(`[convert ${((Date.now() - t0) / 1000).toFixed(0)}s] ${s}`); }
function die(s) { console.error(s); process.exit(1); }
