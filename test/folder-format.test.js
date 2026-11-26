import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  itemToMarkdown, markdownToItem, diffItem, parseItemFile, itemPath, mediaFiles, groupTags, ungroupTags,
  canvasToJsonCanvas, safeName, imageExt,
} from '../src/lib/folder-format.js';

const item = {
  id: '2b7c0f1e-6a41-4c55-9b0e-3d1f7a9c2e10',
  slug: 'climate-crisis-font-079e44',
  title: 'Climate Crisis font: "melting" type',
  source_url: 'https://www.hs.fi/climatecrisisfont/',
  domain: 'hs.fi',
  author: 'Helsingin Sanomat',
  summary: 'A variable typeface whose weight follows Arctic sea-ice data.\nSecond line: with a colon.',
  body_markdown: '## Summary\nA variable typeface.\n\n## Key Snippets\n> The font shows the melting.\n\n---\nNot a header fence.',
  status: 'active',
  needs_review: true,
  kind: 'resource',
  enrichment_status: 'done',
  added_at: '2025-11-03T09:12:00+00:00',
  analyzed_at: null,
  cover_aspect: 1.6,
  last_opened_at: '2026-11-20T18:02:00.000Z',
  open_count: 4,
  metadata: { resource_type: 'typeface', license: 'free' },
  tags: [
    { tag: 'variable-font', category: 'style', weight: 0.9 },
    { tag: 'climate', category: 'subject', weight: 0.9 },
    { tag: 'editorial', category: 'style', weight: 0.6 },
    { tag: 'type: inspiration #1', category: 'collection', weight: 0.9 },
  ],
  images: [
    { path: '/img/u/climate/og-image.png', source: 'og', is_primary: true, width: 2400, height: 1260 },
    { path: '/img/u/sync/abc.webp', source: 'manual', is_primary: false, label: 'Specimen' },
  ],
  snippets: [{ text: 'The font shows the melting.', source: 'ai', added_at: '2026-11-21T00:00:00Z' }],
  deleted_at: null,
};

test('item round-trips exactly through its Markdown file', () => {
  const text = itemToMarkdown(item);
  const back = markdownToItem(text, { slug: item.slug });
  assert.deepEqual(diffItem(item, back), []);
  assert.equal(back.title, item.title);
  assert.equal(back.summary, item.summary);
  assert.equal(back.body_markdown, item.body_markdown);
  assert.equal(back.tags.length, item.tags.length);
  assert.deepEqual(back.images, item.images);
});

test('header is readable YAML-style: one field per line, tags grouped, local image paths', () => {
  const text = itemToMarkdown(item);
  assert.ok(text.startsWith('---\nid: "2b7c0f1e'));
  assert.match(text, /\ntags:\n {2}style: \{"variable-font":0\.9,"editorial":0\.6\}\n/);
  assert.match(text, /\ncover: "\.\.\/\.\.\/media\/climate-crisis-font-079e44\/1\.png"\n/);
  assert.match(text, /\nimages:\n {2}- \{"file":"\.\.\/\.\.\/media\/climate-crisis-font-079e44\/1\.png"/);
  assert.match(text, /\nreview: true\n/);
  const { header } = parseItemFile(text);
  assert.equal(header.kind, 'resource');
  assert.deepEqual(header.meta, item.metadata);
});

test('empty and default fields are left out', () => {
  const bare = { id: 'x', slug: 's', title: 'T', added_at: '2024-01-02T00:00:00Z', tags: [], images: [], snippets: [], needs_review: false, open_count: 0 };
  const text = itemToMarkdown(bare);
  assert.doesNotMatch(text, /review:|tags:|images:|snippets:|meta:/);
  const back = markdownToItem(text);
  assert.deepEqual(diffItem(bare, back), []);
  assert.equal(back.body_markdown, null);
});

test('paths: year folders, safe names, media per item', () => {
  assert.equal(itemPath(item), 'items/2025/climate-crisis-font-079e44.md');
  assert.equal(itemPath({ id: 'abc', slug: 'a/b c' }), 'items/undated/a-b-c.md');
  assert.equal(safeName('../../etc'), 'etc');
  const files = mediaFiles(item);
  assert.deepEqual(files.map((f) => f.file), ['media/climate-crisis-font-079e44/1.png', 'media/climate-crisis-font-079e44/2.webp']);
  assert.equal(mediaFiles(item, {}, 'items/2025/renamed-1234.md')[0].file, 'media/renamed-1234/1.png');
  assert.equal(imageExt('/img/x', 'image/jpeg'), 'jpg');
});

test('tags group and ungroup without loss', () => {
  const g = groupTags(item.tags);
  assert.deepEqual(Object.keys(g), ['style', 'subject', 'collection']);
  assert.equal(ungroupTags(g).length, item.tags.length);
});

test('canvas becomes JSON Canvas with the Stello doc kept', () => {
  const project = {
    id: 'p1', name: 'Brand refresh', rev: 3,
    doc: {
      cards: [{ slug: 'a', x: 10, y: 20 }, { slug: 'b', x: 400, y: 20 }, { slug: 'gone', x: 0, y: 500 }],
      links: [{ id: 'l1', a: 'a', b: 'b', kind: 'influence' }],
      groups: [{ id: 'g1', name: 'Type', slugs: ['a', 'b'] }],
      notes: [{ id: 'n1', kind: 'note', text: 'Why these two', x: 10, y: 400 }],
    },
  };
  const c = canvasToJsonCanvas(project, (s) => (s === 'gone' ? null : `items/2025/${s}.md`));
  assert.equal(c.nodes[0].type, 'group');
  assert.equal(c.nodes.filter((n) => n.type === 'file').length, 2);
  assert.equal(c.nodes.find((n) => n.id === 'card-gone').type, 'text');
  assert.deepEqual(c.edges[0], { id: 'link-l1', fromNode: 'card-a', toNode: 'card-b', label: 'influence' });
  assert.equal(c.stello.doc, project.doc);
});
