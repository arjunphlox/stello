// Folder writes (folder engine plan 4b, part 2): src/lib/folder-write.js against the shared
// fixtures (the Mac's FolderWriterTests reads the same ones), plus trash and fingerprint rules.
const test = require('node:test');
const assert = require('node:assert');
const fixtures = require('./fixtures/folder-write.json');

const load = () => import('../src/lib/folder-write.js');

test('item files match the shared fixtures', async () => {
  const W = await load();
  for (const c of fixtures.items) {
    const out = W.itemFile(c.item, { entities: c.entities, paths: new Set(c.paths.map((p) => p.toLowerCase())), existing: c.existing });
    assert.strictEqual(out.path, c.expect.path, c.name);
    assert.strictEqual(out.text, c.expect.text, c.name);
    assert.deepStrictEqual(out.entities.map((e) => ({ path: e.path, text: e.text })), c.expect.entities, c.name);
    assert.deepStrictEqual(out.media, c.expect.media, c.name);
    assert.strictEqual(W.fingerprint(c.item), c.expect.fingerprint, c.name);
  }
});

test('merges match the shared fixtures', async () => {
  const W = await load();
  for (const c of fixtures.merges) assert.strictEqual(W.copyText(W.mergeCopies(c.a, c.b)), c.expect.text, c.name);
});

test('a written file reads back to the same header', async () => {
  const W = await load();
  for (const c of fixtures.items) {
    const back = W.readCopy(c.expect.text);
    assert.ok(back, c.name);
    assert.strictEqual(back.header.id, c.item.id, c.name);
    assert.strictEqual(W.copyText(back), c.expect.text, c.name);
  }
});

test('opening an item is not an edit; a real edit is', async () => {
  const W = await load();
  const item = fixtures.items[0].item;
  assert.strictEqual(W.fingerprint({ ...item, open_count: 9, last_opened_at: '2027-01-01T00:00:00Z' }), W.fingerprint(item));
  assert.notStrictEqual(W.fingerprint({ ...item, title: 'Changed' }), W.fingerprint(item));
  assert.notStrictEqual(W.fingerprint({ ...item, tags: [] }), W.fingerprint(item));
  // Tags as a JSON string (D1 rows) and as an array give the same fingerprint.
  assert.strictEqual(W.fingerprint({ ...item, tags: JSON.stringify(item.tags) }), W.fingerprint(item));
});

test('mergeCopies keeps the main copy id, and merging twice changes nothing', async () => {
  const W = await load();
  const [c] = fixtures.merges;
  const once = W.mergeCopies(c.a, c.b);
  assert.strictEqual(once.header.id, c.a.header.id);
  const twice = W.mergeCopies({ ...once, mtime: 3000 }, c.b);
  assert.strictEqual(W.copyText(twice), W.copyText(once));
});

test('trash: day folders, 30-day clear-out', async () => {
  const W = await load();
  const now = Date.UTC(2026, 10, 28, 12);
  assert.strictEqual(W.trashPath('items/2026/11/a.md', now), '.trash/2026-11-28/items/2026/11/a.md');
  assert.strictEqual(W.trashExpired('2026-10-28', now), true);
  assert.strictEqual(W.trashExpired('2026-10-30', now), false);
  assert.strictEqual(W.trashExpired('notes', now), false);
});

test('only UUIDs count as library items', async () => {
  const W = await load();
  assert.ok(W.isLibraryId('4c9f1824-45ad-4265-98a6-95b71f16338b'));
  assert.ok(!W.isLibraryId('person-jane-doe'));
  assert.ok(!W.isLibraryId('place-berlin'));
});
