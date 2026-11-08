// Port of StelloTests/ArticleKindTests.swift (kind-line, SwiftData item, refresh and
// enricher-job tests stay with the Apple app).
import { test } from 'node:test';
import { eq, classify } from './readers-helpers.js';
import * as A from '../src/lib/readers/article.js';
import * as C from '../src/lib/readers/classifier.js';
import { appleDate, extractText } from '../src/lib/readers/html.js';

const jsonLD = (body) => `<html><head><script type="application/ld+json">\n${body}\n</script></head><body></body></html>`;
const metas = (pairs, extraHead = '') => {
  const tags = pairs.map(([k, c]) => `<meta ${k.startsWith('og:') || k.startsWith('article:') ? 'property' : 'name'}="${k}" content="${c}">`).join('\n');
  return `<html><head>\n${tags}\n${extraHead}</head><body></body></html>`;
};
const buildArticle = (url, { finalURL = null, html = '', ogTitle = null, pageText = null } = {}) =>
  A.build({ sourceURL: new URL(url), finalURL: finalURL ? new URL(finalURL) : null, html, ogTitle, pageText });
const utc = (y, m, d, h = 0, min = 0) => new Date(Date.UTC(y, m - 1, d, h, min));
const utcApple = (...a) => appleDate(utc(...a));
const words = (n) => Array(n).fill('word').join(' ');

const simonURL = 'https://simonwillison.net/2025/Mar/11/using-llms-for-code/';
const codropsURL = 'https://tympanus.net/codrops/2025/03/11/building-an-infinite-slider-with-gsap/';
const newsArticleJSONLD = `{"@context":"https://schema.org","@type":"NewsArticle","headline":"Chip shortage eases",
 "author":{"@type":"Person","name":"Jane Reporter","url":"/staff/jane"},
 "publisher":{"@type":"Organization","name":"The Daily Bit"},
 "datePublished":"2025-03-11T09:30:00Z"}`;

// Classification

test('Article-family JSON-LD → article', () => {
  for (const type of ['Article', 'NewsArticle', 'BlogPosting', 'TechArticle', 'Report', 'ScholarlyArticle']) {
    eq(classify('https://example.com/some-story', { html: jsonLD(`{"@context":"https://schema.org","@type":"${type}","headline":"x"}`) }).kind, 'article', type);
  }
  eq(classify('https://news.example.com/chips', { html: jsonLD(newsArticleJSONLD) }).kind, 'article');
});

test('article:published_time meta → article', () => {
  eq(classify('https://example.com/some-story', { html: metas([['article:published_time', '2025-03-11T09:30:00Z']]) }).kind, 'article');
});

test('Dated paths → article', () => {
  eq(classify(simonURL).kind, 'article');
  eq(classify('https://example.com/2020/06/some-slug').kind, 'article');
  eq(classify('https://www.nytimes.com/2024/11/05/technology/ai-chips.html').kind, 'article');
  eq(classify('https://example.com/blog/2019/12/31/year-in-review/').kind, 'article');
  eq(classify('https://example.com/2025/03/').kind, 'link');
  eq(classify('https://example.com/2025/13/slug').kind, 'link');
  eq(classify('https://example.com/2525/03/slug').kind, 'link');
  eq(classify('https://example.com/products/2025/xyz').kind !== 'article', true);
});

test('URL path date parsing: numeric and three-letter months, optional day', () => {
  const mar = C.urlPathDate(new URL(simonURL));
  eq([mar?.year, mar?.month, mar?.day], [2025, 3, 11]);
  const june = C.urlPathDate(new URL('https://example.com/2020/06/some-slug'));
  eq([june?.year, june?.month, june?.day ?? null], [2020, 6, null]);
  eq(C.urlPathDate(new URL('https://example.com/2020/sept/slug')), null);
});

test('A blog / post / news segment followed by a slug → article; the index alone is not', () => {
  for (const url of ['https://example.com/blog/my-first-post', 'https://example.com/en/blog/my-first-post/', 'https://example.com/posts/hello-world',
    'https://example.com/news/launch-day', 'https://example.com/essays/on-taste', 'https://example.com/writing/notes-on-grids', 'https://example.com/articles/css-grid'])
    eq(classify(url).kind, 'article', url);
  for (const url of ['https://example.com/blog/', 'https://example.com/blog', 'https://example.com/blog/page/2', 'https://example.com/blog/tag/design',
    'https://example.com/blog/category/news/', 'https://example.com/blog/feed', 'https://example.com/blogging-tips'])
    eq(classify(url).kind !== 'article', true, url);
});

test('og:type article alone is not an article', () => {
  eq(classify('https://example.com/some-page', { ogType: 'article' }).kind, 'link');
});

test('og:type article + an author or date signal → article', () => {
  const author = metas([['og:type', 'article'], ['author', 'Jane Doe']]);
  for (const html of [author, metas([['article:author', 'https://www.facebook.com/jane']]),
    metas([['twitter:label1', 'Written by'], ['twitter:data1', 'Jane Doe']]), metas([['article:modified_time', '2025-03-12T10:00:00Z']]),
    jsonLD('{"@context":"https://schema.org","@type":"WebPage","datePublished":"2025-03-11"}')]) {
    eq(classify('https://example.com/some-page', { html, ogType: 'article' }).kind, 'article');
  }
  eq(classify('https://example.com/some-page', { html: author }).kind, 'link');
});

test('The news label breaks the og:type-article tie; education never makes an article', () => {
  eq(classify('https://example.com/some-page', { ogType: 'article', labels: ['news'] }).kind, 'article');
  eq(classify('https://example.com/some-page', { ogType: 'article', labels: ['News'] }).kind, 'article');
  eq(classify('https://example.com/some-page', { labels: ['news'] }).kind, 'link');
  eq(classify('https://example.com/some-page', { ogType: 'article', labels: ['education'] }).kind, 'link');
  eq(classify('https://example.com/some-page', { labels: ['education'] }).kind, 'link');
});

test('Medium and Substack posts → article; profiles and home pages are not', () => {
  for (const url of ['https://medium.com/@jane/why-grids-matter-3f2a1b', 'https://medium.com/design-bootcamp/why-grids-matter-3f2a1b',
    'https://jane.medium.com/why-grids-matter-3f2a1b', 'https://jane.substack.com/p/why-grids-matter']) eq(classify(url).kind, 'article', url);
  for (const url of ['https://medium.com/@jane', 'https://medium.com/tag/design/archive', 'https://jane.medium.com/',
    'https://jane.substack.com/', 'https://jane.substack.com/archive']) eq(classify(url).kind !== 'article', true, url);
});

test('A dated Codrops URL → article, and a tutorial', () => {
  eq(classify(codropsURL).kind, 'article');
  eq(C.isCodropsArticle(new URL('https://tympanus.net/codrops/2025/x')), true);
  eq(C.isCodropsArticle(new URL('https://tympanus.net/codrops/category/tutorials/')), false);
  eq(buildArticle(codropsURL, { ogTitle: 'Building an Infinite Slider with GSAP | Codrops' }).isTutorial, true);
});

test('A Framer Marketplace page with og:type article stays a resource', () => {
  eq(classify('https://www.framer.com/marketplace/templates/portfolio-pro/', { html: metas([['og:type', 'article'], ['author', 'Studio Nine']]), ogType: 'article' }).kind, 'resource');
});

test('A course page with og:type article is a course, not an article', () => {
  eq(classify('https://www.domestika.org/en/courses/1234-motion-design-basics', { ogType: 'article' }).kind, 'course');
  eq(classify('https://www.skillshare.com/en/classes/branding-101/123456', { ogType: 'article' }).kind, 'course');
});

test('A gen-ai-labelled blog post → article, not tool', () => {
  eq(classify(simonURL, { html: metas([['og:type', 'article'], ['author', 'Simon Willison']]), ogType: 'article', labels: ['gen-ai'] }).kind, 'article');
  const bp = jsonLD('{"@context":"https://schema.org","@type":"BlogPosting","headline":"LLM tools"}');
  eq(classify('https://example.com/blog/llm-tools', { html: bp, labels: ['gen-ai'] }).kind, 'article');
  eq(classify('https://example.com/notes/llm-tools', { html: bp, labels: ['digital-tools'] }).kind, 'article');
  eq(classify('https://example.com/blog/llm-tools', { labels: ['gen-ai'] }).kind, 'article');
  eq(classify('https://example.com/2025/03/llm-tools', { labels: ['digital-tools'] }).kind, 'article');
  eq(classify('https://raycast.com/', { labels: ['digital-tools'] }).kind, 'tool');
});

test('A tweet stays a post, even with article signals or the news label', () => {
  eq(classify('https://x.com/janedoe/status/1453768926539317251', { html: metas([['article:published_time', '2025-03-11T09:30:00Z']]), ogType: 'article', labels: ['news'] }).kind, 'post');
});

test('A bare image file is never an article', () => {
  eq(classify('https://example.com/2025/03/hero.png').kind !== 'article', true);
});

// Readers

test('NewsArticle JSON-LD: author object with url, publisher, datePublished', () => {
  const m = buildArticle('https://news.example.com/chips', { html: jsonLD(newsArticleJSONLD) });
  eq(m.author?.name, 'Jane Reporter');
  eq(m.author?.url, 'https://news.example.com/staff/jane');
  eq(m.author?.kind, 'individual');
  eq(m.publication, 'The Daily Bit');
  eq(m.publishedAt, utcApple(2025, 3, 11, 9, 30));
});

test('Author shapes: string, object, array → first', () => {
  eq(buildArticle('https://example.com/a', { html: jsonLD('{"@type":"BlogPosting","author":"Jane Doe"}') }).author?.name, 'Jane Doe');
  const o = buildArticle('https://example.com/a', { html: jsonLD('{"@type":"BlogPosting","author":{"@type":"Person","name":"Jane Doe","url":"https://jane.dev"}}') }).author;
  eq([o?.name, o?.url], ['Jane Doe', 'https://jane.dev']);
  eq(buildArticle('https://example.com/a', { html: jsonLD('{"@type":"BlogPosting","author":[{"@type":"Person","name":"First Author"},{"@type":"Person","name":"Second"}]}') }).author?.name, 'First Author');
});

test("Author fallbacks: meta author, article:author (not a URL), twitter 'Written by'", () => {
  const a = (html) => buildArticle('https://example.com/a', { html }).author;
  eq(a(metas([['author', 'Meta Author']]))?.name, 'Meta Author');
  eq(a(metas([['article:author', 'Article Author']]))?.name, 'Article Author');
  eq(a(metas([['article:author', 'https://www.facebook.com/jane']])), null);
  eq(a(metas([['article:author', 'https://www.facebook.com/jane'], ['twitter:label1', 'Written by'], ['twitter:data1', 'Twitter Author']]))?.name, 'Twitter Author');
  eq(a(metas([['twitter:label1', 'Est. reading time'], ['twitter:data1', '6 minutes']])), null);
  const both = jsonLD('{"@type":"Article","author":"JSON Author"}').replace('</head>', '<meta name="author" content="Meta Author"></head>');
  eq(a(both)?.name, 'JSON Author');
});

test('Date precedence: JSON-LD datePublished → article:published_time → URL date', () => {
  const all = jsonLD('{"@type":"Article","datePublished":"2024-01-05"}').replace('</head>', '<meta property="article:published_time" content="2023-02-02T08:00:00+00:00"></head>');
  eq(buildArticle(simonURL, { html: all }).publishedAt, utcApple(2024, 1, 5));
  eq(buildArticle(simonURL, { html: metas([['article:published_time', '2023-02-02T08:00:00+00:00']]) }).publishedAt, utcApple(2023, 2, 2, 8));
  eq(buildArticle(simonURL).publishedAt, utcApple(2025, 3, 11, 12));
  eq(buildArticle('https://example.com/2020/06/some-slug').publishedAt, utcApple(2020, 6, 1, 12));
  eq(buildArticle('https://example.com/blog/no-date').publishedAt, null);
});

test('ISO date variants', () => {
  const t = (s) => A.parseDate(s)?.getTime() ?? null;
  const want = utc(2025, 3, 11, 9, 30).getTime();
  eq(t('2025-03-11T09:30:00Z'), want);
  eq(t('2025-03-11T09:30:00.000Z'), want);
  eq(t('2025-03-11T15:00:00+05:30'), want);
  eq(t('2025-03-11T09:30:00'), want);
  eq(t('2025-03-11'), utc(2025, 3, 11).getTime());
  eq(t('last Tuesday'), null);
  eq(t(null), null);
});

test('Reading minutes: words ÷ 230 rounded up, at least 1, nil without text', () => {
  eq(A.readingMinutes(null), null);
  eq(A.readingMinutes('   '), null);
  eq(A.readingMinutes('one'), 1);
  eq(A.readingMinutes(words(230)), 1);
  eq(A.readingMinutes(words(231)), 2);
  eq(A.readingMinutes(words(1380)), 6);
  eq(buildArticle(simonURL, { pageText: words(1380) }).readingMinutes, 6);
});

test('Full page text counts for reading time (not the 4,000-character AI slice)', () => {
  const body = `<html><body><p>${words(2300)}</p></body></html>`;
  eq(extractText(body).length <= 4000, true);
  eq(A.readingMinutes(extractText(body, null)), 10);
});

test('Publication: og:site_name → JSON-LD publisher → host without www', () => {
  eq(buildArticle(simonURL, { html: metas([['og:site_name', 'Simon Willison’s Weblog']]) }).publication, 'Simon Willison’s Weblog');
  eq(buildArticle('https://www.dailybit.com/a', { html: jsonLD('{"@type":"Article","publisher":{"@type":"Organization","name":"The Daily Bit"}}') }).publication, 'The Daily Bit');
  eq(buildArticle(simonURL).publication, 'simonwillison.net');
  eq(buildArticle('https://www.example.com/blog/x').publication, 'example.com');
});

test("Tutorial flag: Codrops host, /tutorial(s)/ segment, 'How to' / 'Tutorial' titles", () => {
  eq(buildArticle(codropsURL).isTutorial, true);
  eq(buildArticle('https://example.com/tutorials/grid-layout').isTutorial, true);
  eq(buildArticle('https://example.com/blog/tutorial/grid-layout').isTutorial, true);
  eq(buildArticle('https://example.com/blog/x', { ogTitle: 'How to build a grid' }).isTutorial, true);
  eq(buildArticle('https://example.com/blog/x', { ogTitle: 'Tutorial: shaders in SwiftUI' }).isTutorial, true);
  eq(buildArticle('https://example.com/blog/x', { ogTitle: 'Why grids matter' }).isTutorial, false);
  eq(buildArticle('https://example.com/blog/how-to-x', { ogTitle: 'Knowing how to wait' }).isTutorial, false);
});

test('Canonical URL: set when the final URL differs, else nil', () => {
  const short = 'https://jane.substack.com/p/why-grids-matter';
  const landed = 'https://www.janedoe.com/p/why-grids-matter';
  eq(buildArticle(short, { finalURL: landed }).canonicalURL, landed);
  eq(buildArticle(short, { finalURL: short }).canonicalURL, null);
  eq(buildArticle(short).canonicalURL, null);
});

test('Rule-based tech stack: known names as whole words, conservative, max 5', () => {
  eq(A.ruleBasedTechStack('We build the scene in three.js, animate it with GSAP and write a GLSL shader. React is optional.'), ['three.js', 'GSAP', 'React', 'GLSL']);
  eq(A.ruleBasedTechStack('How users react to a swift, rive-like change'), []);
  eq(A.ruleBasedTechStack('Built with SwiftUI, not UIKit.'), ['SwiftUI']);
  eq(A.ruleBasedTechStack('Next.js and Tailwind with Vue.js'), ['Next.js', 'Vue', 'Tailwind']);
  eq(A.ruleBasedTechStack('three.js GSAP React WebGL GLSL CSS Figma Svelte').length, 5);
  eq(A.ruleBasedTechStack(null), []);
});

test('Digest: summary stored as a guess; tech stack only for tutorials, rule-based fallback', () => {
  const essay = A.emptyArticleMeta();
  A.applyDigest({ summary: '  Grids remove decisions.  ', techStack: ['CSS'] }, 'CSS grids', essay);
  eq(essay.summary, 'Grids remove decisions.');
  eq(essay.summaryIsGuess, true);
  eq(essay.techStack, []);
  const tut = { ...A.emptyArticleMeta(), isTutorial: true };
  A.applyDigest(null, 'Animate it with GSAP and a WebGL shader.', tut);
  eq(tut.summary, null);
  eq(tut.summaryIsGuess, false);
  eq(tut.techStack, ['GSAP', 'WebGL']);
  const ms = { ...A.emptyArticleMeta(), isTutorial: true };
  A.applyDigest({ summary: null, techStack: ['Rive', 'rive', ' ', 'Figma'] }, 'GSAP', ms);
  eq(ms.techStack, ['Rive', 'Figma']);
  const kept = { ...A.emptyArticleMeta(), summary: 'Existing.' };
  A.applyDigest({ summary: 'New.' }, null, kept);
  eq(kept.summary, 'Existing.');
  eq(A.needsDigest(kept), false);
});

test('A refetch that reads less never erases what capture read; AI fields are kept', () => {
  const previous = { ...A.emptyArticleMeta(), publication: 'The Daily Bit', author: A.authorRef('Jane'), readingMinutes: 4, summary: 'A summary.', summaryIsGuess: true, techStack: ['CSS'], isTutorial: true };
  const m = A.merge({ ...A.emptyArticleMeta(), readingMinutes: 5 }, previous);
  eq(m.publication, 'The Daily Bit');
  eq(m.author?.name, 'Jane');
  eq(m.readingMinutes, 5);
  eq(m.summary, 'A summary.');
  eq(m.summaryIsGuess, true);
  eq(m.techStack, ['CSS']);
  eq(m.isTutorial, true);
});

test('extractText reads the article / main prose, not the site chrome', () => {
  const prose = Array.from({ length: 80 }, (_, i) => `word${i}`).join(' ');
  const github = `<html><body><header><a>Sign in</a></header><main>
    <div class="repo-head"><span>You must be signed in to change notification settings</span>
    <button>Star</button><nav>Code Issues Pull requests</nav></div>
    <article class="markdown-body"><h1>fd</h1><p>A simple, fast and user-friendly alternative to find. ${prose}</p></article>
    <aside>About Contributions Security policy</aside></main><footer>Terms Privacy</footer></body></html>`;
  const t = extractText(github);
  eq(t.startsWith('fd A simple, fast'), true);
  eq(/signed in|Star|Security policy|Terms/.test(t), false);

  // A tiny <article> (a card on a home page) is not the page's prose: read the body.
  const home = `<body><nav>Menu</nav><article>Short card</article><p>${prose}</p></body>`;
  eq(extractText(home).startsWith('Short card word0'), true);

  // An unclosed <header> never swallows the rest of the page.
  eq(extractText(`<body><header>Top ${prose}</body>`).includes('word79'), true);
});
