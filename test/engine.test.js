import { test } from 'node:test';
import assert from 'node:assert/strict';
import { read, ruleTags, matchEntity, makeNet } from '../engine/index.js';
import { readInput, blockedImageURL, fetchImage } from '../src/routes/read.js';

const noNet = makeNet({ fetchImpl: async () => { throw new Error('no network in tests'); } });

const page = `<html><head>
<meta property="og:title" content="Apercu by Colophon">
<meta property="og:description" content="A minimal sans from London">
<meta property="og:image" content="/og.png">
</head><body><p>Hello</p></body></html>`;

test('read turns a page into a folder-v2 header without fetching when html is given', async () => {
  const r = await read({ url: 'https://www.example.com/apercu', html: page, status: 200, collectionLabels: ['type-foundries'], net: noNet });
  assert.equal(r.title, 'Apercu by Colophon');
  assert.equal(r.site, 'example.com');
  assert.equal(r.kind, 'link');
  assert.equal(r.tags.format.website, 0.4);
  assert.equal(r.tags.style.minimalist, 0.65);
  assert.equal(r.tags.collection, undefined, 'collections are references, not tags');
  assert.equal(r.tags.location, undefined, 'places are references, not tags');
  assert.deepEqual(r.collections, ['Type Foundries']);
  assert.ok(r.places.some((p) => p.kind === 'country'));
  assert.deepEqual(r.images, [{ url: 'https://www.example.com/og.png', source: 'og', is_primary: true }]);
  assert.equal(r.engine, 1);
});

test('ruleTags keeps the capture rules', () => {
  const tags = ruleTags({ title: 'Brutalist Figma kit', domain: 'figma.com', description: 'A minimal UI kit', url: 'https://figma.com/x' });
  assert.ok(tags.find((t) => t.tag === 'figma' && t.category === 'format'));
  assert.ok(tags.find((t) => t.tag === 'minimalist' && t.category === 'style'));
});

test('matchEntity matches names and aliases loosely', () => {
  const people = [{ id: 'c1', name: 'Colophon', aliases: ['Colophon Foundry'] }, { id: 'd1', name: 'Daniël van der Winden' }];
  assert.equal(matchEntity(people, 'colophon foundry').id, 'c1');
  assert.equal(matchEntity(people, 'Daniel van der Winden').id, 'd1');
  assert.equal(matchEntity(people, 'Someone else'), null);
});

test('/api/read input checks', () => {
  assert.equal(readInput({ url: 'ftp://x' }), 'url must be an http(s) link');
  const i = readInput({ url: 'https://a.b', html: '' });
  assert.equal(i.fetchPage, false);
  assert.equal(readInput({ url: 'https://a.b' }).fetchPage, true);
});

test('image proxy blocks local and private hosts', async () => {
  for (const u of ['http://localhost/a.png', 'https://127.0.0.1/a.png', 'https://10.0.0.2/a.png', 'https://192.168.1.4/x', 'https://[::1]/x', 'https://nas.local/x', 'file:///etc/passwd', 'https://u:p@example.com/a.png']) {
    assert.equal(blockedImageURL(u), true, u);
  }
  assert.equal(blockedImageURL('https://images.example.com/a.png'), false);
  const bad = await fetchImage('https://10.0.0.1/a.png');
  assert.equal(bad.status, 400);
});

test('image proxy passes images and refuses other types', async () => {
  const fake = (type, body = 'x') => async () => new Response(body, { status: 200, headers: { 'content-type': type } });
  const ok = await fetchImage('https://cdn.example.com/a.png', { fetchImpl: fake('image/png') });
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get('content-type'), 'image/png');
  assert.equal((await fetchImage('https://cdn.example.com/a', { fetchImpl: fake('text/html') })).status, 415);
  const gone = async () => new Response('', { status: 404 });
  assert.equal((await fetchImage('https://cdn.example.com/missing.png', { fetchImpl: gone })).status, 404);
  assert.equal((await fetchImage('https://cdn.example.com/a.svg', { fetchImpl: fake('image/svg+xml') })).status, 415);
});
