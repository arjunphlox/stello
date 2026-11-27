/**
 * The Stello engine: everything that turns a link or a file into a well-described
 * item, with no storage of its own. Plan: docs/plans/folder-engine.md (phase 1).
 *
 *   read(input)        page → item header in folder-v2 shape (kind, typed meta, rule tags,
 *                      people/places as names for the caller to resolve)
 *   ruleTags(...)      the capture-time tag rules (format, domain, subjects, tools, styles…)
 *   related(...)       Layer 1 "related" rules (same colour/style/idea/place/kind/source)
 *   normaliseUrl, nameKey, splitRefs, cleanBody   dedupe and reference helpers
 *   folder format      v1 + v2 file readers and writers
 *
 * Pure apart from read(), which fetches the page (and a few public lookups: Open Library,
 * GitHub, X syndication) through `net`, unless the caller passes the HTML.
 * The Worker (/api/read), the export script and, later, the apps all call this.
 */
import rules from '../src/lib/enrich-rules.js';
import { readPage, makeNet, MAX_HTML_BYTES } from '../src/lib/readers/pipeline.js';
import { groupTags } from '../src/lib/folder-format.js';
import { splitRefs, normaliseUrl, nameKey, cleanBody, titleFromTag } from '../src/lib/folder-v2.js';
import { foldCollections } from '../src/lib/collection-map.js';

export { readPage, makeNet, MAX_HTML_BYTES };
export { related, layer1, search, slimItem, colourHex, COLOR_MAP } from '../src/lib/library.js';
export * as folderV1 from '../src/lib/folder-format.js';
export * as folderV2 from '../src/lib/folder-v2.js';
export { splitRefs, normaliseUrl, nameKey, cleanBody };

export const ENGINE_VERSION = 1;

/** Capture-time tags (list form: [{ tag, category, weight }]). */
export function ruleTags({ title = '', domain = null, description = '', url = null } = {}) {
  return rules.generateTagsFromMetadata({ title, domain, description, sourceUrl: url });
}

/** Below this the readers' kind isn't trusted and the item stays a plain link. */
export const MIN_CONFIDENCE = 0.7;

/**
 * Read one link into an item header (folder v2 vocabulary).
 *   input: { url, html?, status?, finalURL?, collectionLabels?, fetchPage?, net? }
 * Returns {
 *   url, kind, title, site, summary, status,
 *   tags: { category: { tag: weight } }, meta,
 *   images: [{ url, source, is_primary }], image_fallbacks: [url],
 *   people: [{ name, role, kind }], places: [{ name, kind }],
 *   text, confidence, signal, engine
 * }
 * collectionLabels (old collection names, e.g. from an import) are classifier hints and
 * fold into a kind, place or tag (src/lib/collection-map.js); there are no collections.
 * people/places are names: the caller matches them to its own entity
 * files (nameKey + aliases) and stores ids.
 */
export async function read({ url, html = null, status = null, finalURL = null, collectionLabels = [], fetchPage = true, net = makeNet(), now = new Date() } = {}) {
  const page = await readPage({ url, html, status, finalURL, collectionLabels, fetchPage, net, now });
  const trusted = page.kind !== 'link' && (page.confidence ?? 0) >= MIN_CONFIDENCE;
  const folded = foldCollections({
    kind: trusted ? page.kind : 'link',
    tags: ruleTags({ title: page.title, domain: page.domain, description: page.summary || '', url: page.sourceURL || url }),
  }, collectionLabels);
  const kind = folded.kind;
  const tags = groupTags(folded.tags);
  const meta = trusted && page.metadata && typeof page.metadata === 'object' ? JSON.parse(JSON.stringify(page.metadata)) : null;
  const refs = splitRefs({ tags, meta });
  const people = refs.people.map((p) => ({ name: typeof p.raw === 'string' ? p.raw.trim() : p.raw.name.trim(), role: p.role, kind: p.kind }));
  const places = refs.places.map((p) => ({ name: titleFromTag(p.name), kind: p.kind }));
  const imgs = page.images || { urls: [], source: 'og', fallbacks: [] };
  return {
    url: page.sourceURL || url,
    kind,
    title: page.title || null,
    site: page.domain || null,
    summary: page.summary || null,
    status: page.status || 'active',
    tags,
    meta: meta && Object.keys(meta).length ? meta : null,
    images: (imgs.urls || []).map((u, i) => ({ url: u, source: imgs.source || 'og', is_primary: i === 0 })),
    image_fallbacks: imgs.fallbacks || [],
    people,
    places,
    text: page.extractedText || null,
    confidence: page.confidence ?? 0,
    signal: page.signal || null,
    fetched: !!page.fetched,
    engine: ENGINE_VERSION,
  };
}

/**
 * Match names from read() to existing entities.
 *   entities: [{ id, name, aliases? }]
 * Returns the entity for a name, or null (the caller then creates one).
 */
export function matchEntity(entities, name) {
  const k = nameKey(name);
  if (!k) return null;
  return entities.find((e) => nameKey(e.name) === k || (e.aliases || []).some((a) => nameKey(a) === k)) || null;
}
