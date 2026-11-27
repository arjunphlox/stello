/**
 * The Stello folder format, version 2. Plan: docs/plans/folder-engine.md ("Format v2").
 *
 *   items/<YYYY>/<MM>/<name>.md     one file per saved thing (link, tool, post, typeface…)
 *   people/<name>.md                people and organisations (individual, studio, foundry, brand, maker)
 *   places/<name>.md                places (countries, cities)
 *   collections/<name>.md           collections
 *   media/<name>/<n>.<ext>          images Stello downloaded (unchanged from v1)
 *   projects/<id>.canvas            canvases (JSON Canvas)
 *   stello.json                     { format, version: 2, counts }
 *
 * Nothing is stored twice. Items point at people, places and collections by id
 * (`people:`, `places:`, `collections:`); only the item records the link, and the
 * app's index builds the reverse view. Ids never change, so files can be renamed
 * or moved. The header layout is v1's (one JSON value per line), plus those lists.
 *
 * Pure functions only (no I/O).
 */
import { safeName, groupTags, ungroupTags, parseItemFile } from './folder-format.js';

export const FORMAT_VERSION_2 = 2;

/** Item kinds that are people or organisations, so they become people/ files. */
export const PEOPLE_KINDS = new Set(['individual', 'studio', 'foundry']);

const ITEM_FIELDS = [
  'id', 'title', 'url', 'kind', 'site', 'summary', 'status',
  'added', 'analyzed', 'opened', 'open_count', 'cover', 'cover_aspect',
  'review', 'enrichment', 'people', 'places', 'collections', 'sources',
  'tags', 'meta', 'snippets', 'images',
];
const ENTITY_FIELDS = [
  'id', 'name', 'kind', 'aliases', 'url', 'summary', 'status', 'added', 'analyzed', 'opened',
  'open_count', 'cover', 'cover_aspect', 'review', 'enrichment', 'places', 'collections',
  'tags', 'meta', 'snippets', 'images',
];
/** Header keys written one entry per line. */
const LIST_KEYS = new Set(['images', 'snippets', 'people', 'sources']);
/** Header keys written as nested `  key: value` lines. */
const NESTED_KEYS = new Set(['tags']);

const empty = (v) => v === null || v === undefined || v === '' ||
  (Array.isArray(v) && v.length === 0) ||
  (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0);

// ── Names, keys, urls ───────────────────────────────────────────────────────

/** Match key for a name: lowercase, no accents, no punctuation, single spaces. */
export function nameKey(name) {
  return String(name || '').normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().replace(/[@'’"]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
}

/** Display name from a tag value: "south-korea" → "South Korea", "usa" → "USA". */
export function titleFromTag(tag) {
  const t = String(tag || '').trim();
  if (/^[a-z]{2,3}$/.test(t) && ['usa', 'uk', 'uae'].includes(t)) return t.toUpperCase();
  return t.split(/[-_\s]+/).filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(' ');
}

/** Normalised url for dedupe: lowercase host, no www., no hash, no tracking params, no trailing slash. */
export function normaliseUrl(url) {
  if (!url) return '';
  let u;
  try { u = new URL(String(url).trim()); } catch { return String(url).trim().toLowerCase(); }
  u.hash = '';
  u.hostname = u.hostname.toLowerCase().replace(/^www\./, '');
  for (const k of [...u.searchParams.keys()]) {
    if (/^utm_/i.test(k) || ['fbclid', 'gclid', 'mc_cid', 'mc_eid', 'ref', 'ref_src'].includes(k.toLowerCase())) u.searchParams.delete(k);
  }
  let s = `${u.protocol}//${u.host}${u.pathname.replace(/\/+$/, '')}${u.search}`;
  if (u.protocol === 'http:') s = 'https:' + s.slice(5);
  return s;
}

const entityId = (type, name) => `${type}-${safeName(nameKey(name).replace(/ /g, '-'), 'x')}`;

/** items/<YYYY>/<MM>/<name>.md from the item's added date. */
export function itemPathV2(added, name) {
  const m = /^(\d{4})-(\d{2})/.exec(String(added || ''));
  return m ? `items/${m[1]}/${m[2]}/${name}.md` : `items/undated/${name}.md`;
}

// ── Body cleanup (no duplicates) ────────────────────────────────────────────

const snippetText = (s) => String(typeof s === 'string' ? s : (s && s.text) || '').trim();
const squash = (s) => String(s || '').replace(/\s+/g, ' ').trim();

/**
 * Remove the parts of a body that only repeat the header: a "## Summary" section
 * equal to the summary, and a "## Key Snippets" section whose quotes are all
 * header snippets. Everything else (the user's notes) stays as written.
 */
export function cleanBody(body, summary, snippets) {
  const src = String(body || '');
  if (!src.trim()) return '';
  const known = new Set((snippets || []).map((s) => squash(snippetText(s))).filter(Boolean));
  const parts = src.split(/(?=^## )/m);
  const kept = parts.filter((part) => {
    const m = /^## ([^\n]*)\n?([\s\S]*)$/.exec(part);
    if (!m) return true;
    const title = m[1].trim().toLowerCase();
    const text = m[2].trim();
    if (title === 'summary') return !(text === '' || squash(text) === squash(summary));
    if (title === 'key snippets' || title === 'key passages') {
      const quotes = text.split(/\n+/).map((l) => l.replace(/^>\s?/, '').trim()).filter(Boolean);
      return !quotes.every((q) => known.has(squash(q)));
    }
    return true;
  });
  return kept.join('').trim();
}

// ── Writing and reading v2 files ────────────────────────────────────────────

/** Header object → file text. `fields` gives the order; empty values are left out. */
export function headerToText(h, body, fields = ITEM_FIELDS) {
  const lines = ['---'];
  const order = [...fields, ...Object.keys(h).filter((k) => !fields.includes(k))];
  for (const key of order) {
    const v = h[key];
    if (empty(v) || (key === 'review' && v === false)) continue;
    if (NESTED_KEYS.has(key) && typeof v === 'object' && !Array.isArray(v)) {
      lines.push(`${key}:`);
      for (const [k, val] of Object.entries(v)) lines.push(`  ${k}: ${JSON.stringify(val)}`);
    } else if (LIST_KEYS.has(key) && Array.isArray(v)) {
      lines.push(`${key}:`);
      for (const entry of v) lines.push(`  - ${JSON.stringify(entry)}`);
    } else {
      lines.push(`${key}: ${JSON.stringify(v)}`);
    }
  }
  lines.push('---', '');
  const b = String(body || '').replace(/\s+$/, '');
  return lines.join('\n') + (b ? b + '\n' : '');
}

/** File text → { header, body } (same reader as v1). */
export const parseFile = parseItemFile;

/** Rebase a media path written relative to one file so it is relative to another depth. */
function rebase(file, fromDepth, toDepth) {
  if (!file) return file;
  const up = '../'.repeat(fromDepth);
  const rest = String(file).startsWith(up) ? String(file).slice(up.length) : String(file);
  return '../'.repeat(toDepth) + rest;
}
const depthOf = (path) => String(path).split('/').length - 1;

// ── The one-time v1 → v2 conversion ─────────────────────────────────────────

/**
 * Convert a v1 folder's item files to v2.
 *   files: [{ path: 'items/2026/x.md', text }]
 * Returns { items, people, places, collections, moves, report } where each of
 * items/people/places/collections is [{ id, path, text, header, body }] and
 * moves maps old item path → new path (for canvases).
 */
export function convertV1(files) {
  const report = {
    items: 0, people: 0, places: 0, collections: 0,
    merged_urls: 0, bodies_cleared: 0, bodies_trimmed: 0,
    people_from_items: 0, refs: { people: 0, places: 0, collections: 0 },
    challenge_titles: [],
  };
  const parsed = files.map(({ path, text }) => ({ path, ...parseFile(text) }));

  // 1. Entities. People first from people-kind items (they keep their own ids).
  const people = new Map(); // nameKey → entity
  const places = new Map();
  const collections = new Map();
  const aliasIndex = new Map(); // nameKey → people entity
  const addPersonKey = (e, name) => { const k = nameKey(name); if (k && !aliasIndex.has(k)) aliasIndex.set(k, e); };

  for (const f of parsed) {
    const h = f.header;
    if (!PEOPLE_KINDS.has(h.kind)) continue;
    const name = h.title || h.id;
    const e = { id: h.id, name, kind: h.kind, aliases: [], header: h, body: f.body, from: f.path };
    people.set(nameKey(name), e);
    addPersonKey(e, name);
    report.people_from_items++;
  }

  const personRef = (raw, fallbackKind) => {
    const name = typeof raw === 'string' ? raw : raw && raw.name;
    if (!name || !String(name).trim()) return null;
    const clean = String(name).trim();
    // "shakthiharinv / shaktype" → try each part as an alias of a known person.
    const parts = clean.split(/\s+\/\s+|\s*\(([^)]*)\)\s*/).filter(Boolean);
    for (const p of [clean, ...parts]) { const hit = aliasIndex.get(nameKey(p)); if (hit) return hit; }
    const kind = (raw && typeof raw === 'object' && raw.kind) || fallbackKind || 'individual';
    const e = { id: entityId('person', parts[0] || clean), name: parts[0] || clean, kind, aliases: parts.slice(1).filter((a) => nameKey(a) !== nameKey(parts[0])) };
    people.set(nameKey(e.name), e);
    addPersonKey(e, e.name);
    e.aliases.forEach((a) => addPersonKey(e, a));
    return e;
  };
  const placeRef = (raw, kind = 'place') => {
    const name = typeof raw === 'string' ? titleFromTag(raw) : raw && (raw.name ? titleFromTag(raw.name) : null);
    if (!name) return null;
    const k = nameKey(name);
    if (!places.has(k)) places.set(k, { id: entityId('place', name), name, kind, aliases: [] });
    return places.get(k);
  };
  const collectionRef = (tag) => {
    const name = titleFromTag(tag);
    const k = nameKey(name);
    if (!k) return null;
    if (!collections.has(k)) collections.set(k, { id: entityId('collection', name), name, kind: 'collection', aliases: [], tag });
    return collections.get(k);
  };

  // 2. Items and people-kind records: move references out of tags/meta into id lists.
  const records = [];
  for (const f of parsed) {
    const h = { ...f.header };
    const isPerson = PEOPLE_KINDS.has(h.kind);
    const tags = { ...(h.tags || {}) };
    const meta = h.meta && typeof h.meta === 'object' ? { ...h.meta } : null;
    const peopleRefs = [];
    const placeIds = [];
    const collectionIds = [];
    const addPerson = (e, role) => {
      if (!e || e.id === h.id) return;
      if (!peopleRefs.some((r) => r.id === e.id && r.role === role)) peopleRefs.push(role ? { id: e.id, role } : { id: e.id });
    };
    const addPlace = (e) => { if (e && !placeIds.includes(e.id)) placeIds.push(e.id); };

    // Collections (Vancouver is a place used as a collection; it stays a collection).
    for (const tag of Object.keys(tags.collection || {})) { const c = collectionRef(tag); if (c && !collectionIds.includes(c.id)) collectionIds.push(c.id); }
    delete tags.collection;
    // Country tags → places.
    for (const tag of Object.keys(tags.location || {})) addPlace(placeRef(tag, 'country'));
    delete tags.location;

    // Header author → people.
    if (h.author) addPerson(personRef(h.author), 'author');
    delete h.author;

    if (meta) {
      for (const key of ['location', 'geography']) {
        const v = meta[key];
        const list = Array.isArray(v) ? v : [v];
        if (v && list.every((x) => typeof x === 'string' || (x && typeof x === 'object' && x.name))) {
          list.forEach((x) => addPlace(placeRef(x)));
          delete meta[key];
        }
      }
      for (const [key, role] of [['author', 'author'], ['maker', 'maker'], ['brand', 'brand']]) {
        const v = meta[key];
        if (v && (typeof v === 'string' || v.name)) { addPerson(personRef(v, key === 'brand' ? 'brand' : 'individual'), role); delete meta[key]; }
      }
      for (const [key, role, kind] of [['typeDesigner', 'designer', 'individual'], ['typeFoundry', 'foundry', 'foundry']]) {
        const v = meta[key];
        const list = (Array.isArray(v) ? v : [v]).filter((x) => typeof x === 'string' ? x.trim() : x && x.name);
        if (v && list.length && list.length === (Array.isArray(v) ? v.length : 1)) {
          list.forEach((x) => addPerson(personRef(x, kind), role));
          delete meta[key];
        }
      }
    }

    if (/^(just a moment|attention required|access denied)/i.test(String(h.title || ''))) report.challenge_titles.push(h.id);
    records.push({ f, h, isPerson, tags, meta, peopleRefs, placeIds, collectionIds });
  }

  // 3. One item per URL (none today, but the rule holds for later imports).
  const byUrl = new Map();
  const kept = [];
  for (const r of records) {
    const key = !r.isPerson && normaliseUrl(r.h.url);
    const first = key && byUrl.get(key);
    if (!first) { if (key) byUrl.set(key, r); kept.push(r); continue; }
    report.merged_urls++;
    const [older, newer] = String(first.h.added || '') <= String(r.h.added || '') ? [first, r] : [r, first];
    for (const [cat, tags] of Object.entries(newer.tags)) {
      older.tags[cat] = older.tags[cat] || {};
      for (const [t, w] of Object.entries(tags)) older.tags[cat][t] = Math.max(older.tags[cat][t] || 0, w);
    }
    for (const p of newer.peopleRefs) if (!older.peopleRefs.some((x) => x.id === p.id)) older.peopleRefs.push(p);
    for (const id of newer.placeIds) if (!older.placeIds.includes(id)) older.placeIds.push(id);
    for (const id of newer.collectionIds) if (!older.collectionIds.includes(id)) older.collectionIds.push(id);
    // Keep everything the repeat brought: its own text goes into its sources entry,
    // its snippets, images and notes join the older item's.
    const src = { id: newer.h.id, url: newer.h.url, added: newer.h.added };
    if (newer.h.title && newer.h.title !== older.h.title) src.title = newer.h.title;
    if (newer.h.summary && newer.h.summary !== older.h.summary) src.summary = newer.h.summary;
    older.sources = [...(older.sources || []), src];
    const seenSnip = new Set((older.h.snippets || []).map((x) => squash(snippetText(x))));
    for (const x of newer.h.snippets || []) if (!seenSnip.has(squash(snippetText(x)))) (older.h.snippets ||= []).push(x);
    const seenImg = new Set((older.h.images || []).map((x) => x && x.path));
    for (const x of newer.h.images || []) if (x && !seenImg.has(x.path)) (older.h.images ||= []).push(x);
    const notes = cleanBody(newer.f.body, newer.h.summary, newer.h.snippets);
    if (notes && !String(older.f.body || '').includes(notes)) older.f = { ...older.f, body: `${String(older.f.body || '').trim()}\n\n${notes}`.trim() };
    older.mergedFrom = [...(older.mergedFrom || []), newer.f.path];
    if (older !== first) { kept[kept.indexOf(first)] = older; byUrl.set(key, older); }
  }

  // 4. File names and text.
  const used = new Set();
  const unique = (p) => {
    let out = p; let n = 2;
    while (used.has(out.toLowerCase())) out = p.replace(/\.md$/, `-${n++}.md`);
    used.add(out.toLowerCase());
    return out;
  };
  const moves = {};
  const items = [];
  const peopleOut = [];
  for (const r of kept) {
    const oldName = r.f.path.split('/').pop().replace(/\.md$/, '');
    const path = r.isPerson ? unique(`people/${oldName}.md`) : unique(itemPathV2(r.h.added, oldName));
    moves[r.f.path] = path;
    for (const p of r.mergedFrom || []) moves[p] = path;
    const from = depthOf(r.f.path);
    const to = depthOf(path);
    const images = (Array.isArray(r.h.images) ? r.h.images : []).map((img) => (img && img.file ? { ...img, file: rebase(img.file, from, to) } : img));
    const body = cleanBody(r.f.body, r.h.summary, r.h.snippets);
    if (String(r.f.body || '').trim() && !body) report.bodies_cleared++;
    else if (body && body !== String(r.f.body || '').trim()) report.bodies_trimmed++;
    const header = {
      ...r.h,
      cover: r.h.cover ? rebase(r.h.cover, from, to) : r.h.cover,
      images,
      tags: r.tags,
      meta: r.meta,
      people: r.peopleRefs,
      places: r.placeIds,
      collections: r.collectionIds,
      sources: r.sources,
    };
    if (r.isPerson) {
      const e = people.get(nameKey(r.h.title || r.h.id));
      const ph = { ...header, name: e.name, aliases: e.aliases };
      delete ph.title; delete ph.people; delete ph.sources;
      peopleOut.push({ id: ph.id, path, header: ph, body, text: headerToText(ph, body, ENTITY_FIELDS) });
      report.refs.people += r.peopleRefs.length;
    } else {
      items.push({ id: header.id, path, header, body, text: headerToText(header, body, ITEM_FIELDS) });
    }
    report.refs.people += r.isPerson ? 0 : r.peopleRefs.length;
    report.refs.places += r.placeIds.length;
    report.refs.collections += r.collectionIds.length;
  }

  // People referenced by name only, plus places and collections.
  const fromItems = new Set(peopleOut.map((p) => p.id));
  for (const e of people.values()) {
    if (fromItems.has(e.id)) continue;
    const path = unique(`people/${safeName(nameKey(e.name).replace(/ /g, '-'), e.id)}.md`);
    const h = { id: e.id, name: e.name, kind: e.kind, aliases: e.aliases };
    peopleOut.push({ id: e.id, path, header: h, body: '', text: headerToText(h, '', ENTITY_FIELDS) });
  }
  const simple = (map, dir) => [...map.values()].map((e) => {
    const path = unique(`${dir}/${safeName(nameKey(e.name).replace(/ /g, '-'), e.id)}.md`);
    const h = { id: e.id, name: e.name, kind: e.kind, aliases: e.aliases, ...(e.tag ? { tag: e.tag } : {}) };
    return { id: e.id, path, header: h, body: '', text: headerToText(h, '', ENTITY_FIELDS) };
  });
  const placesOut = simple(places, 'places');
  const collectionsOut = simple(collections, 'collections');

  report.items = items.length;
  report.people = peopleOut.length;
  report.places = placesOut.length;
  report.collections = collectionsOut.length;
  return { items, people: peopleOut, places: placesOut, collections: collectionsOut, moves, report };
}

/**
 * Check a v2 conversion against its v1 input: every v1 item is accounted for,
 * every reference resolves, every media path still points at the same file,
 * and every written file parses back to its header. Returns a list of problems.
 */
export function verifyConversion(files, out) {
  const problems = [];
  const all = [...out.items, ...out.people, ...out.places, ...out.collections];
  const ids = new Set(all.map((e) => e.id));
  if (ids.size !== all.length) problems.push('duplicate ids');
  for (const { path } of files) if (!out.moves[path]) problems.push(`not converted: ${path}`);
  const v1 = new Map(files.map(({ path, text }) => [path, parseFile(text).header]));
  const byPath = new Map(all.map((e) => [e.path, e]));
  for (const [oldPath, newPath] of Object.entries(out.moves)) {
    const before = v1.get(oldPath);
    const after = byPath.get(newPath);
    if (!before || !after) continue;
    if (before.id !== after.id && !(after.header.sources || []).some((s) => s.id === before.id)) problems.push(`id changed: ${oldPath}`);
    // Media: resolve both relative paths from their own folder; they must name the same file.
    const resolveFrom = (p, f) => (f ? normalisePath(p.split('/').slice(0, -1).concat(f.split('/')).join('/')) : null);
    const a = (before.images || []).map((i) => resolveFrom(oldPath, i && i.file));
    const b = (after.header.images || []).map((i) => resolveFrom(newPath, i && i.file));
    if (before.id === after.id && JSON.stringify(a) !== JSON.stringify(b.slice(0, a.length))) problems.push(`media moved: ${oldPath}`);
    if (before.id === after.id && resolveFrom(oldPath, before.cover) !== resolveFrom(newPath, after.header.cover)) problems.push(`cover moved: ${oldPath}`);
    // Tags: what left the tags must now be a reference.
    const lostCats = Object.keys(before.tags || {}).filter((c) => !['collection', 'location'].includes(c) && !(after.header.tags || {})[c]);
    if (lostCats.length) problems.push(`tags lost (${lostCats.join(',')}): ${oldPath}`);
  }
  for (const e of all) {
    for (const r of e.header.people || []) if (!ids.has(r.id)) problems.push(`missing person ${r.id} in ${e.path}`);
    for (const id of e.header.places || []) if (!ids.has(id)) problems.push(`missing place ${id} in ${e.path}`);
    for (const id of e.header.collections || []) if (!ids.has(id)) problems.push(`missing collection ${id} in ${e.path}`);
    let back;
    try { back = parseFile(e.text).header; } catch (err) { problems.push(`unreadable ${e.path}: ${err.message}`); continue; }
    if (back.id !== e.id) problems.push(`round trip id ${e.path}`);
  }
  return problems;
}

function normalisePath(p) {
  const out = [];
  for (const seg of p.split('/')) {
    if (seg === '..') out.pop();
    else if (seg && seg !== '.') out.push(seg);
  }
  return out.join('/');
}

/** Rewrite a v1 JSON Canvas so file nodes point at the v2 paths. */
export function remapCanvas(canvas, moves) {
  return {
    ...canvas,
    nodes: (canvas.nodes || []).map((n) => (n.type === 'file' && moves[n.file] ? { ...n, file: moves[n.file] } : n)),
  };
}

export { groupTags, ungroupTags };
