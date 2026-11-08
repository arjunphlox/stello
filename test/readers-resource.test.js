// Port of StelloTests/ResourceKindTests.swift (kind-line, SwiftData item and refresh
// tests stay with the Apple app).
import { test } from 'node:test';
import { eq, classify } from './readers-helpers.js';
import * as R from '../src/lib/readers/resource.js';
import * as C from '../src/lib/readers/classifier.js';

const jsonLD = (body) => `<html><head><script type="application/ld+json">\n${body}\n</script></head><body></body></html>`;
const buildResource = (url, { finalURL = null, html = '', ogTitle = null } = {}) =>
  R.build({ sourceURL: new URL(url), finalURL: finalURL ? new URL(finalURL) : null, html, ogTitle });
const isSingleBook = (url, html = '') => C.isSingleBook(new URL(url), html);

const figmaPluginURL = 'https://www.figma.com/community/plugin/735098390272716381/iconify';
const framerTemplateURL = 'https://www.framer.com/marketplace/templates/portfolio-pro/';
const figmaCreativeWorkJSONLD = `{"@context":"https://schema.org","@type":"CreativeWork","name":"Iconify",
 "creator":[{"@type":"Person","name":"Vjacheslav Trushkin","url":"https://www.figma.com/@cyberalien"}],
 "interactionStatistic":[
   {"@type":"InteractionCounter","interactionType":"https://schema.org/UseAction","userInteractionCount":124000},
   {"@type":"InteractionCounter","interactionType":{"@type":"LikeAction"},"userInteractionCount":"3,210"}
 ]}`;
const framerFreeProductJSONLD = `{"@context":"https://schema.org","@type":"Product","name":"Portfolio Pro",
 "brand":{"@type":"Brand","name":"Studio Nine","url":"https://www.framer.com/@studio-nine/"},
 "offers":{"@type":"Offer","price":"0","priceCurrency":"USD"}}`;
const framerPaidProductJSONLD = `{"@context":"https://schema.org","@type":"Product","name":"Agency X",
 "brand":{"@type":"Brand","name":"Nine Studio"},
 "offers":{"@type":"Offer","price":"49","priceCurrency":"USD"}}`;

// Classification

test('Figma Community plugin / widget / file URLs → resource', () => {
  for (const url of [
    figmaPluginURL, 'https://www.figma.com/community/plugin/735098390272716381',
    'https://www.figma.com/community/widget/1009867213296787406/voting-table',
    'https://www.figma.com/community/file/1035203688168086460/material-3-design-kit',
    'https://figma.com/community/file/1035203688168086460',
    'https://www.figma.com/@cyberalien/plugin/735098390272716381/iconify',
  ]) eq(classify(url).kind, 'resource', url);
  eq(C.figmaCommunityResourceType(new URL(figmaPluginURL)), 'plugin');
});

test('Figma Community home, search, listings, profiles and design files are not resources', () => {
  for (const url of [
    'https://www.figma.com/community', 'https://www.figma.com/community/',
    'https://www.figma.com/community/search?resource_type=plugins&q=icons', 'https://www.figma.com/community/plugins',
    'https://www.figma.com/community/plugin', 'https://www.figma.com/@cyberalien',
    'https://www.figma.com/design/abc123/My-File', 'https://www.figma.com/',
  ]) eq(classify(url).kind !== 'resource', true, url);
});

test('A Figma plugin wins over tool signals', () => {
  const app = jsonLD('{"@context":"https://schema.org","@type":"SoftwareApplication","name":"Iconify"}');
  eq(classify(figmaPluginURL, { html: app }).kind, 'resource');
  eq(classify(figmaPluginURL, { labels: ['digital-tools'] }).kind, 'resource');
});

test('Framer Marketplace template with Product JSON-LD + offers → resource, not product', () => {
  const html = jsonLD(framerFreeProductJSONLD);
  eq(C.productSource(new URL(framerTemplateURL), null, html, []), 'page');
  eq(classify(framerTemplateURL, { html }).kind, 'resource');
  eq(classify(framerTemplateURL, { html, ogType: 'product' }).kind, 'resource');
  eq(classify('https://www.framer.com/marketplace/plugins/lottie/').kind, 'resource');
  eq(classify('https://framer.com/marketplace/components/marquee').kind, 'resource');
  eq(classify('https://www.framer.com/marketplace/vectors/phosphor-icons/').kind, 'resource');
});

test('Framer Marketplace home, type listings, categories and creator pages are not resources', () => {
  for (const url of [
    'https://www.framer.com/marketplace/', 'https://www.framer.com/marketplace/templates/',
    'https://www.framer.com/marketplace/templates/category/portfolio/', 'https://www.framer.com/marketplace/creators/studio-nine/',
    'https://www.framer.com/templates/portfolio-pro/', 'https://www.framer.com/',
  ]) {
    eq(classify(url).kind !== 'resource', true, url);
    eq(C.framerMarketplaceSegment(new URL(url)), null, url);
  }
});

test('CodePen pen → resource; profiles and the home page are not', () => {
  eq(classify('https://codepen.io/jane/pen/abcXYZ').kind, 'resource');
  eq(classify('https://codepen.io/jane/full/abcXYZ').kind, 'resource');
  eq(classify('https://codepen.io/jane').kind !== 'resource', true);
  eq(classify('https://codepen.io/').kind !== 'resource', true);
  eq(classify('https://codepen.io/jane/pens/popular').kind !== 'resource', true);
});

test('digital-resources label on a plain page → resource', () => {
  for (const l of ['digital-resources', 'Digital Resources', 'digital_resources']) eq(classify('https://lucide.dev/', { labels: [l] }).kind, 'resource', l);
  eq(classify('https://cdn.example.com/kit.png', { labels: ['digital-resources'] }).kind !== 'resource', true);
});

test('digital-resources label + article → not a resource', () => {
  eq(classify('https://blog.example.com/best-icon-sets', { ogType: 'article', labels: ['digital-resources'] }).kind, 'link');
  for (const type of ['Article', 'BlogPosting', 'NewsArticle']) {
    const html = jsonLD(`{"@context":"https://schema.org","@type":"${type}","headline":"20 UI kits"}`);
    eq(classify('https://blog.example.com/ui-kits', { html, labels: ['digital-resources'] }).kind !== 'resource', true, type);
  }
});

test('digital-resources label beats a Product JSON-LD node and a tool label', () => {
  eq(classify('https://ui8.net/nine/products/agency-x', { html: jsonLD(framerPaidProductJSONLD), labels: ['digital-resources'] }).kind, 'resource');
  eq(classify('https://lucide.dev/', { labels: ['digital-resources', 'digital-tools'] }).kind, 'resource');
});

test('books label on a list page stays a website, not a resource', () => {
  eq(classify('https://fs.blog/reading-list/', { labels: ['books'] }).kind, 'link');
  eq(buildResource('https://fs.blog/reading-list/', { ogTitle: 'The Great Books Reading List' }).meta.subtype !== 'reading list', true);
});

test('books label on a single book is left to the existing rules', () => {
  eq(classify('https://www.amazon.com/dp/0760383383', { labels: ['books'] }).kind, 'book');
  for (const url of ['https://www.amazon.in/Some-Title/dp/0760383383', 'https://www.goodreads.com/book/show/40121378-atomic-habits',
    'https://openlibrary.org/works/OL17930368W', 'https://app.thestorygraph.com/books/0a1b2c3d']) {
    eq(classify(url, { labels: ['books'] }).kind !== 'resource', true, url);
  }
  const book = jsonLD('{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits","isbn":"0735211299"}');
  eq(classify('https://jamesclear.com/atomic-habits', { html: book, labels: ['books'] }).kind !== 'resource', true);
  const isbn = '<html><head><meta property="book:isbn" content="9780735211292"></head></html>';
  eq(classify('https://example.com/atomic-habits', { html: isbn, labels: ['books'] }).kind !== 'resource', true);
});

test('Amazon /dp/B0… stays a product', () => {
  const url = 'https://www.amazon.com/Stuffcool-Mag-Dock/dp/B0CHX1W1XY';
  for (const labels of [['wishlist'], ['wishlist', 'books'], ['books'], ['wishlist', 'digital-resources']]) eq(classify(url, { labels }).kind, 'product', labels.join());
});

test('A tweet with a digital-resources label stays a post', () => {
  const r = classify('https://x.com/janedoe/status/1453768926539317251', { labels: ['digital-resources'] });
  eq(r.kind, 'post');
  eq(r.postPlatform, 'x');
});

test('isSingleBook cases', () => {
  eq(isSingleBook('https://www.amazon.com/dp/0760383383'), true);
  eq(isSingleBook('https://www.amazon.com/Some-Book/dp/076038338X'), true);
  eq(isSingleBook('https://www.amazon.co.uk/gp/product/076038338x'), true);
  eq(isSingleBook('https://www.amazon.com/dp/B0CHX1W1XY'), false);
  eq(isSingleBook('https://www.amazon.com/dp/07603833'), false);
  eq(isSingleBook('https://www.goodreads.com/book/show/40121378-atomic-habits'), true);
  eq(isSingleBook('https://www.goodreads.com/list/show/1.Best_Books_Ever'), false);
  eq(isSingleBook('https://openlibrary.org/books/OL26331930M'), true);
  eq(isSingleBook('https://openlibrary.org/works/OL17930368W'), true);
  eq(isSingleBook('https://openlibrary.org/authors/OL1A'), false);
  eq(isSingleBook('https://app.thestorygraph.com/books/0a1b2c3d'), true);
  eq(isSingleBook('https://example.com/x', jsonLD('{"@context":"https://schema.org","@type":"Book","name":"Atomic Habits"}')), true);
  eq(isSingleBook('https://example.com/x', '<html><head><meta property="book:isbn" content="9780735211292"></head></html>'), true);
  eq(isSingleBook('https://fs.blog/reading-list/'), false);
  eq(C.isISBN10('0760383383'), true);
  eq(C.isISBN10('076038338X'), true);
  eq(C.isISBN10('B0CHX1W1XY'), false);
});

// Readers

test('Figma CreativeWork JSON-LD: name, creator with url, users + likes', () => {
  const x = buildResource(figmaPluginURL, { html: jsonLD(figmaCreativeWorkJSONLD), ogTitle: 'Iconify | Figma' });
  const m = x.meta;
  eq(m.name, 'Iconify');
  eq(x.title, 'Iconify');
  eq(m.maker?.name, 'Vjacheslav Trushkin');
  eq(m.maker?.url, 'https://www.figma.com/@cyberalien');
  eq(m.users, 124000);
  eq(m.likes, 3210);
  eq(m.subtype, 'plugin');
  eq(m.worksWith, ['Figma']);
  eq(m.pricing, null);
});

test('Interaction statistic shapes: single counter, legacy UserLikes, string counts', () => {
  eq(R.interactionCounts({ '@type': 'InteractionCounter', interactionType: 'http://schema.org/DownloadAction', userInteractionCount: '12.4k' }).users, 12400);
  const c = R.interactionCounts([
    { '@type': 'UserLikes', userInteractionCount: 42 },
    { '@type': 'InteractionCounter', interactionType: 'UserInteraction', userInteractionCount: 7 },
  ]);
  eq(c.likes, 42);
  eq(c.users, null);
  eq(R.interactionCounts(null).users, null);
});

test('Framer Product JSON-LD: brand as maker, offers price 0 → free', () => {
  const m = buildResource(framerTemplateURL, { html: jsonLD(framerFreeProductJSONLD), ogTitle: 'Portfolio Pro — Free Website Template for Framer' }).meta;
  eq(m.name, 'Portfolio Pro');
  eq(m.maker?.name, 'Studio Nine');
  eq(m.maker?.url, 'https://www.framer.com/@studio-nine/');
  eq(m.pricing, 'free');
  eq(m.price, null);
  eq(m.subtype, 'template');
  eq(m.worksWith, ['Framer']);
});

test('Framer paid template: price + currency', () => {
  const m = buildResource(framerTemplateURL, { html: jsonLD(framerPaidProductJSONLD) }).meta;
  eq(m.pricing, 'paid');
  eq(m.price, '49');
  eq(m.currency, 'USD');
});

test("og:title suffix stripping; 'Free' in the title → free", () => {
  eq(R.strippedName('Iconify | Figma'), 'Iconify');
  eq(R.strippedName('Material 3 Design Kit | Figma Community'), 'Material 3 Design Kit');
  eq(R.strippedName('Portfolio — Free Website Template for Framer'), 'Portfolio');
  eq(R.strippedName('Marquee - Framer Marketplace'), 'Marquee');
  eq(R.strippedName('Nova – UI Kit for Framer | Framer Marketplace'), 'Nova');
  eq(R.strippedName('CodePen - Wavy text'), 'Wavy text');
  eq(R.strippedName('Plain name'), 'Plain name');
  eq(R.strippedName('| Figma'), '| Figma');
  const m = buildResource('https://www.framer.com/marketplace/templates/portfolio/', { ogTitle: 'Portfolio — Free Website Template for Framer' }).meta;
  eq(m.name, 'Portfolio');
  eq(m.pricing, 'free');
});

test('Canonical URL: set when the final URL differs at all, else nil', () => {
  eq(buildResource('https://www.figma.com/community/plugin/735098390272716381', { finalURL: figmaPluginURL }).meta.canonicalURL, figmaPluginURL);
  eq(buildResource(figmaPluginURL, { finalURL: figmaPluginURL }).meta.canonicalURL, null);
  eq(buildResource(figmaPluginURL).meta.canonicalURL, null);
});

test('Subtypes: path, CodePen, FigJam, title words, site home page', () => {
  eq(buildResource('https://www.figma.com/community/widget/1/voting').meta.subtype, 'widget');
  eq(buildResource('https://www.figma.com/community/file/1/kit').meta.subtype, 'file');
  const figjam = buildResource('https://www.figma.com/community/file/1/retro', { ogTitle: 'Retro board (FigJam) | Figma' }).meta;
  eq(figjam.worksWith, ['FigJam']);
  eq(figjam.subtype, 'file');
  const pen = buildResource('https://codepen.io/jane/pen/abcXYZ', { ogTitle: 'Wavy text' }).meta;
  eq(pen.subtype, 'pen');
  eq(pen.worksWith, ['CodePen']);
  eq(buildResource('https://www.framer.com/marketplace/components/marquee/').meta.subtype, 'component');
  eq(buildResource('https://www.framer.com/marketplace/plugins/lottie/').meta.subtype, 'plugin');
  eq(buildResource('https://ls.graphics/mockups/iphone', { ogTitle: 'iPhone 17 Mockup' }).meta.subtype, 'mockup');
  eq(buildResource('https://phosphoricons.com/x', { ogTitle: 'Phosphor Icons' }).meta.subtype, 'icon set');
  eq(buildResource('https://ui8.net/x/y', { ogTitle: 'Nova UI Kit' }).meta.subtype, 'file');
  eq(buildResource('https://lucide.dev/').meta.subtype, 'library');
  eq(buildResource('https://example.com/some/page', { ogTitle: 'Something' }).meta.subtype, null);
});

test('A refetch that reads less never erases what capture read', () => {
  const previous = { name: 'Iconify', maker: { name: 'Vjacheslav', kind: 'maker' }, users: 100, subtype: 'plugin', worksWith: ['Figma'] };
  const m = R.merge({ likes: 5, worksWith: [] }, previous);
  eq(m.name, 'Iconify');
  eq(m.maker?.name, 'Vjacheslav');
  eq(m.users, 100);
  eq(m.likes, 5);
  eq(m.subtype, 'plugin');
  eq(m.worksWith, ['Figma']);
});
