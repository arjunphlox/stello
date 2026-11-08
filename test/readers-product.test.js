// Port of the reader half of StelloTests/ProductKindTests.swift (display-only and
// SwiftData item tests stay with the Apple app).
import { test } from 'node:test';
import { eq, FIXED_NOW } from './readers-helpers.js';
import * as P from '../src/lib/readers/product.js';

const buildPage = (url, html, ogTitle = null) => P.build({ sourceURL: url, source: 'page', html, ogTitle, now: FIXED_NOW });
const page = (jsonLD, extraHead = '') => `<html><head>${extraHead}<script type="application/ld+json">${jsonLD}</script></head><body></body></html>`;

const fixture = JSON.stringify({ product: {
  id: 1, title: 'Mag Dock', vendor: 'Stuffcool', product_type: 'Desk Accessories', handle: 'mag-dock', tags: 'desk, cables',
  variants: [{ id: 1, price: '2699.00' }, { id: 2, price: '3199.00' }, { id: 3, price: '2699.00' }],
  images: [
    { src: 'https://stuffcool.com/cdn/shop/files/1.jpg', width: 1200, height: 1200 },
    { src: '//stuffcool.com/cdn/shop/files/2.jpg', width: 1200, height: 900 },
    ...[3, 4, 5, 6, 7, 8, 9, 10].map((n) => ({ src: `https://stuffcool.com/cdn/shop/files/${n}.jpg` })),
  ] } });

test('.json URL strips the query and any /collections/ prefix', () => {
  eq(P.shopifyJSONURL('https://stuffcool.com/collections/desk/products/mag-dock?variant=42'), 'https://stuffcool.com/products/mag-dock.json');
  eq(P.shopifyJSONURL('https://stuffcool.com/pages/about'), null);
});

test('Shopify: title, vendor, product_type, variant price range, images (cap 8)', () => {
  const product = P.parseShopifyProduct(fixture);
  eq(product.title, 'Mag Dock');
  eq(product.variants.length, 3);
  const x = P.build({ sourceURL: 'https://stuffcool.com/products/mag-dock', source: 'page', html: '', ogTitle: 'Mag Dock – Stuffcool', shopify: product });
  const m = x.meta;
  eq(m.productName, 'Mag Dock');
  eq(m.productNameIsGuess, null);
  eq(m.brand?.name, 'Stuffcool');
  eq(m.category, 'Desk Accessories');
  eq(m.price, '2699.00');
  eq(m.priceMin, '2699.00');
  eq(m.priceMax, '3199.00');
  eq(m.pricedAt != null, true);
  eq(m.shop, 'stuffcool.com');
  eq(m.buyURL, 'https://stuffcool.com/products/mag-dock');
  eq(x.imageURLs.length, P.GALLERY_CAP);
  eq(x.imageURLs[1], 'https://stuffcool.com/cdn/shop/files/2.jpg');
  eq(x.title, 'Mag Dock');
});

test('A numeric variant price decodes too; malformed JSON returns null', () => {
  const p = P.parseShopifyProduct('{"product":{"title":"X","variants":[{"price":1999}]}}');
  const m = P.build({ sourceURL: 'https://x.com/products/x', source: 'page', shopify: p }).meta;
  eq(m.price, '1999');
  eq(P.parseShopifyProduct('not json'), null);
});

test('Single Offer: price, currency, availability; brand as object', () => {
  const html = page('{"@context":"https://schema.org","@type":"Product","name":"Mag Dock","sku":"MD-1","brand":{"@type":"Brand","name":"Stuffcool"},"image":["https://stuffcool.com/a.jpg","https://stuffcool.com/b.jpg"],"offers":{"@type":"Offer","price":"2699.00","priceCurrency":"inr","availability":"https://schema.org/InStock"}}');
  const x = buildPage('https://stuffcool.com/item/mag-dock', html);
  eq(x.meta.productName, 'Mag Dock');
  eq(x.meta.brand?.name, 'Stuffcool');
  eq(x.meta.price, '2699.00');
  eq(x.meta.currency, 'INR');
  eq(x.meta.availability, 'in stock');
  eq(x.meta.priceMin, null);
  eq(x.imageURLs.length, 2);
});

test('AggregateOffer: low/high range, brand as string', () => {
  const m = buildPage('https://lumen.example/lamp', page('{"@type":"Product","name":"Desk Lamp","brand":"Lumen","offers":{"@type":"AggregateOffer","lowPrice":19.5,"highPrice":"29.00","priceCurrency":"USD","offerCount":3}}')).meta;
  eq(m.brand?.name, 'Lumen');
  eq(m.price, '19.5');
  eq(m.priceMin, '19.5');
  eq(m.priceMax, '29.00');
  eq(m.currency, 'USD');
});

test('Offers as an array, priceSpecification, out-of-stock', () => {
  const m = buildPage('https://umbra.example/hooks', page('{"@type":"Product","name":"Hooks","brand":[{"@type":"Brand","name":"Umbra"}],"offers":[{"@type":"Offer","availability":"http://schema.org/OutOfStock","priceSpecification":{"@type":"UnitPriceSpecification","price":1299,"priceCurrency":"INR"}},{"@type":"Offer","price":"1499","priceCurrency":"INR"}]}')).meta;
  eq(m.brand?.name, 'Umbra');
  eq(m.price, '1299');
  eq(m.currency, 'INR');
  eq(m.availability, 'out of stock');
});

test('og price without currency; JSON-LD currency wins over og', () => {
  const ogOnly = '<html><head><meta property="og:type" content="product"><meta property="og:site_name" content="Stuffcool"><meta property="product:price:amount" content="2,699.00"></head><body></body></html>';
  const m = buildPage('https://stuffcool.com/item/x', ogOnly, 'Mag Dock').meta;
  eq(m.price, '2699.00');
  eq(m.currency, null);
  eq(m.shop, 'Stuffcool');
  eq(m.productName, 'Mag Dock');
  const merged = buildPage('https://stuffcool.com/item/x', page('{"@type":"Product","name":"Mag Dock","offers":{"@type":"Offer","price":"2699","priceCurrency":"INR"}}', '<meta property="og:price:amount" content="2699"><meta property="og:price:currency" content="USD">')).meta;
  eq(merged.currency, 'INR');
});

test('Availability labels and price normalisation', () => {
  eq(P.availabilityLabel('https://schema.org/PreOrder'), 'pre-order');
  eq(P.availabilityLabel('instock'), 'in stock');
  eq(P.availabilityLabel('oos'), 'out of stock');
  eq(P.normalizePrice('Rs. 2,699.00'), '2699.00');
  eq(P.normalizePrice('0.00'), null);
  eq(P.normalizePrice('free'), null);
});

test('Instagram: og:description carries handle + caption; og:title the display name', () => {
  const info = P.parseInstagramOG('Stuffcool on Instagram: "Mag Dock keeps every cable in place."', '1,234 likes, 56 comments - stuffcool on March 3, 2025: "Mag Dock keeps every cable in place.". ');
  eq(info.handle, 'stuffcool');
  eq(info.displayName, 'Stuffcool');
  eq(info.caption, 'Mag Dock keeps every cable in place.');
  eq(info.postedAt?.toISOString(), '2025-03-03T00:00:00.000Z');
});

test('Instagram title alone (with an @handle in parens) still yields name, handle and caption', () => {
  const info = P.parseInstagramOG('Desk Goods (@deskgoods) on Instagram: "New lamp drop"', null);
  eq(info.handle, 'deskgoods');
  eq(info.displayName, 'Desk Goods');
  eq(info.caption, 'New lamp drop');
});

test('Instagram product build: creator, caption, original post', () => {
  const x = P.build({ sourceURL: 'https://www.instagram.com/reel/C1a2B3c4D5e/', source: 'instagram', ogTitle: 'Stuffcool on Instagram: "Mag Dock"', ogDescription: '12K likes, 300 comments - stuffcool on May 1, 2025: "Mag Dock"', ogImageURL: 'https://scontent.cdninstagram.com/v/t51/abc.jpg?oe=1' });
  eq(x.meta.source, 'instagram');
  eq(x.meta.creatorHandle, 'stuffcool');
  eq(x.meta.creator?.name, 'Stuffcool');
  eq(x.meta.caption, 'Mag Dock');
  eq(x.meta.originalPostURL, 'https://www.instagram.com/reel/C1a2B3c4D5e/');
  eq(x.meta.price, null);
  eq(x.imageURLs.length, 1);
});

test('A non-post Instagram description yields nothing', () => {
  const info = P.parseInstagramOG('Instagram', 'Create an account or log in.');
  eq(info.handle, null);
  eq(info.caption, null);
});

test('Shop CDN filename slug → sentence-case title', () => {
  eq(P.titleFromImageFilename('https://stuffcool.com/cdn/shop/files/umbra-buddy-wall-hooks-set-of-3-black-3.jpg?v=1699'), 'Umbra buddy wall hooks set of 3 black');
  eq(P.titleFromImageFilename('https://x.com/cdn/shop/files/desk_lamp_1024x1024@2x.png'), 'Desk lamp');
  eq(P.titleFromImageFilename('https://x.com/files/Oak%20Stool-a1b2c3d4e5.webp'), 'Oak stool');
});

test('Camera-roll style names give no title', () => {
  eq(P.titleFromImageFilename('https://x.com/cdn/shop/files/IMG_1234.jpg'), null);
  eq(P.titleFromImageFilename('https://x.com/123456.png'), null);
});

test('Image product build marks the filename title as a guess', () => {
  const x = P.build({ sourceURL: 'https://stuffcool.com/cdn/shop/files/umbra-buddy-wall-hooks-set-of-3-black-3.jpg', source: 'image' });
  eq(x.meta.productName, 'Umbra buddy wall hooks set of 3 black');
  eq(x.meta.productNameIsGuess, true);
  eq(x.meta.brand, null);
  eq(x.meta.shop, 'stuffcool.com');
  eq(x.imageURLs.length, 1);
});
