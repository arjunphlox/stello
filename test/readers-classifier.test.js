// Port of StelloTests/PageClassifierTests.swift + the classification half of ProductKindTests.swift.
import { test } from 'node:test';
import { eq, classify } from './readers-helpers.js';
import * as PC from '../src/lib/readers/classifier.js';

const base = 'https://example.com/page';
const run = (html, opts = {}) => PC.classify({ html, baseURL: opts.url ?? base, domain: opts.domain ?? 'example.com', title: opts.title ?? null, ogDescription: opts.ogDescription ?? null, ogType: opts.ogType ?? null });

test('Person JSON-LD → individual with role, location, bio, social', () => {
  const html = `<html><head>
    <meta property="og:description" content="Designer and letterer based in Portland.">
    <script type="application/ld+json">
    { "@context": "https://schema.org", "@type": "Person", "name": "Alex Rivera", "jobTitle": "Type Designer",
      "address": { "@type": "PostalAddress", "addressLocality": "Portland", "addressRegion": "OR" } }
    </script></head><body>
    <a href="https://instagram.com/alexrivera">Instagram</a>
    <a href="https://www.linkedin.com/in/alexrivera">LinkedIn</a>
    </body></html>`;
  const r = run(html, { title: 'Alex Rivera', ogDescription: 'Designer and letterer based in Portland.' });
  eq(r.kind, 'individual');
  eq(r.individualMeta?.bio, 'Designer and letterer based in Portland.');
  eq(r.individualMeta?.currentRole, 'Type Designer');
  eq(r.individualMeta?.location?.name, 'Portland, OR');
  eq(r.individualMeta?.instagramURL, 'https://instagram.com/alexrivera');
  eq(r.individualMeta?.linkedInURL, 'https://www.linkedin.com/in/alexrivera');
});

test('rel=me indie site → individual social URLs', () => {
  const html = `<html><head>
    <meta property="og:type" content="profile">
    <link rel="me" href="https://mastodon.social/@artist">
    <link rel="me" href="https://bsky.app/profile/artist.bsky.social">
    </head><body>
    <a rel="me" href="https://threads.net/@artist">Threads</a>
    <a href="https://x.com/artist">X</a>
    </body></html>`;
  const r = run(html, { url: 'https://artist.example', domain: 'artist.example', title: 'Artist Portfolio', ogType: 'profile' });
  eq(r.kind, 'individual');
  eq(r.individualMeta?.mastodon, 'https://mastodon.social/@artist');
  eq(r.individualMeta?.bluesky, 'https://bsky.app/profile/artist.bsky.social');
  eq(r.individualMeta?.threads, 'https://threads.net/@artist');
  eq(r.individualMeta?.xURL, 'https://x.com/artist');
});

test('Plain article stays link', () => {
  const html = '<html><head><meta property="og:type" content="article"><title>How Grid Layout Works</title></head><body><p>Article body.</p></body></html>';
  const r = run(html, { title: 'How Grid Layout Works', ogDescription: 'A deep dive into CSS grid.' });
  eq(r.kind, 'link');
  eq(r.individualMeta, null);
});

test('Organization with foundry signals → foundry', () => {
  const html = '<html><head><title>Klim Type Foundry</title><script type="application/ld+json">{ "@context": "https://schema.org", "@type": "Organization", "name": "Klim Type Foundry" }</script></head><body></body></html>';
  const r = run(html, { url: 'https://klim.co.nz/fonts', domain: 'klim.co.nz', title: 'Klim Type Foundry' });
  eq(r.kind, 'foundry');
});

test('Conflicting individual + foundry signals → link', () => {
  const html = '<html><head><meta property="og:type" content="profile"><script type="application/ld+json">{ "@type": "Organization", "name": "Acme Type Foundry" }</script></head><body></body></html>';
  const r = run(html, { url: 'https://acme-typefoundry.com', domain: 'acme-typefoundry.com', title: 'Acme Type Foundry', ogType: 'profile' });
  eq(r.kind, 'link');
});

test('Organization without foundry keywords stays link', () => {
  const html = '<html><head><script type="application/ld+json">{ "@type": "Organization", "name": "Acme Corp" }</script></head></html>';
  eq(run(html, { domain: 'acme.com', title: 'Acme Corp' }).kind, 'link');
});

test('Yoast @graph article with nested author Person → article, not individual', () => {
  const html = `<html><head><title>10 Tips</title><script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[{"@type":"Article","headline":"10 Tips for Better Type Design",
      "author":{"@type":"Person","name":"Jane Writer","jobTitle":"Staff Writer",
      "address":{"@type":"PostalAddress","addressLocality":"Brooklyn","addressRegion":"NY"}},
      "publisher":{"@type":"Organization","name":"Design Weekly"}}]}
    </script></head><body></body></html>`;
  const r = run(html, { domain: 'designweekly.com', title: '10 Tips for Better Type Design' });
  eq(r.kind, 'article');
  eq(r.individualMeta, null);
});

test("Publisher article with 'fonts' in the title + Organization node → article, not foundry", () => {
  const html = `<html><head><title>The 10 Best Free Fonts of 2026</title><script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[{"@type":"Article","headline":"The 10 Best Free Fonts of 2026"},{"@type":"Organization","name":"Design Weekly"}]}
    </script></head><body></body></html>`;
  eq(run(html, { domain: 'designweekly.com', title: 'The 10 Best Free Fonts of 2026' }).kind, 'article');
});

test('Person referenced as @graph mainEntity → individual', () => {
  const html = `<html><head><script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[{"@type":"ProfilePage","mainEntity":{"@id":"https://people.example/jo#person"}},
      {"@type":"Person","@id":"https://people.example/jo#person","name":"Jo Glyph","jobTitle":"Lettering Artist"}]}
    </script></head><body></body></html>`;
  const r = run(html, { url: 'https://people.example/jo', domain: 'people.example', title: 'Jo Glyph' });
  eq(r.kind, 'individual');
  eq(r.individualMeta?.currentRole, 'Lettering Artist');
});

const profile = (body, head = '') => `<html><head><meta property="og:type" content="profile"><script type="application/ld+json">{ "@type": "Person", "name": "Alex Rivera" }</script>${head}</head><body>${body}</body></html>`;

test('Twitter intent/share widget link is ignored', () => {
  const r = run(profile('<a href="https://twitter.com/intent/tweet?text=hello">Share</a>'), { title: 'Alex Rivera', ogDescription: 'Portfolio site.' });
  eq(r.kind, 'individual');
  eq(r.individualMeta?.xURL, null);
});

test('Spoofed host is rejected; a real linkedin.com subdomain matches', () => {
  const r = run(profile('<a href="https://linkedin.com.evil.net/in/impersonator">x</a><a href="https://business.linkedin.com/some-page">y</a>'), { title: 'Alex Rivera', ogDescription: 'Portfolio site.' });
  eq(r.individualMeta?.linkedInURL, 'https://business.linkedin.com/some-page');
});

test('rel=me to an unrecognized host is left unset', () => {
  const r = run(profile('<a href="https://instagram.com/alexrivera">Instagram</a>', '<link rel="me" href="https://github.com/alexrivera">'), { title: 'Alex Rivera', ogDescription: 'Portfolio site.' });
  eq(r.individualMeta?.mastodon, null);
  eq(r.individualMeta?.instagramURL, 'https://instagram.com/alexrivera');
});

test('rel=me link beats a body anchor for the same platform', () => {
  const r = run(profile('<a href="https://bsky.app/profile/someoneelse.bsky.social">a</a><a rel="me" href="https://bsky.app/profile/alexrivera.bsky.social">b</a>'), { title: 'Alex Rivera', ogDescription: 'Portfolio site.' });
  eq(r.individualMeta?.bluesky, 'https://bsky.app/profile/alexrivera.bsky.social');
});

// ─── Product classification (ProductKindTests.swift) ─────────────────────

test('og:type product → product (page)', () => {
  const r = classify('https://shop.example.com/item/lamp', { ogType: 'product' });
  eq(r.kind, 'product');
  eq(r.productSource, 'page');
  eq(classify('https://shop.example.com/item/lamp', { ogType: 'og:product' }).kind, 'product');
  eq(classify('https://shop.example.com/item/lamp', { ogType: 'product.item' }).kind, 'product');
});

test('Product JSON-LD → product', () => {
  const html = '<html><head><script type="application/ld+json">{"@context":"https://schema.org","@type":"Product","name":"Mag Dock","brand":"Stuffcool","offers":{"@type":"Offer","price":"2699","priceCurrency":"INR"}}</script></head><body></body></html>';
  const r = classify('https://stuffcool.com/item/mag-dock', { html });
  eq(r.kind, 'product');
  eq(r.productSource, 'page');
});

test('SaaS Product JSON-LD without an offer, or next to SoftwareApplication, stays non-product', () => {
  const noOffer = '<html><head><script type="application/ld+json">{"@context":"https://schema.org","@type":"Product","name":"Acme Analytics"}</script></head></html>';
  eq(classify('https://acme.io/', { html: noOffer }).kind !== 'product', true);
  const software = '<html><head><script type="application/ld+json">[{"@type":"SoftwareApplication","name":"Acme","operatingSystem":"macOS"},{"@type":"Product","name":"Acme","offers":{"@type":"Offer","price":"0"}}]</script></head></html>';
  eq(classify('https://acme.io/', { html: software }).kind !== 'product', true);
});

test('Shopify /products/ path with a storefront marker → product', () => {
  const html = '<html><head><link rel="preconnect" href="https://cdn.shopify.com"></head><body></body></html>';
  eq(classify('https://stuffcool.com/products/mag-dock', { html }).kind, 'product');
  eq(classify('https://stuffcool.com/collections/desk/products/mag-dock?variant=1', { html }).kind, 'product');
  eq(classify('https://store.myshopify.com/products/mag-dock').kind, 'product');
});

test('A /products/ path on a non-Shopify site stays link', () => {
  eq(classify('https://saas.example.com/products/analytics', { html: '<html><head><title>Analytics</title></head><body>Our analytics product</body></html>' }).kind, 'link');
});

test('Amazon product and Kickstarter project pages → product; other Amazon pages do not', () => {
  eq(classify('https://www.amazon.in/Umbra-Buddy-Hooks/dp/B00ABC1234').kind, 'product');
  eq(classify('https://www.amazon.co.uk/gp/product/B00ABC1234').kind, 'product');
  eq(classify('https://amzn.to/3xYzAbc').kind, 'product');
  eq(classify('https://www.kickstarter.com/projects/maker/desk-lamp').kind, 'product');
  eq(classify('https://www.amazon.in/').kind, 'link');
  eq(classify('https://amazon.com.evil.net/dp/B00ABC1234').kind, 'link');
  eq(classify('https://www.kickstarter.com/discover').kind, 'link');
});

test('Bare image URL is a product only with the wishlist label', () => {
  const url = 'https://stuffcool.com/cdn/shop/files/umbra-buddy-wall-hooks-set-of-3-black-3.jpg?v=12';
  const labelled = classify(url, { labels: ['Wishlist'] });
  eq(labelled.kind, 'product');
  eq(labelled.productSource, 'image');
  eq(classify(url).kind, 'link');
  eq(classify(url, { labels: ['digital-tools'] }).kind, 'link');
});

test('Wishlist override: an Instagram post → product only when wishlisted', () => {
  const post = 'https://www.instagram.com/reel/C1a2B3c4D5e/';
  const w = classify(post, { labels: ['wishlist'] });
  eq(w.kind, 'product');
  eq(w.productSource, 'instagram');
  eq(classify(post, { ogType: 'product' }).kind, 'post');
  eq(PC.socialPostHost('https://www.instagram.com/stuffcool/'), null);
});

test('Wishlisted X / Pinterest posts → product (page source)', () => {
  const x = classify('https://x.com/maker/status/1234567890', { labels: ['wishlist'] });
  eq(x.kind, 'product');
  eq(x.productSource, 'page');
  eq(classify('https://in.pinterest.com/pin/123456/', { labels: ['wishlist'] }).kind, 'product');
  eq(PC.socialPostHost('https://dribbble.com/shots/123-lamp'), 'dribbble');
  eq(PC.socialPostHost('https://www.behance.net/gallery/1/x'), 'behance');
});

test('An article that lists products stays an article', () => {
  const roundup = '<html><head><script type="application/ld+json">{"@context":"https://schema.org","@type":"Article","headline":"10 best desk lamps","mainEntity":{"@type":"ItemList","itemListElement":[{"@type":"ListItem","position":1,"item":{"@type":"Product","name":"Lamp A"}}]}}</script></head></html>';
  eq(classify('https://blog.example.com/best-desk-lamps', { html: roundup }).kind, 'article');
  const yoast = '<html><head><script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"Article","headline":"Review: Lamp A"},{"@type":"Product","name":"Lamp A"}]}</script></head></html>';
  eq(classify('https://blog.example.com/lamp-a-review', { html: yoast, ogType: 'article' }).kind, 'article');
  eq(classify('https://blog.example.com/lamp-a-review', { html: yoast, labels: ['wishlist'] }).kind, 'article');
});
