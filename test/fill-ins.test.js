// Web Enrich fill-ins per kind: rules first, one model call for the gaps, guesses
// flagged and never over a read value (Mac EnrichmentService.apply…IfNeeded).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fillIns, plan, parseReply, JOBS } from '../src/lib/readers/fill-ins.js';

const model = (reply) => {
  const calls = [];
  const fn = async (job) => { calls.push(job); return reply; };
  fn.calls = calls;
  return fn;
};

test('every job schema is strict: all keys required, no extras', () => {
  for (const [kind, job] of Object.entries(JOBS)) {
    assert.equal(job.schema.additionalProperties, false, kind);
    assert.deepEqual(job.schema.required, Object.keys(job.schema.properties), kind);
    assert.ok(job.system.length > 100, kind);
  }
});

test('tool: the model fills missing platforms + pricing as guesses', async () => {
  const item = { kind: 'tool', metadata: JSON.stringify({ name: 'Raycast', platforms: [], topics: [] }) };
  const m = model({ platforms: ['mac', 'Web'], pricing: 'freemium' });
  const f = await fillIns({ item, text: 'Raycast. Download for Mac. Free plan, Pro $8/month.', callModel: m });
  assert.equal(m.calls.length, 1);
  assert.match(m.calls[0].user, /^Page text: Raycast/);
  assert.deepEqual(f.metadata.platforms, ['macOS', 'Web']);
  assert.equal(f.metadata.platformsAreGuess, true);
  assert.equal(f.metadata.pricing, 'freemium');
  assert.equal(f.metadata.pricingIsGuess, true);
});

test('tool: without a key the rule pass fills what it can', async () => {
  const item = { kind: 'tool', metadata: { platforms: [] } };
  const f = await fillIns({ item, text: 'Download for Mac. Free forever plan, or upgrade to Pro.' });
  assert.deepEqual(f.metadata.platforms, ['macOS']);
  assert.equal(f.metadata.pricing, 'freemium');
});

test('tool: read values are never replaced and nothing is asked', async () => {
  const item = { kind: 'tool', metadata: { platforms: ['macOS'], pricing: 'paid' } };
  const m = model({ platforms: ['Windows'], pricing: 'free' });
  assert.equal(await fillIns({ item, text: 'Download for Windows', callModel: m }), null);
  assert.equal(m.calls.length, 0);
});

test('book: authors + year guessed; a failed call changes nothing', async () => {
  const item = { kind: 'book', metadata: { title: 'Intro to Algorithms', authors: [] } };
  const f = await fillIns({ item, text: 'By Thomas H. Cormen and Clifford Stein. MIT Press, 2009.', callModel: model({ authors: ['Thomas H. Cormen', 'Clifford Stein'], year: 2009 }) });
  assert.deepEqual(f.metadata.authors.map((a) => a.name), ['Thomas H. Cormen', 'Clifford Stein']);
  assert.equal(f.metadata.authorsAreGuess, true);
  assert.equal(f.metadata.publishedYear, 2009);
  const failing = async () => { throw new Error('boom'); };
  assert.equal(await fillIns({ item, text: 'x', callModel: failing }), null);
});

test('course: model guess, lessons from the rules', async () => {
  const item = { kind: 'course', metadata: { name: 'DS in Figma' } };
  const f = await fillIns({
    item, text: 'Join the next cohort. 24 lessons over six weeks of live sessions.',
    callModel: model({ format: 'cohort', durationText: '6 weeks', topics: ['Figma', 'Variables'] }),
  });
  assert.equal(f.metadata.format, 'cohort');
  assert.equal(f.metadata.formatIsGuess, true);
  assert.equal(f.metadata.durationText, '6 weeks');
  assert.deepEqual(f.metadata.topics, ['Figma', 'Variables']);
  assert.equal(f.metadata.lessons, 24);
});

test('article: summary as a guess; a tutorial with no model stack gets rule names', async () => {
  const item = { kind: 'article', metadata: { isTutorial: true, techStack: [] } };
  const f = await fillIns({
    item, text: 'In this tutorial we build a slider with GSAP and three.js.',
    callModel: model({ summary: 'Builds a slider.', techStack: [] }),
  });
  assert.equal(f.metadata.summary, 'Builds a slider.');
  assert.equal(f.metadata.summaryIsGuess, true);
  assert.ok(f.metadata.techStack.length > 0);
});

test('article: an existing summary is never re-asked', () => {
  assert.equal(plan({ kind: 'article', meta: { summary: 'Done', isTutorial: false }, text: 'x' }), null);
});

test('post: AI-art flag from labels, then the prompt guessed', async () => {
  const item = {
    kind: 'post',
    tags: [{ tag: 'midjourney', category: 'collection' }],
    metadata: { text: 'Brutalist library at dusk #aiart' },
  };
  const m = model({ prompt: 'brutalist library at dusk, cinematic' });
  const f = await fillIns({ item, text: null, callModel: m });
  assert.equal(f.metadata.isAIArt, true);
  assert.equal(f.metadata.aiModel, 'Midjourney');
  assert.match(m.calls[0].user, /^Model: Midjourney\nPost text:/);
  assert.equal(f.metadata.prompt, 'brutalist library at dusk, cinematic');
  assert.equal(f.metadata.promptIsGuess, true);
});

test('post: a rule-read prompt wins, no model call', async () => {
  const item = { kind: 'post', tags: [], metadata: { text: 'Prompt: neon city, rain --ar 3:2' } };
  const m = model({ prompt: 'other' });
  const f = await fillIns({ item, callModel: m });
  assert.equal(m.calls.length, 0);
  assert.equal(f.metadata.promptIsGuess, false);
  assert.match(f.metadata.prompt, /neon city/);
});

test('product: Instagram name + brand guessed; a title that was the old guess follows', async () => {
  const item = {
    kind: 'product', title: 'Dock',
    metadata: { source: 'instagram', caption: 'the @stuffcool Mag Dock', productName: 'Dock', productNameIsGuess: true },
  };
  const f = await fillIns({ item, callModel: model({ productName: 'Mag Dock', brand: 'Stuffcool' }) });
  assert.equal(f.metadata.productName, 'Mag Dock');
  assert.equal(f.metadata.brand.name, 'Stuffcool');
  assert.equal(f.metadata.brandIsGuess, true);
  assert.equal(f.title, 'Mag Dock');
});

test('product: shop pages are left to the readers', async () => {
  const item = { kind: 'product', metadata: { source: 'page' } };
  assert.equal(await fillIns({ item, callModel: model({ productName: 'X' }) }), null);
});

test('product: a bare image falls back to its filename', async () => {
  const item = { kind: 'product', source_url: 'https://cdn.x.com/u/ceramic-mug-blue_2.jpg', metadata: { source: 'image' } };
  const f = await fillIns({ item });
  assert.equal(f.metadata.productName, 'Ceramic mug blue');
});

test('music: a YouTube compound title is parsed', async () => {
  const item = {
    kind: 'music', title: 'Thassadiya - Video Song | Maa Inti Bangaaram | Samantha',
    metadata: { platform: 'youtube', artists: [] },
  };
  const f = await fillIns({ item, callModel: model({ artist: null, track: 'Thassadiya', version: null, film: 'Maa Inti Bangaaram' }) });
  assert.equal(f.metadata.cleanTitle, 'Thassadiya');
  assert.equal(f.metadata.film, 'Maa Inti Bangaaram');
  assert.deepEqual(f.metadata.artists, []);
});

test('music: other platforms are not asked', () => {
  assert.equal(plan({ kind: 'music', meta: { platform: 'spotify' }, title: 'A - B' }), null);
});

test('untyped items and curated kinds are skipped', async () => {
  assert.equal(await fillIns({ item: { kind: 'link', metadata: null } }), null);
  assert.equal(await fillIns({ item: { kind: 'typeface', metadata: {} } }), null);
});

test('parseReply tolerates a fence and rejects junk', () => {
  assert.deepEqual(parseReply('```json\n{"a":1}\n```'), { a: 1 });
  assert.equal(parseReply('nope'), null);
  assert.equal(parseReply('[1]'), null);
});
