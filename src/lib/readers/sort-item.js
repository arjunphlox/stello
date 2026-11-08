/**
 * Sorting a saved item: run the page readers and write the kind + typed metadata.
 *
 * Save first, sort second. Capture inserts the item, answers the client, and only then
 * sorts it (ctx.waitUntil), so a page that is slow or runs past the Workers CPU limit
 * never loses the save. An item the rules can't type stays a plain link with no kind
 * and no metadata: the Mac app's web-inbox fill-in (SyncWire.needsClassify) picks those up.
 */
import { readPage, makeNet } from './pipeline.js';

/** Below this the rules' answer isn't written (see pipeline.confidenceFor). */
export const MIN_CONFIDENCE = 0.7;

/**
 * The item fields a page read sets, or null when the rules aren't sure enough to
 * type the item.
 */
export function sortedFields(read) {
  if (!read || read.kind === 'link' || read.confidence < MIN_CONFIDENCE) return null;
  const fields = { kind: read.kind, metadata: read.metadata ?? null };
  if (read.title) fields.title = String(read.title).replace(/"/g, "'");
  if (read.domain) fields.domain = read.domain;
  if (read.status === 'gone') fields.status = 'gone';
  return fields;
}

/**
 * Reads the item's page and writes what the rules found. Never throws.
 * @param {object} p
 * @param {object} p.client   db.js user-scoped client
 * @param {object} p.item     the saved row ({ id, source_url, kind, metadata })
 * @param {object} [p.net]    makeNet() instance (tests pass a fake)
 * @returns {Promise<{ sorted: boolean, kind: string, confidence: number, signal: string } | null>}
 */
export async function sortSavedItem({ client, item, net = makeNet(), now = new Date() }) {
  if (!item?.source_url) return null;
  // Already typed (the Apple app or an earlier sort got there first): leave it.
  if (item.kind && item.kind !== 'link' && item.metadata != null) return null;
  try {
    const read = await readPage({ url: item.source_url, net, now });
    const fields = sortedFields(read);
    console.log('sort', JSON.stringify({ id: item.id, kind: read.kind, confidence: read.confidence, signal: read.signal, subrequests: net.used }));
    if (fields) await client.from('items').update(fields).eq('id', item.id);
    return { sorted: !!fields, kind: read.kind, confidence: read.confidence, signal: read.signal };
  } catch (err) {
    console.warn('sort failed', item.id, err?.message || err);
    return null;
  }
}
