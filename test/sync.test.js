import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeD1, SCHEMA } from './d1-shim.js';
import {
  applyChanges, pullChanges, mergeChange, purgeExpired, deleteChange, restoreChange,
  writeSnapshot, RESTORE_WINDOW_MS, MAX_FUTURE_MS,
} from '../src/lib/sync.js';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const full = (id, fields, clock) => ({ id, fields, clock, full: true });

test('create needs a full item; a partial change to an unknown id asks for one', async () => {
  const db = makeD1(SCHEMA);
  let r = await applyChanges(db, 'u1', [{ id: A, fields: { title: 'x' }, clock: 1 }]);
  assert.equal(r.results[0].status, 'needs_full');
  r = await applyChanges(db, 'u1', [full(A, { title: 'Hello', tags: [{ name: 'a', category: 'style', weight: 1 }] }, 100)]);
  assert.equal(r.results[0].status, 'applied');
  assert.equal(r.cursor, 1);
  const { items } = await pullChanges(db, 'u1', 0);
  assert.equal(items[0].title, 'Hello');
  assert.equal(items[0].slug, A);
  assert.deepEqual(items[0].tags, [{ category: 'style', name: 'a', weight: 1 }]);
});

test('per-field last write wins, ties keep the server value', async () => {
  const db = makeD1(SCHEMA);
  await applyChanges(db, 'u1', [full(A, { title: 'one', summary: 's1' }, 100)]);
  // App: newer title, older summary.
  await applyChanges(db, 'u1', [{ id: A, fields: { title: 'two', summary: 'old' }, clock: { title: 200, summary: 50 } }]);
  let [item] = (await pullChanges(db, 'u1', 0)).items;
  assert.equal(item.title, 'two');
  assert.equal(item.summary, 's1');
  // Tie on title.
  await applyChanges(db, 'u1', [{ id: A, fields: { title: 'tie' }, clock: { title: 200 } }]);
  [item] = (await pullChanges(db, 'u1', 0)).items;
  assert.equal(item.title, 'two');
});

test('echo with the same value does not bump seq', async () => {
  const db = makeD1(SCHEMA);
  await applyChanges(db, 'u1', [full(A, { title: 't', tags: [{ weight: 1, name: 'n' }] }, 100)]);
  const r = await applyChanges(db, 'u1', [{ id: A, fields: { title: 't', tags: [{ name: 'n', weight: 1 }] }, clock: 999 }]);
  assert.equal(r.results[0].status, 'unchanged');
  assert.equal(r.cursor, 1);
});

test('pull pages in seq order and never skips', async () => {
  const db = makeD1(SCHEMA);
  const ids = Array.from({ length: 30 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`);
  await applyChanges(db, 'u1', ids.map((id, i) => full(id, { title: `t${i}` }, 10)));
  await applyChanges(db, 'u1', [{ id: ids[0], fields: { title: 'edited' }, clock: 20 }]);
  const seen = [];
  let since = 0;
  for (;;) {
    const page = await pullChanges(db, 'u1', since, 7);
    seen.push(...page.items.map((i) => i.title));
    since = page.cursor;
    if (!page.more) break;
  }
  assert.equal(seen.length, 30);
  assert.equal(seen[seen.length - 1], 'edited');
  assert.ok(!seen.includes('t0'));
});

test('users are isolated, even with a colliding id', async () => {
  const db = makeD1(SCHEMA);
  await applyChanges(db, 'u1', [full(A, { title: 'mine' }, 1)]);
  const r = await applyChanges(db, 'u2', [full(A, { title: 'theirs' }, 2)]);
  assert.equal(r.results[0].status, 'conflict');
  assert.equal((await pullChanges(db, 'u2', 0)).items.length, 0);
  assert.equal((await pullChanges(db, 'u1', 0)).items[0].title, 'mine');
});

test('delete is a field: a later edit does not undelete, a later restore does', async () => {
  const db = makeD1(SCHEMA);
  await applyChanges(db, 'u1', [full(A, { title: 't' }, 100)]);
  await applyChanges(db, 'u1', [deleteChange(A, 200)]);
  await applyChanges(db, 'u1', [{ id: A, fields: { title: 'edit' }, clock: 300 }]);
  let [item] = (await pullChanges(db, 'u1', 0)).items;
  assert.equal(item.deleted_at, 200);
  assert.equal(item.title, 'edit');
  await applyChanges(db, 'u1', [restoreChange(A, 400)]);
  [item] = (await pullChanges(db, 'u1', 0)).items;
  assert.equal(item.deleted_at, null);
});

test('purge keeps a tombstone and refuses changes to it', async () => {
  const db = makeD1(SCHEMA);
  const now = Date.now();
  await applyChanges(db, 'u1', [full(A, { title: 't', images: [{ path: '/img/u1/a.webp' }] }, 1)]);
  await applyChanges(db, 'u1', [full(B, { title: 'keep' }, 1)]);
  await applyChanges(db, 'u1', [deleteChange(A, now - RESTORE_WINDOW_MS - 1000)], now);
  const out = await purgeExpired(db, now);
  assert.equal(out.purged, 1);
  assert.deepEqual(out.imagePaths, ['/img/u1/a.webp']);
  const row = db.raw.prepare('SELECT * FROM items WHERE id = ?').get(A);
  assert.equal(row.title, '');
  assert.ok(row.purged_at);
  const r = await applyChanges(db, 'u1', [restoreChange(A, now)], now);
  assert.equal(r.results[0].status, 'purged');
});

test('clocks far in the future are clamped', () => {
  const now = 1_000_000;
  const row = { id: A, seq: 1, title: 'a', field_clock: '{}' };
  const m = mergeChange(row, { id: A, fields: { title: 'b' }, clock: now * 10 }, now);
  assert.equal(m.clock.title, now + MAX_FUTURE_MS);
});

test('wrong types and unknown fields are ignored', () => {
  const m = mergeChange(null, full(A, { title: 5, needs_review: 'yes', user_id: 'u2', summary: 's' }, 1));
  assert.equal(m.write.summary, 's');
  assert.equal(m.write.title, '');
  assert.ok(!('needs_review' in m.write));
  assert.ok(!('user_id' in m.write));
});

test('snapshot writes gzipped JSON of every row', async () => {
  const db = makeD1(SCHEMA);
  await applyChanges(db, 'u1', [full(A, { title: 'one' }, 1), full(B, { title: 'two' }, 1)]);
  const store = {};
  const bucket = { put: async (k, v) => { store[k] = v; } };
  const out = await writeSnapshot(db, bucket, 'u1', new Date('2026-11-06T00:00:00Z'));
  assert.equal(out.count, 2);
  const blob = store['snapshots/u1/2026-11-06.json.gz'];
  const text = await new Response(blob.stream().pipeThrough(new DecompressionStream('gzip'))).text();
  const json = JSON.parse(text);
  assert.deepEqual(json.items.map((i) => i.title).sort(), ['one', 'two']);
});

test('a full push of 100 items fits D1 limits', async () => {
  const db = makeD1(SCHEMA);
  const ids = Array.from({ length: 100 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`);
  const fields = {
    slug: 's', title: 't', source_url: 'https://x', domain: 'x', author: 'a', summary: 's', body_markdown: 'b',
    status: 'active', needs_review: false, kind: 'link', enrichment_status: 'done', added_at: '2026-11-07T00:00:00Z',
    analyzed_at: null, cover_aspect: 1.5, metadata: { a: 1 }, tags: [], images: [], snippets: [],
  };
  const r = await applyChanges(db, 'u1', ids.map((id) => full(id, fields, 10)));
  assert.equal(r.results.filter((x) => x.status === 'applied').length, 100);
  const again = await applyChanges(db, 'u1', ids.map((id) => ({ id, fields: { title: 'u' }, clock: 20 })));
  assert.equal(again.results.filter((x) => x.status === 'applied').length, 100);
});

test('duplicate links merge into the richest row and the rest are soft-deleted', async () => {
  const { mergeDuplicates } = await import('../src/lib/dedupe.js');
  const db = makeD1(SCHEMA);
  const C = '33333333-3333-4333-8333-333333333333';
  await applyChanges(db, 'u1', [
    full(A, { title: 'old', source_url: 'https://www.kargul.studio/', added_at: '2026-01-01T00:00:00Z',
      tags: [{ tag: 'studio', category: 'subject', weight: 0.5 }], snippets: [{ text: 'a' }] }, 1),
    full(B, { title: 'new', source_url: 'https://kargul.studio', added_at: '2026-11-04T00:00:00Z', summary: 'S',
      images: [{ path: '/img/x.webp', is_primary: true }], tags: [{ tag: 'Studio', category: 'subject', weight: 0.9 }] }, 1),
    full(C, { title: 'other', source_url: 'https://example.com', added_at: '2026-02-01T00:00:00Z' }, 1),
  ]);
  const preview = await mergeDuplicates(db, 'u1');
  assert.equal(preview.applied, false);
  assert.equal(preview.groups, 1);
  assert.equal(preview.plans[0].keep, B);
  const done = await mergeDuplicates(db, 'u1', { apply: true, now: 1000 });
  assert.equal(done.statuses.applied, 2);
  const items = Object.fromEntries((await pullChanges(db, 'u1', 0)).items.map((i) => [i.id, i]));
  assert.equal(items[A].deleted_at, 1000);
  assert.equal(items[B].added_at, '2026-01-01T00:00:00Z');
  assert.deepEqual(items[B].snippets.map((s) => s.text), ['a']);
  assert.equal(items[B].tags.length, 1);
  assert.equal(items[B].tags[0].weight, 0.9);
  assert.equal(items[C].deleted_at, null);
});
