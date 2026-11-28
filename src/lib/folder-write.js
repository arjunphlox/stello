/**
 * Writing Stello items into a folder (folder engine plan, section 4b; phase 2, part 2).
 *
 * Pure functions only (no I/O), shared by the web (`folders.js` loads this as
 * /lib/folder-write.js) and the tests. The Mac twin is `Store/FolderWriter.swift`;
 * both are checked against the same fixtures (test/fixtures/folder-write.json).
 *
 *   itemFile(item, ctx)     an item (sync API shape) → its v2 file, plus any new
 *                           people/places files it points at and the images to copy
 *   mergeCopies(a, b)       two copies of one item → one (tags and links combine,
 *                           the newer value wins, both notes kept)
 *   trashPath(path, now)    where a deleted copy goes: .trash/<YYYY-MM-DD>/<path>
 *   trashExpired(dir, now)  true when a .trash/<YYYY-MM-DD> folder is past 30 days
 *   fingerprint(item)       what a write depends on, so opening an item never writes
 */
import { safeName, groupTags, imageExt } from './folder-format.js';
import {
  ITEM_FIELDS, ENTITY_FIELDS, PEOPLE_KINDS, headerToText, parseFile, splitRefs, cleanBody,
  nameKey, coreKey, titleFromTag, itemPathV2, fileName, entityId,
} from './folder-v2.js';

export const TRASH_DIR = '.trash';
export const TRASH_DAYS = 30;

/** Item (sync API shape) field → v2 header key. */
const RENAMES = {
  source_url: 'url', domain: 'site', added_at: 'added', analyzed_at: 'analyzed',
  last_opened_at: 'opened', needs_review: 'review', enrichment_status: 'enrichment', metadata: 'meta',
};
const SCALARS = ['id', 'title', 'source_url', 'kind', 'domain', 'summary', 'status',
  'added_at', 'analyzed_at', 'last_opened_at', 'open_count', 'cover_aspect', 'needs_review',
  'enrichment_status', 'metadata'];
/** Fields left out of the fingerprint: opening an item changes them, and an open is not an edit. */
const NOT_EDITS = new Set(['last_opened_at', 'open_count']);

const empty = (v) => v === null || v === undefined || v === '' ||
  (Array.isArray(v) && v.length === 0) ||
  (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0);
const parseJson = (v, fallback) => {
  if (v == null) return fallback;
  if (typeof v !== 'string') return v;
  try { return JSON.parse(v); } catch { return fallback; }
};
/** JSON with sorted keys, so the same data always gives the same string. */
function stable(v) {
  if (Array.isArray(v)) return `[${v.map(stable).join(',')}]`;
  if (v && typeof v === 'object') return `{${Object.keys(v).sort().filter((k) => v[k] !== undefined).map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(',')}}`;
  return JSON.stringify(v === undefined ? null : v);
}

/** What a folder write depends on. Changes to it (and only it) mean the file needs writing. */
export function fingerprint(item) {
  const out = {};
  for (const f of [...SCALARS, 'slug', 'author', 'body_markdown']) if (!NOT_EDITS.has(f)) out[f] = empty(item[f]) ? null : item[f];
  out.tags = parseJson(item.tags, []).map((t) => [t.category, t.tag, t.weight]);
  out.images = parseJson(item.images, []).map((i) => i && (i.path || i.url));
  out.snippets = parseJson(item.snippets, []).map((s) => (typeof s === 'string' ? s : s && s.text));
  out.metadata = parseJson(item.metadata, null);
  // A short hash keeps the stored map small (one entry per item).
  const s = stable(out);
  let h1 = 0x811c9dc5, h2 = 0x01000193;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 16777619) >>> 0;
    h2 = Math.imul(h2 ^ c, 2246822519) >>> 0;
  }
  return h1.toString(36) + h2.toString(36) + s.length.toString(36);
}

// ── Item → file ─────────────────────────────────────────────────────────────

/** Entity lookup built from a folder's people/ and places/ headers. */
export function entityIndex(entities = []) {
  const people = [], places = [];
  for (const e of entities) (e.type === 'place' || String(e.id).startsWith('place-') ? places : people).push(e);
  const byKey = (list) => {
    const m = new Map();
    for (const e of list) for (const n of [e.name, ...(e.aliases || [])]) { const k = nameKey(n); if (k && !m.has(k)) m.set(k, e); }
    return m;
  };
  const core = new Map();
  for (const e of people) if (e.kind !== 'individual') { const k = coreKey(e.name); if (k && !core.has(k)) core.set(k, e); }
  return { people: byKey(people), core, places: byKey(places) };
}

/**
 * An item (sync API shape) → its v2 file.
 *   ctx.entities  [{ id, name, aliases, kind, type: 'person'|'place', path }] already in the folder
 *   ctx.paths     Set of lowercased paths already used in the folder (new names avoid them)
 *   ctx.existing  { path, header, body } of the item's current file, when it has one
 * Returns {
 *   path, header, body, text,
 *   entities: [{ id, path, header, text }]   new people/places files to write first
 *   media: [{ index, remote, file }]         images to copy in (file = folder-relative path)
 * }
 * An existing file keeps its path, its `sources`, and any image already copied in.
 */
export function itemFile(item, ctx = {}) {
  const ix = ctx.ix || entityIndex(ctx.entities || []);
  const used = ctx.paths || new Set();
  const existing = ctx.existing || null;
  const isPerson = PEOPLE_KINDS.has(item.kind);

  // Path: keep the current one; a new file gets items/<year>/<month>/<slug>.md (people/ for people).
  const unique = (p) => {
    let out = p; let n = 2;
    while (used.has(out.toLowerCase())) out = p.replace(/\.md$/, `-${n++}.md`);
    used.add(out.toLowerCase());
    return out;
  };
  const base = safeName(item.slug, String(item.id || 'item'));
  const path = existing ? existing.path : unique(isPerson
    ? `people/${fileName(item.title || base, base)}.md`
    : itemPathV2(item.added_at, base));
  const up = '../'.repeat(path.split('/').length - 1);
  const mediaName = path.split('/').pop().replace(/\.md$/, '');

  const h = {};
  for (const f of SCALARS) h[RENAMES[f] || f] = item[f];
  h.meta = parseJson(item.metadata, null);
  h.meta = h.meta && typeof h.meta === 'object' ? JSON.parse(JSON.stringify(h.meta)) : null;
  const tags = groupTags(parseJson(item.tags, []).map(({ tag, category, weight }) => ({ tag, category, weight })));
  h.snippets = parseJson(item.snippets, []);

  // People and places become references, matched to the folder's own files.
  const refs = splitRefs({ author: item.author, tags, meta: h.meta });
  const created = [];
  const person = (raw, kind) => {
    const name = String(typeof raw === 'string' ? raw : (raw && raw.name) || '').trim();
    if (!name) return null;
    const parts = name.split(/\s+\/\s+|\s*\(([^)]*)\)\s*/).filter(Boolean);
    for (const p of [name, ...parts]) { const hit = ix.people.get(nameKey(p)); if (hit) return hit; }
    for (const p of [name, ...parts]) { const hit = ix.core.get(coreKey(p)); if (hit && hit.kind !== 'individual') return hit; }
    const first = parts[0] || name;
    const e = { id: entityId('person', first), name: first, kind: (raw && typeof raw === 'object' && raw.kind) || kind || 'individual', aliases: parts.slice(1).filter((a) => nameKey(a) !== nameKey(first)), type: 'person' };
    e.path = unique(`people/${fileName(e.name, e.id)}.md`);
    for (const n of [e.name, ...e.aliases]) ix.people.set(nameKey(n), e);
    if (e.kind !== 'individual') ix.core.set(coreKey(e.name), e);
    created.push(e);
    return e;
  };
  const place = (raw, kind) => {
    const name = titleFromTag(raw);
    const k = nameKey(name);
    if (!k) return null;
    const hit = ix.places.get(k);
    if (hit) return hit;
    const e = { id: entityId('place', name), name, kind, aliases: [], type: 'place' };
    e.path = unique(`places/${fileName(name, e.id)}.md`);
    ix.places.set(k, e);
    created.push(e);
    return e;
  };
  const people = [];
  for (const p of refs.people) {
    const e = person(p.raw, p.kind);
    if (e && e.id !== item.id && !people.some((r) => r.id === e.id && r.role === p.role)) people.push(p.role ? { id: e.id, role: p.role } : { id: e.id });
  }
  const places = [];
  for (const p of refs.places) { const e = place(p.name, p.kind); if (e && !places.includes(e.id)) places.push(e.id); }

  // Images: keep copies already in the folder, plan copies for the rest.
  const prior = (existing && Array.isArray(existing.header.images)) ? existing.header.images : [];
  const media = [];
  const images = parseJson(item.images, []).map((img, i) => {
    if (!img) return img;
    const key = img.path || img.url;
    const had = prior.find((p) => p && (p.path || p.url) === key && p.file);
    if (had) return { file: had.file, ...img };
    if (!img.path) return { ...img };
    const file = `media/${mediaName}/${i + 1}.${imageExt(img.path)}`;
    media.push({ index: i, remote: img.path, file });
    return { file: up + file, ...img };
  });
  const primary = images.findIndex((img) => img && img.is_primary);
  const coverAt = primary >= 0 ? primary : (images.length ? 0 : -1);
  const cover = coverAt >= 0 && images[coverAt] && images[coverAt].file ? images[coverAt].file : null;

  let header = {
    ...h, cover, images, tags, people, places,
    sources: existing && Array.isArray(existing.header.sources) ? existing.header.sources : undefined,
  };
  if (h.meta && !Object.keys(h.meta).length) header.meta = null;
  const body = cleanBody(item.body_markdown, item.summary, h.snippets);
  let fields = ITEM_FIELDS;
  if (isPerson) {
    header = { ...header, name: item.title || base, aliases: existing && existing.header.aliases ? existing.header.aliases : undefined };
    delete header.title; delete header.people; delete header.sources;
    fields = ENTITY_FIELDS;
  }
  const text = headerToText(header, body, fields);
  const entities = created.map((e) => {
    const eh = { id: e.id, name: e.name, kind: e.kind, aliases: e.aliases };
    return { id: e.id, path: e.path, header: eh, text: headerToText(eh, '', ENTITY_FIELDS) };
  });
  return { path, header, body, text, entities, media, fields };
}

// ── Merging two copies ──────────────────────────────────────────────────────

const LISTS = {
  people: (x) => x && `${x.id}|${x.role || ''}`,
  places: (x) => x,
  sources: (x) => x && (x.id || x.url),
  snippets: (x) => String(typeof x === 'string' ? x : (x && x.text) || '').replace(/\s+/g, ' ').trim(),
  images: (x) => x && (x.path || x.url || x.file),
  aliases: (x) => nameKey(x),
};
const union = (a, b, key) => {
  const out = []; const seen = new Set();
  for (const x of [...(Array.isArray(a) ? a : []), ...(Array.isArray(b) ? b : [])]) {
    const k = key(x);
    if (k === null || k === undefined || k === '' || seen.has(k)) continue;
    seen.add(k); out.push(x);
  }
  return out;
};

/**
 * Two copies of one item → one, the way sync conflict copies merge (Arjun, Nov 28 2026):
 * tags and links combine, the newer copy's value wins for other fields, and both notes
 * are kept. `a` is the main copy (its id and file name win); each is { header, body, mtime }.
 */
export function mergeCopies(a, b) {
  const [newer, older] = (b.mtime || 0) > (a.mtime || 0) ? [b, a] : [a, b];
  const header = {};
  const keys = [...new Set([...Object.keys(a.header || {}), ...Object.keys(b.header || {})])];
  for (const k of keys) {
    const x = (newer.header || {})[k], y = (older.header || {})[k];
    if (k === 'tags') {
      const out = {};
      for (const src of [y, x]) for (const [cat, tags] of Object.entries(src || {})) {
        out[cat] = out[cat] || {};
        for (const [t, w] of Object.entries(tags || {})) out[cat][t] = Math.max(out[cat][t] ?? -Infinity, w);
      }
      header.tags = out;
    } else if (LISTS[k]) {
      header[k] = union(x, y, LISTS[k]);
    } else {
      header[k] = empty(x) ? y : x;
    }
  }
  header.id = a.header.id;
  const body = mergeNotes(String(a.body || '').trim(), String(b.body || '').trim());
  return { header, body };
}

/** Both notes kept: one inside the other keeps the longer, else the main note then the other. */
export function mergeNotes(main, other) {
  if (!other || main.includes(other)) return main;
  if (!main || other.includes(main)) return other;
  return `${main}\n\n${other}`;
}

/** Reads a file into { header, body }, or null when it isn't a Stello file. */
export function readCopy(text) {
  try {
    const { header, body } = parseFile(text);
    return header && header.id ? { header, body } : null;
  } catch {
    return null;
  }
}

/** A merged copy → file text (people-kind files keep the entity layout). */
export function copyText({ header, body }) {
  const fields = PEOPLE_KINDS.has(header.kind) || header.name ? ENTITY_FIELDS : ITEM_FIELDS;
  return headerToText(header, body, fields);
}

// ── Trash ───────────────────────────────────────────────────────────────────

const day = (now) => new Date(now).toISOString().slice(0, 10);

/** .trash/<YYYY-MM-DD>/<path>: the day folder makes the 30-day clear-out a folder check. */
export function trashPath(path, now = Date.now()) {
  return `${TRASH_DIR}/${day(now)}/${path}`;
}

/** True when a .trash/<YYYY-MM-DD> day folder is more than 30 days old. */
export function trashExpired(dayName, now = Date.now()) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dayName));
  if (!m) return false;
  const t = Date.UTC(+m[1], +m[2] - 1, +m[3]);
  return now - t > TRASH_DAYS * 86400000;
}

/** Item ids are UUIDs; people/places that exist only as files have person-/place- ids. */
export function isLibraryId(id) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(id || ''));
}
