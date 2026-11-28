#!/usr/bin/env node
/**
 * Writes test/fixtures/folder-write.json (inputs + the JS writer's output) and the Swift
 * copy apple/Stello/StelloTests/FolderWriteFixtures.swift, so the web writer
 * (src/lib/folder-write.js) and the Mac one (Store/FolderWriter.swift) are checked
 * against the same expected files. Run after changing either writer:
 *   node scripts/make-folder-write-fixtures.mjs
 * Review the diff of the JSON before committing: it is the expected output.
 */
import { writeFileSync } from 'node:fs';
import { itemFile, mergeCopies, copyText, fingerprint } from '../src/lib/folder-write.js';

const ID = '4c9f1824-45ad-4265-98a6-95b71f16338b';
const base = {
  id: ID, slug: 'kometa-fonts', title: 'Future-facing fonts', source_url: 'https://kometa.xyz/?utm_source=x',
  kind: 'typeface', domain: 'kometa.xyz', author: 'Kometa Type Foundry', summary: 'Fonts with a “future” feel.',
  status: 'active', added_at: '2026-11-28T07:00:00.000Z', analyzed_at: '2026-11-28T07:01:00.000Z',
  needs_review: false, enrichment_status: 'done', open_count: 2, last_opened_at: '2026-11-28T08:00:00.000Z',
  cover_aspect: 1.5,
  metadata: { typeDesigner: 'Jane Doe', location: 'Berlin', price: '10' },
  tags: [{ tag: 'serif', category: 'style', weight: 0.9, source: 'ai' }, { tag: 'germany', category: 'location', weight: 1 }, { tag: 'blue', category: 'color', weight: 0.6 }],
  images: [{ path: '/img/u/a.webp', is_primary: true, source: 'og', width: 1200, height: 800 }, { path: 'https://cdn.example/b.png', source: 'page' }],
  snippets: [{ text: 'A quote', source: 'page', added_at: '2026-11-28T07:00:00.000Z' }],
  body_markdown: 'My note about it.\n\n## Key Snippets\n> A quote',
};
const entities = [
  { id: 'person-kometa', name: 'Kometa', kind: 'foundry', aliases: [], type: 'person', path: 'people/kometa.md' },
  { id: 'place-germany', name: 'Germany', kind: 'country', aliases: [], type: 'place', path: 'places/germany.md' },
];

const cases = [];
const addItem = (name, item, ctx = {}) => {
  const paths = ctx.paths || [];
  const out = itemFile(item, { entities: ctx.entities || [], paths: new Set(paths.map((p) => p.toLowerCase())), existing: ctx.existing || null });
  cases.push({
    name, type: 'item', item, entities: ctx.entities || [], paths, existing: ctx.existing || null,
    expect: { path: out.path, text: out.text, entities: out.entities.map((e) => ({ path: e.path, text: e.text })), media: out.media, fingerprint: fingerprint(item) },
  });
};
addItem('new save, people and places matched or created', base, { entities });
addItem('new save, name taken', { ...base, author: null, metadata: null, tags: [] }, { paths: ['items/2026/11/kometa-fonts.md'] });
addItem('person-kind save goes to people/', { ...base, id: '11111111-2222-4333-8444-555555555555', slug: 'jane-studio', title: 'Jane Studio', kind: 'studio', author: null, metadata: null, images: [], snippets: [], body_markdown: null });
addItem('edit of an existing file keeps path, sources and copied images', { ...base, title: 'Kometa fonts', images: [base.images[0]] }, {
  entities,
  existing: {
    path: 'items/2026/10/kometa.md',
    header: { id: ID, title: 'Old', sources: [{ id: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', url: 'https://kometa.xyz/old' }], images: [{ file: '../../../media/kometa/1.webp', path: '/img/u/a.webp' }] },
    body: 'Old note',
  },
});
addItem('a written note keeps its own details and text where it is', {
  id: '573ea3bf-aef7-878f-98b6-f8551431c1ef', slug: 'kyoto-spring-573ea3', title: 'Kyoto, spring', kind: null, status: 'active',
  added_at: '2024-03-02T00:00:00.000Z', enrichment_status: 'text_done', body_markdown: '# Day one\n\nWe walked to the river.\n\nMap: https://maps.example/kyoto',
  tags: [{ tag: 'note', category: 'format', weight: 0.9 }, { tag: 'travel', category: 'subject', weight: 0.9 }],
}, {
  existing: {
    path: 'Journal/Trip to Kyoto.md',
    header: { aliases: ['Kyoto trip'], created: '2024-03-02', cssclass: 'wide' },
    body: '# Day one\n\nWe walked to the river.\n\nMap: https://maps.example/kyoto\n',
  },
});
addItem('undated, no slug', { id: '99999999-2222-4333-8444-555555555555', title: 'A note', kind: 'link', body_markdown: 'Just text' });

const merges = [];
const addMerge = (name, a, b) => {
  const m = mergeCopies(a, b);
  merges.push({ name, type: 'merge', a, b, expect: { text: copyText(m) } });
};
addMerge('newer copy wins fields, tags and links combine, both notes kept',
  { header: { id: ID, title: 'Main title', kind: 'typeface', summary: 'Old summary', tags: { style: { serif: 0.5 } }, people: [{ id: 'person-a', role: 'author' }], places: ['place-x'] }, body: 'Main note', mtime: 1000 },
  { header: { id: ID, title: 'Newer title', kind: 'typeface', summary: '', status: 'active', tags: { style: { serif: 0.9, display: 1 }, mood: { calm: 0.7 } }, people: [{ id: 'person-b', role: 'designer' }, { id: 'person-a', role: 'author' }], places: ['place-x', 'place-y'] }, body: 'Other note', mtime: 2000 });
addMerge('older other copy: main wins, a note inside the other is not repeated',
  { header: { id: ID, title: 'Main', snippets: [{ text: 'one' }] }, body: 'Note plus more', mtime: 5000 },
  { header: { id: ID, title: 'Stale', snippets: [{ text: 'one' }, { text: 'two' }], images: [{ path: '/img/x.webp' }] }, body: 'Note', mtime: 10 });

writeFileSync(new URL('../test/fixtures/folder-write.json', import.meta.url), JSON.stringify({ items: cases, merges }, null, 2) + '\n');

// Swift: the JSON as a raw string literal (#"""…"""#), so the test bundle needs no resource file.
const json = JSON.stringify({ items: cases, merges });
const swift = `// Generated by scripts/make-folder-write-fixtures.mjs from test/fixtures/folder-write.json. Don't edit.
// The web writer's expected output; FolderWriterTests checks FolderWriter.swift gives the same files.
enum FolderWriteFixtures {
    static let json = #"""
${json}
"""#
}
`;
writeFileSync(new URL('../apple/Stello/StelloTests/FolderWriteFixtures.swift', import.meta.url), swift);
console.log(`${cases.length} item cases, ${merges.length} merge cases`);
