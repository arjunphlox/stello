/**
 * Course reader: Course / EducationEvent JSON-LD, og / meta tags, the URL.
 * Port of CourseReader.swift. No extra network.
 */
import { jsonLDTypedNodes, nodeTypes, typeNames as htmlTypeNames, typeIs, metaTagAttributes, appleDate, isDict, toURL, bareHost, wordTokens } from './html.js';
import { isCourseType, isEducationEventType, courseHost, coursePathFormat } from './classifier.js';
import { string, brandName } from './product.js';
import { clean, makerRef as toolMaker, offerPricing } from './tool.js';
import { makerRef, parseCount } from './resource.js';
import { looksLikeURL, authorRef, parseDate } from './article.js';

export const FORMATS = ['self-paced', 'cohort', 'program', 'video series', 'workshop'];
export const MAX_TOPICS = 8;
export const MAX_GUESSED_TOPICS = 5;

export function pageTags(html) {
  const t = { siteName: null, author: null };
  if (!html) return t;
  for (const a of metaTagAttributes(html)) {
    const content = clean(a.content);
    if (!content) continue;
    const key = (a.property ?? a.name ?? '').toLowerCase();
    if (key === 'og:site_name') t.siteName ??= content;
    else if (key === 'author') t.author ??= content;
  }
  return t;
}

export const typeNames = htmlTypeNames;

export function dicts(value) {
  if (isDict(value)) return [value];
  if (Array.isArray(value)) return value.filter(isDict);
  return [];
}

export function strings(value) {
  const s = string(value);
  if (s) return [s];
  if (Array.isArray(value)) return value.map(string).filter(Boolean);
  return [];
}

export function boolValue(value) {
  if (typeof value === 'boolean') return value;
  switch (string(value)?.toLowerCase()) {
    case 'true': return true;
    case 'false': return false;
    default: return null;
  }
}

/** "Shift Nudge" → "shiftnudge" (letters + digits). */
export function normalizedKey(value) {
  return String(value).toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
}

export function cleanName(raw, providerNames) {
  let text = clean(raw);
  if (!text) return null;
  const keys = providerNames.map(normalizedKey).filter((k) => k.length >= 3);
  const bar = text.lastIndexOf(' | ');
  if (bar >= 0) {
    const head = text.slice(0, bar).trim();
    const tail = text.slice(bar + 3);
    if (head && [...tail].length <= 40) text = head;
  }
  for (const sep of [' - ', ' — ', ' – ']) {
    const i = text.lastIndexOf(sep);
    if (i < 0) continue;
    const head = text.slice(0, i).trim();
    const tail = normalizedKey(text.slice(i + sep.length));
    if (!head || tail.length < 3) continue;
    if (keys.some((k) => k === tail || k.includes(tail) || tail.includes(k))) {
      text = head;
      break;
    }
  }
  return clean(text);
}

export const FRIENDLY_HOST_NAMES = {
  'frontendmasters.com': 'Frontend Masters',
  'maven.com': 'Maven',
  'udemy.com': 'Udemy',
  'coursera.org': 'Coursera',
  'domestika.org': 'Domestika',
  'skillshare.com': 'Skillshare',
  'egghead.io': 'egghead',
  'motiondesign.school': 'Motion Design School',
  'university.webflow.com': 'Webflow University',
  'superhi.com': 'SuperHi',
  'designcourse.com': 'DesignCourse',
  'shiftnudge.com': 'Shift Nudge',
  'joshwcomeau.com': 'Josh W. Comeau',
  'thebasics.dev': 'The Basics',
};

export function friendlyHostName(url) {
  const root = courseHost(url);
  return root ? FRIENDLY_HOST_NAMES[root] ?? null : null;
}

export function provider(node, tags, url, base) {
  if (node) {
    const ref = makerRef(node.provider, base);
    if (ref) return ref;
  }
  if (tags.siteName) return toolMaker(tags.siteName);
  const name = friendlyHostName(url) ?? bareHost(url);
  return name ? toolMaker(name) : null;
}

export function instructor(node, instances, tags, base, providerName) {
  const providerKey = providerName ? normalizedKey(providerName) : null;
  const isProvider = (n) => !!providerKey && normalizedKey(n) === providerKey;
  const candidates = [];
  if (node) candidates.push(node.instructor, node.author, node.creator);
  for (const i of instances) candidates.push(i.instructor);
  for (const v of candidates) {
    const ref = makerRef(v, base);
    if (ref && !looksLikeURL(ref.name) && !isProvider(ref.name)) return { ...ref, kind: 'individual' };
  }
  if (tags.author && !looksLikeURL(tags.author) && !isProvider(tags.author)) return authorRef(tags.author);
  return null;
}

export function formatFromCourseMode(value) {
  for (const raw of strings(value)) {
    const lower = raw.toLowerCase();
    const words = new Set(wordTokens(lower));
    if (lower.includes('self-paced') || lower.includes('self paced') || lower.includes('selfpaced')
      || lower.includes('on-demand') || lower.includes('on demand') || words.has('ondemand')
      || words.has('asynchronous') || lower.includes('own pace')) return 'self-paced';
    if (words.has('cohort') || words.has('cohorts') || words.has('live') || words.has('synchronous')) return 'cohort';
  }
  return null;
}

const LESSON_TYPES = ['LearningResource', 'Lesson', 'VideoObject', 'Episode', 'Clip', 'Chapter'];

export function lessons(node) {
  const count = parseCount(node.numberOfLessons);
  if (count != null && count > 0) return count;
  const parts = dicts(node.hasPart);
  if (!parts.length || !parts.every((p) => typeNames(p['@type']).some((t) => typeIs(t, ...LESSON_TYPES)))) return null;
  return parts.length;
}

/** ISO 8601 duration → { minutes } for h/m/s, or { text } when a y/m/w/d part is present. */
export function parseDuration(raw) {
  const value = clean(raw);
  if (!value) return { minutes: null, text: null };
  const upper = value.toUpperCase();
  if (!upper.startsWith('P')) {
    if ([...value].length <= 30 && /\d/.test(value)) return { minutes: null, text: value };
    return { minutes: null, text: null };
  }
  const empty = { minutes: null, text: null };
  const v = {};
  let inTime = false;
  let number = '';
  for (const ch of upper.slice(1)) {
    if (ch === 'T') {
      if (number || inTime) return empty;
      inTime = true;
      continue;
    }
    if (/[0-9]/.test(ch)) { number += ch; continue; }
    if (ch === '.' || ch === ',') { number += '.'; continue; }
    if (!/^\d*\.?\d+$|^\d+\.$/.test(number)) return empty;
    const amount = Number(number);
    number = '';
    const key = (inTime ? 'T' : 'D') + ch;
    const map = { DY: 'years', DM: 'months', DW: 'weeks', DD: 'days', TH: 'hours', TM: 'minutes', TS: 'seconds' };
    if (!map[key]) return empty;
    v[map[key]] = amount;
  }
  if (number) return empty;
  const dateParts = [v.years, v.months, v.weeks, v.days].filter((x) => x != null && x > 0);
  const total = (v.hours ?? 0) * 3600 + (v.minutes ?? 0) * 60 + (v.seconds ?? 0);
  if (!dateParts.length) {
    if (total <= 0) return empty;
    return { minutes: Math.max(1, Math.round(total / 60)), text: null };
  }
  const amountText = (a, one, many) => `${Number.isInteger(a) ? String(a) : a.toFixed(1)} ${a === 1 ? one : many}`;
  const parts = [];
  if (v.years > 0) parts.push(amountText(v.years, 'year', 'years'));
  if (v.months > 0) parts.push(amountText(v.months, 'month', 'months'));
  if (v.weeks > 0) parts.push(amountText(v.weeks, 'week', 'weeks'));
  if (v.days > 0) parts.push(amountText(v.days, 'day', 'days'));
  if (v.hours > 0) parts.push(amountText(v.hours, 'h', 'h'));
  if (v.minutes > 0) parts.push(amountText(v.minutes, 'min', 'min'));
  return { minutes: null, text: parts.join(' ') };
}

export function level(value) {
  let text = brandName(value);
  if (!text) return null;
  if (looksLikeURL(text)) {
    const parts = text.split('/').filter(Boolean);
    if (parts.length) text = parts[parts.length - 1];
  }
  const c = clean(text);
  if (!c) return null;
  return c.charAt(0).toUpperCase() + c.slice(1);
}

export function names(value) {
  const s = string(value);
  if (s) return [s];
  if (isDict(value)) return [string(value.name)].filter(Boolean);
  if (Array.isArray(value)) return value.flatMap(names);
  return [];
}

export function topics(node) {
  let raw = names(node.teaches);
  if (typeof node.keywords === 'string') raw = raw.concat(node.keywords.split(','));
  else raw = raw.concat(names(node.keywords));
  raw = raw.concat(names(node.about));
  return cleanTopics(raw, MAX_TOPICS);
}

export function cleanTopics(values, max) {
  const out = [];
  const seen = new Set();
  for (const v of values) {
    const t = clean(v);
    if (!t || [...t].length > 60) continue;
    if (!seen.has(t.toLowerCase())) { seen.add(t.toLowerCase()); out.push(t); }
    if (out.length === max) break;
  }
  return out;
}

export function startsAt(events, instances, now) {
  let best = null;
  for (const e of [...events, ...instances]) {
    const d = parseDate(string(e.startDate));
    if (d && d >= now && (best == null || d < best)) best = d;
  }
  return best;
}

/** Swift's CourseMeta always encodes these. */
export function emptyCourseMeta() {
  return { formatIsGuess: false, lessonsIsGuess: false, durationIsGuess: false, topics: [], topicsAreGuess: false };
}

export function build({ sourceURL, finalURL = null, html = '', ogTitle = null, now = new Date() }) {
  const source = toURL(sourceURL);
  const final = toURL(finalURL);
  const meta = emptyCourseMeta();
  const base = final ?? source;
  const tags = pageTags(html);
  const nodes = html ? jsonLDTypedNodes(html) : [];
  const courseNode = nodes.find((n) => nodeTypes(n.dict).some(isCourseType))?.dict ?? null;
  const events = nodes.filter((n) => nodeTypes(n.dict).some(isEducationEventType)).map((n) => n.dict);
  const instances = dicts(courseNode?.hasCourseInstance);
  const primary = courseNode ?? events[0] ?? null;

  setIf(meta, 'provider', provider(primary, tags, source, base));
  const providerNames = [meta.provider?.name, tags.siteName, friendlyHostName(source), bareHost(source)].filter(Boolean);
  setIf(meta, 'name', cleanName(string(primary?.name), providerNames) ?? cleanName(ogTitle, providerNames));
  setIf(meta, 'instructor', instructor(primary, instances, tags, base, meta.provider?.name ?? null));

  let mode = formatFromCourseMode(courseNode?.courseMode);
  for (const i of instances) if (mode == null) mode = formatFromCourseMode(i.courseMode);
  setIf(meta, 'format', mode ?? (events.length ? 'cohort' : null) ?? coursePathFormat(source) ?? (final ? coursePathFormat(final) : null));

  if (courseNode) {
    setIf(meta, 'lessons', lessons(courseNode));
    let duration = parseDuration(string(courseNode.timeRequired));
    if (duration.minutes == null && duration.text == null) {
      for (const w of [courseNode.courseWorkload, ...instances.map((i) => i.courseWorkload)]) {
        duration = parseDuration(string(w));
        if (duration.minutes != null || duration.text != null) break;
      }
    }
    setIf(meta, 'durationMinutes', duration.minutes);
    setIf(meta, 'durationText', duration.text);
    setIf(meta, 'level', level(courseNode.educationalLevel));
    meta.topics = topics(courseNode);
  }

  setIf(meta, 'isFree', boolValue(primary?.isAccessibleForFree));
  const offerSources = [primary?.offers, ...instances.map((i) => i.offers), ...events.map((e) => e.offers)];
  for (const src of offerSources) {
    const offers = offerPricing(src);
    if (!offers.pricing) continue;
    if (offers.pricing === 'free') {
      if (meta.isFree == null) meta.isFree = true;
    } else {
      setIf(meta, 'price', offers.price);
      setIf(meta, 'currency', offers.currency);
      if (meta.isFree == null && offers.pricing === 'paid') meta.isFree = false;
    }
    break;
  }

  setIf(meta, 'startsAt', appleDate(startsAt(events, instances, now)));
  if (final && final.href !== source.href) meta.canonicalURL = final.href;
  return { meta, title: meta.name ?? null };
}

// ─── Guess ──────────────────────────────────────────────────────────────

export function needsGuess(m) {
  return (m.format == null || m.formatIsGuess)
    || ((m.durationMinutes == null && m.durationText == null) || m.durationIsGuess)
    || (!m.topics?.length || m.topicsAreGuess);
}

export function normalizeFormat(raw) {
  const lower = clean(raw)?.toLowerCase();
  if (!lower) return null;
  const spaced = lower.replace(/[-_]/g, ' ');
  const words = new Set(wordTokens(spaced));
  if (words.has('workshop') || words.has('workshops')) return 'workshop';
  if (words.has('cohort') || words.has('cohorts') || words.has('live')) return 'cohort';
  if (spaced.includes('self paced') || spaced.includes('on demand') || spaced.includes('own pace') || words.has('asynchronous')) return 'self-paced';
  if (words.has('program') || words.has('programme') || words.has('programs')) return 'program';
  if (words.has('video') || words.has('videos')) return 'video series';
  return null;
}

export function cleanDurationText(raw) {
  const t = clean(raw);
  return t && [...t].length <= 30 && /\d/.test(t) ? t : null;
}

const LESSONS_RE = /\b(\d{1,4})\+?\s+(?:video\s+|bite-sized\s+|in-depth\s+)?lessons\b/i;
const HOURS_RE = /\b(\d{1,3}(?:\.\d)?)\+?\s*(?:hours?|hrs?)\s+of\s+(?:video|content|lessons?|instruction|training|footage)\b/i;

export function ruleBasedFacts(text) {
  const c = clean(text);
  if (!c) return null;
  const lower = c.toLowerCase();
  const words = new Set(wordTokens(lower));
  let format = null;
  if (words.has('cohort') || words.has('cohorts') || lower.includes('live sessions') || lower.includes('live session')) format = 'cohort';
  else if (lower.includes('self-paced') || lower.includes('self paced') || lower.includes('at your own pace')) format = 'self-paced';
  let lessonCount = null;
  const lm = LESSONS_RE.exec(c);
  if (lm && +lm[1] > 0) lessonCount = +lm[1];
  let durationText = null;
  const hm = HOURS_RE.exec(c);
  if (hm) durationText = hm[1] === '1' ? '1 hour' : `${hm[1]} hours`;
  if (format == null && lessonCount == null && durationText == null) return null;
  return { format, durationText, topics: [], lessons: lessonCount };
}

export function applyGuess(facts, m) {
  const format = normalizeFormat(facts.format);
  if (format && (m.format == null || m.formatIsGuess)) { m.format = format; m.formatIsGuess = true; }
  const duration = cleanDurationText(facts.durationText);
  if (duration && m.durationMinutes == null && (m.durationText == null || m.durationIsGuess)) {
    m.durationText = duration;
    m.durationIsGuess = true;
  }
  const t = cleanTopics(facts.topics || [], MAX_GUESSED_TOPICS);
  if (t.length && (!m.topics?.length || m.topicsAreGuess)) { m.topics = t; m.topicsAreGuess = true; }
  if (facts.lessons > 0 && (m.lessons == null || m.lessonsIsGuess)) { m.lessons = facts.lessons; m.lessonsIsGuess = true; }
}

export function merge(fresh, previous) {
  if (!previous) return fresh;
  const m = { ...fresh };
  for (const k of ['name', 'provider', 'instructor', 'level', 'isFree', 'startsAt', 'canonicalURL']) {
    if (m[k] == null && previous[k] != null) m[k] = previous[k];
  }
  if (m.format == null) { setIf(m, 'format', previous.format); m.formatIsGuess = !!previous.formatIsGuess; }
  if (m.lessons == null) { setIf(m, 'lessons', previous.lessons); m.lessonsIsGuess = !!previous.lessonsIsGuess; }
  if (m.durationMinutes == null && m.durationText == null) {
    setIf(m, 'durationMinutes', previous.durationMinutes);
    setIf(m, 'durationText', previous.durationText);
    m.durationIsGuess = !!previous.durationIsGuess;
  }
  if (m.price == null) { setIf(m, 'price', previous.price); setIf(m, 'currency', previous.currency); }
  if (!m.topics?.length) { m.topics = previous.topics ?? []; m.topicsAreGuess = !!previous.topicsAreGuess; }
  return m;
}

function setIf(obj, key, value) {
  if (value != null) obj[key] = value;
}
