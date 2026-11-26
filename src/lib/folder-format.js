/**
 * The Stello folder format, version 1: one Markdown file per item.
 * Plan: docs/plans/folder-engine.md.
 *
 *   items/<YYYY>/<slug>.md      header (one field per line) + the item's Markdown body
 *   media/<slug>/<n>.<ext>      the item's images, as stored
 *   projects/<id>.canvas        canvas docs as JSON Canvas (+ the full Stello doc under "stello")
 *   stello.json                 format version, counts, export info
 *
 * Header values are written as JSON (valid YAML flow values), so Obsidian and
 * any YAML reader can open them, and parsing back is exact. Tags are grouped
 * by category with their weights; images are a list, one per line.
 *
 * Pure functions only (no I/O), so the web, the export script and tests share them.
 */

export const FORMAT = 'stello-folder';
export const FORMAT_VERSION = 1;

/** Header field order. Fields with no value are left out of the file. */
const HEADER_FIELDS = [
  'id', 'title', 'url', 'kind', 'site', 'author', 'summary', 'status',
  'added', 'analyzed', 'opened', 'open_count', 'cover', 'cover_aspect',
  'review', 'enrichment', 'tags', 'meta', 'snippets', 'images',
];

/** Item (sync API shape) field ↔ header key. */
const RENAMES = {
  source_url: 'url',
  domain: 'site',
  added_at: 'added',
  analyzed_at: 'analyzed',
  last_opened_at: 'opened',
  needs_review: 'review',
  enrichment_status: 'enrichment',
  metadata: 'meta',
};
const SCALARS = ['id', 'title', 'source_url', 'kind', 'domain', 'author', 'summary', 'status',
  'added_at', 'analyzed_at', 'last_opened_at', 'open_count', 'cover_aspect', 'needs_review',
  'enrichment_status', 'metadata', 'snippets'];

const empty = (v) => v === null || v === undefined || v === '' ||
  (Array.isArray(v) && v.length === 0) ||
  (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0);

/** Safe file/folder name from a slug (slugs are already URL-safe; this guards the rest). */
export function safeName(slug, fallback = 'item') {
  const s = String(slug || '').normalize('NFKD').replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^[-.]+|[-.]+$/g, '').slice(0, 120);
  return s || fallback;
}

/** items/<year>/<slug>.md, the year from added_at (unknown → 'undated'). */
export function itemPath(item) {
  const m = /^(\d{4})-/.exec(String(item.added_at || ''));
  return `items/${m ? m[1] : 'undated'}/${safeName(item.slug, item.id)}.md`;
}

/** File extension for a stored image path or content type. */
export function imageExt(path, contentType = '') {
  const t = String(contentType).toLowerCase();
  if (t.includes('webp')) return 'webp';
  if (t.includes('png')) return 'png';
  if (t.includes('jpeg') || t.includes('jpg')) return 'jpg';
  if (t.includes('gif')) return 'gif';
  if (t.includes('avif')) return 'avif';
  if (t.includes('heic')) return 'heic';
  const m = /\.([A-Za-z0-9]{2,5})(?:$|\?)/.exec(String(path || ''));
  return m ? m[1].toLowerCase().replace('jpeg', 'jpg') : 'img';
}

/**
 * The media plan for an item: each stored image gets a local file name.
 * `ext` may be overridden per index once the download knows the real type;
 * `itemFile` (the item's .md path) names the folder when the file name had to change.
 */
export function mediaFiles(item, exts = {}, itemFile = null) {
  const name = itemFile ? String(itemFile).split('/').pop().replace(/\.md$/, '') : safeName(item.slug, item.id);
  const dir = `media/${name}`;
  return (Array.isArray(item.images) ? item.images : []).map((img, i) => ({
    index: i,
    remote: img && img.path,
    file: img && img.path ? `${dir}/${i + 1}.${exts[i] || imageExt(img.path)}` : null,
  }));
}

/** Tags list → { category: { tag: weight } }, categories and tags in first-seen order. */
export function groupTags(tags) {
  const out = {};
  for (const t of Array.isArray(tags) ? tags : []) {
    if (!t || typeof t.tag !== 'string') continue;
    const cat = typeof t.category === 'string' && t.category ? t.category : 'subject';
    (out[cat] ||= {})[t.tag] = typeof t.weight === 'number' ? t.weight : 1;
  }
  return out;
}

/** { category: { tag: weight } } → tags list. */
export function ungroupTags(grouped) {
  const out = [];
  for (const [category, tags] of Object.entries(grouped || {})) {
    for (const [tag, weight] of Object.entries(tags || {})) out.push({ tag, category, weight });
  }
  return out;
}

/**
 * Item (sync API shape) → Markdown file text.
 * `files` = mediaFiles() result, so header image entries point at the local copies.
 * The file sits two folders down (items/<year>/), so local paths get "../../".
 */
export function itemToMarkdown(item, files = mediaFiles(item)) {
  const h = {};
  for (const f of SCALARS) h[RENAMES[f] || f] = item[f];
  h.tags = groupTags(item.tags);
  const imgs = Array.isArray(item.images) ? item.images : [];
  h.images = imgs.map((img, i) => {
    const local = files[i] && files[i].file;
    return local ? { file: `../../${local}`, ...img } : { ...img };
  });
  const primary = imgs.findIndex((img) => img && img.is_primary);
  const coverAt = primary >= 0 ? primary : (imgs.length ? 0 : -1);
  if (coverAt >= 0 && files[coverAt] && files[coverAt].file) h.cover = `../../${files[coverAt].file}`;

  const lines = ['---'];
  for (const key of HEADER_FIELDS) {
    const v = h[key];
    if (empty(v) || (key === 'review' && v === false)) continue; // false is the default
    if (key === 'tags') {
      lines.push('tags:');
      for (const [cat, tags] of Object.entries(v)) lines.push(`  ${cat}: ${JSON.stringify(tags)}`);
    } else if (key === 'images' || key === 'snippets') {
      lines.push(`${key}:`);
      for (const entry of v) lines.push(`  - ${JSON.stringify(entry)}`);
    } else {
      lines.push(`${key}: ${JSON.stringify(v)}`);
    }
  }
  lines.push('---', '');
  const body = String(item.body_markdown || '').replace(/\s+$/, '');
  return lines.join('\n') + (body ? body + '\n' : '');
}

/** Markdown file text → { header, body }. Throws on a malformed header line. */
export function parseItemFile(text) {
  // Bodies keep their own line endings; the header may have \r\n if edited elsewhere.
  const src = String(text);
  const open = /^---\r?\n/.exec(src);
  if (!open) return { header: {}, body: src };
  const close = /\r?\n---\r?\n/.exec(src.slice(open[0].length - 1));
  const headEnd = close ? open[0].length - 1 + close.index : src.length;
  const head = src.slice(open[0].length, headEnd);
  const body = close ? src.slice(headEnd + close[0].length).replace(/^\r?\n/, '') : '';
  const header = {};
  let block = null;
  for (let line of head.split('\n')) {
    line = line.replace(/\r$/, '');
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    if (line.startsWith('  - ')) {
      if (!block) throw new Error(`list entry outside a block: ${line}`);
      if (!Array.isArray(header[block])) header[block] = [];
      header[block].push(JSON.parse(line.slice(4)));
      continue;
    }
    if (line.startsWith('  ')) {
      if (!block) throw new Error(`nested key outside a block: ${line}`);
      const at = line.indexOf(': ');
      if (at < 0) throw new Error(`bad nested line: ${line}`);
      if (!header[block] || typeof header[block] !== 'object' || Array.isArray(header[block])) header[block] = {};
      header[block][line.slice(2, at).trim()] = JSON.parse(line.slice(at + 2));
      continue;
    }
    const at = line.indexOf(':');
    if (at < 0) throw new Error(`bad header line: ${line}`);
    const key = line.slice(0, at).trim();
    const rest = line.slice(at + 1).trim();
    if (!rest) { block = key; header[key] = null; continue; }
    block = null;
    header[key] = JSON.parse(rest);
  }
  return { header, body };
}

/** Markdown file text → item (sync API shape), the inverse of itemToMarkdown. */
export function markdownToItem(text, { slug } = {}) {
  const { header: h, body } = parseItemFile(text);
  const item = {};
  for (const f of SCALARS) {
    const v = h[RENAMES[f] || f];
    item[f] = v === undefined ? null : v;
  }
  item.needs_review = h.review === true;
  item.open_count = typeof h.open_count === 'number' ? h.open_count : 0;
  item.snippets = Array.isArray(h.snippets) ? h.snippets : [];
  item.metadata = h.meta && typeof h.meta === 'object' ? h.meta : null;
  item.tags = ungroupTags(h.tags);
  item.images = (Array.isArray(h.images) ? h.images : []).map(({ file, ...img }) => img);
  item.body_markdown = body.replace(/\s+$/, '') || null;
  if (slug) item.slug = slug;
  return item;
}

/**
 * Compare an item from the API with the same item read back from its file.
 * Returns the list of fields that differ (empty = exact round trip).
 */
export function diffItem(original, roundTripped) {
  const norm = {
    tags: (v) => JSON.stringify(ungroupTags(groupTags(v))),
    images: (v) => JSON.stringify(Array.isArray(v) ? v : []),
    snippets: (v) => JSON.stringify(Array.isArray(v) ? v : []),
    metadata: (v) => JSON.stringify(empty(v) ? null : v),
    body_markdown: (v) => String(v || '').replace(/\s+$/, ''),
    needs_review: (v) => !!v,
    open_count: (v) => Number(v || 0),
  };
  const fields = [...SCALARS, 'tags', 'images', 'body_markdown'];
  const out = [];
  for (const f of fields) {
    const n = norm[f] || ((v) => (empty(v) ? null : v));
    if (JSON.stringify(n(original[f])) !== JSON.stringify(n(roundTripped[f]))) out.push(f);
  }
  return out;
}

/**
 * Stello canvas doc → JSON Canvas (jsoncanvas.org, the format Obsidian reads).
 * Cards become file nodes pointing at the item files; notes become text nodes;
 * Layer 2 links become labelled edges; groups become group nodes around their
 * cards. The full Stello doc rides along under "stello" so nothing is lost.
 * `pathFor(slug)` → the item's file path in the folder, or null.
 */
export function canvasToJsonCanvas(project, pathFor) {
  const doc = (project && project.doc) || {};
  const W = 240, H = 300;
  const nodes = [];
  const edges = [];
  const pos = {};
  for (const c of doc.cards || []) {
    const id = `card-${safeName(c.slug)}`;
    pos[c.slug] = { x: Math.round(c.x || 0), y: Math.round(c.y || 0), id };
    const file = pathFor(c.slug);
    nodes.push(file
      ? { id, type: 'file', file, x: pos[c.slug].x, y: pos[c.slug].y, width: W, height: H }
      : { id, type: 'text', text: c.slug, x: pos[c.slug].x, y: pos[c.slug].y, width: W, height: 80 });
  }
  for (const n of doc.notes || []) {
    if (typeof n.x !== 'number' || typeof n.y !== 'number' || !n.text) continue;
    nodes.push({ id: `note-${n.id}`, type: 'text', text: n.text, x: Math.round(n.x), y: Math.round(n.y), width: W, height: 120 });
  }
  for (const g of doc.groups || []) {
    const members = (g.slugs || []).map((s) => pos[s]).filter(Boolean);
    if (!members.length) continue;
    const x0 = Math.min(...members.map((m) => m.x)) - 40;
    const y0 = Math.min(...members.map((m) => m.y)) - 60;
    const x1 = Math.max(...members.map((m) => m.x + W)) + 40;
    const y1 = Math.max(...members.map((m) => m.y + H)) + 40;
    nodes.unshift({ id: `group-${g.id}`, type: 'group', label: g.name || '', x: x0, y: y0, width: x1 - x0, height: y1 - y0 });
  }
  for (const l of doc.links || []) {
    if (!pos[l.a] || !pos[l.b]) continue;
    edges.push({ id: `link-${l.id}`, fromNode: pos[l.a].id, toNode: pos[l.b].id, label: l.label || l.kind || '' });
  }
  return { nodes, edges, stello: { id: project.id, name: project.name || doc.name || '', rev: project.rev, doc } };
}
