import { test } from 'node:test';
import assert from 'node:assert/strict';
import { itemToMarkdown, mediaFiles, itemPath } from '../src/lib/folder-format.js';
import {
  convertV1, verifyConversion, normaliseUrl, cleanBody, nameKey, itemPathV2, remapCanvas, parseFile,
} from '../src/lib/folder-v2.js';

const v1 = (it) => { const path = itemPath(it); return { path, text: itemToMarkdown(it, mediaFiles(it, {}, path)) }; };

const library = [
  { id: 'p1', slug: 'andrei-robu', title: 'Andrei Robu', kind: 'individual', added_at: '2026-03-02T00:00:00Z', status: 'active',
    metadata: { location: { kind: 'place', name: 'barcelona', slug: 'barcelona' }, professions: ['type designer'] }, tags: [], images: [] },
  { id: 'f1', slug: 'martype', title: 'Martype', kind: 'foundry', added_at: '2026-03-02T00:00:00Z', status: 'active',
    tags: [{ tag: 'type-foundries', category: 'collection', weight: 0.9 }], images: [] },
  { id: 't1', slug: 'some-face', title: 'Some Face', kind: 'typeface', source_url: 'https://www.martype.com/face/?utm_source=x',
    summary: 'A face.', added_at: '2026-03-05T00:00:00Z', status: 'active',
    metadata: { typeDesigner: 'andrei robu', typeFoundry: 'Martype', license: 'paid' },
    tags: [{ tag: 'usa', category: 'location', weight: 0.6 }, { tag: 'serif', category: 'style', weight: 0.8 }, { tag: 'type-foundries', category: 'collection', weight: 0.9 }],
    images: [{ path: '/img/u/some-face/og.png', is_primary: true }],
    snippets: [{ text: 'Quote one.' }],
    body_markdown: '## Summary\nA face.\n\n## Key Snippets\n> Quote one.\n\n## Notes\nMy own note.' },
  { id: 't2', slug: 'some-face-dup', title: 'Some Face (again)', kind: 'typeface', source_url: 'http://martype.com/face#specimen',
    added_at: '2026-04-05T00:00:00Z', status: 'active', author: '@sergeantsref (Sgt Sref)',
    tags: [{ tag: 'bold', category: 'style', weight: 0.9 }], images: [{ path: '/img/u/dup/2.png' }], snippets: [{ text: 'Quote two.' }] },
  { id: 'a1', slug: 'plain', title: 'Plain', kind: 'link', source_url: 'https://example.com/a', summary: 'S.',
    added_at: '2026-11-20T00:00:00Z', status: 'active', body_markdown: '## Summary\nS.', tags: [{ tag: 'x', category: 'subject', weight: 0.5 }], images: [] },
];

test('url normalising for dedupe', () => {
  assert.equal(normaliseUrl('http://WWW.Example.com/a/?utm_source=z&q=1#top'), 'https://example.com/a?q=1');
  assert.equal(normaliseUrl('https://rsms.me/'), normaliseUrl('https://rsms.me'));
  assert.equal(nameKey('Zoë  O’Neil'), 'zoe oneil');
});

test('bodies lose only what repeats the header', () => {
  assert.equal(cleanBody('## Summary\nS.', 'S.', []), '');
  assert.equal(cleanBody('## Summary\n', 'S.', []), '');
  assert.equal(cleanBody('## Summary\nS.\n\n## Key Snippets\n> Q.\n\n## Notes\nMine', 'S.', [{ text: 'Q.' }]), '## Notes\nMine');
  assert.equal(cleanBody('## Summary\nDifferent.', 'S.', []), '## Summary\nDifferent.');
  assert.equal(cleanBody('Free text, no sections.', 'S.', []), 'Free text, no sections.');
});

test('month folders', () => {
  assert.equal(itemPathV2('2026-03-05T00:00:00Z', 'x'), 'items/2026/03/x.md');
  assert.equal(itemPathV2(null, 'x'), 'items/undated/x.md');
});

test('v1 library converts to v2 with entities, references and no duplicates', () => {
  const files = library.map(v1);
  const out = convertV1(files);
  assert.deepEqual(verifyConversion(files, out), []);

  // People-kind items became people files with their own ids.
  const robu = out.people.find((p) => p.id === 'p1');
  assert.equal(robu.path, 'people/andrei-robu.md');
  assert.deepEqual(robu.header.places, ['place-barcelona']);
  assert.equal(robu.header.meta.location, undefined);
  assert.ok(out.people.find((p) => p.id === 'f1'));

  // The typeface points at them by id; collection and location tags became references.
  const face = out.items.find((i) => i.id === 't1');
  assert.equal(face.path, 'items/2026/03/some-face.md');
  assert.deepEqual(face.header.people.filter((r) => r.role !== 'author'), [{ id: 'p1', role: 'designer' }, { id: 'f1', role: 'foundry' }]);
  assert.deepEqual(face.header.places, ['place-usa']);
  assert.deepEqual(face.header.collections, ['collection-type-foundries']);
  assert.equal(face.header.tags.collection, undefined);
  assert.equal(face.header.tags.location, undefined);
  assert.deepEqual(face.header.meta, { license: 'paid' });

  // The repeat sighting merged in: its source, author, tags, snippet and image kept.
  assert.equal(out.items.find((i) => i.id === 't2'), undefined);
  assert.equal(face.header.sources[0].id, 't2');
  assert.equal(face.header.sources[0].title, 'Some Face (again)');
  assert.ok(face.header.people.some((r) => r.role === 'author'));
  assert.equal(face.header.tags.style.bold, 0.9);
  assert.deepEqual(face.header.snippets.map((s) => s.text), ['Quote one.', 'Quote two.']);
  assert.equal(face.header.images.length, 2);
  assert.equal(face.body, '## Notes\nMy own note.');

  // Media paths now go up three folders, to the same file.
  assert.equal(face.header.cover, '../../../media/some-face/1.png');

  // Summary-only body is gone; the summary stays in the header.
  const plain = out.items.find((i) => i.id === 'a1');
  assert.equal(plain.body, '');
  assert.equal(parseFile(plain.text).header.summary, 'S.');

  assert.equal(out.places.length, 2);
  assert.equal(out.report.merged_urls, 1);
  assert.equal(out.moves['items/2026/some-face-dup.md'], 'items/2026/03/some-face.md');
});

test('organisations match by core name, people files are named from the name', () => {
  const files = [
    { id: 'c1', slug: 'colophon', title: 'Colophon', kind: 'foundry', added_at: '2026-07-01T00:00:00Z', tags: [], images: [] },
    { id: 'd1', slug: 'danie-l-van-der-winden', title: 'Daniël van der Winden', kind: 'individual', added_at: '2026-07-01T00:00:00Z', tags: [], images: [] },
    { id: 'x1', slug: 'apercu', title: 'Apercu', kind: 'typeface', source_url: 'https://myfonts.com/apercu', added_at: '2026-07-06T00:00:00Z',
      metadata: { typeFoundry: 'Colophon Foundry', distributedOn: [{ kind: 'foundry', name: 'MyFonts', slug: 'myfonts' }] }, tags: [], images: [] },
  ].map(v1);
  const out = convertV1(files);
  assert.deepEqual(verifyConversion(files, out), []);
  assert.ok(out.people.find((p) => p.path === 'people/daniel-van-der-winden.md'));
  const colophon = out.people.find((p) => p.id === 'c1');
  assert.deepEqual(colophon.header.aliases, ['Colophon Foundry']);
  const apercu = out.items.find((i) => i.id === 'x1');
  assert.deepEqual(apercu.header.people, [{ id: 'c1', role: 'foundry' }, { id: 'person-myfonts', role: 'distributor' }]);
  assert.equal(out.people.length, 3);
});

test('place kind does not depend on item order', () => {
  const a = { id: 'a', slug: 'a', title: 'A', kind: 'link', source_url: 'https://a.com', added_at: '2026-01-01T00:00:00Z', metadata: { geography: { kind: 'place', name: 'switzerland' } }, tags: [], images: [] };
  const b = { id: 'b', slug: 'b', title: 'B', kind: 'link', source_url: 'https://b.com', added_at: '2026-01-02T00:00:00Z', tags: [{ tag: 'switzerland', category: 'location', weight: 0.6 }], images: [] };
  for (const order of [[a, b], [b, a]]) {
    const out = convertV1(order.map(v1));
    assert.equal(out.places.find((p) => p.id === 'place-switzerland').header.kind, 'country');
  }
});

test('canvases follow the moves', () => {
  const c = remapCanvas({ nodes: [{ id: 'a', type: 'file', file: 'items/2026/x.md' }, { id: 'b', type: 'text', text: 'hi' }], edges: [] }, { 'items/2026/x.md': 'items/2026/03/x.md' });
  assert.equal(c.nodes[0].file, 'items/2026/03/x.md');
  assert.equal(c.nodes[1].text, 'hi');
});
