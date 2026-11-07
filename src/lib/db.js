/**
 * A small supabase-js–shaped query builder over Cloudflare D1.
 *
 * The routes were written against `client.from('items').select().eq()…`.
 * Rather than rewrite every handler, this reproduces the subset they use:
 *
 *   from(t) · select(cols) · insert(row|rows) · update(patch) · upsert(row, {onConflict})
 *   delete() · eq · neq · is · not(col,'is',null) · in · gt/gte/lt/lte
 *   order(col,{ascending}) · limit(n) · range(a,b) · single() · maybeSingle()
 *
 * and resolves to `{ data, error }` like supabase-js.
 *
 * What it adds on top, so no route has to remember it:
 *   * Row scoping (the old RLS): a user client (`forUser(env, userId)`) adds
 *     `user_id = ?` to every query on user tables and forces it on inserts.
 *   * Items soft delete: reads/updates skip rows with deleted_at set, and
 *     delete() on items sets deleted_at instead of removing the row.
 *   * Sync bookkeeping on every items write: bumps users.sync_seq, stamps
 *     items.seq with it, sets updated_at (epoch ms) and records per-field
 *     timestamps in items.field_clock.
 *   * JSON columns are stringified on write and parsed on read.
 */

const USER_TABLES = new Set(['items', 'user_settings', 'batch_jobs']);
const JSON_COLS = {
  items: new Set(['tags', 'images', 'snippets', 'enrichment_candidates', 'metadata']),
  user_settings: new Set(['setting_value']),
  batch_jobs: new Set(['urls', 'results']),
};
const BOOL_COLS = { items: new Set(['needs_review']) };
// Bookkeeping columns a caller may not set directly through the builder.
const ITEM_MANAGED = new Set(['seq', 'field_clock', 'updated_at', 'deleted_at', 'purged_at']);
const IDENT = /^[a-z_][a-z0-9_]*$/;

function ident(name) {
  if (!IDENT.test(name)) throw new Error(`bad column name: ${name}`);
  return name;
}

/** Parse a stored JSON value. Tolerates JSON double-encoded as a string. */
function parseJson(v) {
  let out = v;
  for (let i = 0; i < 2 && typeof out === 'string'; i++) {
    try { out = JSON.parse(out); } catch { return out; }
  }
  return out;
}

function encodeValue(table, col, v) {
  if (v === undefined) return undefined;
  if (JSON_COLS[table]?.has(col)) {
    if (v === null) return null;
    if (typeof v === 'string') {
      // Callers often pass JSON.stringify(x). Store it once-encoded.
      const p = parseJson(v);
      return typeof p === 'string' ? JSON.stringify(p) : JSON.stringify(p);
    }
    return JSON.stringify(v);
  }
  if (BOOL_COLS[table]?.has(col)) return v == null ? null : (v ? 1 : 0);
  if (typeof v === 'boolean') return v ? 1 : 0;
  if (v instanceof Date) return v.toISOString();
  if (v !== null && typeof v === 'object') return JSON.stringify(v);
  return v;
}

function decodeRow(table, row) {
  if (!row) return row;
  const out = { ...row };
  for (const c of JSON_COLS[table] || []) if (c in out) out[c] = parseJson(out[c]);
  for (const c of BOOL_COLS[table] || []) if (c in out && out[c] != null) out[c] = !!out[c];
  if (table === 'items') {
    if (typeof out.updated_at === 'number') out.updated_at = new Date(out.updated_at).toISOString();
    if ('field_clock' in out) out.field_clock = parseJson(out.field_clock) || {};
  }
  return out;
}

function nowIso() { return new Date().toISOString(); }

class Query {
  constructor(client, table) {
    this.c = client;
    this.table = ident(table);
    this.op = 'select';
    this.cols = '*';
    this.where = [];
    this.params = [];
    this.orders = [];
    this.lim = null;
    this.off = null;
    this.returning = false;
    this.one = null;          // 'single' | 'maybe'
    this.rows = null;
    this.patch = null;
    this.conflict = null;
  }

  // --- operations ---
  select(cols = '*') {
    const list = String(cols || '*').split(',').map(s => s.trim()).filter(Boolean);
    this.cols = list.length === 0 || list.includes('*') ? '*' : list.map(ident).join(', ');
    if (this.op !== 'select') this.returning = true;
    return this;
  }
  insert(rows) { this.op = 'insert'; this.rows = Array.isArray(rows) ? rows : [rows]; return this; }
  upsert(rows, opts = {}) {
    this.op = 'upsert';
    this.rows = Array.isArray(rows) ? rows : [rows];
    this.conflict = (opts.onConflict || 'id').split(',').map(s => ident(s.trim()));
    return this;
  }
  update(patch) { this.op = 'update'; this.patch = patch || {}; return this; }
  delete() { this.op = 'delete'; return this; }

  // --- filters ---
  _w(sql, ...p) { this.where.push(sql); this.params.push(...p); return this; }
  eq(col, v) { return v === null ? this._w(`${ident(col)} IS NULL`) : this._w(`${ident(col)} = ?`, encodeValue(this.table, col, v)); }
  neq(col, v) { return v === null ? this._w(`${ident(col)} IS NOT NULL`) : this._w(`${ident(col)} != ?`, encodeValue(this.table, col, v)); }
  gt(col, v) { return this._w(`${ident(col)} > ?`, v); }
  gte(col, v) { return this._w(`${ident(col)} >= ?`, v); }
  lt(col, v) { return this._w(`${ident(col)} < ?`, v); }
  lte(col, v) { return this._w(`${ident(col)} <= ?`, v); }
  is(col, v) {
    if (v === null) return this._w(`${ident(col)} IS NULL`);
    return this._w(`${ident(col)} = ?`, v ? 1 : 0);
  }
  not(col, op, v) {
    if (op === 'is' && v === null) return this._w(`${ident(col)} IS NOT NULL`);
    if (op === 'eq') return this._w(`${ident(col)} != ?`, v);
    if (op === 'in') return this._w(`${ident(col)} NOT IN (${v.map(() => '?').join(',')})`, ...v);
    throw new Error(`db.not: unsupported operator ${op}`);
  }
  in(col, values) {
    if (!values.length) return this._w('0');
    return this._w(`${ident(col)} IN (${values.map(() => '?').join(',')})`, ...values);
  }
  order(col, { ascending = true } = {}) { this.orders.push(`${ident(col)} ${ascending ? 'ASC' : 'DESC'}`); return this; }
  limit(n) { this.lim = Math.max(0, parseInt(n, 10) || 0); return this; }
  range(from, to) { this.off = from; this.lim = to - from + 1; return this; }
  single() { this.one = 'single'; return this; }
  maybeSingle() { this.one = 'maybe'; return this; }

  then(resolve, reject) { return this._run().then(resolve, reject); }

  // --- execution ---
  _scope() {
    const where = [...this.where];
    const params = [...this.params];
    if (this.c.userId && USER_TABLES.has(this.table)) {
      where.push('user_id = ?');
      params.push(this.c.userId);
    }
    if (this.table === 'items' && !this.c.includeDeleted) where.push('deleted_at IS NULL');
    return { where, params };
  }

  _whereSql(where) { return where.length ? ` WHERE ${where.join(' AND ')}` : ''; }

  _tail() {
    let s = '';
    if (this.orders.length) s += ` ORDER BY ${this.orders.join(', ')}`;
    if (this.lim != null) s += ` LIMIT ${this.lim}`;
    else if (this.off != null) s += ' LIMIT -1';
    if (this.off != null) s += ` OFFSET ${this.off}`;
    return s;
  }

  async _run() {
    try {
      const data = await this[`_${this.op}`]();
      return this._shape(data);
    } catch (err) {
      console.warn('db error', this.table, this.op, err.message);
      return { data: null, error: { message: err.message } };
    }
  }

  _shape(rows) {
    if (rows === undefined) return { data: null, error: null };
    const decoded = rows.map(r => decodeRow(this.table, r));
    if (this.one) {
      if (decoded.length === 1) return { data: decoded[0], error: null };
      if (decoded.length === 0 && this.one === 'maybe') return { data: null, error: null };
      return {
        data: null,
        error: { code: 'PGRST116', message: decoded.length ? 'Multiple rows returned' : 'No rows found' },
      };
    }
    return { data: decoded, error: null };
  }

  async _select() {
    const { where, params } = this._scope();
    const sql = `SELECT ${this.cols} FROM ${this.table}${this._whereSql(where)}${this._tail()}`;
    const { results } = await this.c.db.prepare(sql).bind(...params).all();
    return results;
  }

  _prepRow(row) {
    const r = {};
    for (const [k, v] of Object.entries(row)) {
      if (v === undefined) continue;
      if (this.table === 'items' && ITEM_MANAGED.has(k) && !this.c.raw) continue;
      r[ident(k)] = encodeValue(this.table, k, v);
    }
    if (this.c.userId && USER_TABLES.has(this.table)) r.user_id = this.c.userId;
    const now = Date.now();
    if ((this.table === 'items' || this.table === 'batch_jobs') && !r.id) r.id = crypto.randomUUID();
    if (this.table === 'items') {
      if (!r.added_at) r.added_at = nowIso();
      if (r.updated_at == null) r.updated_at = now;
      if (!this.c.raw || r.field_clock == null) {
        const clock = {};
        for (const k of Object.keys(r)) if (!['id', 'user_id', 'seq', 'field_clock', 'updated_at', 'deleted_at'].includes(k)) clock[k] = now;
        r.field_clock = JSON.stringify(clock);
      }
    }
    if (this.table === 'batch_jobs') {
      if (!r.created_at) r.created_at = nowIso();
      r.updated_at = nowIso();
    }
    return r;
  }

  async _insert() { return this._write(false); }
  async _upsert() { return this._write(true); }

  async _write(isUpsert) {
    const rows = this.rows.map(r => this._prepRow(r));
    if (!rows.length) return [];
    const stmts = [];
    const db = this.c.db;
    const isItems = this.table === 'items';
    const userIds = isItems ? [...new Set(rows.map(r => r.user_id))] : [];
    for (const uid of userIds) {
      if (!uid) throw new Error('items insert without user_id');
      stmts.push(db.prepare('UPDATE users SET sync_seq = sync_seq + 1 WHERE id = ?').bind(uid));
    }
    const resultIdx = [];
    for (const r of rows) {
      if (isItems && !(this.c.raw && r.seq != null)) {
        r.seq = { sql: '(SELECT sync_seq FROM users WHERE id = ?)', param: r.user_id };
      }
      const cols = Object.keys(r);
      const vals = [];
      const ph = cols.map(c => {
        const v = r[c];
        if (v && typeof v === 'object' && 'sql' in v) { vals.push(v.param); return v.sql; }
        vals.push(v);
        return '?';
      });
      let sql = `INSERT INTO ${this.table} (${cols.join(', ')}) VALUES (${ph.join(', ')})`;
      if (isUpsert) {
        const upd = cols.filter(c => !this.conflict.includes(c) && c !== 'id');
        sql += ` ON CONFLICT (${this.conflict.join(', ')}) DO ` +
          (upd.length ? `UPDATE SET ${upd.map(c => `${c} = excluded.${c}`).join(', ')}` : 'NOTHING');
      }
      if (this.returning) sql += ` RETURNING ${this.cols}`;
      resultIdx.push(stmts.length);
      stmts.push(db.prepare(sql).bind(...vals));
    }
    const out = await db.batch(stmts);
    if (!this.returning) return undefined;
    return resultIdx.flatMap(i => out[i].results || []);
  }

  async _update() {
    const { where, params } = this._scope();
    const isItems = this.table === 'items';
    const sets = [];
    const vals = [];
    const changed = [];
    for (const [k, v] of Object.entries(this.patch)) {
      if (v === undefined) continue;
      if (isItems && ITEM_MANAGED.has(k)) continue;
      if (k === 'id' || k === 'user_id') continue;
      sets.push(`${ident(k)} = ?`);
      vals.push(encodeValue(this.table, k, v));
      changed.push(k);
    }
    if (this.table === 'batch_jobs') { sets.push('updated_at = ?'); vals.push(nowIso()); }
    if (!sets.length) return this.returning ? this._select() : undefined;
    return this._mutate(sets, vals, changed, where, params);
  }

  async _delete() {
    const { where, params } = this._scope();
    if (this.table === 'items') {
      // Soft delete: keep the row (and its images) for 30 days so a sync peer
      // learns about the delete and the user can restore it.
      return this._mutate(['deleted_at = ?'], [Date.now()], ['deleted_at'], where, params);
    }
    let sql = `DELETE FROM ${this.table}${this._whereSql(where)}`;
    if (this.returning) sql += ` RETURNING ${this.cols}`;
    const { results } = await this.c.db.prepare(sql).bind(...params).all();
    return this.returning ? results : undefined;
  }

  /** UPDATE with sync bookkeeping for items. */
  async _mutate(sets, vals, changed, where, params) {
    const db = this.c.db;
    const whereSql = this._whereSql(where);
    if (this.table !== 'items') {
      let sql = `UPDATE ${this.table} SET ${sets.join(', ')}${whereSql}`;
      if (this.returning) sql += ` RETURNING ${this.cols}`;
      const { results } = await db.prepare(sql).bind(...vals, ...params).all();
      return this.returning ? results : undefined;
    }
    const now = Date.now();
    // Only stamp fields whose value really changes (callers often resend
    // unchanged fields). SET expressions see the old row, so `col IS ?`
    // compares old against new.
    const clockVals = [];
    const clockArgs = changed.map((k, i) => {
      clockVals.push(vals[i]);
      return `'$.${k}', CASE WHEN ${k} IS ? THEN COALESCE(json_extract(field_clock, '$.${k}'), 0) ELSE ${now} END`;
    }).join(', ');
    const allSets = [
      ...sets,
      'updated_at = ?',
      `field_clock = json_set(COALESCE(field_clock, '{}'), ${clockArgs})`,
      'seq = (SELECT sync_seq FROM users WHERE users.id = items.user_id)',
    ];
    const bump = db.prepare(
      `UPDATE users SET sync_seq = sync_seq + 1 WHERE id IN (SELECT user_id FROM items${whereSql})`
    ).bind(...params);
    let sql = `UPDATE items SET ${allSets.join(', ')}${whereSql}`;
    // Soft-deleted rows stay invisible to RETURNING callers.
    if (this.returning) sql += ` RETURNING ${this.cols}`;
    const out = await db.batch([bump, db.prepare(sql).bind(...vals, now, ...clockVals, ...params)]);
    return this.returning ? out[1].results : undefined;
  }
}

class Client {
  constructor(db, opts = {}) {
    this.db = db;
    this.userId = opts.userId || null;
    this.includeDeleted = !!opts.includeDeleted;
    this.raw = !!opts.raw;   // migration only: allows setting seq/updated_at/field_clock
  }
  from(table) { return new Query(this, table); }
}

/** Client scoped to one user (row-level isolation). */
function forUser(env, userId) {
  if (!userId) throw new Error('forUser: missing userId');
  return new Client(env.DB, { userId });
}

/** Unscoped client (cron jobs, admin). Still hides soft-deleted items. */
function admin(env, opts = {}) {
  return new Client(env.DB, opts);
}

module.exports = { forUser, admin, Client, parseJson, decodeRow, encodeValue, JSON_COLS };
