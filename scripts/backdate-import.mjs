#!/usr/bin/env node
/**
 * Back-date one bulk import: give every item it made a random saved date (added_at) between
 * two dates, with about the same number per week. Only added_at changes.
 *
 *   node scripts/backdate-import.mjs                     plan only: lists the import groups, writes nothing
 *   node scripts/backdate-import.mjs --added <iso> --expect <n> --apply
 *
 *   --added <iso>     the exact added_at the import stamped on all its items (the import
 *                     run writes one timestamp for the whole run, so this picks out its
 *                     items and nothing else)
 *   --expect <n>      stop unless exactly n live items carry that timestamp
 *   --from <date>     first day, inclusive (default 2024-01-01)
 *   --to <date>       last day, inclusive (default 2026-01-31)
 *   --seed <n>        random seed (default 20261127), so plan and apply give the same dates
 *   --base, --token   as in the other scripts (STELLO_TOKEN works; default: pair now)
 *   --keep-token      don't revoke a token this run paired
 *
 * Before writing, the items' current added_at is saved to
 * ~/Documents/Stello-backups/backdate-before-<date>.json (and the new dates beside it).
 * Writes go through /api/sync/push, so the Apple apps pull them as normal edits.
 * Undo: push the backup's added_at values back the same way.
 */
import { writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { execFile } from 'node:child_process';
import { rng, spreadDates, shuffle, weeks } from '../src/lib/backdate.js';

const args = parseArgs(process.argv.slice(2));
const BASE = (args.base || 'https://stello.arjunphlox.workers.dev').replace(/\/$/, '');
const APPLY = !!args.apply;
const DAY = 86400000;
const FROM = Date.parse(`${args.from || '2024-01-01'}T00:00:00Z`);
const TO = Date.parse(`${args.to || '2026-01-31'}T00:00:00Z`) + DAY; // exclusive
const SEED = parseInt(args.seed || '20261127', 10);
const t0 = Date.now();

main().catch((e) => die(e && e.stack || String(e)));

async function main() {
  if (!(FROM < TO)) die('--from must be before --to.');
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
    const groups = new Map();
    for (const i of live) groups.set(i.added_at, (groups.get(i.added_at) || 0) + 1);
    const top = [...groups].filter(([, n]) => n > 1).sort((a, b) => b[1] - a[1]).slice(0, 5);
    log(`Library: ${live.length} live items. Largest groups sharing one added_at: ${JSON.stringify(top)}`);
    if (!args.added) { log('Plan only. Pass --added <iso> --expect <n> to pick a group.'); return; }

    const picked = live.filter((i) => i.added_at === args.added);
    if (args.expect && picked.length !== Number(args.expect)) die(`Expected ${args.expect} items at ${args.added}, found ${picked.length}. Nothing written.`);
    if (!picked.length) die(`No items at ${args.added}.`);

    const random = rng(SEED);
    const ids = shuffle(picked.map((i) => i.id).sort(), random);
    const dates = spreadDates(ids.length, FROM, TO, random);
    const plan = ids.map((id, k) => ({ id, added_at: new Date(dates[k]).toISOString() }));
    const perWeek = weeks(FROM, TO).map((w) => dates.filter((d) => d >= w.start && d < w.end).length);
    const summary = {
      items: plan.length, from: new Date(FROM).toISOString(), to: new Date(TO - 1).toISOString(),
      weeks: perWeek.length, per_week_min: Math.min(...perWeek), per_week_max: Math.max(...perWeek),
      last_week_days: Math.round((TO - weeks(FROM, TO).at(-1).start) / DAY), last_week_items: perWeek.at(-1),
      earliest: plan.reduce((a, p) => (p.added_at < a ? p.added_at : a), plan[0].added_at),
      latest: plan.reduce((a, p) => (p.added_at > a ? p.added_at : a), plan[0].added_at),
      others_untouched: live.length - plan.length,
    };
    log(JSON.stringify(summary));
    if (!APPLY) { log('Plan only. Re-run with --apply to write.'); return; }

    const dir = join(homedir(), 'Documents', 'Stello-backups');
    await mkdir(dir, { recursive: true });
    const day = new Date().toISOString().slice(0, 10);
    const before = join(dir, `backdate-before-${day}.json`);
    await writeFile(before, JSON.stringify(picked.map((i) => ({ id: i.id, slug: i.slug, title: i.title, added_at: i.added_at })), null, 1));
    await writeFile(join(dir, `backdate-after-${day}.json`), JSON.stringify(plan, null, 1));
    log(`Saved the before-state of ${picked.length} items to ${before}`);

    const now = Date.now();
    let applied = 0;
    const other = {};
    for (let i = 0; i < plan.length; i += 100) {
      const changes = plan.slice(i, i + 100).map((p) => ({ id: p.id, fields: { added_at: p.added_at }, clock: now }));
      const out = await api('/api/sync/push', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ changes }) });
      for (const r of out.results || []) { if (r.status === 'applied') applied++; else other[r.status] = (other[r.status] || 0) + 1; }
    }
    console.log(JSON.stringify({ ...summary, applied, not_applied: other, backup: before, seconds: Math.round((Date.now() - t0) / 1000) }, null, 2));
  } finally {
    if (paired && !args['keep-token']) await fetch(`${BASE}/api/auth/logout`, { method: 'POST', headers: { authorization: `Bearer ${token}` } }).catch(() => {});
  }
}

async function pair() {
  const start = await fetchJson(`${BASE}/api/pair/start`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ label: 'Back-date import' }) });
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
function log(s) { console.log(`[backdate ${((Date.now() - t0) / 1000).toFixed(0)}s] ${s}`); }
function die(s) { console.error(s); process.exit(1); }
