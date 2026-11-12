/**
 * The signed-in user's profile (name, designation, photo), shared by the web Settings
 * panel and the Apple apps' preferences header. Stored in user_settings under
 * `profile` as { name, designation, avatar_path, clock }.
 *
 * `clock` is { name, designation, avatar } in epoch ms: when each field last changed.
 * A write keeps, field by field, whichever side changed it last (ties keep the server
 * value), the same rule as items in src/lib/sync.js. Values saved before clocks existed
 * have clock 0, so any dated write wins over them.
 */
const MAX_TEXT = 80;
const MAX_FUTURE_MS = 5 * 60 * 1000;
const FIELDS = ['name', 'designation', 'avatar'];

function normalize(v) {
  v = v && typeof v === 'object' ? v : {};
  const c = v.clock && typeof v.clock === 'object' ? v.clock : {};
  const clock = {};
  for (const f of FIELDS) clock[f] = Number.isFinite(c[f]) ? c[f] : 0;
  return {
    name: typeof v.name === 'string' ? v.name : '',
    designation: typeof v.designation === 'string' ? v.designation : '',
    avatar_path: typeof v.avatar_path === 'string' && v.avatar_path ? v.avatar_path : null,
    clock,
  };
}

/** Clock for one field of a write: the caller's (clamped to now + 5 min) or now. */
function clockFor(given, now) {
  if (!Number.isFinite(given)) return now;
  return Math.min(Math.round(given), now + MAX_FUTURE_MS);
}

/**
 * Applies `patch` ({ name?, designation?, avatar_path? }; avatar_path null removes the
 * photo) with optional per-field `clock` ({ name?, designation?, avatar? }, or one
 * number for all). Returns { profile, changed }.
 */
function mergeProfile(current, patch, clock, now = Date.now()) {
  const next = normalize(current);
  const clocks = typeof clock === 'number' ? { name: clock, designation: clock, avatar: clock } : (clock || {});
  let changed = false;
  for (const f of ['name', 'designation']) {
    if (typeof patch[f] !== 'string') continue;
    const at = clockFor(clocks[f], now);
    if (at <= next.clock[f]) continue;
    next[f] = patch[f].trim().slice(0, MAX_TEXT);
    next.clock[f] = at;
    changed = true;
  }
  if ('avatar_path' in patch) {
    const at = clockFor(clocks.avatar, now);
    if (at > next.clock.avatar) {
      next.avatar_path = patch.avatar_path || null;
      next.clock.avatar = at;
      changed = true;
    }
  }
  return { profile: next, changed };
}

module.exports = { normalize, mergeProfile, MAX_TEXT, MAX_FUTURE_MS };
