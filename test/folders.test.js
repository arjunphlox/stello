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
