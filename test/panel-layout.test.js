// Web port of the Mac item panel (panel-layout.js). Dedupe cases mirror
// apple/Stello/StelloTests/PanelDedupeTests.swift; layout cases check each
// kind's cards and rows against CardSubcards.swift.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const P = createRequire(import.meta.url)('../panel-layout.js');

const base = (over) => ({
  slug: 's', title: 'Untitled', source_url: null, domain: null, author: null, summary: null,
  added_at: '2026-11-04T10:00:00Z', tags: [], images: [], snippets: [], enrichment_candidates: {},
  ...over,
});
const card = (panel, title) => panel.cards.find((c) => c.title === title);
const rows = (c) => Object.fromEntries((c ? c.rows : []).map((r) => [r.label, r.value]));

test('normalize / isRedundant / isSameValue match PanelDedupe', () => {
  assert.equal(P.normalize('Fish &amp; Chips &gt; all'), 'fish chips all');
  assert.equal(P.normalize('https://www.X.com/'), 'x com');
  assert.equal(P.normalize('@nickfloats'), 'nickfloats');
  assert.equal(P.normalize('  Nick   St. Pierre · @nickfloats '), 'nick st pierre nickfloats');
  assert.ok(P.isRedundant('X.com', ['https://www.x.com/']));
  assert.ok(P.isRedundant('Free', ['Mac · Free']));
  assert.equal(P.isRedundant('free', ['freedom of type']), false);
  assert.equal(P.isSameValue('Hybrid Theory', ['In the End · Linkin Park · Hybrid Theory · 2000']), false);
  assert.notEqual(P.factKey('Weights', '12'), P.factKey('Styles', '12'));
  assert.equal(P.factKey('Price', 'Free'), P.factKey('Paid / free', 'free'));
  assert.notEqual(P.factKey('Price range', '$$'), P.factKey('Price range', '$$$'));
  assert.deepEqual(
    P.filterTags(['x.com', 'nickfloats', 'midjourney', 'Midjourney', 'dribbble', 'typography', 'ai-art'],
      ['x.com', 'Nick St. Pierre · @nickfloats', 'Midjourney', 'dribbble.com']),
    ['typography', 'ai-art'],
  );
  assert.ok(P.namesSameSite('Frontend Masters', 'frontendmasters.com'));
  assert.equal(P.namesSameSite('The Verge', 'simonwillison.net'), false);
});

test('formatting helpers', () => {
  assert.equal(P.formattedPrice('2699.00', 'INR'), '₹2,699');
  assert.equal(P.formattedPrice('19.5', 'USD'), '$19.50');
  assert.equal(P.formattedPrice('10', 'SEK'), 'SEK 10');
  assert.equal(P.compactCount(12400), '12.4k');
  assert.equal(P.compactCount(1250000), '1.3M');
  assert.equal(P.weekLabel('2026-11-04T10:00:00Z'), 'W45 2026');
  // Swift JSONEncoder dates are seconds since 2001-01-01.
  assert.equal(P.toDate(0).toISOString(), '2001-01-01T00:00:00.000Z');
});

test('link item: Summary has Source + Added; Notes card; snippets deduped against the summary', () => {
  const item = base({
    title: 'Grid systems', source_url: 'https://example.com/grids', domain: 'example.com',
    author: 'Jane Doe', summary: 'A primer on grid systems for editorial design.',
    body_markdown: '## Summary\nx\n\n## Notes\nSome notes', snippets: [
      { text: 'A primer on grid systems' }, { text: 'Columns breathe.' },
    ],
  });
  const p = P.layout(item);
  assert.equal(p.kind, 'link');
  assert.equal(p.header.title, 'Grid systems');
  assert.equal(p.header.mainText, 'A primer on grid systems for editorial design.');
  const s = card(p, 'Summary');
  assert.deepEqual(s.rows.map((r) => r.label), ['Author', 'Source', 'Added']);
  assert.equal(s.rows[1].url, 'https://example.com/grids');
  assert.ok(card(p, 'Notes'));
  assert.deepEqual(P.visibleSnippets(item.snippets, p).map((x) => x.index), [1]);
});

test('music track: Album + Album artist (hidden when same as artist), genres, tracklist', () => {
  const meta = {
    subtype: 'track', cleanTitle: 'One More Time', artists: [{ name: 'Daft Punk', kind: 'individual' }],
    album: 'Discovery', albumArtist: 'Daft Punk', platform: 'spotify', releaseYear: '2001',
    genres: ['House'], trackList: [], totalDurationSeconds: 320,
  };
  const item = base({ kind: 'music', title: 'One More Time', source_url: 'https://open.spotify.com/track/1', domain: 'open.spotify.com', metadata: meta });
  let r = rows(card(P.layout(item), 'Summary'));
  assert.equal(r.Track, 'One More Time');
  assert.equal(r.Artist, 'Daft Punk');
  assert.equal(r.Album, 'Discovery');
  assert.equal(r['Album artist'], undefined);
  assert.equal(r.Duration, '5:20');
  assert.equal(r.Platform, 'Spotify');
  assert.deepEqual(card(P.layout(item), 'Genres').chips, ['House']);

  const comp = base({ ...item, metadata: { ...meta, albumArtist: 'Various Artists' } });
  assert.equal(rows(card(P.layout(comp), 'Summary'))['Album artist'], 'Various Artists');

  // A ref that resolves to a library item becomes an Artists card, not a row.
  const p = P.layout(item, { resolveSlug: (s) => s === 'daft-punk' });
  assert.equal(rows(card(p, 'Summary')).Artist, 'Daft Punk');
  const linked = base({ ...item, metadata: { ...meta, artists: [{ name: 'Daft Punk', slug: 'daft-punk', kind: 'individual' }] } });
  const p2 = P.layout(linked, { resolveSlug: (s) => s === 'daft-punk' });
  assert.equal(rows(card(p2, 'Summary')).Artist, undefined);
  assert.equal(card(p2, 'Artists').refs[0].name, 'Daft Punk');
});

test('product: Name identity row, prices, Posted by, Buy link', () => {
  const item = base({
    kind: 'product', title: 'Desk lamp', source_url: 'https://shop.example/lamp', domain: 'shop.example',
    metadata: {
      productName: 'Desk lamp', brand: { name: 'Lumo', kind: 'studio' }, price: '2699.00', currency: 'INR',
      pricedAt: 783000000, shop: 'Shop Example', buyURL: 'https://buy.example/lamp',
      creator: { name: 'Ana', kind: 'individual' },
    },
  });
  const p = P.layout(item);
  assert.equal(p.header.kindLine, '₹2,699 · Lumo');
  const r = rows(card(p, 'Summary'));
  assert.equal(r.Name, 'Desk lamp');
  assert.equal(r.Brand, 'Lumo'); // a part of the kind line is not a repeat
  assert.match(r['Price when saved'], /^₹2,699 · /);
  assert.ok(card(p, 'Posted by'));
  assert.equal(card(p, 'Links').rows[0].label, 'Buy');
});

test('post: AI art card with prompt; no snippets card', () => {
  const item = base({
    kind: 'post', title: '@nickfloats: a dreamy portrait of', source_url: 'https://x.com/nickfloats/status/1', domain: 'x.com',
    metadata: { platform: 'x', author: { name: 'Nick St. Pierre', kind: 'individual' }, authorHandle: 'nickfloats',
      text: 'a dreamy portrait of a fox', isAIArt: true, aiModel: 'Midjourney', prompt: '--sref 123' },
    tags: [{ tag: 'midjourney', category: 'tool', weight: 0.9 }, { tag: 'portrait', category: 'subject', weight: 0.8 }],
  });
  const p = P.layout(item);
  assert.equal(p.header.title, 'Nick St. Pierre · @nickfloats');
  assert.equal(p.header.mainText, 'a dreamy portrait of a fox');
  assert.equal(card(p, 'AI art').model, 'Midjourney');
  assert.deepEqual(P.visibleTags(item.tags, p).map((t) => t.tag), ['portrait']);
});

test('tool, resource, book, course, article build their cards', () => {
  const tool = P.layout(base({ kind: 'tool', title: 'owner/repo', source_url: 'https://github.com/owner/repo', domain: 'github.com',
    metadata: { subtype: 'library', name: 'owner/repo', tagline: 'Fast thing', repoURL: 'https://github.com/owner/repo', stars: 12400,
      language: 'Rust', license: 'MIT', topics: ['cli'], pricing: 'open source', homepageURL: 'https://repo.dev' } }));
  assert.equal(tool.header.kindLine, 'Open source · ★ 12.4k');
  assert.ok(card(tool, 'GitHub'));
  assert.equal(card(tool, 'Links').rows[0].label, 'Website');

  const res = P.layout(base({ kind: 'resource', title: 'Icons', source_url: 'https://figma.com/community/plugin/1', domain: 'figma.com',
    metadata: { subtype: 'plugin', worksWith: ['Figma'], pricing: 'free', users: 1200 } }));
  assert.equal(res.header.kindLine, 'Figma plugin · Free');

  const book = P.layout(base({ kind: 'book', title: 'Intro to Algorithms', source_url: 'https://openlibrary.org/b/1', domain: 'openlibrary.org',
    metadata: { authors: [{ name: 'Thomas H. Cormen', kind: 'individual' }, { name: 'C. Leiserson', kind: 'individual' }],
      publishedYear: 2009, pages: 1312, isbn13: '9780262033848', language: 'en', subjects: ['Algorithms', 'Computer science'] } }));
  const br = rows(card(book, 'Summary'));
  assert.equal(br.Authors, 'Thomas H. Cormen, C. Leiserson');
  assert.equal(br.Language, 'English');
  // 'Algorithms' is a word of the title, so it drops (Mac rule).
  assert.deepEqual(card(book, 'Subjects').chips, ['Computer science']);

  const course = P.layout(base({ kind: 'course', title: 'CSS', source_url: 'https://maven.com/c', domain: 'maven.com',
    metadata: { name: 'CSS for JS devs', provider: { name: 'Maven', kind: 'studio' }, format: 'cohort', lessons: 24, durationMinutes: 330, topics: ['css', 'layout'] } }));
  assert.equal(rows(card(course, 'Summary')).Length, '24 lessons · 5 h 30 min');
  assert.ok(card(course, 'Teaches'));

  const art = P.layout(base({ kind: 'article', title: 'Post', source_url: 'https://simonwillison.net/x', domain: 'simonwillison.net',
    metadata: { publication: 'simonwillison.net', readingMinutes: 6, summary: 'On-device summary.', summaryIsGuess: true } }));
  assert.equal(art.header.kindLine, 'simonwillison.net · 6 min');
  assert.equal(art.header.mainIsAISummary, true);
});

test('typeface and website dossiers keep their sections', () => {
  const tf = P.layout(base({ kind: 'typeface', title: 'Inter', metadata: {
    classification: ['Sans'], weightTypes: ['Regular', 'Bold'], weightCount: 2, license: 'OFL', paidOrFree: 'Free',
    faqs: [{ question: 'Q?', answer: 'A.' }], typeFoundry: { name: 'Rsms', kind: 'foundry' },
  } }));
  assert.deepEqual(tf.cards.map((c) => c.title), ['Summary', 'Classification', 'Weights', 'Foundry & designer', 'Letterform graphics', 'Previews', 'FAQs']);
  assert.equal(rows(card(tf, 'Summary')).Price, 'Free');
  assert.equal(card(tf, 'Weights').caption, '2 weights');

  const web = P.layout(base({ kind: 'website', title: 'Linear', metadata: {
    tagline: 'A fast issue tracker for teams', description: 'A fast issue tracker', categories: ['SaaS'],
    review: 'A fast issue tracker for teams', techStack: ['React'],
  } }));
  assert.equal(web.header.mainText, 'A fast issue tracker for teams');
  assert.deepEqual(web.header.extraTexts, []);
  assert.equal(card(web, 'Review'), undefined); // repeats the tagline
  assert.ok(card(web, 'Tech stack'));
});

test('kind without metadata falls back to the link panel', () => {
  assert.equal(P.layout(base({ kind: 'music', metadata: null })).kind, 'link');
  assert.equal(P.layout(base({ kind: 'music', metadata: '{"subtype":"track"}' })).kind, 'music');
});
