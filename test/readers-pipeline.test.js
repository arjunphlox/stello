// The page-reader pipeline end to end, with the network faked: readPage, the
// save-then-sort step and the /api/classify body handling.
import { test } from 'node:test';
import { eq } from './readers-helpers.js';
import { readPage, makeNet, confidenceFor } from '../src/lib/readers/pipeline.js';
import { sortSavedItem, sortedFields } from '../src/lib/readers/sort-item.js';
import { classifyPages, pageInput, batchMax } from '../src/routes/classify.js';

/** A fetch stub: url → { status, body } (string or object); anything else 404s. */
function fakeFetch(routes) {
  const calls = [];
  const impl = async (url) => {
    calls.push(String(url));
    const r = routes[String(url)];
    const body = r == null ? 'not found' : (typeof r.body === 'string' ? r.body : JSON.stringify(r.body));
    return new Response(body, { status: r?.status ?? (r ? 200 : 404) });
  };
  return { impl, calls };
}

const githubRepo = { name: 'ripgrep', full_name: 'BurntSushi/ripgrep', owner: { login: 'BurntSushi' }, html_url: 'https://github.com/BurntSushi/ripgrep',
  description: 'ripgrep recursively searches directories for a regex pattern', stargazers_count: 48211, language: 'Rust',
  license: { spdx_id: 'Unlicense', name: 'The Unlicense' }, pushed_at: '2026-09-30T14:02:11Z', topics: ['cli'] };

test('A GitHub repo page → tool, with the REST API facts', async () => {
  const f = fakeFetch({
    'https://github.com/BurntSushi/ripgrep': { body: '<html><head><meta property="og:title" content="GitHub - BurntSushi/ripgrep"><meta property="og:image" content="https://opengraph.githubassets.com/x"></head><body><p>ripgrep</p></body></html>' },
    'https://api.github.com/repos/BurntSushi/ripgrep': { body: githubRepo },
  });
  const r = await readPage({ url: 'https://github.com/BurntSushi/ripgrep', net: makeNet({ fetchImpl: f.impl }) });
  eq(r.kind, 'tool');
  eq(r.title, 'BurntSushi/ripgrep');
  eq(r.metadata.stars, 48211);
  eq(r.metadata.pricing, 'open source');
  eq(r.images.urls, ['https://opengraph.githubassets.com/x']);
  eq(r.confidence >= 0.85, true);
  eq(f.calls.length, 2);
});

test('HTML from the app is read as given: no page fetch from the Worker', async () => {
  const f = fakeFetch({});
  const html = '<html><head><script type="application/ld+json">{"@type":"Course","name":"Motion basics","provider":{"@type":"Organization","name":"Motion Lab"}}</script></head></html>';
  const r = await readPage({ url: 'https://example.com/motion-basics', html, status: 200, net: makeNet({ fetchImpl: f.impl }) });
  eq(r.kind, 'course');
  eq(r.metadata.provider?.name, 'Motion Lab');
  eq(f.calls, []);
});

test('Shopify product: the .json endpoint fills the gallery and price', async () => {
  const shop = { product: { title: 'Mag Dock', vendor: 'Stuffcool', product_type: 'Desk', variants: [{ price: '2699.00' }],
    images: [{ src: 'https://stuffcool.com/cdn/shop/files/1.jpg' }, { src: 'https://stuffcool.com/cdn/shop/files/2.jpg' }] } };
  const f = fakeFetch({ 'https://stuffcool.com/products/mag-dock.json': { body: shop } });
  const html = '<html><head><link rel="preconnect" href="https://cdn.shopify.com"><meta property="og:image" content="https://stuffcool.com/og.jpg"></head></html>';
  const r = await readPage({ url: 'https://stuffcool.com/products/mag-dock', html, status: 200, net: makeNet({ fetchImpl: f.impl }) });
  eq(r.kind, 'product');
  eq(r.metadata.price, '2699.00');
  eq(r.images.source, 'product');
  eq(r.images.urls.length, 2);
  eq(r.images.fallbacks, ['https://stuffcool.com/og.jpg']);
});

test('A 404 page is gone; an unreadable page is a low-confidence link', async () => {
  const gone = await readPage({ url: 'https://example.com/blog/old-post', html: '<html></html>', status: 404, net: makeNet({ fetchImpl: fakeFetch({}).impl }) });
  eq(gone.status, 'gone');
  const failing = makeNet({ fetchImpl: async () => { throw new Error('blocked'); } });
  const unread = await readPage({ url: 'https://example.com/', net: failing });
  eq(unread.kind, 'link');
  eq(unread.fetched, false);
  eq(unread.confidence, 0.2);
  eq(confidenceFor('link', { status: 200 }, null).signal, 'no-rule-matched');
});

test('The subrequest budget stops extra calls', async () => {
  const f = fakeFetch({});
  const net = makeNet({ fetchImpl: f.impl, budget: 1 });
  eq((await net.get('https://a.example/')) != null, true);
  eq(await net.get('https://b.example/'), null);
  eq(f.calls.length, 1);
});

// Save first, sort second

function fakeClient() {
  const updates = [];
  return {
    updates,
    from: () => ({ update: (fields) => ({ eq: async (col, id) => { updates.push({ id, fields }); return { error: null }; } }) }),
  };
}

test('sortSavedItem writes kind, metadata, cleaned title and display domain', async () => {
  const f = fakeFetch({
    'https://github.com/BurntSushi/ripgrep': { body: '<html><head><title>GitHub - BurntSushi/ripgrep</title></head></html>' },
    'https://api.github.com/repos/BurntSushi/ripgrep': { body: githubRepo },
  });
  const client = fakeClient();
  const out = await sortSavedItem({ client, item: { id: 7, source_url: 'https://github.com/BurntSushi/ripgrep', kind: null, metadata: null }, net: makeNet({ fetchImpl: f.impl }) });
  eq(out.sorted, true);
  eq(client.updates.length, 1);
  eq(client.updates[0].id, 7);
  eq(client.updates[0].fields.kind, 'tool');
  eq(client.updates[0].fields.title, 'BurntSushi/ripgrep');
  eq(client.updates[0].fields.metadata.repoURL, 'https://github.com/BurntSushi/ripgrep');
});

test('An unsure page is left untyped for the Mac fill-in; a typed item is never re-sorted', async () => {
  const client = fakeClient();
  const plain = fakeFetch({ 'https://example.com/': { body: '<html><head><title>Home</title></head></html>' } });
  const out = await sortSavedItem({ client, item: { id: 1, source_url: 'https://example.com/' }, net: makeNet({ fetchImpl: plain.impl }) });
  eq(out.sorted, false);
  eq(client.updates, []);
  eq(await sortSavedItem({ client, item: { id: 2, source_url: 'https://example.com/', kind: 'book', metadata: { title: 'x' } } }), null);
  eq(await sortSavedItem({ client, item: { id: 3, source_url: null } }), null);
  eq(sortedFields({ kind: 'article', confidence: 0.5, metadata: {} }), null);
  eq(sortedFields({ kind: 'article', confidence: 0.85, metadata: {}, status: 'gone', title: 'Say "hi"' }), { kind: 'article', metadata: {}, title: "Say 'hi'", status: 'gone' });
});

// /api/classify body handling

test('/api/classify: one page in, one answer out; HTML given means no refetch', async () => {
  const f = fakeFetch({});
  const out = await classifyPages({ url: 'https://example.com/blog/my-first-post', html: '<html><head><title>Hi</title></head><body>words</body></html>', status: 200 }, {}, { net: makeNet({ fetchImpl: f.impl }) });
  eq(out.status, 200);
  eq(out.body.kind, 'article');
  eq(f.calls, []);
});

test('/api/classify: batch size follows CLASSIFY_BATCH_MAX (default 1); bad pages report errors', async () => {
  eq(batchMax({}), 1);
  eq(batchMax({ CLASSIFY_BATCH_MAX: '8' }), 8);
  eq(batchMax({ CLASSIFY_BATCH_MAX: 'x' }), 1);
  const pages = [{ url: 'https://example.com/blog/a', html: '' }, { url: 'ftp://nope' }];
  eq((await classifyPages({ pages }, {})).status, 413);
  const out = await classifyPages({ pages }, { CLASSIFY_BATCH_MAX: '2' }, { net: makeNet({ fetchImpl: fakeFetch({}).impl }) });
  eq(out.status, 200);
  eq(out.body.results[0].kind, 'article');
  eq(out.body.results[1].error, 'url must be an http(s) link');
  eq((await classifyPages({ url: 'javascript:alert(1)' }, {})).status, 400);
  eq(pageInput({ url: 'https://x.com/a', collectionLabels: ['gen-ai', 5] }).collectionLabels, ['gen-ai']);
});
