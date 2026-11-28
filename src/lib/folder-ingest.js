/**
 * Folder ingest (folder engine plan 4b, part 3): the person's own files in a folder
 * (not Stello item files) turned into items. Pure: no file access, no network.
 * Web: folders.js (served as /lib/folder-ingest.js). Mac twin: Store/FolderIngest.swift,
 * checked against the same expected output (test/fixtures/folder-ingest.json; regenerate
 * with `node scripts/make-folder-ingest-fixtures.mjs`).
 *
 * What each file gives (plan doc, "What the engine takes from it"):
 *   Markdown, plain text   every link; the rest of its line as a note; the headings above it as tags
 *   .webloc, .url          the one link; the file name as its title
 *   CSV                    the URL column, plus title, tags, notes, folder and date columns when found
 *   Bookmarks HTML         every link, with its folders as tags and the saved date
 * Images and PDFs come in the next chunk.
 *
 * Collections are retired, so headings and bookmark folders become subject tags.
 * Nothing here calls AI or reads a page (import speed rule): a new link is a plain link
 * (`awaiting_classify`) that the Mac sorts later, as for any web save.
 *
 *   ingestType(path)                 'markdown' | 'webloc' | 'url' | 'csv' | 'bookmarks' | null
 *   readLinks(path, text, { modified })  [{ url, key, title, note, summary, tags, added }]
 *   linkItemId(key)                  the same UUID on every device for one link (async, SHA-256)
 *   linkChange(link, { id, now })    a /api/sync/push change for a new item
 */
import { normaliseUrl } from './folder-v2.js';

export { normaliseUrl };

export const MAX_FILE_BYTES = 20 * 1024 * 1024;
const TAG_WEIGHT = 0.6;
const MAX_TAGS = 8;

// ── Which files ─────────────────────────────────────────────────────────────

const TYPES = { md: 'markdown', markdown: 'markdown', txt: 'markdown', webloc: 'webloc', url: 'url', csv: 'csv', html: 'bookmarks', htm: 'bookmarks' };

/** The kind of file Stello reads links from, by its name, or null. */
export function ingestType(path) {
  const name = String(path || '').split('/').pop();
  if (!name || name.startsWith('.')) return null;
  const m = /\.([a-z0-9]+)$/i.exec(name);
  return (m && TYPES[m[1].toLowerCase()]) || null;
}

/** Stello's own files in a folder: never read as the person's files. */
export function isStelloPath(path) {
  return /^(stello\.json|export-report\.json|conversion-report\.json)$/i.test(String(path || ''));
}

// ── Small helpers ───────────────────────────────────────────────────────────

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', '#39': "'" };
function decodeEntities(s) {
  return String(s || '').replace(/&(#x[0-9a-f]+|#\d+|[a-z]+\d*);/gi, (all, e) => {
    if (e[0] === '#') {
      const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : all;
    }
    const v = ENTITIES[e.toLowerCase()];
    return v == null ? all : v;
  });
}

const squash = (s) => String(s || '').replace(/\s+/g, ' ').trim();

/** "Type & Lettering" → "type-lettering". */
export function tagSlug(s) {
  return String(s || '')
    .toLowerCase()
    .normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/g, '');
}

function addTags(list, names) {
  for (const n of names) {
    const t = tagSlug(n);
    if (t && !list.includes(t)) list.push(t);
  }
  return list;
}

/** An http(s) link with its trailing punctuation removed, or null. */
function cleanUrl(raw) {
  let u = String(raw || '').trim().replace(/^<|>$/g, '');
  // Trailing punctuation from prose, and a closing bracket with no opening one.
  for (;;) {
    const before = u;
    u = u.replace(/[.,;:!?'"*_~]+$/, '');
    if (u.endsWith(')') && (u.match(/\(/g) || []).length < (u.match(/\)/g) || []).length) u = u.slice(0, -1);
    if (u.endsWith(']') && !u.includes('[')) u = u.slice(0, -1);
    if (u === before) break;
  }
  if (!/^https?:\/\/[^\s/?#]+\.[^\s/?#]/i.test(u)) return null;
  try { new URL(u); } catch { return null; }
  return u;
}

function fileTitle(path) {
  const name = String(path || '').split('/').pop() || '';
  return squash(name.replace(/\.[a-z0-9]+$/i, '').replace(/[_]+/g, ' ')) || null;
}

/** A date from a sheet or bookmark: unix seconds or ms, or any date text. ISO, or null. */
function toISO(v) {
  const s = String(v == null ? '' : v).trim();
  if (!s) return null;
  if (/^\d{9,13}(\.\d+)?$/.test(s)) {
    const n = Number(s);
    const ms = n > 1e11 ? n : n * 1000;
    const d = new Date(ms);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  }
  const t = Date.parse(s);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

/** Links collected from one file, one per link key (first sighting wins, tags combine). */
function collector() {
  const byKey = new Map();
  return {
    add(l) {
      const url = cleanUrl(l.url);
      if (!url) return;
      const key = normaliseUrl(url);
      const old = byKey.get(key);
      if (old) {
        addTags(old.tags, l.tags || []);
        if (!old.title && squash(l.title)) old.title = squash(l.title);
        if (!old.note && squash(l.note)) old.note = squash(l.note);
        return;
      }
      byKey.set(key, {
        url, key,
        title: squash(l.title) || null,
        note: squash(l.note) || null,
        summary: squash(l.summary) || null,
        tags: addTags([], l.tags || []).slice(0, MAX_TAGS),
        added: l.added || null,
      });
    },
    list: () => [...byKey.values()].map((l) => ({ ...l, tags: l.tags.slice(0, MAX_TAGS) })),
  };
}

// ── Markdown and plain text ─────────────────────────────────────────────────

const MD_IMAGE = /!\[[^\]]*\]\([^)]*\)/g;
const MD_LINK = /\[([^\]]*)\]\(\s*<?(https?:\/\/[^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/gi;
const AUTO_LINK = /<(https?:\/\/[^>\s]+)>/gi;
const BARE_URL = /https?:\/\/[^\s<>"'`\[\]{}|\\^]+/gi;

function stripInline(s) {
  return String(s || '')
    .replace(MD_IMAGE, '')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[*_`~]+/g, '')
    .replace(/<[^>]+>/g, '');
}

/** What's left of a line once its links are taken out: the link's note. */
function lineNote(line) {
  let s = String(line)
    .replace(MD_IMAGE, ' ')
    .replace(MD_LINK, ' ')
    .replace(AUTO_LINK, ' ')
    .replace(BARE_URL, ' ')
    .replace(/^\s*(?:>\s*)*/, '')
    .replace(/^\s*(?:[-*+]|\d+[.)])\s+/, '')
    .replace(/^\s*\[[ xX]\]\s+/, '')
    .replace(/[*_`~]+/g, '');
  s = squash(s.replace(/\(\s*\)/g, ' ').replace(/(^|\s)[(\[](?=\s|$)/g, '$1').replace(/(^|\s)[)\]](?=\s|$)/g, '$1'));
  s = s.replace(/^[\s\-–—:|,;·•]+|[\s\-–—:|,;·•(]+$/g, '').trim();
  return s.length >= 3 ? s : null;
}

function readMarkdown(text, added) {
  const out = collector();
  let lines = String(text).replace(/^﻿/, '').split(/\r?\n/);
  // A front-matter block (Obsidian and others) holds no saves.
  if (lines[0] === '---') {
    const end = lines.indexOf('---', 1);
    if (end > 0) lines = lines.slice(end + 1);
  }
  const heads = [];
  let fence = null;
  for (const line of lines) {
    const f = /^\s*(```|~~~)/.exec(line);
    if (f) { fence = fence === f[1] ? null : fence || f[1]; continue; }
    if (fence) continue;
    const h = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
    if (h) {
      const level = h[1].length;
      while (heads.length && heads[heads.length - 1].level >= level) heads.pop();
      const name = squash(stripInline(h[2]));
      if (name) heads.push({ level, name });
      // A link in a heading is still a save.
    }
    if (!/https?:\/\//i.test(line)) continue;
    const tags = heads.slice(-3).map((x) => x.name);
    const note = h ? null : lineNote(line);
    const found = [];
    let rest = line.replace(MD_IMAGE, ' ');
    rest = rest.replace(MD_LINK, (all, label, url) => {
      const title = squash(stripInline(label));
      found.push({ url, title: title && !/^https?:\/\//i.test(title) ? title : null });
      return ' ';
    });
    rest = rest.replace(AUTO_LINK, (all, url) => { found.push({ url }); return ' '; });
    for (const m of rest.match(BARE_URL) || []) found.push({ url: m });
    // Several links on one line share no single note.
    for (const l of found) out.add({ ...l, note: found.length === 1 ? note : null, tags, added });
  }
  return out.list();
}

// ── .webloc and .url ────────────────────────────────────────────────────────

function readWebloc(text, path, added) {
  // XML plists hold the link in <string>; binary plists keep it as plain ASCII bytes.
  const m = /<string>\s*(https?:\/\/[^<\s]+)\s*<\/string>/i.exec(text) || /(https?:\/\/[\x21-\x7e]+)/.exec(text);
  if (!m) return [];
  const out = collector();
  out.add({ url: decodeEntities(m[1]), title: fileTitle(path), added });
  return out.list();
}

function readUrlFile(text, path, added) {
  const m = /^\s*URL\s*=\s*(\S+)\s*$/im.exec(text);
  if (!m) return [];
  const out = collector();
  out.add({ url: m[1], title: fileTitle(path), added });
  return out.list();
}

// ── CSV ─────────────────────────────────────────────────────────────────────

/** RFC 4180 rows: quoted fields, doubled quotes, newlines inside quotes. */
export function parseCSV(text, delim = ',') {
  const s = String(text).replace(/^﻿/, '');
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (quoted) {
      if (c === '"') {
        if (s[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += c;
    } else if (c === '"' && field === '') quoted = true;
    else if (c === delim) { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && s[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== '' || row.length) { row.push(field); if (row.length > 1 || row[0] !== '') rows.push(row); }
  return rows;
}

function delimiterOf(text) {
  const first = String(text).replace(/^﻿/, '').split(/\r?\n/, 1)[0] || '';
  const count = (ch) => first.split(ch).length - 1;
  const best = [[',', count(',')], [';', count(';')], ['\t', count('\t')]].sort((a, b) => b[1] - a[1])[0];
  return best[1] > 0 ? best[0] : ',';
}

const COLS = {
  url: ['url', 'link', 'href', 'source url', 'source_url', 'uri', 'address', 'website', 'web address', 'page url'],
  title: ['title', 'name', 'page title', 'bookmark'],
  note: ['note', 'notes', 'comment', 'comments', 'highlights', 'annotation', 'annotations'],
  summary: ['excerpt', 'description', 'summary'],
  tags: ['tags', 'tag', 'labels', 'label', 'keywords'],
  folder: ['folder', 'collection', 'category', 'list', 'group'],
  date: ['created', 'created_at', 'created at', 'date added', 'added', 'added_at', 'added at', 'time_added', 'saved', 'saved at', 'date', 'timestamp'],
};
const NOT_FOLDERS = new Set(['unsorted', 'uncategorized', 'uncategorised', 'none', 'default']);

function readCSV(text, added) {
  const rows = parseCSV(text, delimiterOf(text));
  if (rows.length < 2) return [];
  const head = rows[0].map((h) => squash(h).toLowerCase());
  const col = (names) => { for (const n of names) { const i = head.indexOf(n); if (i >= 0) return i; } return -1; };
  let url = col(COLS.url);
  if (url < 0) {
    // No named column: the one whose values are mostly links.
    let best = -1, bestShare = 0.5;
    for (let c = 0; c < head.length; c++) {
      const vals = rows.slice(1, 41).map((r) => r[c]).filter((v) => v && v.trim());
      const share = vals.length ? vals.filter((v) => /^\s*https?:\/\//i.test(v)).length / vals.length : 0;
      if (share > bestShare) { best = c; bestShare = share; }
    }
    url = best;
  }
  if (url < 0) return [];
  const at = { title: col(COLS.title), note: col(COLS.note), summary: col(COLS.summary), tags: col(COLS.tags), folder: col(COLS.folder), date: col(COLS.date) };
  const out = collector();
  for (const r of rows.slice(1)) {
    const get = (i) => (i >= 0 && r[i] != null ? String(r[i]) : '');
    const tags = get(at.tags).split(/[,;|]/).map((t) => t.trim()).filter(Boolean);
    const folder = get(at.folder).split('/').map((t) => t.trim()).filter((t) => t && !NOT_FOLDERS.has(t.toLowerCase()));
    out.add({
      url: get(url).trim(),
      title: get(at.title),
      note: get(at.note),
      summary: get(at.summary),
      tags: [...folder, ...tags],
      added: toISO(get(at.date)) || added,
    });
  }
  return out.list();
}

// ── Browser bookmarks (Netscape bookmark file: Chrome, Safari, Firefox, Arc) ─

const ROOT_FOLDERS = new Set(['bookmarks bar', 'bookmarks menu', 'bookmarks toolbar', 'other bookmarks', 'mobile bookmarks',
  'favorites', 'favourites', 'favorites bar', 'bookmarks', 'imported', 'reading list']);

function attr(attrs, name) {
  const m = new RegExp(`\\b${name}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i').exec(attrs);
  return m ? decodeEntities(m[2] ?? m[3] ?? m[4] ?? '') : null;
}

function readBookmarks(text, added) {
  if (!/NETSCAPE-Bookmark-file/i.test(text)) return [];
  const out = collector();
  const stack = [];
  let pending = null;
  let last = null;
  const re = /<h3\b[^>]*>([\s\S]*?)<\/h3>|<dl\b[^>]*>|<\/dl>|<a\b([^>]*)>([\s\S]*?)<\/a>|<dd>([^<]*)/gi;
  let m;
  while ((m = re.exec(text))) {
    const tag = m[0].slice(0, 4).toLowerCase();
    if (m[1] != null) { pending = squash(decodeEntities(m[1].replace(/<[^>]+>/g, ''))); last = null; }
    else if (tag.startsWith('<dl')) { stack.push(pending); pending = null; }
    else if (tag.startsWith('</dl')) { stack.pop(); pending = null; }
    else if (m[2] != null) {
      const folders = stack.filter((f) => f && !ROOT_FOLDERS.has(f.toLowerCase()));
      const own = (attr(m[2], 'tags') || '').split(',').map((t) => t.trim()).filter(Boolean);
      last = {
        url: attr(m[2], 'href'),
        title: squash(decodeEntities(m[3].replace(/<[^>]+>/g, ''))),
        tags: [...folders.slice(-3), ...own],
        added: toISO(attr(m[2], 'add_date')) || added,
      };
      out.add(last);
    } else if (m[4] != null && last) {
      // <DD> right after a link is its description.
      const note = squash(decodeEntities(m[4]));
      if (note) out.add({ ...last, note });
      last = null;
    }
  }
  return out.list();
}

// ── Entry points ────────────────────────────────────────────────────────────

/**
 * Links in one file. `modified` (ms) dates links that carry no date of their own.
 * Returns [{ url, key, title, note, summary, tags: [slug], added: ISO | null }].
 */
export function readLinks(path, text, { modified = null } = {}) {
  const added = modified ? new Date(modified).toISOString() : null;
  switch (ingestType(path)) {
    case 'markdown': return readMarkdown(text, added);
    case 'webloc': return readWebloc(text, path, added);
    case 'url': return readUrlFile(text, path, added);
    case 'csv': return readCSV(text, added);
    case 'bookmarks': return readBookmarks(text, added);
    default: return [];
  }
}

function hex(bytes) { return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join(''); }

/** Link key → UUID (SHA-256, version 8), so every device makes the same id for one link. */
export function idFromDigest(bytes) {
  const b = Array.from(bytes.slice(0, 16));
  b[6] = (b[6] & 0x0f) | 0x80;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = hex(b);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

export async function linkItemId(key) {
  const data = new TextEncoder().encode(`stello-link\n${key}`);
  const subtle = globalThis.crypto && globalThis.crypto.subtle;
  const digest = await subtle.digest('SHA-256', data);
  return idFromDigest(new Uint8Array(digest));
}

/** "Future-facing fonts" → "future-facing-fonts-4c9f18". */
export function linkSlug(title, id) {
  const base = tagSlug(title).slice(0, 60).replace(/-+$/g, '') || 'item';
  return `${base}-${String(id).slice(0, 6)}`;
}

function domainOf(url) {
  try { return new URL(url).hostname.replace(/^www\./, ''); } catch { return null; }
}

/**
 * A new item for a link, as a /api/sync/push change. A plain link waiting for the Mac's
 * rules to sort it (no AI, no page read here). `now` is ISO; `clock` is its epoch ms.
 */
export function linkChange(link, { id, now }) {
  const domain = domainOf(link.url);
  const title = String(link.title || domain || link.url).slice(0, 300);
  return {
    id,
    full: true,
    clock: Date.parse(now),
    fields: {
      slug: linkSlug(title, id),
      title,
      source_url: link.url,
      domain,
      summary: link.summary ? link.summary.slice(0, 300) : null,
      body_markdown: link.note || null,
      status: 'active',
      needs_review: false,
      kind: 'link',
      enrichment_status: 'awaiting_classify',
      added_at: link.added || now,
      tags: link.tags.map((tag) => ({ tag, category: 'subject', weight: TAG_WEIGHT })),
      images: [],
      snippets: [],
      metadata: null,
    },
  };
}
