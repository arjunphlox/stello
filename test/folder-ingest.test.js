// Folder ingest (folder engine plan 4b, part 3): links from the person's own files.
// The same fixture checks the Mac reader (StelloTests/FolderIngestTests.swift).
const test = require('node:test');
const assert = require('node:assert');
const fixtures = require('./fixtures/folder-ingest.json');

const lib = import('../src/lib/folder-ingest.js');

test('every sample file gives the expected links, ids and new items', async () => {
  const I = await lib;
  for (const c of fixtures.cases) {
    assert.strictEqual(I.ingestType(c.path), c.expect.type, c.path);
    const links = I.readLinks(c.path, c.text, { modified: c.modified });
    assert.deepStrictEqual(links, c.expect.links, c.path);
    for (const [i, l] of links.entries()) {
      const id = await I.linkItemId(l.key);
      assert.strictEqual(id, c.expect.items[i].id, `${c.path} id ${i}`);
      assert.deepStrictEqual(I.linkChange(l, { id, now: c.now }), c.expect.items[i].change, `${c.path} item ${i}`);
    }
  }
});

test('written notes: about 50 words of own writing make the note an item, details kept', async () => {
  const I = await lib;
  for (const c of fixtures.cases) {
    const want = c.expect.note;
    assert.strictEqual(I.ownWords(c.text), want.words, c.path);
    assert.strictEqual(I.isWrittenNote(c.path, c.text), want.written, c.path);
    if (!want.written) continue;
    const id = await I.noteItemId(c.path);
    const n = I.noteItem(c.path, c.text, { id, modified: c.modified, now: c.now });
    assert.deepStrictEqual(n && { id: n.id, extra: n.extra, body: n.body, change: n.change }, want.item, c.path);
  }
  const kyoto = fixtures.cases.find((c) => c.path.includes('Kyoto')).expect.note.item;
  assert.deepStrictEqual(kyoto.change.fields.tags.map((t) => t.tag), ['note', 'travel', 'japan', 'temples']);
  assert.strictEqual(kyoto.change.fields.added_at, '2024-03-02T00:00:00.000Z');
  // Front matter Stello can't keep safely (nested details) leaves the file alone.
  assert.strictEqual(fixtures.cases.find((c) => c.path === 'Ideas/nested.md').expect.note.item, null);
});

test('reading files never calls AI or the network: new links wait for the Mac to sort them', async () => {
  const I = await lib;
  const [l] = I.readLinks('a.md', '- https://example.com/page');
  const c = I.linkChange(l, { id: await I.linkItemId(l.key), now: '2026-11-28T09:00:00.000Z' });
  assert.strictEqual(c.fields.kind, 'link');
  assert.strictEqual(c.fields.enrichment_status, 'awaiting_classify');
  assert.strictEqual(c.full, true);
});

test('one link gets one id on every device, whatever its tracking bits', async () => {
  const I = await lib;
  const a = I.readLinks('a.md', 'https://www.Example.com/x/?utm_source=a#top')[0];
  const b = I.readLinks('b.csv', 'url\nhttp://example.com/x\n')[0];
  assert.strictEqual(a.key, b.key);
  assert.strictEqual(await I.linkItemId(a.key), await I.linkItemId(b.key));
  assert.match(await I.linkItemId(a.key), /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test('a 7,000-row sheet reads in well under a second', async () => {
  const I = await lib;
  const rows = ['title,url,tags'];
  for (let i = 0; i < 7000; i++) rows.push(`Item ${i},https://site${i % 50}.example/p/${i},"a, b"`);
  const t = Date.now();
  const links = I.readLinks('big.csv', rows.join('\n'));
  assert.strictEqual(links.length, 7000);
  assert.ok(Date.now() - t < 1000, `${Date.now() - t} ms`);
});

test('Stello files and others are told apart by name', async () => {
  const I = await lib;
  for (const p of ['notes.md', 'a/b.markdown', 'x.txt', 'y.webloc', 'z.url', 'r.csv', 'bookmarks.html', 'b.htm']) assert.ok(I.ingestType(p), p);
  for (const p of ['photo.jpg', 'doc.pdf', '.hidden.md', 'stello.json']) assert.strictEqual(I.ingestType(p), null, p);
});
