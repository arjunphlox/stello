const test = require('node:test');
const assert = require('node:assert');
const { pickOfflineSet, imageUrls, imageFetches, OFFLINE_CAP, RECENT_DAYS, OPENED_DAYS } = require('../offline.js');

const DAY = 86400000;
const NOW = Date.parse('2026-11-12T12:00:00Z');
const item = (slug, daysAgo, extra = {}) => ({ slug, added_at: new Date(NOW - daysAgo * DAY).toISOString(), ...extra });

test('cap and window match the agreed scope', () => {
  assert.strictEqual(OFFLINE_CAP, 1000);
  assert.strictEqual(RECENT_DAYS, 28);
  assert.strictEqual(OPENED_DAYS, 30);
});

test('items opened in the last 30 days fill the room left after recent saves and picks', () => {
  const opened = (slug, daysAgo, openedDaysAgo) => item(slug, daysAgo, { last_opened_at: new Date(NOW - openedDaysAgo * DAY).toISOString() });
  const items = [item('r1', 1), item('p1', 300), opened('o1', 200, 2), opened('o2', 200, 10), opened('stale', 200, 45)];
  const set = pickOfflineSet(items, new Map([['p1', NOW]]), NOW);
  assert.deepStrictEqual([...set.slugs], ['r1', 'p1', 'o1', 'o2']);
  assert.strictEqual(set.opened, 2);
  // Picks beat opened items when the cap is tight.
  const tight = pickOfflineSet(items, new Map([['p1', NOW]]), NOW, 3);
  assert.deepStrictEqual([...tight.slugs], ['r1', 'p1', 'o1']);
  assert.deepStrictEqual(tight.dropped, []);
});

test('offline downloads ask for the 1200px copy only when the image is wider or of unknown width', () => {
  const f = imageFetches({
    images: [{ path: '/img/u/big.png', width: 2400 }, { path: '/img/u/small.webp', width: 800 }, { path: '/img/u/nodims.jpg' }],
    og_image_path: '/img/u/og.png',
  });
  assert.deepStrictEqual(f, [
    { path: '/img/u/big.png', fetch: '/img/u/big.png?w=1200' },
    { path: '/img/u/small.webp', fetch: '/img/u/small.webp' },
    { path: '/img/u/nodims.jpg', fetch: '/img/u/nodims.jpg?w=1200' },
    { path: '/img/u/og.png', fetch: '/img/u/og.png?w=1200' },
  ]);
});

test('recent items are offline, older ones only when picked', () => {
  const items = [item('new', 1), item('edge', 27.9), item('old', 40), item('older', 400)];
  const set = pickOfflineSet(items, new Map([['older', NOW]]), NOW);
  assert.deepStrictEqual([...set.slugs].sort(), ['edge', 'new', 'older']);
  assert.strictEqual(set.recent, 2);
  assert.strictEqual(set.pinned, 1);
});

test('deleted items never count', () => {
  const items = [item('a', 1, { deleted_at: NOW }), item('b', 50, { deleted_at: NOW })];
  const set = pickOfflineSet(items, new Map([['b', NOW]]), NOW);
  assert.strictEqual(set.slugs.size, 0);
});

test('cap: recent first (newest first), then newest picks; the rest are dropped', () => {
  const items = [item('r1', 1), item('r2', 2), item('r3', 3), item('p1', 100), item('p2', 200)];
  const pins = new Map([['p1', NOW - 1000], ['p2', NOW]]);
  const set = pickOfflineSet(items, pins, NOW, 4);
  assert.deepStrictEqual([...set.slugs], ['r1', 'r2', 'r3', 'p2']);
  assert.deepStrictEqual(set.dropped, ['p1']);
  const tight = pickOfflineSet(items, pins, NOW, 2);
  assert.deepStrictEqual([...tight.slugs], ['r1', 'r2']);
  assert.deepStrictEqual(tight.dropped, ['p2', 'p1']);
});

test('a pick that is also recent is not counted twice', () => {
  const set = pickOfflineSet([item('a', 1)], new Map([['a', NOW]]), NOW);
  assert.strictEqual(set.slugs.size, 1);
  assert.strictEqual(set.pinned, 0);
});

test('image URLs: every stored image plus the og image, de-duplicated, R2 only', () => {
  const urls = imageUrls({
    images: [{ path: '/img/u/a.webp' }, { path: '/img/u/b.webp' }, { path: 'https://elsewhere/x.png' }, null],
    og_image_path: '/img/u/a.webp',
  });
  assert.deepStrictEqual(urls, ['/img/u/a.webp', '/img/u/b.webp']);
  assert.deepStrictEqual(imageUrls({}), []);
});

test('10k items pick in well under 50 ms', () => {
  const items = Array.from({ length: 10000 }, (_, i) => item('s' + i, i / 50));
  const pins = new Map(Array.from({ length: 2000 }, (_, i) => ['s' + (9999 - i), NOW - i]));
  const t = performance.now();
  const set = pickOfflineSet(items, pins, NOW);
  const ms = performance.now() - t;
  assert.strictEqual(set.slugs.size, 1000);
  assert.ok(ms < 50, `took ${ms.toFixed(1)} ms`);
});

test('deleting an image also deletes its offline copy in R2', async () => {
  const storage = require('../src/lib/storage.js');
  let deleted = null;
  const env = { BUCKET: { delete: async (keys) => { deleted = keys; } } };
  await storage.remove(env, ['/img/u/a/og.png', 'https://elsewhere.com/x.png']);
  assert.deepStrictEqual(deleted, ['u/a/og.png', 'u/a/og.png.w1200.webp']);
});
