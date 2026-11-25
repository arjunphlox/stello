/**
 * Audience sharing: the rules shared by /api/me/sharing, /api/share-links and
 * (phase 2) the viewer page at /s/<token>. Plan: docs/plans/audience-sharing.md.
 *
 * Audiences are nested circles (rank 1 = innermost, e.g. Family) plus standalone
 * lists. Stored per user in user_settings under 'sharing' as
 *   { audiences: [{ id, name, kind, rank, location, color, deleted_at, clock }],
 *     private_places: { value: [{ name, words, lat, lng, radius_m }], clock } }
 * `clock` is epoch ms per field, merged field by field with last-write-wins (ties
 * keep the server value), like items (src/lib/sync.js) and the profile.
 *
 * Each item lists its audience ids in items.audiences ([] = private).
 */

export const MAX_FUTURE_MS = 5 * 60 * 1000;
export const MAX_AUDIENCES = 32;
export const MAX_PLACES = 50;
export const MAX_NAME = 60;
export const KINDS = ['circle', 'list'];
export const LOCATIONS = ['exact', 'city', 'hidden'];
const AUDIENCE_FIELDS = ['name', 'rank', 'location', 'color', 'deleted_at'];
const ID_RE = /^[a-z0-9-]{1,64}$/;
const COLOR_RE = /^#[0-9a-f]{6}$/i;

/** The four circles every account starts with. Fixed ids, so the web and each
 *  Apple device seed the same rows and never make duplicates. Clock 0, so any
 *  dated edit wins over the seed. */
export const DEFAULT_AUDIENCES = [
  { id: 'family', name: 'Family', kind: 'circle', rank: 1, location: 'exact', color: '#e0565b' },
  { id: 'close-friends', name: 'Close friends', kind: 'circle', rank: 2, location: 'city', color: '#e39a3b' },
  { id: 'acquaintances', name: 'Acquaintances', kind: 'circle', rank: 3, location: 'city', color: '#4f9d69' },
  { id: 'public', name: 'Public', kind: 'circle', rank: 4, location: 'hidden', color: '#4a7fd6' },
];

const zeroClock = () => Object.fromEntries(AUDIENCE_FIELDS.map((f) => [f, 0]));

function cleanAudience(a) {
  if (!a || typeof a !== 'object' || typeof a.id !== 'string' || !ID_RE.test(a.id)) return null;
  const kind = KINDS.includes(a.kind) ? a.kind : 'list';
  const c = a.clock && typeof a.clock === 'object' ? a.clock : {};
  const clock = zeroClock();
  for (const f of AUDIENCE_FIELDS) if (Number.isFinite(c[f])) clock[f] = c[f];
  return {
    id: a.id,
    name: typeof a.name === 'string' ? a.name.trim().slice(0, MAX_NAME) : '',
    kind,
    rank: kind === 'circle' && Number.isInteger(a.rank) && a.rank > 0 ? a.rank : null,
    location: LOCATIONS.includes(a.location) ? a.location : 'hidden',
    color: typeof a.color === 'string' && COLOR_RE.test(a.color) ? a.color.toLowerCase() : null,
    deleted_at: Number.isFinite(a.deleted_at) ? a.deleted_at : null,
    clock,
  };
}

function cleanPlace(p) {
  if (!p || typeof p !== 'object') return null;
  const name = typeof p.name === 'string' ? p.name.trim().slice(0, MAX_NAME) : '';
  const words = (Array.isArray(p.words) ? p.words : [])
    .filter((w) => typeof w === 'string' && w.trim())
    .map((w) => w.trim().toLowerCase().slice(0, 80))
    .slice(0, 10);
  const lat = Number.isFinite(p.lat) && Math.abs(p.lat) <= 90 ? p.lat : null;
  const lng = Number.isFinite(p.lng) && Math.abs(p.lng) <= 180 ? p.lng : null;
  const radius = Number.isFinite(p.radius_m) && p.radius_m > 0 ? Math.min(Math.round(p.radius_m), 50000) : 500;
  if (!words.length && (lat == null || lng == null)) return null;
  return { name, words, lat, lng, radius_m: radius };
}

/** Stored value (or nothing) → the full settings, defaults filled in. */
export function normalizeSharing(v) {
  v = v && typeof v === 'object' ? v : {};
  const byId = new Map();
  for (const d of DEFAULT_AUDIENCES) byId.set(d.id, cleanAudience({ ...d, clock: zeroClock() }));
  for (const raw of Array.isArray(v.audiences) ? v.audiences : []) {
    const a = cleanAudience(raw);
    if (a) byId.set(a.id, a);
  }
  const pp = v.private_places && typeof v.private_places === 'object' ? v.private_places : {};
  return {
    audiences: [...byId.values()].slice(0, MAX_AUDIENCES),
    private_places: {
      value: (Array.isArray(pp.value) ? pp.value : []).map(cleanPlace).filter(Boolean).slice(0, MAX_PLACES),
      clock: Number.isFinite(pp.clock) ? pp.clock : 0,
    },
  };
}

function clockFor(given, now) {
  if (!Number.isFinite(given)) return now;
  return Math.min(Math.round(given), now + MAX_FUTURE_MS);
}

/**
 * Applies a patch: { audiences?: [{ id, kind?, name?, rank?, location?, color?,
 * deleted_at?, clock? }], private_places?: { value, clock? } }. `clock` is per field
 * ({ name: ms, … }) or one number; missing = now (web edits). A new id is created
 * (its kind is fixed from then on). Returns { sharing, changed }.
 */
export function mergeSharing(current, patch, now = Date.now()) {
  const next = normalizeSharing(current);
  const byId = new Map(next.audiences.map((a) => [a.id, a]));
  let changed = false;

  for (const raw of Array.isArray(patch?.audiences) ? patch.audiences : []) {
    if (!raw || typeof raw.id !== 'string') continue;
    const id = raw.id.toLowerCase();
    if (!ID_RE.test(id)) continue;
    let a = byId.get(id);
    if (!a) {
      if (byId.size >= MAX_AUDIENCES) continue;
      a = cleanAudience({ id, kind: raw.kind, location: 'hidden' });
      byId.set(id, a);
      next.audiences.push(a);
      changed = true;
    }
    const clocks = typeof raw.clock === 'number' ? Object.fromEntries(AUDIENCE_FIELDS.map((f) => [f, raw.clock])) : (raw.clock || {});
    for (const f of AUDIENCE_FIELDS) {
      if (!(f in raw)) continue;
      const value = fieldValue(a, f, raw[f]);
      if (value === undefined) continue;
      const at = clockFor(clocks[f], now);
      if (at <= a.clock[f]) continue;
      a.clock[f] = at;
      a[f] = value;
      changed = true; // a newer clock is worth saving even when the value is the same
    }
  }

  if (patch?.private_places && Array.isArray(patch.private_places.value)) {
    const at = clockFor(patch.private_places.clock, now);
    if (at > next.private_places.clock) {
      next.private_places = {
        value: patch.private_places.value.map(cleanPlace).filter(Boolean).slice(0, MAX_PLACES),
        clock: at,
      };
      changed = true;
    }
  }
  return { sharing: next, changed };
}

function fieldValue(a, f, v) {
  switch (f) {
    case 'name': return typeof v === 'string' && v.trim() ? v.trim().slice(0, MAX_NAME) : undefined;
    case 'rank': return a.kind === 'circle' && Number.isInteger(v) && v > 0 ? v : undefined;
    case 'location': return LOCATIONS.includes(v) ? v : undefined;
    case 'color': return v === null || (typeof v === 'string' && COLOR_RE.test(v)) ? (v && v.toLowerCase()) : undefined;
    case 'deleted_at': return v === null || Number.isFinite(v) ? v : undefined;
    default: return undefined;
  }
}

/** Live (not deleted) audiences, circles first by rank, then lists by name. */
export function liveAudiences(sharing) {
  return sharing.audiences
    .filter((a) => a.deleted_at == null)
    .sort((x, y) => (x.kind === y.kind ? (x.kind === 'circle' ? x.rank - y.rank : x.name.localeCompare(y.name)) : x.kind === 'circle' ? -1 : 1));
}

/**
 * Does a link for `audienceId` show an item shared with `itemAudiences`?
 * Yes when the item lists that audience, or when the audience is a circle and the
 * item's circle is the same or further out (higher rank). Deleted or unknown
 * audiences count for nothing, so an old id left on an item never leaks it.
 */
export function isVisible(itemAudiences, audienceId, sharing) {
  if (!Array.isArray(itemAudiences) || !itemAudiences.length) return false;
  const live = new Map(sharing.audiences.filter((a) => a.deleted_at == null).map((a) => [a.id, a]));
  const target = live.get(audienceId);
  if (!target) return false;
  for (const id of itemAudiences) {
    const a = live.get(id);
    if (!a) continue;
    if (a.id === target.id) return true;
    if (target.kind === 'circle' && a.kind === 'circle' && a.rank >= target.rank) return true;
  }
  return false;
}

/** Audience ids whose items a link for `audienceId` shows (for an IN (...) query). */
export function visibleAudienceIds(audienceId, sharing) {
  const live = sharing.audiences.filter((a) => a.deleted_at == null);
  const target = live.find((a) => a.id === audienceId);
  if (!target) return [];
  if (target.kind !== 'circle') return [target.id];
  return live.filter((a) => a.kind === 'circle' && a.rank >= target.rank).map((a) => a.id);
}

/**
 * The place line a viewer sees. `precision` is the audience's location setting.
 * Text places only for now ("Cafe, Area, City, Country"): city = the last two
 * comma parts. Anything matching a private place is hidden at every precision.
 */
export function viewerLocation(location, precision, privatePlaces = []) {
  if (typeof location !== 'string' || !location.trim() || precision === 'hidden') return null;
  const lower = location.toLowerCase();
  for (const p of privatePlaces) if ((p.words || []).some((w) => lower.includes(w))) return null;
  if (precision === 'exact') return location.trim();
  const parts = location.split(',').map((s) => s.trim()).filter(Boolean);
  return parts.slice(-2).join(', ') || null;
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

const enc = new TextEncoder();

function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function hmacKey(secret) {
  return crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
}

/** The URL token of a link: 128 bits of HMAC(secret, "<id>:<version>"), 22 chars.
 *  Recomputable, so only its hash is stored and the owner can still copy it. */
export async function linkToken(secret, id, version) {
  const sig = await crypto.subtle.sign('HMAC', await hmacKey(secret), enc.encode(`${id}:${version}`));
  return b64url(new Uint8Array(sig).slice(0, 16));
}

export async function hashToken(token) {
  const d = await crypto.subtle.digest('SHA-256', enc.encode(token));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** SHARE_SECRET from `wrangler secret put`, else one the Worker made and kept in D1. */
export async function shareSecret(env) {
  if (env.SHARE_SECRET) return env.SHARE_SECRET;
  const row = await env.DB.prepare("SELECT value FROM app_secrets WHERE name = 'share_links'").first();
  if (row?.value) return row.value;
  const fresh = b64url(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB.prepare("INSERT INTO app_secrets (name, value, created_at) VALUES ('share_links', ?, ?) ON CONFLICT(name) DO NOTHING")
    .bind(fresh, Date.now()).run();
  const again = await env.DB.prepare("SELECT value FROM app_secrets WHERE name = 'share_links'").first();
  return again.value;
}

// ---------------------------------------------------------------------------
// Share-link filters
// ---------------------------------------------------------------------------

const MAX_FILTER_LIST = 20;
const strList = (v, max = 80) =>
  (Array.isArray(v) ? v : []).filter((s) => typeof s === 'string' && s.trim()).map((s) => s.trim().slice(0, max)).slice(0, MAX_FILTER_LIST);
const isoDay = (v) => (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v) && !Number.isNaN(Date.parse(v)) ? v.slice(0, 10) : undefined);

/** A link's filter, narrowing its audience: { kinds, tags, collection, project, from, to }. */
export function cleanFilter(f) {
  f = f && typeof f === 'object' ? f : {};
  const out = {};
  const kinds = strList(f.kinds, 32).map((k) => k.toLowerCase());
  if (kinds.length) out.kinds = kinds;
  const tags = strList(f.tags).map((t) => t.toLowerCase());
  if (tags.length) out.tags = tags;
  if (typeof f.collection === 'string' && f.collection.trim()) out.collection = f.collection.trim().slice(0, 120);
  if (typeof f.project === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(f.project)) out.project = f.project;
  const from = isoDay(f.from), to = isoDay(f.to);
  if (from) out.from = from;
  if (to) out.to = to;
  return out;
}
