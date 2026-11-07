/**
 * Two-copy sync: the merge rules shared by the Apple bridge (/api/sync/push) and
 * every web write. See docs/plans/apple-web-sync.md.
 *
 * Each item row carries:
 *   seq          per-user change counter; "what changed since N" = seq > N
 *   field_clock  JSON {field: epoch ms}, when each field last changed
 *   deleted_at   soft delete (a field like any other, with its own clock)
 *   purged_at    set once the 30-day restore window has passed and content is cleared
 *
 * A write keeps, field by field, whichever side changed it last. Writes whose value
 * already matches are dropped without bumping seq, so echoes settle after one round.
 */

// Table/column names in one place, so step 1's final schema is a one-line change.
export const T = {
  items: 'items',
  users: 'users',
  userSeq: 'sync_seq',
};

/** Synced fields → storage type. Anything else in a change is ignored. */
export const FIELDS = {
  slug: 'text',
  title: 'text',
  source_url: 'text',
  domain: 'text',
  author: 'text',
  summary: 'text',
  body_markdown: 'text',
  status: 'text',
  needs_review: 'bool',
  kind: 'text',
  enrichment_status: 'text',
  added_at: 'iso', // ISO-8601 text, as in the Supabase export
  analyzed_at: 'iso',
  cover_aspect: 'real',
  metadata: 'json',
  tags: 'json',
  images: 'json',
  snippets: 'json',
  deleted_at: 'int',
};

const FIELD_NAMES = Object.keys(FIELDS);
export const MAX_PUSH = 100; // ids are read back in chunks of READ_CHUNK (D1: ≤100 bound values per statement)
export const MAX_PULL = 500;
export const MAX_FUTURE_MS = 5 * 60 * 1000;
export const RESTORE_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/** JSON with sorted object keys, so equal values always compare equal. */
export function stableStringify(value) {
  if (value === undefined) return 'null';
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(stableStringify).join(',') + ']';
  const keys = Object.keys(value).filter((k) => value[k] !== undefined).sort();
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + stableStringify(value[k])).join(',') + '}';
}

/** API value → D1 value. Returns undefined for a value of the wrong type. */
export function toDb(field, value) {
  if (value === null || value === undefined) {
    return field === 'title' || field === 'slug' ? '' : null;
  }
  switch (FIELDS[field]) {
    case 'text': return typeof value === 'string' ? value : undefined;
    case 'iso': return typeof value === 'string' && !Number.isNaN(Date.parse(value)) ? value : undefined;
    case 'bool': return typeof value === 'boolean' ? (value ? 1 : 0) : undefined;
    case 'int': return Number.isFinite(value) ? Math.round(value) : undefined;
    case 'real': return Number.isFinite(value) ? value : undefined;
    case 'json': return typeof value === 'object' ? stableStringify(value) : undefined;
    default: return undefined;
  }
}

/** D1 value → API value. */
export function fromDb(field, value) {
  if (value === null || value === undefined) return FIELDS[field] === 'json' ? defaultJson(field) : null;
  switch (FIELDS[field]) {
    case 'bool': return !!value;
    case 'json':
      try { return JSON.parse(value); } catch { return defaultJson(field); }
    default: return value;
  }
}

function defaultJson(field) {
  return field === 'metadata' ? null : [];
}

function parseClock(text) {
  if (!text) return {};
  try {
    const c = JSON.parse(text);
    return c && typeof c === 'object' ? c : {};
  } catch { return {}; }
}

/** A row as the API returns it (pull and push replies). */
export function rowToApi(row) {
  const out = { id: row.id, seq: row.seq, clock: parseClock(row.field_clock) };
  for (const f of FIELD_NAMES) out[f] = fromDb(f, row[f]);
  out.purged = row.purged_at != null;
  return out;
}

// ---------------------------------------------------------------------------
// Merge (pure)
// ---------------------------------------------------------------------------

/**
 * Decide what one incoming change does to one stored row.
 *
 * change: { id, fields: {field: value}, clock: {field: ms} | ms, full?: bool }
 *   `clock` may be one number for every field (web writes, first link-up).
 *   `full` marks a complete item; only a full change may create a row.
 * row: the stored D1 row, or null.
 *
 * Returns { status, write?: {field: dbValue}, clock?: {...} }
 *   status: 'applied' | 'unchanged' | 'needs_full' | 'invalid' | 'purged'
 */
export function mergeChange(row, change, now = Date.now()) {
  if (!change || typeof change.id !== 'string' || !UUID_RE.test(change.id)) return { status: 'invalid' };
  const fields = change.fields && typeof change.fields === 'object' ? change.fields : {};
  if (!row && !change.full) return { status: 'needs_full' };
  if (row && row.purged_at != null) return { status: 'purged' };

  const stored = row ? parseClock(row.field_clock) : {};
  const nextClock = { ...stored };
  const write = {};

  for (const field of Object.keys(fields)) {
    if (!(field in FIELDS)) continue;
    let incoming = typeof change.clock === 'number' ? change.clock : change.clock?.[field];
    if (!Number.isFinite(incoming)) continue;
    incoming = Math.min(Math.round(incoming), now + MAX_FUTURE_MS);
    const dbValue = toDb(field, fields[field]);
    if (dbValue === undefined) continue;
    const current = row ? row[field] : undefined;

    if (row && incoming <= (stored[field] ?? 0)) continue; // server's is newer (or a tie)
    if (row && sameValue(field, current, dbValue)) continue; // echo: nothing new
    write[field] = dbValue;
    nextClock[field] = incoming;
  }

  if (!row) {
    if (write.slug === undefined || write.slug === '') write.slug = change.id;
    if (write.title === undefined) write.title = '';
    if (write.added_at === undefined) write.added_at = new Date(now).toISOString(); // NOT NULL in 0001
  }
  if (Object.keys(write).length === 0) return { status: 'unchanged' };
  return { status: 'applied', write, clock: nextClock };
}

function sameValue(field, a, b) {
  if (a === undefined) return false;
  if ((a ?? null) === (b ?? null)) return true;
  if (FIELDS[field] === 'json' && a != null && b != null) {
    try { return stableStringify(JSON.parse(a)) === b; } catch { return false; }
  }
  return false;
}

// ---------------------------------------------------------------------------
// D1
// ---------------------------------------------------------------------------

/**
 * Apply up to MAX_PUSH changes for one user. Used by /api/sync/push and, with a
 * single change and clock = now, by every web write.
 *
 * Seq numbers are assigned inside the same D1 batch (one transaction) as the
 * writes, so commit order and seq order always agree and a puller never skips one.
 * Updates are guarded on the seq they were merged against; a row that moved in
 * between is merged again (up to 3 tries).
 */
export async function applyChanges(db, userId, changes, now = Date.now()) {
  if (!Array.isArray(changes)) throw new SyncError(400, 'changes must be an array');
  if (changes.length > MAX_PUSH) throw new SyncError(413, `at most ${MAX_PUSH} changes per push`);

  const results = new Map();
  let pending = changes.filter((c) => {
    if (!c || typeof c.id !== 'string' || !UUID_RE.test(c.id)) {
      results.set(String(c?.id), { id: c?.id ?? null, status: 'invalid' });
      return false;
    }
    return true;
  });
  // Last change for an id wins inside one push (the client should never send two).
  pending = [...new Map(pending.map((c) => [c.id.toLowerCase(), { ...c, id: c.id.toLowerCase() }])).values()];

  for (let attempt = 0; attempt < 3 && pending.length; attempt++) {
    const rows = await readRows(db, userId, pending.map((c) => c.id));
    const plans = [];
    for (const change of pending) {
      const row = rows.get(change.id) || null;
      const merged = mergeChange(row, change, now);
      if (merged.status !== 'applied') {
        results.set(change.id, { id: change.id, status: merged.status });
      } else {
        plans.push({ change, row, merged });
      }
    }
    pending = [];
    if (!plans.length) break;

    const n = plans.length;
    const stmts = [
      db.prepare(`UPDATE ${T.users} SET ${T.userSeq} = ${T.userSeq} + ? WHERE id = ?`).bind(n, userId),
    ];
    plans.forEach((p, i) => stmts.push(writeStatement(db, userId, p, n - 1 - i)));
    const out = await db.batch(stmts);

    plans.forEach((p, i) => {
      const changed = out[i + 1]?.meta?.changes ?? 0;
      if (changed > 0) results.set(p.change.id, { id: p.change.id, status: 'applied' });
      else pending.push(p.change); // row moved since we read it (or another user owns the id)
    });
  }
  for (const c of pending) results.set(c.id, { id: c.id, status: 'conflict' });

  const cursor = await headSeq(db, userId);
  return { results: [...results.values()], cursor };
}

function writeStatement(db, userId, { change, row, merged }, offset) {
  const seqExpr = `(SELECT ${T.userSeq} FROM ${T.users} WHERE id = ?) - ?`;
  const cols = Object.keys(merged.write);
  const vals = cols.map((c) => merged.write[c]);
  const clock = JSON.stringify(merged.clock);
  if (!row) {
    const names = ['id', 'user_id', ...cols, 'field_clock', 'updated_at', 'seq'];
    const marks = names.slice(0, -1).map(() => '?').concat(seqExpr);
    return db
      .prepare(`INSERT INTO ${T.items} (${names.join(', ')}) VALUES (${marks.join(', ')}) ON CONFLICT(id) DO NOTHING`)
      .bind(change.id, userId, ...vals, clock, Date.now(), userId, offset);
  }
  const sets = cols.map((c) => `${c} = ?`).concat('field_clock = ?', `seq = ${seqExpr}`, 'updated_at = ?');
  return db
    .prepare(`UPDATE ${T.items} SET ${sets.join(', ')} WHERE id = ? AND user_id = ? AND seq = ?`)
    .bind(...vals, clock, userId, offset, Date.now(), change.id, userId, row.seq);
}

// D1 allows at most 100 bound values per statement; user_id takes one.
const READ_CHUNK = 50;

async function readRows(db, userId, ids) {
  const rows = new Map();
  for (let i = 0; i < ids.length; i += READ_CHUNK) {
    const chunk = ids.slice(i, i + READ_CHUNK);
    const marks = chunk.map(() => '?').join(', ');
    const { results } = await db
      .prepare(`SELECT * FROM ${T.items} WHERE user_id = ? AND id IN (${marks})`)
      .bind(userId, ...chunk)
      .all();
    for (const r of results || []) rows.set(r.id, r);
  }
  return rows;
}

export async function headSeq(db, userId) {
  const row = await db.prepare(`SELECT ${T.userSeq} AS s FROM ${T.users} WHERE id = ?`).bind(userId).first();
  return row?.s ?? 0;
}

/** Rows changed after `since`, oldest first. Includes tombstones. */
export async function pullChanges(db, userId, since, limit = MAX_PULL) {
  const n = Math.min(Math.max(parseInt(limit, 10) || MAX_PULL, 1), MAX_PULL);
  const after = Math.max(parseInt(since, 10) || 0, 0);
  const { results } = await db
    .prepare(`SELECT * FROM ${T.items} WHERE user_id = ? AND seq > ? ORDER BY seq LIMIT ?`)
    .bind(userId, after, n)
    .all();
  const items = (results || []).map(rowToApi);
  const cursor = items.length ? items[items.length - 1].seq : after;
  return { items, cursor, more: items.length === n };
}

/** Soft delete (web Trash) or restore, through the same merge as everything else. */
export function deleteChange(id, now = Date.now()) {
  return { id, fields: { deleted_at: now }, clock: now };
}
export function restoreChange(id, now = Date.now()) {
  return { id, fields: { deleted_at: null }, clock: now };
}

/**
 * Clears content of items deleted more than 30 days ago, keeping a tombstone row
 * (id + deleted_at + seq) so an offline device can't bring them back. Returns the
 * R2 image paths that are no longer referenced, for the caller to delete.
 */
export async function purgeExpired(db, now = Date.now()) {
  const cutoff = now - RESTORE_WINDOW_MS;
  const { results } = await db
    .prepare(`SELECT id, user_id, images FROM ${T.items} WHERE deleted_at IS NOT NULL AND deleted_at < ? AND purged_at IS NULL LIMIT 500`)
    .bind(cutoff)
    .all();
  if (!results?.length) return { purged: 0, imagePaths: [] };
  const imagePaths = [];
  for (const r of results) {
    for (const img of fromDb('images', r.images) || []) if (img?.path) imagePaths.push(img.path);
  }
  const stmts = results.map((r) =>
    db
      .prepare(
        `UPDATE ${T.items} SET title = '', summary = NULL, body_markdown = NULL, author = NULL,
         metadata = NULL, tags = '[]', images = '[]', snippets = '[]', purged_at = ? WHERE id = ?`,
      )
      .bind(now, r.id),
  );
  await db.batch(stmts);
  return { purged: results.length, imagePaths };
}

/**
 * Gzipped JSON snapshot of one user's library (every row, tombstones included),
 * written to R2 at snapshots/<user>/<YYYY-MM-DD>.json.gz. Pages through D1 so a
 * 10k library never sits in memory as one string.
 */
export async function writeSnapshot(db, bucket, userId, now = new Date()) {
  const gzip = new CompressionStream('gzip');
  const writer = gzip.writable.getWriter();
  const chunks = [];
  const reading = (async () => {
    const reader = gzip.readable.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }
  })();
  const enc = new TextEncoder();
  await writer.write(enc.encode(`{"user_id":${JSON.stringify(userId)},"taken_at":${now.getTime()},"items":[`));
  let since = -1;
  let first = true;
  let count = 0;
  for (;;) {
    const { results } = await db
      .prepare(`SELECT * FROM ${T.items} WHERE user_id = ? AND seq > ? ORDER BY seq LIMIT 500`)
      .bind(userId, since)
      .all();
    if (!results?.length) break;
    for (const r of results) {
      await writer.write(enc.encode((first ? '' : ',') + JSON.stringify(rowToApi(r))));
      first = false;
      count++;
    }
    since = results[results.length - 1].seq;
    if (results.length < 500) break;
  }
  await writer.write(enc.encode(']}'));
  await writer.close();
  await reading;
  const body = new Blob(chunks);
  const key = `snapshots/${userId}/${now.toISOString().slice(0, 10)}.json.gz`;
  await bucket.put(key, body, { httpMetadata: { contentType: 'application/json', contentEncoding: 'gzip' } });
  return { key, count, bytes: body.size };
}

/** Deletes snapshots older than 30 days for one user. */
export async function pruneSnapshots(bucket, userId, now = Date.now()) {
  const cutoff = new Date(now - RESTORE_WINDOW_MS).toISOString().slice(0, 10);
  const listed = await bucket.list({ prefix: `snapshots/${userId}/` });
  const old = listed.objects.map((o) => o.key).filter((k) => k.split('/').pop().slice(0, 10) < cutoff);
  if (old.length) await bucket.delete(old);
  return old.length;
}

export class SyncError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
