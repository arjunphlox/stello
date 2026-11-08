// Port of StelloTests/CourseKindTests.swift (kind-line, SwiftData item and refresh tests
// stay with the Apple app).
import { test } from 'node:test';
import { eq, classify } from './readers-helpers.js';
import * as K from '../src/lib/readers/course.js';
import { appleDate } from '../src/lib/readers/html.js';

const jsonLD = (body) => `<html><head><script type="application/ld+json">\n${body}\n</script></head><body></body></html>`;
const metas = (pairs) => `<html><head>\n${pairs.map(([k, c]) => `<meta ${k.startsWith('og:') || k.startsWith('article:') ? 'property' : 'name'}="${k}" content="${c}">`).join('\n')}\n</head><body></body></html>`;
const utc = (y, m, d, h = 0) => new Date(Date.UTC(y, m - 1, d, h));
const buildCourse = (url, { finalURL = null, html = '', ogTitle = null, now = utc(2026, 10, 1) } = {}) =>
  K.build({ sourceURL: new URL(url), finalURL: finalURL ? new URL(finalURL) : null, html, ogTitle, now }).meta;
const dur = (minutes = null, text = null) => ({ minutes, text });

const frontendMastersURL = 'https://frontendmasters.com/courses/complete-react-v9/';
const shiftNudgeURL = 'https://shiftnudge.com/';
const mavenURL = 'https://maven.com/jane-builder/ai-engineering';
const webflowURL = 'https://university.webflow.com/courses/webflow-101';
const frontendMastersJSONLD = `{"@context":"https://schema.org","@type":"Course","name":"Complete Intro to React, v9",
 "description":"Learn React from the ground up.",
 "provider":{"@type":"Organization","name":"Frontend Masters","sameAs":"https://frontendmasters.com"},
 "author":{"@type":"Person","name":"Brian Holt","url":"https://frontendmasters.com/teachers/brian-holt/"},
 "timeRequired":"PT5H","isAccessibleForFree":false,
 "offers":{"@type":"Offer","category":"Subscription","price":"39","priceCurrency":"USD"},
 "hasCourseInstance":{"@type":"CourseInstance","courseMode":"online","courseWorkload":"PT5H"}}`;
const shiftNudgeJSONLD = `{"@context":"https://schema.org","@type":"Course","name":"Shift Nudge",
 "description":"Interface design course.",
 "provider":{"@type":"Organization","name":"Shift Nudge","sameAs":"https://shiftnudge.com"},
 "author":{"@type":"Person","name":"Matt D. Smith"},
 "courseMode":"online","educationalLevel":"beginner","numberOfLessons":234,
 "teaches":["Interface design","Typography","Color","Layout"],
 "isAccessibleForFree":true}`;
const mavenJSONLD = `{"@context":"https://schema.org","@graph":[
 {"@type":"Course","name":"AI Engineering Bootcamp",
  "provider":{"@type":"Organization","name":"Maven","url":"https://maven.com"},
  "instructor":[{"@type":"Person","name":"Jane Builder","url":"https://maven.com/jane-builder"},
                {"@type":"Person","name":"Second Teacher"}],
  "offers":{"@type":"Offer","price":"1500","priceCurrency":"USD"}},
 {"@type":"EducationEvent","name":"AI Engineering Bootcamp — Cohort 4",
  "startDate":"2026-11-03T17:00:00Z","endDate":"2026-12-15T19:00:00Z"}
]}`;
const webflowJSONLD = `{"@context":"https://schema.org","@type":"Course","name":"Webflow 101",
 "provider":{"@type":"Organization","name":"Webflow University","sameAs":"https://university.webflow.com"}}`;

// Classification

test('Course JSON-LD → course (top level and inside @graph)', () => {
  eq(classify('https://example.com/motion-basics', { html: jsonLD('{"@context":"https://schema.org","@type":"Course","name":"Motion basics"}') }).kind, 'course');
  eq(classify('https://example.com/motion-basics', { html: jsonLD('{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},{"@type":"Course","name":"x"}]}') }).kind, 'course');
  eq(classify(mavenURL, { html: jsonLD(mavenJSONLD) }).kind, 'course');
});

test('Frontend Masters: /courses/<slug> → course; blog posts and the home page are not', () => {
  eq(classify(frontendMastersURL).kind, 'course');
  eq(classify('https://frontendmasters.com/blog/react-19-and-the-compiler/').kind, 'article');
  eq(classify('https://frontendmasters.com/').kind !== 'course', true);
  eq(classify('https://frontendmasters.com/courses/').kind !== 'course', true);
});

test('Big multi-purpose hosts need a course path', () => {
  for (const url of ['https://www.udemy.com/course/the-web-developer-bootcamp/', 'https://www.coursera.org/learn/machine-learning',
    'https://www.domestika.org/en/courses/1234-motion-design-basics', 'https://www.skillshare.com/en/classes/branding-101/123456',
    'https://egghead.io/courses/build-a-react-app', webflowURL]) eq(classify(url).kind, 'course', url);
  for (const url of ['https://www.udemy.com/user/jane-doe/', 'https://www.coursera.org/', 'https://www.domestika.org/en/blog/1234-color-theory',
    'https://www.skillshare.com/en/browse/design', 'https://egghead.io/q/react']) eq(classify(url).kind !== 'course', true, url);
});

test('Maven: /<instructor>/<slug> → course; site pages and profiles are not', () => {
  eq(classify(mavenURL).kind, 'course');
  for (const url of ['https://maven.com/jane-builder', 'https://maven.com/blog/how-cohorts-work', 'https://maven.com/categories/engineering'])
    eq(classify(url).kind !== 'course', true, url);
});

test('Single-purpose course sites count on any non-blog path', () => {
  for (const url of ['https://shiftnudge.com/', 'https://www.superhi.com/courses/intro-to-web', 'https://thebasics.dev/', 'https://designcourse.com/ui-ux-fundamentals'])
    eq(classify(url).kind, 'course', url);
  eq(classify('https://shiftnudge.com/blog/designing-with-grids').kind, 'article');
  eq(classify('https://www.joshwcomeau.com/courses/').kind, 'course');
  eq(classify('https://www.joshwcomeau.com/css/center-a-div/').kind !== 'course', true);
});

test('A Motion Design School course page with og:type article → course', () => {
  eq(classify('https://motiondesign.school/products/cinema-4d-basecamp', { html: metas([['og:type', 'article'], ['author', 'Motion Design School']]), ogType: 'article' }).kind, 'course');
});

test("LABASAD master page: education label + 'Master' in the title → course", () => {
  eq(classify('https://www.labasad.com/en/master/master-in-illustration/', { html: metas([['og:type', 'article'], ['author', 'LABASAD']]), ogType: 'article', labels: ['education'], title: 'Master in Illustration | LABASAD' }).kind, 'course');
  eq(classify('https://example.com/mastering-grids', { labels: ['education'], title: 'Mastering grids' }).kind, 'link');
});

test('Course path segments: followed by a slug or last with something before; never on a blog', () => {
  for (const url of ['https://example.com/courses/motion-basics', 'https://example.com/en/course/motion-basics', 'https://example.com/program/ux-design',
    'https://example.com/programs/ux-design', 'https://example.com/design/masterclass', 'https://example.com/bootcamp/frontend', 'https://example.com/events/workshop'])
    eq(classify(url).kind, 'course', url);
  for (const url of ['https://example.com/courses', 'https://example.com/courses/', 'https://example.com/courses/page/2',
    'https://example.com/blog/courses/my-favourites', 'https://example.com/2025/03/workshop/recap', 'https://example.com/courses-i-like'])
    eq(classify(url).kind !== 'course', true, url);
});

test('A /program/ path → course with the program format; /workshop → workshop', () => {
  eq(classify('https://example.com/program/ux-design').kind, 'course');
  eq(buildCourse('https://example.com/program/ux-design').format, 'program');
  eq(buildCourse('https://example.com/events/workshop').format, 'workshop');
  eq(buildCourse('https://example.com/courses/motion-basics').format, null);
});

test('The education label alone never makes a course; on a blog post it stays an article', () => {
  eq(classify('https://example.com/blog/what-i-learned-this-year', { labels: ['education'] }).kind, 'article');
  eq(classify('https://example.com/blog/how-i-learn-design', { labels: ['education'], title: 'How I learn design' }).kind, 'article');
  eq(classify('https://example.com/some-page', { labels: ['education'] }).kind, 'link');
  eq(classify('https://example.com/some-page', { ogType: 'article', labels: ['education'] }).kind, 'link');
});

test('Education label + a course word in the title on a plain page → course', () => {
  for (const title of ['Design Systems Course', 'Figma Masterclass', 'Frontend Bootcamp', 'Type Workshop', 'Motion Academy', 'Learn Rive'])
    eq(classify('https://example.com/design-systems', { labels: ['education'], title }).kind, 'course', title);
  eq(classify('https://example.com/design-systems', { title: 'Design Systems Course' }).kind, 'link');
});

test('A dated URL with Article JSON-LD and no course signal stays an article', () => {
  eq(classify('https://example.com/2025/03/best-figma-courses', { html: jsonLD('{"@context":"https://schema.org","@type":"Article","headline":"The best Figma courses"}'), labels: ['education'], title: 'The best Figma courses' }).kind, 'article');
});

test("An EducationEvent node on a course-ish page → course; on an unrelated page it isn't", () => {
  const html = jsonLD('{"@context":"https://schema.org","@type":"EducationEvent","name":"x","startDate":"2026-11-03"}');
  eq(classify('https://example.com/spring-type', { html, title: 'Spring Type Workshop' }).kind, 'course');
  eq(classify('https://example.com/spring-type', { html, labels: ['education'] }).kind, 'course');
  eq(classify('https://example.com/spring-type', { html }).kind, 'link');
});

test('A course page that also carries a Product node with offers → course, not product', () => {
  const html = jsonLD(`[{"@context":"https://schema.org","@type":"Course","name":"Motion basics"},
   {"@context":"https://schema.org","@type":"Product","name":"Motion basics","offers":{"@type":"Offer","price":"99"}}]`);
  eq(classify('https://example.com/motion-basics', { html }).kind, 'course');
});

test("A course host's GitHub repo stays a tool; a tweet stays a post", () => {
  const html = jsonLD('{"@context":"https://schema.org","@type":"Course","name":"React"}');
  eq(classify('https://github.com/FrontendMasters/complete-intro-to-react', { html }).kind, 'tool');
  eq(classify('https://x.com/FrontendMasters/status/1453768926539317251', { html }).kind, 'post');
  eq(classify('https://x.com/FrontendMasters/status/1453768926539317251', { labels: ['education'], title: 'New course' }).kind, 'post');
});

test('A bare image file is never a course', () => {
  eq(classify('https://example.com/courses/cover.png').kind !== 'course', true);
});

// Readers

test('Frontend Masters: author, offers, timeRequired, isAccessibleForFree, hasCourseInstance', () => {
  const m = buildCourse(frontendMastersURL, { html: jsonLD(frontendMastersJSONLD), ogTitle: 'Complete Intro to React, v9 | Frontend Masters' });
  eq(m.name, 'Complete Intro to React, v9');
  eq(m.provider?.name, 'Frontend Masters');
  eq(m.provider?.url, 'https://frontendmasters.com');
  eq(m.instructor?.name, 'Brian Holt');
  eq(m.instructor?.url, 'https://frontendmasters.com/teachers/brian-holt/');
  eq(m.instructor?.kind, 'individual');
  eq(m.durationMinutes, 300);
  eq(m.durationText, null);
  eq(m.format, null);
  eq(m.isFree, false);
  eq(m.price, '39');
  eq(m.currency, 'USD');
});

test('Shift Nudge: courseMode, educationalLevel, numberOfLessons, teaches, isAccessibleForFree', () => {
  const m = buildCourse(shiftNudgeURL, { html: jsonLD(shiftNudgeJSONLD) });
  eq(m.name, 'Shift Nudge');
  eq(m.provider?.name, 'Shift Nudge');
  eq(m.instructor?.name, 'Matt D. Smith');
  eq(m.format, null);
  eq(m.level, 'Beginner');
  eq(m.lessons, 234);
  eq(m.topics, ['Interface design', 'Typography', 'Color', 'Layout']);
  eq(m.topicsAreGuess, false);
  eq(m.isFree, true);
});

test('Maven: Course + EducationEvent startDate → cohort, the next start date', () => {
  const m = buildCourse(mavenURL, { html: jsonLD(mavenJSONLD) });
  eq(m.name, 'AI Engineering Bootcamp');
  eq(m.provider?.name, 'Maven');
  eq(m.instructor?.name, 'Jane Builder');
  eq(m.instructor?.url, 'https://maven.com/jane-builder');
  eq(m.format, 'cohort');
  eq(m.formatIsGuess, false);
  eq(m.startsAt, appleDate(utc(2026, 11, 3, 17)));
  eq(m.isFree, false);
  eq(m.price, '1500');
  const later = buildCourse(mavenURL, { html: jsonLD(mavenJSONLD), now: utc(2027, 1, 1) });
  eq(later.startsAt, null);
  eq(later.format, 'cohort');
});

test('Webflow University: provider only', () => {
  const m = buildCourse(webflowURL, { html: jsonLD(webflowJSONLD) });
  eq(m.name, 'Webflow 101');
  eq(m.provider?.name, 'Webflow University');
  for (const k of ['instructor', 'format', 'lessons', 'durationMinutes', 'isFree']) eq(m[k], null, k);
  eq(m.topics, []);
});

test('No JSON-LD: og:title cleaned, provider from og:site_name or the known host', () => {
  const fm = buildCourse(frontendMastersURL, { ogTitle: 'Complete Intro to React, v9 | Frontend Masters' });
  eq(fm.name, 'Complete Intro to React, v9');
  eq(fm.provider?.name, 'Frontend Masters');
  const site = buildCourse('https://example.com/courses/motion-basics', { html: metas([['og:site_name', 'Motion Lab'], ['author', 'Jane Doe']]), ogTitle: 'Motion Basics - Motion Lab' });
  eq(site.name, 'Motion Basics');
  eq(site.provider?.name, 'Motion Lab');
  eq(site.instructor?.name, 'Jane Doe');
  eq(buildCourse('https://www.example.com/courses/x').provider?.name, 'example.com');
});

test("Name cleaning: ' | Site' always, ' - Provider' only when it names the provider", () => {
  const names = ['Shift Nudge', 'shiftnudge.com'];
  eq(K.cleanName('Design Systems - Shift Nudge', names), 'Design Systems');
  eq(K.cleanName('Design Systems — Shift Nudge', names), 'Design Systems');
  eq(K.cleanName('Shift Nudge - Interface Design Course', names), 'Shift Nudge - Interface Design Course');
  eq(K.cleanName('The Web Developer Bootcamp | Udemy', ['udemy.com']), 'The Web Developer Bootcamp');
  eq(K.cleanName('  ', names), null);
});

test('Instructor: never the provider itself; meta author fallback', () => {
  eq(buildCourse(shiftNudgeURL, { html: jsonLD('{"@type":"Course","name":"x","provider":{"@type":"Organization","name":"Shift Nudge"},"author":{"@type":"Organization","name":"Shift Nudge"}}') }).instructor, null);
  eq(buildCourse('https://example.com/courses/x', { html: jsonLD('{"@type":"Course","name":"x","hasCourseInstance":[{"@type":"CourseInstance","instructor":{"@type":"Person","name":"Ada"}}]}') }).instructor?.name, 'Ada');
});

test("Format from courseMode words; online / onsite / blended aren't formats", () => {
  eq(K.formatFromCourseMode('Self-paced'), 'self-paced');
  eq(K.formatFromCourseMode('on demand'), 'self-paced');
  eq(K.formatFromCourseMode(['online', 'Cohort-based']), 'cohort');
  eq(K.formatFromCourseMode('Live online'), 'cohort');
  eq(K.formatFromCourseMode('asynchronous'), 'self-paced');
  eq(K.formatFromCourseMode('synchronous'), 'cohort');
  for (const mode of ['online', 'Onsite', 'blended', 'https://schema.org/Online']) eq(K.formatFromCourseMode(mode), null, mode);
  eq(buildCourse('https://example.com/courses/x', { html: jsonLD('{"@type":"Course","name":"x","hasCourseInstance":{"@type":"CourseInstance","courseMode":"Self-paced"}}') }).format, 'self-paced');
});

test('Lessons: numberOfLessons, else lesson-typed hasPart items', () => {
  const b = (j) => buildCourse('https://example.com/courses/x', { html: jsonLD(j) }).lessons;
  eq(b('{"@type":"Course","name":"x","hasPart":[{"@type":"LearningResource","name":"1"},{"@type":"VideoObject","name":"2"},{"@type":"LearningResource","name":"3"}]}'), 3);
  eq(b('{"@type":"Course","name":"x","hasPart":[{"@type":"Course","name":"Module 1"}]}'), null);
  eq(b('{"@type":"Course","name":"x","numberOfLessons":"42"}'), 42);
});

test('Level and topics shapes: DefinedTerm, keywords string / array, about', () => {
  const m = buildCourse('https://example.com/courses/x', { html: jsonLD(`{"@type":"Course","name":"x",
   "educationalLevel":{"@type":"DefinedTerm","name":"intermediate"},
   "teaches":[{"@type":"DefinedTerm","name":"Rive"},"State machines"],
   "keywords":"motion, Rive , interaction",
   "about":[{"@type":"Thing","name":"Animation"}]}`) });
  eq(m.level, 'Intermediate');
  eq(m.topics, ['Rive', 'State machines', 'motion', 'interaction', 'Animation']);
  eq(buildCourse('https://example.com/courses/x', { html: jsonLD('{"@type":"Course","name":"x","keywords":["a11y","CSS"]}') }).topics, ['a11y', 'CSS']);
});

test('ISO 8601 durations: minutes for H/M/S, text for D/W/M/Y', () => {
  eq(K.parseDuration('PT5H30M'), dur(330));
  eq(K.parseDuration('PT45M'), dur(45));
  eq(K.parseDuration('PT5H'), dur(300));
  eq(K.parseDuration('pt1h30m15s'), dur(90));
  eq(K.parseDuration('PT90S'), dur(2));
  eq(K.parseDuration('PT2.5H'), dur(150));
  eq(K.parseDuration('P2W'), dur(null, '2 weeks'));
  eq(K.parseDuration('P1W'), dur(null, '1 week'));
  eq(K.parseDuration('P3D'), dur(null, '3 days'));
  eq(K.parseDuration('P1DT2H'), dur(null, '1 day 2 h'));
  eq(K.parseDuration('P1.5W'), dur(null, '1.5 weeks'));
  eq(K.parseDuration('P6M'), dur(null, '6 months'));
  eq(K.parseDuration('5 hours'), dur(null, '5 hours'));
  for (const bad of ['PT0S', 'P', 'PT', 'PT5X', 'P5', 'nonsense', '']) eq(K.parseDuration(bad), dur(), bad);
  eq(K.parseDuration(null), dur());
  const m = buildCourse('https://example.com/courses/x', { html: jsonLD('{"@type":"Course","name":"x","timeRequired":"P6W"}') });
  eq(m.durationMinutes, null);
  eq(m.durationText, '6 weeks');
});

test('Canonical URL: set when the final URL differs, else nil', () => {
  const landed = 'https://frontendmasters.com/courses/complete-react-v9/?utm=x';
  eq(buildCourse(frontendMastersURL, { finalURL: landed }).canonicalURL, landed);
  eq(buildCourse(frontendMastersURL, { finalURL: frontendMastersURL }).canonicalURL, null);
});

test("Rule-based guess: cohort / self-paced words, 'N lessons', 'N hours of video'", () => {
  eq(K.ruleBasedFacts('Join the next cohort with weekly live sessions. 24 video lessons and 6 hours of video.'), { format: 'cohort', durationText: '6 hours', topics: [], lessons: 24 });
  eq(K.ruleBasedFacts('Learn at your own pace. 1 hour of content.'), { format: 'self-paced', durationText: '1 hour', topics: [], lessons: null });
  eq(K.ruleBasedFacts('A beautiful course about type.'), null);
  eq(K.ruleBasedFacts(null), null);
});

test('Guess fills only empty fields and marks them; read values win', () => {
  const m = { ...K.emptyCourseMeta(), lessons: 12 };
  K.applyGuess({ format: 'Cohort-based', durationText: '6 weeks', topics: ['Figma', 'figma', 'Variables'], lessons: 30 }, m);
  eq(m.format, 'cohort');
  eq(m.formatIsGuess, true);
  eq(m.durationText, '6 weeks');
  eq(m.durationIsGuess, true);
  eq(m.topics, ['Figma', 'Variables']);
  eq(m.topicsAreGuess, true);
  eq(m.lessons, 12);
  eq(m.lessonsIsGuess ?? false, false);
  const read = { ...K.emptyCourseMeta(), format: 'self-paced', durationMinutes: 300, topics: ['React'] };
  K.applyGuess({ format: 'cohort', durationText: '6 weeks', topics: ['Vue'] }, read);
  eq(read.format, 'self-paced');
  eq(read.formatIsGuess ?? false, false);
  eq(read.durationText, null);
  eq(read.topics, ['React']);
  eq(K.needsGuess(read), false);
  eq(K.normalizeFormat('On-demand video course'), 'self-paced');
  eq(K.normalizeFormat('Live workshop'), 'workshop');
  eq(K.normalizeFormat('Certificate programme'), 'program');
  eq(K.normalizeFormat('video series'), 'video series');
  eq(K.normalizeFormat('online'), null);
});

test('A refetch that reads less never erases what capture read; guesses survive', () => {
  const previous = { ...K.emptyCourseMeta(), provider: { name: 'Maven', kind: 'maker' }, format: 'cohort', formatIsGuess: true, topics: ['Figma'], topicsAreGuess: true, durationMinutes: 300 };
  const m = K.merge({ ...K.emptyCourseMeta(), lessons: 10 }, previous);
  eq(m.provider?.name, 'Maven');
  eq(m.format, 'cohort');
  eq(m.formatIsGuess, true);
  eq(m.topics, ['Figma']);
  eq(m.topicsAreGuess, true);
  eq(m.durationMinutes, 300);
  eq(m.lessons, 10);
});
