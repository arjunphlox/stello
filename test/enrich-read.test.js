// Web Enrich: fresh reads stored like the Mac's EnrichmentService.applyFreshRead, and AI
// snippets written onto the item like EnrichmentService.apply.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { canApply, freshReadFields, mergeProduct, mergePost } from '../src/lib/readers/enrich-read.js';

const require = createRequire(import.meta.url);
const { stripSections } = require('../src/lib/markdown.js');

test('canApply: same kind, link to reader kind, migrations only', () => {
  const read = (kind) => ({ kind, metadata: {} });
  assert.equal(canApply(read('tool'), { kind: 'tool' }), true);
  assert.equal(canApply(read('tool'), { kind: 'link' }), true);
  assert.equal(canApply(read('tool'), { kind: null }), true);
  assert.equal(canApply(read('resource'), { kind: 'tool' }), true);
  assert.equal(canApply(read('tool'), { kind: 'resource' }), false);
  assert.equal(canApply(read('tool'), { kind: 'typeface' }), false);
  assert.equal(canApply({ kind: 'link', metadata: {} }, { kind: 'link' }), false);
  assert.equal(canApply({ kind: 'tool', metadata: null }, { kind: 'link' }), false);
});

test('freshReadFields: a curated kind is never flipped', () => {
  assert.equal(freshReadFields({ kind: 'tool', metadata: { name: 'X' } }, { kind: 'website' }), null);
});

test('freshReadFields: a refetch that reads less keeps the earlier read', () => {
  const item = { kind: 'tool', metadata: JSON.stringify({ subtype: 'app', name: 'Figma', platforms: ['mac'], topics: [] }) };
  const f = freshReadFields({ kind: 'tool', metadata: { subtype: 'app', platforms: [], topics: [] }, domain: 'figma.com' }, item);
  assert.equal(f.kind, 'tool');
  assert.equal(f.metadata.name, 'Figma');
  assert.deepEqual(f.metadata.platforms, ['mac']);
  assert.equal(f.domain, 'figma.com');
});

test('freshReadFields: a migration starts a fresh dossier', () => {
  const item = { kind: 'product', metadata: { price: 10, brand: 'B' } };
  const f = freshReadFields({ kind: 'resource', metadata: { subtype: 'template' } }, item);
  assert.equal(f.kind, 'resource');
  assert.equal(f.metadata.price, undefined);
});

test('freshReadFields: gone page marks the item gone', () => {
  const f = freshReadFields({ kind: 'link', metadata: null, status: 'gone' }, { kind: 'link', status: 'active' });
  assert.deepEqual(f, { status: 'gone' });
});

test('freshReadFields: music replaces the dossier on link or music items only', () => {
  assert.equal(freshReadFields({ kind: 'music', metadata: { album: 'A' } }, { kind: 'link' }).kind, 'music');
  assert.equal(freshReadFields({ kind: 'music', metadata: { album: 'A' } }, { kind: 'book' }), null);
});

test('mergeProduct: price when saved is a snapshot; read names beat guesses', () => {
  const m = mergeProduct(
    { price: 20, currency: 'USD', productName: 'Guess', productNameIsGuess: true },
    { price: 10, currency: 'EUR', pricedAt: '2026-01-01', productName: 'Real', productNameIsGuess: false },
  );
  assert.equal(m.price, 10);
  assert.equal(m.currency, 'EUR');
  assert.equal(m.productName, 'Real');
});

test('mergePost: keeps text and AI-art fields', () => {
  const m = mergePost({ text: null, isAIArt: false }, { text: 'hi', isAIArt: true, prompt: 'p' });
  assert.equal(m.text, 'hi');
  assert.equal(m.isAIArt, true);
  assert.equal(m.prompt, 'p');
});

test('post title follows the new reading only while it is the rule-made one', () => {
  const read = { kind: 'post', metadata: { authorHandle: 'ann', text: 'New words here today' } };
  const ours = freshReadFields(read, { kind: 'post', title: '@ann: Old', metadata: { authorHandle: 'ann', text: 'Old' } });
  assert.match(ours.title, /^@ann: /);
  const edited = freshReadFields(read, { kind: 'post', title: 'My own title', metadata: { authorHandle: 'ann', text: 'Old' } });
  assert.equal(edited.title, undefined);
});

test('stripSections still drops a section', () => {
  assert.equal(stripSections('# T\n\n## Key Snippets\n> a\n\n## Notes\nx', ['Key Snippets']), '# T\n\n## Notes\nx');
});

test('AI snippets: a user-run Enrich replaces earlier AI picks, never the user\'s own', () => {
  const { mergeAISnippets, withKeySnippets } = require('../src/routes/enrich.js');
  const existing = [{ text: 'Menu Home About', source: 'ai' }, { text: 'Mine', source: 'manual' }];
  const r = mergeAISnippets(existing, ['A real line', 'mine'], { replace: true, now: 't' });
  assert.deepEqual(r.snippets.map(s => s.text), ['Mine', 'A real line']);
  assert.equal(r.snippets[1].source, 'ai');
  const auto = mergeAISnippets(existing, ['menu home about'], { now: 't' });
  assert.equal(auto.changed, false);
  assert.equal(withKeySnippets('# T\n\n## Key Snippets\n> old', r.snippets), '# T\n\n## Key Snippets\n> Mine\n\n> A real line');
});
