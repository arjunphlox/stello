// Port of StelloTests/PostKindTests.swift (display and SwiftData tests stay with the Apple app).
import { test } from 'node:test';
import { eq, classify } from './readers-helpers.js';
import * as PC from '../src/lib/readers/classifier.js';
import * as Post from '../src/lib/readers/post.js';
import { APPLE_EPOCH } from '../src/lib/readers/html.js';

const buildPost = (url, platform, o = {}) => Post.build({ sourceURL: url, platform, html: o.html ?? '', ogTitle: o.ogTitle ?? null, ogDescription: o.ogDescription ?? null, ogImageURL: o.ogImage ?? null, ogType: o.ogType ?? null, syndication: o.syndication ?? null });
const syndication = (json, status = 200) => Post.parseSyndication(json, status);
const toDate = (apple) => new Date((apple + APPLE_EPOCH) * 1000);

const photoTweetJSON = JSON.stringify({
  __typename: 'Tweet', id_str: '1453768926539317251', lang: 'en',
  text: 'Four colour studies in blue &amp; orange https://t.co/AbC123xyz',
  created_at: '2021-10-28T17:00:00.000Z',
  user: { id_str: '1', name: 'Jane Doe', screen_name: 'janedoe' },
  mediaDetails: ['a', 'b', 'c', 'd'].map((x) => ({ type: 'photo', media_url_https: `https://pbs.twimg.com/media/${x}.jpg`, original_info: { width: 1200, height: 800 } })),
  photos: ['a', 'b', 'c', 'd'].map((x) => ({ url: `https://pbs.twimg.com/media/${x}.jpg`, width: 1200, height: 800 })),
});
const videoTweetJSON = JSON.stringify({
  __typename: 'Tweet', id_str: '1700000000000000000', text: 'gm https://t.co/Vid123', created_at: '2023-09-08T09:30:00.000Z',
  user: { name: 'Motion Lab', screen_name: 'motionlab' },
  mediaDetails: [{ type: 'video', media_url_https: 'https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/poster.jpg', original_info: { width: 1920, height: 1080 } }],
  video: { poster: 'https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/poster.jpg' },
});
const tombstoneJSON = '{"__typename":"TweetTombstone","tombstone":{"text":{"text":"This Post is from an account that no longer exists."}}}';

test('A single post on each platform → post, with its platform', () => {
  for (const [url, platform] of [
    ['https://x.com/janedoe/status/1453768926539317251', 'x'],
    ['https://twitter.com/janedoe/status/1453768926539317251?s=20', 'x'],
    ['https://mobile.twitter.com/janedoe/status/1453768926539317251', 'x'],
    ['https://www.instagram.com/p/C1a2B3c4D5e/', 'instagram'],
    ['https://www.instagram.com/reel/C1a2B3c4D5e/', 'instagram'],
    ['https://www.instagram.com/reels/C1a2B3c4D5e/', 'instagram'],
    ['https://www.instagram.com/tv/C1a2B3c4D5e/', 'instagram'],
    ['https://www.behance.net/gallery/123456/Brand-Identity', 'behance'],
    ['https://dribbble.com/shots/123456-Desk-lamp', 'dribbble'],
    ['https://www.pinterest.com/pin/123456789/', 'pinterest'],
    ['https://in.pinterest.com/pin/123456789/', 'pinterest'],
  ]) {
    const r = classify(url);
    eq(r.kind, 'post', url);
    eq(r.postPlatform, platform, url);
    eq(r.productSource, null, url);
  }
});

test('Profiles, feeds and boards are not posts', () => {
  for (const url of ['https://x.com/janedoe', 'https://twitter.com/home', 'https://www.instagram.com/stuffcool/', 'https://www.behance.net/janedoe', 'https://dribbble.com/janedoe', 'https://www.pinterest.com/janedoe/desk-ideas/']) {
    eq(classify(url).kind !== 'post', true, url);
  }
});

test('A wishlisted post stays a product', () => {
  const reel = classify('https://www.instagram.com/reel/C1a2B3c4D5e/', { labels: ['Wishlist'] });
  eq(reel.kind, 'product');
  eq(reel.productSource, 'instagram');
  eq(reel.postPlatform, null);
  eq(classify('https://x.com/maker/status/1234567890', { labels: ['wishlist'] }).kind, 'product');
  eq(PC.postPlatform('https://x.com/maker/status/1234567890', ['wishlist']), null);
});

test('A post beats og:type product; AI-art labels never decide the kind', () => {
  eq(classify('https://www.instagram.com/p/C1a2B3c4D5e/', { ogType: 'product' }).kind, 'post');
  eq(classify('https://example.com/gallery/neon-koi', { labels: ['gen-ai', 'midjourney'] }).kind, 'link');
  eq(classify('https://example.com/gallery/neon-koi', { labels: ['gen-ai'] }).kind, 'tool');
  eq(classify('https://x.com/janedoe/status/1', { labels: ['gen-ai'] }).kind, 'post');
});

test("Token: the embed widget's base-36 formula", () => {
  eq(Post.syndicationToken('20'), '6dq1a2xwd93');
  eq(Post.syndicationToken('1234567890'), '6iio5bzbwyw');
  eq(Post.syndicationToken('1700000000000000000'), '44cpgxmyurn');
  eq(Post.syndicationToken('1453768926539317251'), '3iv5e449nho');
  eq(Post.syndicationToken('not-a-number'), 'a');
});

test('Tweet id, handle and endpoint from the URL', () => {
  const url = 'https://x.com/janedoe/status/1453768926539317251/photo/1';
  eq(Post.tweetID(url), '1453768926539317251');
  eq(Post.handleFromXURL(url), 'janedoe');
  eq(Post.handleFromXURL('https://x.com/i/status/1453768926539317251'), null);
  eq(Post.tweetID('https://x.com/janedoe'), null);
  eq(Post.syndicationURL('1453768926539317251'), 'https://cdn.syndication.twimg.com/tweet-result?id=1453768926539317251&lang=en&token=3iv5e449nho');
});

test('Photo tweet: text cleaned, author, date, 4 photos → carousel', () => {
  const outcome = syndication(photoTweetJSON);
  eq(outcome.kind, 'tweet');
  const x = buildPost('https://x.com/janedoe/status/1453768926539317251', 'x', { ogTitle: 'JavaScript is not available.', syndication: outcome });
  const m = x.meta;
  eq(m.platform, 'x');
  eq(m.text, 'Four colour studies in blue & orange');
  eq(m.authorHandle, 'janedoe');
  eq(m.author?.name, 'Jane Doe');
  eq(m.mediaType, 'carousel');
  eq(m.mediaCount, 4);
  eq(toDate(m.postedAt).toISOString(), '2021-10-28T17:00:00.000Z');
  eq(x.imageURLs, ['a', 'b', 'c', 'd'].map((n) => `https://pbs.twimg.com/media/${n}.jpg`));
  eq(m.canonicalURL, 'https://x.com/janedoe/status/1453768926539317251');
  eq(m.embedURL, 'https://platform.twitter.com/embed/Tweet.html?id=1453768926539317251');
  eq(x.title, '@janedoe: Four colour studies in blue & orange');
  eq(x.isGone, false);
});

test('Video tweet: poster as the image, mediaType video, count 1', () => {
  const x = buildPost('https://twitter.com/motionlab/status/1700000000000000000', 'x', { syndication: syndication(videoTweetJSON) });
  eq(x.meta.mediaType, 'video');
  eq(x.meta.mediaCount, 1);
  eq(x.meta.text, 'gm');
  eq(x.imageURLs.length, 1);
  eq(x.title, '@motionlab: gm');
});

test('Tombstone, 404 and an empty body are gone; garbage is unavailable', () => {
  eq(syndication(tombstoneJSON).kind, 'gone');
  eq(Post.parseSyndication('', 404).kind, 'gone');
  eq(syndication('').kind, 'gone');
  eq(syndication('{}').kind, 'gone');
  eq(syndication('<html>rate limited</html>').kind, 'unavailable');
  eq(Post.parseSyndication(null, null).kind, 'unavailable');
  const gone = buildPost('https://x.com/janedoe/status/1', 'x', { ogTitle: 'Jane Doe (@janedoe) on X', syndication: syndication(tombstoneJSON) });
  eq(gone.isGone, true);
  eq(gone.meta.authorHandle, 'janedoe');
});

test('og fallback when syndication is unavailable', () => {
  const x = buildPost('https://x.com/janedoe/status/1', 'x', { ogTitle: 'Jane Doe on X: "Shipping the new type specimen today"', ogImage: 'https://pbs.twimg.com/media/og.jpg', syndication: { kind: 'unavailable' } });
  eq(x.meta.text, 'Shipping the new type specimen today');
  eq(x.meta.author?.name, 'Jane Doe');
  eq(x.meta.authorHandle, 'janedoe');
  eq(x.meta.mediaType, 'image');
  eq(x.imageURLs.length, 1);
  eq(x.title, '@janedoe: Shipping the new type specimen today');
});

test('Instagram image post: handle, name, caption, date, one image', () => {
  const x = buildPost('https://www.instagram.com/p/C1a2B3c4D5e/', 'instagram', {
    ogTitle: 'Jane Doe on Instagram: "Golden hour on the rooftop with the new lens"',
    ogDescription: '1,234 likes, 56 comments - janedoe on March 3, 2025: "Golden hour on the rooftop with the new lens". ',
    ogImage: 'https://scontent.cdninstagram.com/v/t51/abc.jpg?oe=1',
  });
  const m = x.meta;
  eq(m.platform, 'instagram');
  eq(m.authorHandle, 'janedoe');
  eq(m.author?.name, 'Jane Doe');
  eq(m.text, 'Golden hour on the rooftop with the new lens');
  eq(m.mediaType, 'image');
  eq(m.mediaCount, 1);
  eq(m.embedURL, 'https://www.instagram.com/p/C1a2B3c4D5e/embed');
  eq(toDate(m.postedAt).toISOString().slice(0, 10), '2025-03-03');
  eq(x.imageURLs.length, 1);
  eq(x.title, '@janedoe: Golden hour on the rooftop with the new…');
});

test('og:video or og:type video → video', () => {
  const withTag = buildPost('https://www.instagram.com/p/C1a2B3c4D5e/', 'instagram', { html: '<html><head><meta property="og:video" content="https://scontent.cdninstagram.com/v/clip.mp4"></head></html>', ogTitle: 'Motion Lab on Instagram: "Loop"', ogImage: 'https://scontent.cdninstagram.com/v/poster.jpg' });
  eq(withTag.meta.mediaType, 'video');
  const withType = buildPost('https://www.instagram.com/p/C1a2B3c4D5e/', 'instagram', { ogTitle: 'Motion Lab on Instagram: "Loop"', ogImage: 'https://scontent.cdninstagram.com/v/poster.jpg', ogType: 'video.other' });
  eq(withType.meta.mediaType, 'video');
  eq(withType.meta.authorHandle, null);
  eq(withType.title, 'Motion Lab: Loop');
});

test('Behance: oEmbed author + handle; the work title loses its boilerplate', () => {
  const x = Post.build({ sourceURL: 'https://www.behance.net/gallery/123456/Brand-Identity', platform: 'behance', ogTitle: 'Brand Identity for Foo on Behance', ogDescription: 'A full identity system for Foo.', ogImageURL: 'https://mir-s3-cdn-cf.behance.net/project_modules/a.jpg', oembed: { title: 'Brand Identity for Foo', authorName: 'Jane Doe', authorURL: 'https://www.behance.net/janedoe', thumbnailURL: null } });
  eq(x.meta.author?.name, 'Jane Doe');
  eq(x.meta.authorHandle, 'janedoe');
  eq(x.meta.text, 'A full identity system for Foo.');
  eq(x.title, 'Brand Identity for Foo');
  eq(Post.behanceOEmbedURL('https://www.behance.net/gallery/1/x?tracking=1'), 'https://www.behance.net/services/oembed?url=https%3A%2F%2Fwww.behance.net%2Fgallery%2F1%2Fx');
});

test("Dribbble: 'by Name on Dribbble' gives the author and the shot title", () => {
  const x = buildPost('https://dribbble.com/shots/123456-Desk-lamp', 'dribbble', { ogTitle: 'Desk lamp by Jane Doe on Dribbble', ogImage: 'https://cdn.dribbble.com/users/1/screenshots/1/lamp.png' });
  eq(x.meta.author?.name, 'Jane Doe');
  eq(x.title, 'Desk lamp');
  eq(x.meta.mediaType, 'image');
});

test('Pinterest: boilerplate description names the pinner, not the text', () => {
  const x = buildPost('https://www.pinterest.com/pin/123456789/', 'pinterest', { ogTitle: 'Pin on Interiors', ogDescription: 'This Pin was discovered by Jane Doe. Discover (and save!) your own Pins on Pinterest.', ogImage: 'https://i.pinimg.com/736x/a.jpg' });
  eq(x.meta.author?.name, 'Jane Doe');
  eq(x.meta.text, null);
  eq(x.title, 'Pin on Interiors');
});

test('AI art: labels, tags, Midjourney params', () => {
  eq(Post.aiArtSignal(['Midjourney'], [], null), { isAIArt: true, model: 'Midjourney' });
  eq(Post.aiArtSignal(['nijijourney'], [], null).model, 'Midjourney');
  eq(Post.aiArtSignal(['Gen AI'], [], null), { isAIArt: true, model: null });
  eq(Post.aiArtSignal(['ai-art', 'dall-e'], [], null).model, 'DALL·E');
  eq(Post.aiArtSignal(['wishlist', 'typography'], [], null).isAIArt, false);
  eq(Post.aiArtSignal([], ['stable-diffusion'], null), { isAIArt: true, model: 'Stable Diffusion' });
  eq(Post.aiArtSignal([], [], 'neon koi pond --ar 16:9 --v 6'), { isAIArt: true, model: 'Midjourney' });
  eq(Post.aiArtSignal([], [], 'foggy tower —style raw').isAIArt, true);
  eq(Post.aiArtSignal([], [], '--sref 12345 --stylize 250').isAIArt, true);
  eq(Post.aiArtSignal([], [], '--chaos 20').isAIArt, true);
  eq(Post.aiArtSignal([], [], '--niji 6 cat').isAIArt, true);
  eq(Post.aiArtSignal([], [], 'a --variant of the logo').isAIArt, false);
  eq(Post.aiArtSignal([], [], 'I love this art').isAIArt, false);
  eq(Post.aiArtSignal(['gen-ai'], [], 'made with Midjourney').model, 'Midjourney');
});

test("Prompt: after 'prompt:' / 'Prompt —', else the sentence with the params", () => {
  eq(Post.extractPrompt('New piece! Prompt: a neon koi pond at night, ukiyo-e style --ar 3:2'), 'a neon koi pond at night, ukiyo-e style --ar 3:2');
  eq(Post.extractPrompt('Prompt — "misty pine forest, morning light"'), 'misty pine forest, morning light');
  eq(Post.extractPrompt('Made this today. a brutalist tower in fog, cinematic --ar 2:3 --v 6\n#midjourney'), 'a brutalist tower in fog, cinematic --ar 2:3 --v 6');
  eq(Post.extractPrompt('just vibes'), null);
  eq(Post.extractPrompt(null), null);
});

test("A param needs a value or the end of the line: \"the --sref's\" is no prompt", () => {
  const tweet = "Made a free Midjourney Style Reference Tool\n\n>15k srefs\n>smart AI search\n"
    + '>view prompt + parameters\n>search by color, hex code, vibe, subject\n\n'
    + "I also curated 5 boards to visualize the --sref's against different styles\n\n"
    + "Link below. It's free and very useful";
  eq(Post.hasMidjourneyParams(tweet), false);
  eq(Post.extractPrompt(tweet), null);
  const meta = { text: tweet, isAIArt: false, promptIsGuess: false };
  Post.applyAIArt(meta, ['midjourney'], []);
  eq(meta.isAIArt, true);
  eq(meta.aiModel, 'Midjourney');
  eq(meta.prompt, null);
  eq(Post.hasMidjourneyParams('the --sref, again'), false);
  eq(Post.hasMidjourneyParams('koi pond --ar 16:9'), true);
  eq(Post.hasMidjourneyParams('--sref 123'), true);
  eq(Post.hasMidjourneyParams('tower --v 6'), true);
  eq(Post.hasMidjourneyParams('cat in rain --niji'), true);
});

test('applyAIArt: rule-read prompt replaces a guess; no signal clears the flag', () => {
  const meta = { text: 'Made this today. a brutalist tower in fog --ar 2:3', prompt: 'old guess', promptIsGuess: true, isAIArt: false };
  Post.applyAIArt(meta, [], []);
  eq(meta.isAIArt, true);
  eq(meta.aiModel, 'Midjourney');
  eq(meta.prompt, 'a brutalist tower in fog --ar 2:3');
  eq(meta.promptIsGuess, false);
  const plain = { text: 'Golden hour on the rooftop', isAIArt: true, aiModel: 'x', promptIsGuess: false };
  Post.applyAIArt(plain, [], []);
  eq(plain.isAIArt, false);
  eq(plain.aiModel, null);
});

const longText = 'Shipping the new type specimen today with every weight and the italics';

test('Generic platform titles are recognised; real titles are not', () => {
  for (const t of ['Jane Doe (@janedoe) on X', 'Jane Doe on X: "hello"', 'Jane Doe on Twitter', 'Jane Doe on Twitter: "hello"', 'Jane Doe on Instagram: "hello"', 'Jane Doe (@janedoe) • Instagram photos and videos', 'Instagram', 'Behance', 'Dribbble', 'Pin on Interiors', 'x.com', '']) {
    eq(Post.isGenericPostTitle(t), true, t);
  }
  eq(Post.isGenericPostTitle('Brand Identity for Foo on Behance'), false);
  eq(Post.isGenericPostTitle('Desk lamp'), false);
});

test("Each generic pattern becomes '@handle: first 8 words…'", () => {
  for (const t of ['Jane Doe (@janedoe) on X', 'Jane Doe on X: "Shipping…"', 'Jane Doe on Twitter', 'Jane Doe on Instagram: "Shipping…"', 'Behance', 'Dribbble']) {
    eq(Post.postTitle({ currentTitle: t, handle: 'janedoe', authorName: 'Jane Doe', text: longText }), '@janedoe: Shipping the new type specimen today with every…', t);
  }
});

test("Short text keeps no ellipsis; no handle uses the author's name", () => {
  eq(Post.postTitle({ currentTitle: 'Jane Doe on X', handle: 'janedoe', authorName: null, text: 'gm' }), '@janedoe: gm');
  eq(Post.postTitle({ currentTitle: 'Instagram', handle: null, authorName: 'Jane Doe', text: 'New lamp drop' }), 'Jane Doe: New lamp drop');
  eq(Post.textExcerpt('one two three four five six seven eight'), 'one two three four five six seven eight');
  eq(Post.textExcerpt('one, two, three, four, five, six, seven, eight, nine'), 'one, two, three, four, five, six, seven, eight…');
});

test('No text falls back to the original title; a real title is kept', () => {
  eq(Post.postTitle({ currentTitle: 'Jane Doe (@janedoe) on X', handle: 'janedoe', authorName: null, text: null }), 'Jane Doe (@janedoe) on X');
  eq(Post.postTitle({ currentTitle: 'My favourite lamp', handle: 'janedoe', authorName: null, text: longText }), 'My favourite lamp');
  eq(Post.postTitle({ currentTitle: 'Desk lamp by Jane Doe on Dribbble', handle: null, authorName: null, text: null }), 'Desk lamp');
});
