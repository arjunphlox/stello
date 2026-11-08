// Port of StelloTests/ToolKindTests.swift (display-only kind-line and SwiftData item tests
// stay with the Apple app).
import { test } from 'node:test';
import { eq, classify } from './readers-helpers.js';
import * as T from '../src/lib/readers/tool.js';
import { githubRepo, isMacAppStoreURL } from '../src/lib/readers/classifier.js';
import { appleDate } from '../src/lib/readers/html.js';

const jsonLD = (body) => `<html><head><script type="application/ld+json">\n${body}\n</script></head><body></body></html>`;
const buildTool = (url, { finalURL = null, html = '', ogDescription = null, github = null } = {}) =>
  T.build({ sourceURL: new URL(url), finalURL: finalURL ? new URL(finalURL) : null, html, ogDescription, github });

const softwareAppJSONLD = `{"@context":"https://schema.org","@type":"SoftwareApplication","name":"Things 3",
 "operatingSystem":"macOS","applicationCategory":"ProductivityApplication",
 "offers":{"@type":"Offer","price":"49.99","priceCurrency":"USD"},
 "author":{"@type":"Organization","name":"Cultured Code"}}`;
const githubRepoJSON = `{"id":1,"name":"ripgrep","full_name":"BurntSushi/ripgrep",
 "owner":{"login":"BurntSushi","id":2},
 "html_url":"https://github.com/BurntSushi/ripgrep",
 "description":"ripgrep recursively searches directories for a regex pattern",
 "homepage":"https://burntsushi.net/ripgrep/",
 "stargazers_count":48211,"language":"Rust",
 "license":{"key":"unlicense","name":"The Unlicense","spdx_id":"Unlicense"},
 "pushed_at":"2026-09-30T14:02:11Z",
 "topics":["cli","search","regex"],"archived":false}`;
const githubNoLicenseJSON = `{"name":"dotfiles","full_name":"jane/dotfiles","owner":{"login":"jane"},
 "html_url":"https://github.com/jane/dotfiles","stargazers_count":12,"language":"Shell",
 "license":null,"pushed_at":"2025-01-02T03:04:05Z","topics":[]}`;

// Classification

test('SoftwareApplication / WebApplication / MobileApplication JSON-LD → tool', () => {
  eq(classify('https://culturedcode.com/things/', { html: jsonLD(softwareAppJSONLD) }).kind, 'tool');
  eq(classify('https://www.figma.com/', { html: jsonLD('{"@context":"https://schema.org","@type":"WebApplication","name":"Figma"}') }).kind, 'tool');
  eq(classify('https://halide.cam/', { html: jsonLD('{"@context":"https://schema.org","@type":"MobileApplication","name":"Halide"}') }).kind, 'tool');
  eq(classify('https://linear.app/', { html: jsonLD('{"@context":"https://schema.org","@graph":[{"@type":"WebSite","name":"Linear"},{"@type":"WebApplication","name":"Linear"}]}') }).kind, 'tool');
});

test('App Store URLs → tool', () => {
  eq(classify('https://apps.apple.com/us/app/things-3/id904237743').kind, 'tool');
  eq(classify('https://apps.apple.com/app/id904237743').kind, 'tool');
  eq(classify('https://itunes.apple.com/us/app/things-3/id904237743?mt=12').kind, 'tool');
  eq(classify('macappstore://apps.apple.com/app/id904280696').kind, 'tool');
  eq(isMacAppStoreURL(new URL('https://apps.apple.com/us/app/things-3/id904280696?mt=12')), true);
  eq(isMacAppStoreURL(new URL('https://apps.apple.com/us/app/things-3/id904237743')), false);
  eq(classify('https://apps.apple.com/us/charts').kind !== 'tool', true);
  eq(classify('https://music.apple.com/us/album/x/1').kind !== 'tool', true);
});

test('GitHub repo root and repo subpages → tool', () => {
  for (const url of [
    'https://github.com/BurntSushi/ripgrep', 'https://github.com/BurntSushi/ripgrep/', 'https://www.github.com/BurntSushi/ripgrep',
    'https://github.com/BurntSushi/ripgrep/releases', 'https://github.com/BurntSushi/ripgrep/blob/master/README.md', 'https://github.com/BurntSushi/ripgrep.git',
  ]) eq(classify(url).kind, 'tool', url);
  const repo = githubRepo(new URL('https://github.com/BurntSushi/ripgrep.git'));
  eq(repo?.owner, 'BurntSushi');
  eq(repo?.repo, 'ripgrep');
});

test('GitHub profiles, site pages and gists are not tools', () => {
  for (const url of [
    'https://github.com/BurntSushi', 'https://github.com/', 'https://github.com/topics/cli', 'https://github.com/orgs/vercel/repositories',
    'https://github.com/features/copilot', 'https://github.com/marketplace/actions/checkout', 'https://github.com/settings/profile',
    'https://github.com/about/careers', 'https://github.com/pricing/plans', 'https://github.com/collections/clean-code-linters',
    'https://github.com/sponsors/BurntSushi', 'https://gist.github.com/jane/0123456789abcdef',
  ]) {
    eq(classify(url).kind !== 'tool', true, url);
    eq(githubRepo(new URL(url)), null, url);
  }
});

test('A digital-tools / digital-productivity / gen-ai label on a plain page → tool', () => {
  eq(classify('https://raycast.com/', { labels: ['digital-tools'] }).kind, 'tool');
  eq(classify('https://raycast.com/', { labels: ['Digital Productivity'] }).kind, 'tool');
  eq(classify('https://runwayml.com/', { labels: ['gen-ai'] }).kind, 'tool');
  eq(classify('https://runwayml.com/', { labels: ['Gen AI'] }).kind, 'tool');
  eq(classify('https://raycast.com/', { labels: ['typography'] }).kind, 'link');
  eq(classify('https://cdn.example.com/screenshot.png', { labels: ['digital-tools'] }).kind, 'link');
});

test('gen-ai label + og:type article → not a tool', () => {
  eq(classify('https://blog.example.com/what-is-diffusion', { ogType: 'article', labels: ['gen-ai'] }).kind, 'link');
});

test('gen-ai label + Article / BlogPosting / NewsArticle JSON-LD → not a tool', () => {
  for (const type of ['Article', 'BlogPosting', 'NewsArticle']) {
    const html = jsonLD(`{"@context":"https://schema.org","@type":"${type}","headline":"10 AI tools"}`);
    eq(classify('https://news.example.com/ai-tools', { html, labels: ['gen-ai'] }).kind !== 'tool', true, type);
    eq(classify('https://news.example.com/ai-tools', { html, labels: ['digital-tools'] }).kind !== 'tool', true, type);
  }
  const yoast = jsonLD('{"@context":"https://schema.org","@graph":[{"@type":"Article","headline":"x"},{"@type":"WebPage"}]}');
  eq(classify('https://blog.example.com/x', { html: yoast, labels: ['gen-ai'] }).kind !== 'tool', true);
});

test('Article override beats a SoftwareApplication node, but never a repo or an App Store URL', () => {
  const review = jsonLD(`[{"@context":"https://schema.org","@type":"Article","headline":"Review: Things 3"},
   {"@context":"https://schema.org","@type":"SoftwareApplication","name":"Things 3"}]`);
  eq(classify('https://blog.example.com/things-review', { html: review }).kind !== 'tool', true);
  eq(classify('https://blog.example.com/things-review', { html: jsonLD(softwareAppJSONLD), ogType: 'article' }).kind !== 'tool', true);
  eq(classify('https://github.com/BurntSushi/ripgrep', { html: review, ogType: 'article' }).kind, 'tool');
  eq(classify('https://apps.apple.com/us/app/things-3/id904237743', { html: review, ogType: 'article' }).kind, 'tool');
});

test('A tweet with a gen-ai label stays a post', () => {
  const r = classify('https://x.com/janedoe/status/1453768926539317251', { labels: ['gen-ai'] });
  eq(r.kind, 'post');
  eq(r.postPlatform, 'x');
});

test('A wishlisted Shopify product stays a product, even with a tool label', () => {
  const html = '<html><head><link rel="preconnect" href="https://cdn.shopify.com"></head><body></body></html>';
  const r = classify('https://stuffcool.com/products/mag-dock', { html, labels: ['wishlist', 'digital-tools'] });
  eq(r.kind, 'product');
  eq(r.productSource, 'page');
});

// JSON-LD reader

test('SoftwareApplication: name, platform, category, paid price, maker', () => {
  const x = buildTool('https://culturedcode.com/things/', { html: jsonLD(softwareAppJSONLD) });
  const m = x.meta;
  eq(m.name, 'Things 3');
  eq(x.title, 'Things 3');
  eq(m.platforms, ['macOS']);
  eq(m.category, 'Productivity');
  eq(m.pricing, 'paid');
  eq(m.price, '49.99');
  eq(m.currency, 'USD');
  eq(m.maker?.name, 'Cultured Code');
  eq(m.subtype, 'app');
});

test('operatingSystem: comma string vs array, normalised and de-duped', () => {
  eq(T.platforms('Mac OS X 10.15, Windows 10, Linux'), ['macOS', 'Windows', 'Linux']);
  eq(T.platforms('OSX; macOS'), ['macOS']);
  eq(T.platforms(['iOS 17.0 or later', 'iPadOS', 'Android', 'Web browser']), ['iOS', 'iPadOS', 'Android', 'Web']);
  eq(T.platforms('Requires iOS 17.0 or later.'), ['iOS']);
  eq(T.platforms(null), []);
  eq(T.normalizePlatform('Any'), null);
});

test('Offers: price 0 → free; AggregateOffer 0…12 → freemium; an array mixes', () => {
  const free = T.offerPricing({ '@type': 'Offer', price: '0', priceCurrency: 'USD' });
  eq(free.pricing, 'free');
  eq(free.price, null);
  eq(T.offerPricing({ '@type': 'Offer', price: 0 }).pricing, 'free');
  const agg = T.offerPricing({ '@type': 'AggregateOffer', lowPrice: '0', highPrice: '12', priceCurrency: 'usd' });
  eq(agg.pricing, 'freemium');
  eq(agg.price, '12');
  eq(agg.currency, 'USD');
  const tiers = T.offerPricing([{ '@type': 'Offer', price: '0' }, { '@type': 'Offer', price: '8', priceCurrency: 'EUR' }, { '@type': 'Offer', price: '16', priceCurrency: 'EUR' }]);
  eq(tiers.pricing, 'freemium');
  eq(tiers.price, '8');
  const paid = T.offerPricing({ '@type': 'Offer', price: '4.99', priceCurrency: 'GBP' });
  eq(paid.pricing, 'paid');
  eq(paid.price, '4.99');
  eq(T.offerPricing(null).pricing, null);
});

test("A free web app from JSON-LD reads 'Web · Free'", () => {
  const html = jsonLD(`{"@context":"https://schema.org","@type":"WebApplication","name":"Excalidraw",
   "operatingSystem":"Web","applicationCategory":"DesignApplication","offers":{"@type":"Offer","price":0}}`);
  const m = buildTool('https://excalidraw.com/', { html }).meta;
  eq(m.pricing, 'free');
  eq(m.category, 'Design');
  eq(m.subtype, 'web app');
  eq(m.platforms, ['Web']);
});

test('applicationCategory cleanup', () => {
  eq(T.cleanCategory('DeveloperApplication'), 'Developer');
  eq(T.cleanCategory('https://schema.org/GameApplication'), 'Game');
  eq(T.cleanCategory('SocialNetworkingApplication'), 'Social Networking');
  eq(T.cleanCategory('Productivity'), 'Productivity');
  eq(T.cleanCategory('Photo & Video'), 'Photo & Video');
  eq(T.cleanCategory(['UtilitiesApplication']), 'Utilities');
  eq(T.cleanCategory('Application'), 'Application');
  eq(T.cleanCategory(null), null);
});

test('og tags: tagline from og:description, else meta description; site name as maker', () => {
  const html = '<html><head>\n<meta property="og:site_name" content="Raycast">\n<meta name="description" content="Your shortcut to everything.">\n</head><body></body></html>';
  const m = buildTool('https://raycast.com/', { html }).meta;
  eq(m.tagline, 'Your shortcut to everything.');
  eq(m.maker?.name, 'Raycast');
  eq(m.subtype, 'web app');
  eq(buildTool('https://raycast.com/', { html, ogDescription: 'A launcher.' }).meta.tagline, 'A launcher.');
  const store = '<html><head><meta property="og:site_name" content="App Store"></head></html>';
  eq(buildTool('https://apps.apple.com/us/app/things-3/id904237743', { html: store }).meta.maker, null);
});

test('App Store: the URL itself, else the first App Store badge link on the page', () => {
  const d = buildTool('https://apps.apple.com/us/app/things-3/id904280696?mt=12').meta;
  eq(d.appStoreURL, 'https://apps.apple.com/us/app/things-3/id904280696?mt=12');
  eq(d.platforms, ['macOS']);
  eq(d.subtype, 'app');
  const html = '<html><body>\n<a href="https://apps.apple.com/us/charts">Charts</a>\n<a class="badge" href="https://apps.apple.com/us/app/halide-mark-ii/id885697368?l=en&amp;x=1">Download</a>\n</body></html>';
  eq(buildTool('https://halide.cam/', { html }).meta.appStoreURL, 'https://apps.apple.com/us/app/halide-mark-ii/id885697368?l=en&x=1');
});

test('Subtypes: extension hosts, Hugging Face models, web app default', () => {
  eq(buildTool('https://chromewebstore.google.com/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm').meta.subtype, 'extension');
  eq(buildTool('https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/').meta.subtype, 'extension');
  eq(buildTool('https://huggingface.co/black-forest-labs/FLUX.1-dev').meta.subtype, 'AI model');
  eq(buildTool('https://huggingface.co/spaces/foo/bar').meta.subtype, 'web app');
  eq(buildTool('https://github.com/BurntSushi/ripgrep').meta.subtype, 'library');
});

// GitHub

test('REST JSON fixture: stars, language, licence, pushed date, topics, owner, homepage', () => {
  const repo = T.parseGitHubRepo(githubRepoJSON, 200);
  const x = buildTool('https://github.com/BurntSushi/ripgrep', {
    ogDescription: 'ripgrep recursively searches... Contribute to BurntSushi/ripgrep development by creating an account on GitHub.', github: repo });
  const m = x.meta;
  eq(m.name, 'BurntSushi/ripgrep');
  eq(x.title, 'BurntSushi/ripgrep');
  eq(m.tagline, 'ripgrep recursively searches directories for a regex pattern');
  eq(m.maker?.name, 'BurntSushi');
  eq(m.stars, 48211);
  eq(m.language, 'Rust');
  eq(m.license, 'Unlicense');
  eq(m.pricing, 'open source');
  eq(m.topics, ['cli', 'search', 'regex']);
  eq(m.homepageURL, 'https://burntsushi.net/ripgrep/');
  eq(m.repoURL, 'https://github.com/BurntSushi/ripgrep');
  eq(m.subtype, 'library');
  eq(m.lastPushedAt, appleDate(new Date('2026-09-30T14:02:11Z')));
});

test("No licence: not 'open source'", () => {
  const m = buildTool('https://github.com/jane/dotfiles', { github: T.parseGitHubRepo(githubNoLicenseJSON, 200) }).meta;
  eq(m.license, null);
  eq(m.pricing, null);
  eq(m.stars, 12);
});

test('Rate limit / errors skip the API; the URL still gives repo, name and owner', () => {
  eq(T.parseGitHubRepo('{"message":"API rate limit exceeded"}', 403), null);
  eq(T.parseGitHubRepo(githubRepoJSON, 429), null);
  eq(T.parseGitHubRepo('not json', 200), null);
  eq(T.parseGitHubRepo(null, null), null);
  const m = buildTool('https://github.com/BurntSushi/ripgrep/issues', {
    ogDescription: 'ripgrep recursively searches directories for a regex pattern - BurntSushi/ripgrep. Contribute to BurntSushi/ripgrep development by creating an account on GitHub.' }).meta;
  eq(m.repoURL, 'https://github.com/BurntSushi/ripgrep');
  eq(m.name, 'BurntSushi/ripgrep');
  eq(m.maker?.name, 'BurntSushi');
  eq(m.tagline, 'ripgrep recursively searches directories for a regex pattern - BurntSushi/ripgrep.');
  eq(T.githubAPIURL(new URL('https://github.com/BurntSushi/ripgrep/issues'))?.toString(), 'https://api.github.com/repos/BurntSushi/ripgrep');
});

test('Licence label: SPDX id, NOASSERTION falls back to the name', () => {
  eq(T.licenseLabel({ spdx_id: 'MIT', name: 'MIT License' }), 'MIT');
  eq(T.licenseLabel({ spdx_id: 'NOASSERTION', name: 'Other' }), 'Other');
  eq(T.licenseLabel(null), null);
});

// Redirects, guess, merge

test("Redirect to another host sets canonicalURL; same host doesn't", () => {
  eq(buildTool('https://old-name.app/', { finalURL: 'https://www.newname.com/home' }).meta.canonicalURL, 'https://www.newname.com/home');
  eq(buildTool('https://raycast.com/', { finalURL: 'https://www.raycast.com/' }).meta.canonicalURL, null);
  eq(buildTool('https://raycast.com/').meta.canonicalURL, null);
});

test('Rule-based guess is conservative; applyGuess fills gaps only and flags them', () => {
  eq(T.ruleBasedFacts('A beautiful note-taking app.'), null);
  eq(T.ruleBasedFacts(null), null);
  eq(T.ruleBasedFacts('Download for Mac. Free plan for individuals, Pro at $8 per month.'), { platforms: ['macOS'], pricing: 'freemium' });
  const empty = T.emptyToolMeta();
  T.applyGuess({ platforms: ['mac', 'Windows 11'], pricing: 'Freemium' }, empty);
  eq(empty.platforms, ['macOS', 'Windows']);
  eq(empty.platformsAreGuess, true);
  eq(empty.pricing, 'freemium');
  eq(empty.pricingIsGuess, true);
  const read = { ...T.emptyToolMeta(), platforms: ['Web'], pricing: 'paid' };
  T.applyGuess({ platforms: ['macOS'], pricing: 'free' }, read);
  eq(read.platforms, ['Web']);
  eq(read.platformsAreGuess, false);
  eq(read.pricing, 'paid');
  eq(read.pricingIsGuess, false);
  const junk = T.emptyToolMeta();
  T.applyGuess({ platforms: [], pricing: 'cheap' }, junk);
  eq(junk.pricing, null);
});

test('A refetch that reads less never erases what capture read', () => {
  const previous = { ...T.emptyToolMeta(), stars: 100, language: 'Swift', topics: ['ios'], platforms: ['iOS'], platformsAreGuess: true };
  const fresh = { ...T.emptyToolMeta(), repoURL: 'https://github.com/a/b' };
  const m = T.merge(fresh, previous);
  eq(m.stars, 100);
  eq(m.language, 'Swift');
  eq(m.topics, ['ios']);
  eq(m.platforms, ['iOS']);
  eq(m.platformsAreGuess, true);
  eq(m.repoURL, 'https://github.com/a/b');
});
