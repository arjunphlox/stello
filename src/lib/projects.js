/**
 * Canvas docs on D1: the library canvas (id 'library') and named projects.
 *
 * A doc is saved whole, with a rev check: PUT sends the rev it last read and
 * gets 409 + the current doc when someone else saved first. The web canvas,
 * the Figma plugin (FigJam Board sync) and the MCP connector all use this.
 *
 * Doc shape (unknown keys are dropped, sizes are capped):
 *   {
 *     name:      string,
 *     groupBy:   string | null          — 'topic' | 'kind' | 'source' | 'colour' | 'time' | custom
 *     cards:     [{ slug, x, y, note?, state? }]        state: 'use' | 'rejected'
 *     links:     [{ id, a, b, kind, label?, source? }]  Layer 2 only; Layer 1 similarity is computed
 *                 kind:   'manual' | 'influence' | 'contrast' | 'part_of' | 'question' | 'maybe'
 *                 source: 'web' | 'mac' | 'figjam' | 'mcp'
 *     groups:    [{ id, name, slugs: [slug] }]
 *     notes:     [{ id, kind, text, x?, y?, near?, slug?, rx?, ry?, slugs? }]
 *                 kind: 'note' | 'question' | 'region' | 'set'
 *                 region: { slug, rx, ry } = a point on that item's image, as 0–1 fractions
 *                 set:    a "part of" hub; `slugs` are its members
 *     dismissed: [slug]                 — ghost suggestions the user waved away
 *   }
 */

export const LIBRARY_ID = 'library';
export const LINK_KINDS = ['manual', 'influence', 'contrast', 'part_of', 'question', 'maybe'];
export const NOTE_KINDS = ['note', 'question', 'region', 'set'];
export const CARD_STATES = ['use', 'rejected'];
export const SOURCES = ['web', 'mac', 'figjam', 'mcp'];
export const LIMITS = { cards: 5000, links: 10000, groups: 500, notes: 2000, dismissed: 5000, text: 2000, name: 200 };
const MAX_DOC_BYTES = 900 * 1024; // under D1's 1 MB row limit

const str = (v, max) => (typeof v === 'string' ? v.slice(0, max) : '');
const num = (v) => (Number.isFinite(+v) ? Math.round(+v * 100) / 100 : 0);
const frac = (v) => Math.min(1, Math.max(0, Number.isFinite(+v) ? +v : 0));
const slugOk = (s) => typeof s === 'string' && s.length > 0 && s.length <= 300;
const idOk = (s) => typeof s === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(s);
const pick = (v, list, dflt) => (list.includes(v) ? v : dflt);

export function newId() {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 16);
}

/** Clean a doc from any client. Returns a new object; never throws. */
export function normalizeDoc(input) {
  const d = input && typeof input === 'object' ? input : {};
  const arr = (v, max) => (Array.isArray(v) ? v.slice(0, max) : []);
  const seen = new Set();
  const cards = [];
  for (const c of arr(d.cards, LIMITS.cards)) {
    if (!c || !slugOk(c.slug) || seen.has(c.slug)) continue;
    seen.add(c.slug);
    const out = { slug: c.slug, x: num(c.x), y: num(c.y) };
    const note = str(c.note, LIMITS.text);
    if (note) out.note = note;
    if (CARD_STATES.includes(c.state)) out.state = c.state;
    cards.push(out);
  }
  const links = [];
  const linkIds = new Set();
  for (const l of arr(d.links, LIMITS.links)) {
    if (!l || !slugOk(l.a) || !slugOk(l.b) || l.a === l.b) continue;
    const id = idOk(l.id) && !linkIds.has(l.id) ? l.id : newId();
    linkIds.add(id);
    const out = { id, a: l.a, b: l.b, kind: pick(l.kind, LINK_KINDS, 'manual') };
    const label = str(l.label, 200);
    if (label) out.label = label;
    if (SOURCES.includes(l.source)) out.source = l.source;
    links.push(out);
  }
  const groups = [];
  for (const g of arr(d.groups, LIMITS.groups)) {
    if (!g) continue;
    const slugs = arr(g.slugs, LIMITS.cards).filter(slugOk);
    groups.push({ id: idOk(g.id) ? g.id : newId(), name: str(g.name, LIMITS.name), slugs: [...new Set(slugs)] });
  }
  const notes = [];
  for (const n of arr(d.notes, LIMITS.notes)) {
    if (!n) continue;
    const kind = pick(n.kind, NOTE_KINDS, 'note');
    const out = { id: idOk(n.id) ? n.id : newId(), kind, text: str(n.text, LIMITS.text) };
    if (n.x != null) out.x = num(n.x);
    if (n.y != null) out.y = num(n.y);
    if (slugOk(n.near)) out.near = n.near;
    if (kind === 'region') {
      if (!slugOk(n.slug)) continue;
      out.slug = n.slug; out.rx = frac(n.rx); out.ry = frac(n.ry);
    }
    if (kind === 'set') out.slugs = [...new Set(arr(n.slugs, LIMITS.cards).filter(slugOk))];
    notes.push(out);
  }
  const out = {
    name: str(d.name, LIMITS.name),
    groupBy: typeof d.groupBy === 'string' ? d.groupBy.slice(0, 40) : null,
    cards, links, groups, notes,
    dismissed: [...new Set(arr(d.dismissed, LIMITS.dismissed).filter(slugOk))],
  };
  // Doc format version (web canvas: 2 = starts empty, items only by drag-in).
  if (Number.isInteger(d.v) && d.v > 0 && d.v < 1000) out.v = d.v;
  return out;
}

function rowToProject(row) {
  let doc = {};
  try { doc = JSON.parse(row.doc || '{}'); } catch { doc = {}; }
  return {
    id: row.id, name: row.name, rev: row.rev,
    created_at: row.created_at, updated_at: row.updated_at,
    doc: normalizeDoc({ ...doc, name: row.name }),
  };
}

export async function listProjects(db, userId) {
  const { results } = await db.prepare(
    `SELECT id, name, rev, created_at, updated_at, doc FROM projects
      WHERE user_id = ? AND deleted_at IS NULL ORDER BY updated_at DESC`
  ).bind(userId).all();
  return (results || []).map((r) => {
    const p = rowToProject(r);
    return { id: p.id, name: p.name, rev: p.rev, updated_at: p.updated_at, cards: p.doc.cards.length };
  });
}

export async function getProject(db, userId, id) {
  const row = await db.prepare(
    'SELECT * FROM projects WHERE user_id = ? AND id = ? AND deleted_at IS NULL'
  ).bind(userId, id).first();
  if (row) return rowToProject(row);
  if (id === LIBRARY_ID) {
    // The library canvas always exists; it's created on first save.
    return { id, name: 'Library canvas', rev: 0, created_at: null, updated_at: null, doc: normalizeDoc({ name: 'Library canvas' }) };
  }
  return null;
}

export async function createProject(db, userId, input) {
  const doc = normalizeDoc(input || {});
  if (!doc.name) doc.name = 'Untitled project';
  const id = newId();
  const now = new Date().toISOString();
  const text = JSON.stringify(doc);
  if (text.length > MAX_DOC_BYTES) return { error: 'too_large' };
  await db.prepare(
    `INSERT INTO projects (id, user_id, name, doc, rev, created_at, updated_at) VALUES (?, ?, ?, ?, 1, ?, ?)`
  ).bind(id, userId, doc.name, text, now, now).run();
  return { project: { id, name: doc.name, rev: 1, created_at: now, updated_at: now, doc } };
}

/**
 * Save a whole doc. `rev` must match the stored rev (0 for a library canvas
 * that has never been saved). Returns { project } or { conflict: project }.
 */
export async function saveProject(db, userId, id, input, rev) {
  if (!idOk(id)) return { error: 'bad_id' };
  const doc = normalizeDoc(input || {});
  const current = await getProject(db, userId, id);
  if (!current) return { error: 'not_found' };
  if (!doc.name) doc.name = current.name;
  if (Number(rev) !== current.rev) return { conflict: current };
  const text = JSON.stringify(doc);
  if (text.length > MAX_DOC_BYTES) return { error: 'too_large' };
  const now = new Date().toISOString();
  if (current.rev === 0) {
    const r = await db.prepare(
      `INSERT OR IGNORE INTO projects (id, user_id, name, doc, rev, created_at, updated_at) VALUES (?, ?, ?, ?, 1, ?, ?)`
    ).bind(id, userId, doc.name, text, now, now).run();
    if (!r.meta || !r.meta.changes) return { conflict: await getProject(db, userId, id) };
    return { project: { id, name: doc.name, rev: 1, created_at: now, updated_at: now, doc } };
  }
  const r = await db.prepare(
    `UPDATE projects SET name = ?, doc = ?, rev = rev + 1, updated_at = ?
      WHERE user_id = ? AND id = ? AND rev = ? AND deleted_at IS NULL`
  ).bind(doc.name, text, now, userId, id, current.rev).run();
  if (!r.meta || !r.meta.changes) return { conflict: await getProject(db, userId, id) };
  return { project: { id, name: doc.name, rev: current.rev + 1, created_at: current.created_at, updated_at: now, doc } };
}

export async function deleteProject(db, userId, id) {
  const r = await db.prepare(
    'UPDATE projects SET deleted_at = ? WHERE user_id = ? AND id = ? AND deleted_at IS NULL'
  ).bind(new Date().toISOString(), userId, id).run();
  return !!(r.meta && r.meta.changes);
}

/**
 * Merge a FigJam board into a doc (Board sync). The board wins for every
 * card, link, group and note it carries; cards, links and notes that only
 * exist in Stello stay. Removed: links/notes from an earlier FigJam sync that
 * are gone from the board, and anything Stello laid out on the board that the
 * user deleted there (`board.removed: { notes: [id], links: [id] }`).
 */
export function mergeBoard(doc, board) {
  const base = normalizeDoc(doc);
  const b = normalizeDoc(board);
  const removed = (board && board.removed) || {};
  const goneLinks = new Set(Array.isArray(removed.links) ? removed.links : []);
  const goneNotes = new Set(Array.isArray(removed.notes) ? removed.notes : []);

  const bySlug = new Map(base.cards.map((c) => [c.slug, c]));
  for (const c of b.cards) bySlug.set(c.slug, { ...(bySlug.get(c.slug) || {}), ...c });

  const pair = (l) => [l.a, l.b].sort().join('|');
  const baseById = new Map(base.links.map((l) => [l.id, l]));
  const boardLinks = b.links.map((l) => ({ ...l, source: (baseById.get(l.id) || {}).source || 'figjam' }));
  const boardIds = new Set(boardLinks.map((l) => l.id));
  const boardPairs = new Set(boardLinks.map(pair));
  const links = base.links
    .filter((l) => l.source !== 'figjam' && !goneLinks.has(l.id) && !boardIds.has(l.id) && !boardPairs.has(pair(l)))
    .concat(boardLinks);

  const groupNames = new Set(b.groups.map((g) => g.name.toLowerCase()));
  const regrouped = new Set(b.groups.flatMap((g) => g.slugs));
  const groups = base.groups
    .filter((g) => !groupNames.has(g.name.toLowerCase()))
    .map((g) => ({ ...g, slugs: g.slugs.filter((s) => !regrouped.has(s)) }))
    .filter((g) => g.slugs.length)
    .concat(b.groups);

  const boardNoteIds = new Set(b.notes.map((n) => n.id));
  const notes = base.notes
    .filter((n) => !String(n.id).startsWith('fj') && !goneNotes.has(n.id) && !boardNoteIds.has(n.id))
    .concat(b.notes);

  return normalizeDoc({
    ...base,
    name: base.name || b.name, // a board never renames an existing project
    groupBy: b.groups.length ? 'custom' : base.groupBy,
    cards: [...bySlug.values()], links, groups, notes,
  });
}
