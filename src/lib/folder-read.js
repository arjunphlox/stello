/**
 * Reading Stello items back from the files in a folder (grid part 1, Nov 28 2026).
 *
 * Stello shows only what's in the added folders, and an edit made to a file outside
 * Stello (in a text editor, by a script or an agent) shows up in Stello. Pure functions
 * only (no I/O), shared by the web (`folders.js` loads this as /lib/folder-read.js) and
 * the tests. The Mac twin is `Store/FolderReader.swift`; both are checked against the
 * same fixtures (test/fixtures/folder-read.json, `node scripts/make-folder-read-fixtures.mjs`).
 *
 *   fileEdits(item, text, ctx)   an item Stello has + its file → the fields the file changed
 *                                (sync API names), or null when the file says the same thing
 *   itemFromFile(text, path, ctx) a file whose item Stello doesn't have yet → that item
 *
 * How an edit is found: Stello works out the file it would write for the item it has
 * (folder-write.js `itemFile`, keeping the file's own path and extras) and compares it,
 * field by field, with the file. Only fields that differ are taken from the file, so a
 * file Stello wrote itself never changes anything.
 */
import { itemFile, readCopy, isLibraryId } from './folder-write.js';
import { safeName } from './folder-format.js';
import { nameKey, titleFromTag } from './folder-v2.js';

/** Header key → item field, for the details a person may change in a file. */
const MAP = [
  ['title', 'title'], ['url', 'source_url'], ['kind', 'kind'], ['site', 'domain'],
  ['summary', 'summary'], ['status', 'status'], ['added', 'added_at'], ['review', 'needs_review'],
  ['cover_aspect', 'cover_aspect'], ['meta', 'metadata'], ['snippets', 'snippets'], ['images', 'images'],
];
/** Details Stello keeps up itself; a file is read for them only when the item is new. */
const MACHINE = [['analyzed', 'analyzed_at'], ['opened', 'last_opened_at'], ['open_count', 'open_count'], ['enrichment', 'enrichment_status']];

const empty = (v) => v === null || v === undefined || v === '' || v === false ||
  (Array.isArray(v) && v.length === 0) ||
  (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0);
/** JSON with sorted keys and empty values dropped, so equal data compares equal. */
function stable(v) {
  if (empty(v)) return 'null';
  if (Array.isArray(v)) return `[${v.map(stable).join(',')}]`;
  if (typeof v === 'object') {
    return `{${Object.keys(v).sort().filter((k) => !empty(v[k])).map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v);
}
const same = (a, b) => stable(a) === stable(b);
const parseJson = (v, fallback) => {
  if (v == null) return fallback;
  if (typeof v !== 'string') return v;
  try { return JSON.parse(v); } catch { return fallback; }
};
const trimEnd = (s) => String(s || '').replace(/\s+$/, '');
/** Images as the item holds them: the folder's own copy (`file`) is the file's business. */
const imagesOf = (list) => (Array.isArray(list) ? list : []).map((img) => {
  if (!img || typeof img !== 'object') return img;
  const { file, ...rest } = img;
  return rest;
});
/** A header's title: people files keep it under `name`. */
const titleOf = (h) => (h.title !== undefined ? h.title : h.name);

/** Entity id → its name, from the folder's people/ and places/ files. */
function nameOf(id, entities) {
  const e = (entities || []).find((x) => x.id === id);
  if (e && e.name) return e.name;
  return titleFromTag(String(id || '').replace(/^(person|place)-/, ''));
}
const placeTag = (name) => nameKey(name).replace(/ /g, '-');

/** Tags from a file: its grouped tags plus its places as location tags; `source` kept where known. */
function tagsFrom(header, entities, known = []) {
  const out = [];
  for (const [category, tags] of Object.entries(header.tags || {})) {
    if (category === 'location') continue;
    for (const [tag, weight] of Object.entries(tags || {})) {
      const had = known.find((t) => t.category === category && t.tag === tag);
      const t = { tag, category, weight: typeof weight === 'number' ? weight : 1 };
      if (had && had.source) t.source = had.source;
      out.push(t);
    }
  }
  for (const id of Array.isArray(header.places) ? header.places : []) {
    const tag = placeTag(nameOf(id, entities));
    if (!tag || out.some((t) => t.category === 'location' && t.tag === tag)) continue;
    const had = known.find((t) => t.category === 'location' && placeTag(titleFromTag(t.tag)) === tag);
    out.push(had ? { ...had } : { tag, category: 'location', weight: 1 });
  }
  return out;
}

/**
 * Metadata after a file edit. Some details live as people and places in the file (a type
 * designer, a city), so only keys the file shows are taken from it; the rest stay.
 */
function metaFrom(had, shown, now) {
  const out = had && typeof had === 'object' && !Array.isArray(had) ? { ...had } : {};
  for (const k of Object.keys(shown || {})) delete out[k];
  for (const [k, v] of Object.entries(now && typeof now === 'object' ? now : {})) out[k] = v;
  return Object.keys(out).length ? out : null;
}

/** The author's name from a file's people list (the entry marked author). */
function authorFrom(header, entities) {
  const a = (Array.isArray(header.people) ? header.people : []).find((p) => p && p.role === 'author');
  return a ? nameOf(a.id, entities) : null;
}

/**
 * What a file changed about an item Stello already has.
 *   item  the item (sync API shape) as Stello holds it
 *   text  the file's text
 *   ctx   { path, entities, paths }  (entities as in folder-write.js itemFile)
 * Returns { fields } with only the changed fields (sync API names), or null.
 */
export function fileEdits(item, text, ctx = {}) {
  const copy = readCopy(text);
  if (!copy || String(copy.header.id).toLowerCase() !== String(item.id).toLowerCase()) return null;
  const mine = itemFile(item, {
    entities: ctx.entities || [], paths: new Set(ctx.paths || []),
    existing: { path: ctx.path || 'item.md', header: copy.header, body: copy.body },
  });
  const theirs = copy.header;
  const fields = {};
  for (const [key, field] of MAP) {
    const a = key === 'title' ? titleOf(mine.header) : mine.header[key];
    const b = key === 'title' ? titleOf(theirs) : theirs[key];
    if (key === 'images' ? same(imagesOf(a), imagesOf(b)) : same(a, b)) continue;
    if (key === 'review') fields[field] = b === true;
    else if (key === 'images') fields[field] = imagesOf(b);
    else if (key === 'snippets') fields[field] = Array.isArray(b) ? b : [];
    else if (key === 'meta') fields[field] = metaFrom(parseJson(item.metadata, null), a, b);
    else if (key === 'title') fields[field] = empty(b) ? '' : b;
    else if (key === 'status' || key === 'added') { if (!empty(b)) fields[field] = b; }
    else fields[field] = empty(b) ? null : b;
  }
  if (!same(mine.header.tags, theirs.tags) || !same(mine.header.places, theirs.places)) {
    fields.tags = tagsFrom(theirs, ctx.entities, parseJson(item.tags, []));
  }
  if (!same(mine.header.people, theirs.people)) {
    const author = authorFrom(theirs, ctx.entities);
    if (!same(author, item.author)) fields.author = author;
  }
  if (trimEnd(mine.body).trim() !== trimEnd(copy.body).trim()) fields.body_markdown = trimEnd(copy.body) || null;
  return Object.keys(fields).length ? { fields } : null;
}

/**
 * A file whose item Stello doesn't have yet → that item as a /api/sync/push change
 * ({ id, full: true, fields }), or null when the file isn't a library item.
 * `modified` (ms) stands in for dates the file doesn't give.
 */
export function itemFromFile(text, path, ctx = {}) {
  const copy = readCopy(text);
  if (!copy || !isLibraryId(copy.header.id)) return null;
  const h = copy.header;
  const id = String(h.id).toLowerCase();
  const fields = {};
  for (const [key, field] of [...MAP, ...MACHINE]) {
    const v = key === 'title' ? titleOf(h) : h[key];
    fields[field] = empty(v) ? null : v;
  }
  const stamp = new Date(ctx.modified || Date.now()).toISOString();
  const name = String(path || '').split('/').pop().replace(/\.md$/i, '');
  fields.slug = safeName(name, id);
  fields.title = fields.title || name || 'Untitled';
  fields.added_at = fields.added_at || stamp;
  fields.status = fields.status || 'active';
  // A link with no kind yet waits for the rules that sort it, like any new link.
  fields.enrichment_status = fields.enrichment_status || (fields.source_url && !fields.kind ? 'awaiting_classify' : 'done');
  fields.needs_review = h.review === true;
  fields.open_count = typeof h.open_count === 'number' ? h.open_count : 0;
  fields.images = imagesOf(h.images);
  fields.snippets = Array.isArray(h.snippets) ? h.snippets : [];
  fields.tags = tagsFrom(h, ctx.entities);
  fields.author = authorFrom(h, ctx.entities);
  fields.body_markdown = trimEnd(copy.body) || null;
  return { id, full: true, fields };
}
