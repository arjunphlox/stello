// Reading items back from folder files (grid part 1): src/lib/folder-read.js against the
// shared fixtures (the Mac's FolderReaderTests reads the same ones).
const test = require('node:test');
const assert = require('node:assert');
const fixtures = require('./fixtures/folder-read.json');

const load = () => import('../src/lib/folder-read.js');

test('edits found in files match the shared fixtures', async () => {
  const R = await load();
  for (const c of fixtures.edits) {
    assert.deepStrictEqual(R.fileEdits(c.item, c.text, { path: c.path, entities: c.entities }), c.expect, c.name);
  }
});

test('new items read from files match the shared fixtures', async () => {
  const R = await load();
  for (const c of fixtures.fresh) {
    assert.deepStrictEqual(R.itemFromFile(c.text, c.path, { entities: c.entities, modified: c.modified }), c.expect, c.name);
  }
});

test('a file Stello writes for any written fixture reads back as no edit', async () => {
  const R = await load();
  const W = await import('../src/lib/folder-write.js');
  const wf = require('./fixtures/folder-write.json');
  for (const c of wf.items) {
    const ents = [...c.entities, ...c.expect.entities.map((e) => ({ id: W.readCopy(e.text).header.id, name: W.readCopy(e.text).header.name }))];
    assert.strictEqual(R.fileEdits(c.item, c.expect.text, { path: c.expect.path, entities: ents }), null, c.name);
  }
});

test('an edit changes only what the file changed, and applying it settles', async () => {
  const R = await load();
  const W = await import('../src/lib/folder-write.js');
  const c = fixtures.edits.find((x) => x.name === 'title changed');
  const e = R.fileEdits(c.item, c.text, { path: c.path, entities: c.entities });
  const next = { ...c.item, ...e.fields };
  assert.strictEqual(R.fileEdits(next, c.text, { path: c.path, entities: c.entities }), null);
  assert.notStrictEqual(W.fingerprint(next), W.fingerprint(c.item));
});
