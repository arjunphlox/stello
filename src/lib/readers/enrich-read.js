/**
 * Enrich on the web: store a fresh page read over what the item has, as the Mac's
 * EnrichmentService.applyFreshRead / applyMusicRead do.
 *
 * A refetch that reads less (bot wall, rate-limited GitHub, tombstone) never erases what
 * was read before; curated kinds (typeface, website, individual, …) are never flipped;
 * a post title the user edited is kept. Pure: returns the item fields to write.
 */
import { merge as mergeTool } from './tool.js';
import { merge as mergeResource } from './resource.js';
import { merge as mergeBook } from './book.js';
import { merge as mergeCourse } from './course.js';
import { merge as mergeArticle } from './article.js';
import { postTitle, isGenericPostTitle } from './post.js';

/** Kinds a plain link may become on Enrich (Mac WorkerSorter.linkKinds). */
export const LINK_KINDS = new Set(['post', 'product', 'resource', 'book', 'tool', 'course', 'article', 'music']);
/** Kind changes a fresh read may make on a typed item (Mac EnrichmentService.migrations). */
export const MIGRATIONS = new Set(['product>resource', 'tool>resource', 'article>course']);

function parseMeta(v) {
  if (v == null) return null;
  if (typeof v === 'object') return v;
  try { return JSON.parse(v); } catch { return null; }
}

/** Whether a fresh read may be stored on the item. */
export function canApply(read, item) {
  const current = item.kind || 'link';
  if (!read || read.kind === 'link' || read.metadata == null) return false;
  if (read.kind === current) return true;
  if (current === 'link') return LINK_KINDS.has(read.kind);
  return MIGRATIONS.has(`${current}>${read.kind}`);
}

/** "Price when saved" is a snapshot; a read name or brand is never replaced by a guess. */
export function mergeProduct(fresh, previous) {
  const m = { ...fresh };
  if (!previous) return m;
  if (previous.price != null) {
    for (const k of ['price', 'priceMin', 'priceMax', 'currency', 'pricedAt']) {
      if (previous[k] != null) m[k] = previous[k]; else delete m[k];
    }
  }
  if (previous.productName != null && (m.productName == null || m.productNameIsGuess === true)) {
    m.productName = previous.productName;
    m.productNameIsGuess = previous.productNameIsGuess;
  }
  if (previous.brand != null && (m.brand == null || m.brandIsGuess === true)) {
    m.brand = previous.brand;
    m.brandIsGuess = previous.brandIsGuess;
  }
  return m;
}

/** A refetch that reads less never erases what capture read; AI-art fields are kept. */
export function mergePost(fresh, previous) {
  const m = { ...fresh };
  if (!previous) return m;
  for (const k of ['text', 'author', 'authorHandle', 'postedAt', 'embedURL']) {
    if (m[k] == null && previous[k] != null) m[k] = previous[k];
  }
  if (m.mediaType == null) { m.mediaType = previous.mediaType; m.mediaCount = previous.mediaCount; }
  for (const k of ['isAIArt', 'aiModel', 'prompt', 'promptIsGuess']) {
    if (previous[k] !== undefined) m[k] = previous[k]; else delete m[k];
  }
  return m;
}

const MERGERS = {
  tool: mergeTool, resource: mergeResource, book: mergeBook, course: mergeCourse, article: mergeArticle,
};

/**
 * The item fields a fresh read sets (kind, metadata, domain, title for posts, status),
 * or null when the read may not be stored.
 */
export function freshReadFields(read, item) {
  if (!read) return null;
  const current = item.kind || 'link';
  const fields = {};
  if (read.status === 'gone' && item.status !== 'gone') fields.status = 'gone';

  // Music: the readers rebuild the whole dossier (link or music items only).
  if (read.kind === 'music') {
    if (read.metadata == null || !['music', 'link'].includes(current)) return Object.keys(fields).length ? fields : null;
    return { ...fields, kind: 'music', metadata: read.metadata };
  }
  if (!canApply(read, item)) return Object.keys(fields).length ? fields : null;

  // A migration (product → resource, …) starts fresh: the old dossier is another shape.
  const previous = read.kind === current ? parseMeta(item.metadata) : null;
  let meta;
  if (read.kind === 'product') meta = mergeProduct(read.metadata, previous);
  else if (read.kind === 'post') {
    meta = mergePost(read.metadata, previous);
    // The title the rule would have written from the old dossier: if the item still
    // carries it, the user hasn't edited it and it may follow the new reading.
    const previousRuleTitle = previous
      ? postTitle({ currentTitle: null, handle: previous.authorHandle, authorName: previous.author?.name, text: previous.text })
      : null;
    const titleIsOurs = isGenericPostTitle(item.title) || item.title === previousRuleTitle;
    const next = titleIsOurs
      ? postTitle({ currentTitle: null, handle: meta.authorHandle, authorName: meta.author?.name, text: meta.text })
      : null;
    if (next) fields.title = String(next).replace(/"/g, "'");
  } else if (MERGERS[read.kind]) meta = MERGERS[read.kind](read.metadata, previous);
  else return Object.keys(fields).length ? fields : null;

  fields.kind = read.kind;
  fields.metadata = meta;
  if (read.domain) fields.domain = read.domain;
  return fields;
}
