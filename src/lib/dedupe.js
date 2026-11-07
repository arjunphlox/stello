/**
 * Merge items saved more than once (same link). For each group the keeper is the
 * row with the most content (images + snippets + summary), oldest on a tie. The
 * keeper gains the others' tags, snippets and images and the earliest added_at;
 * the others are soft-deleted (30-day restore). Everything goes through
 * applyChanges, so the Apple apps pull the result like any other edit.
 */
import { T, fromDb, applyChanges, MAX_PUSH } from './sync.js';

export function urlKey(url) {
  if (typeof url !== 'string' || !url.trim()) return null;
  try {
    const u = new URL(url.trim());
    const host = u.hostname.toLowerCase().replace(/^www\./, '');
    const path = u.pathname.replace(/\/+$/, '');
    return `${host}${path}${u.search}`;
  } catch {
    return url.trim().toLowerCase().replace(/\/+$/, '');
  }
}

const richness = (r) =>
  (fromDb('images', r.images) || []).length * 2 + (fromDb('snippets', r.snippets) || []).length + (r.summary ? 1 : 0);

/** Pure: rows (live, one user) → [{ keep, drop: [ids], fields }]. */
export function planMerges(rows) {
  const groups = new Map();
  for (const r of rows) {
    const k = urlKey(r.source_url);
    if (!k) continue;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(r);
  }
  const plans = [];
  for (const [key, list] of groups) {
    if (list.length < 2) continue;
    list.sort((a, b) => richness(b) - richness(a) || String(a.added_at).localeCompare(String(b.added_at)));
    const [keep, ...rest] = list;

    const tags = new Map();
    const snippets = new Map();
    const images = new Map();
    for (const r of [keep, ...rest]) {
      for (const t of fromDb('tags', r.tags) || []) {
        const name = t?.tag ?? t?.name;
        if (!name || !t.category) continue;
        const id = `${t.category}:${String(name).toLowerCase()}`;
        const prev = tags.get(id);
        if (!prev || (t.weight ?? 0) > (prev.weight ?? 0)) tags.set(id, t);
      }
      for (const s of fromDb('snippets', r.snippets) || []) if (s?.text && !snippets.has(s.text)) snippets.set(s.text, s);
      for (const img of fromDb('images', r.images) || []) {
        if (!img?.path || images.has(img.path)) continue;
        images.set(img.path, r === keep ? img : { ...img, is_primary: false });
      }
    }
    const fields = {
      tags: [...tags.values()],
      snippets: [...snippets.values()],
      images: [...images.values()],
      added_at: [keep, ...rest].map((r) => r.added_at).filter(Boolean).sort()[0] ?? keep.added_at,
    };
    for (const f of ['summary', 'body_markdown', 'author']) {
      if (!keep[f]) {
        const donor = rest.find((r) => r[f]);
        if (donor) fields[f] = donor[f];
      }
    }
    plans.push({ url: key, keep: keep.id, keepTitle: keep.title, drop: rest.map((r) => r.id), fields });
  }
  return plans;
}

export async function mergeDuplicates(db, userId, { apply = false, now = Date.now() } = {}) {
  const { results } = await db
    .prepare(`SELECT * FROM ${T.items} WHERE user_id = ? AND deleted_at IS NULL AND purged_at IS NULL`)
    .bind(userId)
    .all();
  const plans = planMerges(results || []);
  const summary = { groups: plans.length, dropped: plans.reduce((n, p) => n + p.drop.length, 0), plans };
  if (!apply) return { applied: false, ...summary };

  const changes = [];
  for (const p of plans) {
    changes.push({ id: p.keep, fields: p.fields, clock: now });
    for (const id of p.drop) changes.push({ id, fields: { deleted_at: now }, clock: now });
  }
  const statuses = {};
  for (let i = 0; i < changes.length; i += MAX_PUSH) {
    const { results: out } = await applyChanges(db, userId, changes.slice(i, i + MAX_PUSH), now);
    for (const r of out) statuses[r.status] = (statuses[r.status] || 0) + 1;
  }
  return { applied: true, statuses, ...summary };
}
