// Folder sources (folder engine plan 4b): pure helpers in folders.js + the panel's Folder rows.
const test = require('node:test');
const assert = require('node:assert');
const F = require('../folders.js');
const P = require('../panel-layout.js');

test('headerId reads the id line of a Stello header only', () => {
  assert.strictEqual(F.headerId('---\nid: "a-1"\ntitle: "T"\n---\nbody'), 'a-1');
  assert.strictEqual(F.headerId('---\r\ntitle: "T"\r\nid: "b-2"\r\n---\r\n'), 'b-2');
  assert.strictEqual(F.headerId('---\ntitle: "T"\n---\nid: "body-not-header"\n'), null);
  assert.strictEqual(F.headerId('# plain note\nid: "x"'), null);
  assert.strictEqual(F.headerId(''), null);
});

test('skipDir leaves out media, projects and dot-folders', () => {
  for (const n of ['media', 'projects', '.stello-v1', '.trash']) assert.ok(F.skipDir(n), n);
  for (const n of ['items', 'people', 'places', '2026']) assert.ok(!F.skipDir(n), n);
});

test('buildLookup lists every folder holding an item, oldest-added first', () => {
  const folders = [
    { id: 'f2', name: 'Dropbox Stello', addedAt: 20 },
    { id: 'f1', name: 'Stello', addedAt: 10 },
  ];
  const indexes = {
    f1: { files: { 'items/2026/11/a.md': { id: 'A' }, 'items/2026/11/b.md': { id: 'B' } } },
    f2: { files: { 'items/a.md': { id: 'A' } } },
  };
  const m = F.buildLookup(folders, indexes);
  assert.deepStrictEqual(m.get('A').map((x) => x.name), ['Stello', 'Dropbox Stello']);
  assert.deepStrictEqual(m.get('B'), [{ folderId: 'f1', name: 'Stello', path: 'items/2026/11/b.md' }]);
  assert.strictEqual(m.get('C'), undefined);
});

test('panel shows one Folder row per folder, just above Added', () => {
  const item = { slug: 's', title: 'Thing', source_url: 'https://example.com/x', domain: 'example.com', added_at: '2026-11-20T00:00:00Z' };
  const none = P.layout(item, {});
  assert.ok(!none.cards[0].rows.some((r) => r.label === 'Folder'));
  const two = P.layout(item, { folders: [
    { folderId: 'f1', name: 'Stello', path: 'items/2026/11/x.md' },
    { folderId: 'f2', name: 'Dropbox Stello', path: 'items/x.md' },
  ] });
  const labels = two.cards[0].rows.map((r) => r.label);
  assert.deepStrictEqual(labels.slice(-3), ['Folder', 'Folder', 'Added']);
  const row = two.cards[0].rows.find((r) => r.label === 'Folder');
  assert.deepStrictEqual(row.folder, { folderId: 'f1', path: 'items/2026/11/x.md' });
  assert.strictEqual(row.url, null);
});

test('countItems leaves out people and places that are only files', () => {
  const files = {
    'items/a.md': { id: '4c9f1824-45ad-4265-98a6-95b71f16338b' },
    'items/b.md': { id: '4C9F1824-45AD-4265-98A6-95B71F16338B' },
    'people/jane.md': { id: 'person-jane' },
    'people/studio.md': { id: '11111111-2222-4333-8444-555555555555' },
    'places/berlin.md': { id: 'place-berlin' },
  };
  assert.strictEqual(F.countItems(files), 2);
});

test('headerEntity reads a people/places header', () => {
  const e = F.headerEntity('---\nid: "person-kometa"\nname: "Kometa"\nkind: "foundry"\naliases: ["Kometa Type"]\n---\n');
  assert.deepStrictEqual(e, { id: 'person-kometa', name: 'Kometa', kind: 'foundry', aliases: ['Kometa Type'] });
});

test('savesFolder: the marked folder, else the oldest added', () => {
  assert.strictEqual(F.savesFolder([{ id: 'b', addedAt: 2 }, { id: 'a', addedAt: 1 }]).id, 'a');
  assert.strictEqual(F.savesFolder([{ id: 'b', addedAt: 2, takesSaves: true }, { id: 'a', addedAt: 1 }]).id, 'b');
  assert.strictEqual(F.savesFolder([]), null);
});

test('part 3: a file of the person\'s own that lists a link shows as Found in, after the item\'s copies', () => {
  const folders = [{ id: 'f1', name: 'Notes', addedAt: 10 }];
  const indexes = { f1: {
    files: { 'items/2026/11/a.md': { id: 'A' } },
    found: { 'Reading/links.md': { links: [{ key: 'k1', id: 'A' }, { key: 'k2', id: 'B' }] } },
  } };
  const m = F.buildLookup(folders, indexes);
  assert.deepStrictEqual(m.get('A'), [
    { folderId: 'f1', name: 'Notes', path: 'items/2026/11/a.md' },
    { folderId: 'f1', name: 'Notes', path: 'Reading/links.md', found: true },
  ]);
  assert.deepStrictEqual(m.get('B'), [{ folderId: 'f1', name: 'Notes', path: 'Reading/links.md', found: true }]);
  const ids = ['11111111-2222-4333-8444-555555555555', '11111111-2222-4333-8444-666666666666'];
  assert.strictEqual(F.countItems({ 'a.md': { id: ids[0] } }, { 'l.md': { links: [{ id: ids[0] }, { id: ids[1] }] } }), 2);
  for (const n of ['links.md', 'export.csv', 'Bookmarks.html', 'x.webloc', 'y.url', 'z.txt']) assert.ok(F.ingestFile(n), n);
  for (const n of ['.x.md', 'photo.jpg', 'doc.pdf', 'stello.json']) assert.ok(!F.ingestFile(n), n);
  const layout = P.layout({ slug: 's', title: 'T', added_at: '2026-11-20T00:00:00Z' }, { folders: m.get('B') });
  const row = layout.cards[0].rows.find((r) => r.label === 'Found in');
  assert.strictEqual(row.value, 'links.md');
  assert.strictEqual(row.folder.name, 'Notes');
});
