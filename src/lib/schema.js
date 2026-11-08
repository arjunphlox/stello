/**
 * Self-applying D1 schema. migrations/0001_init.sql is imported as text
 * (wrangler.jsonc `rules`) and run once per isolate. Every statement is
 * idempotent (IF NOT EXISTS), so a cold start costs one small batch.
 */
import INIT_SQL from '../../migrations/0001_init.sql';

let ready = null;

/** Columns added after 0001 shipped. CREATE TABLE IF NOT EXISTS never adds a
 *  column to a live table, so each one is added here when it's missing. */
export const ADDED_COLUMNS = {
  items: [
    ['last_opened_at', 'TEXT'],              // revisit tracking (Apple: Item.lastOpenedAt)
    ['open_count', 'INTEGER NOT NULL DEFAULT 0'],
  ],
};

async function addMissingColumns(db) {
  for (const [table, cols] of Object.entries(ADDED_COLUMNS)) {
    const { results } = await db.prepare(`PRAGMA table_info(${table})`).all();
    const have = new Set((results || []).map((r) => r.name));
    const missing = cols.filter(([name]) => !have.has(name));
    if (!missing.length) continue;
    await db.batch(missing.map(([name, type]) => db.prepare(`ALTER TABLE ${table} ADD COLUMN ${name} ${type}`)))
      .catch((err) => { if (!/duplicate column/i.test(String(err?.message))) throw err; });
  }
}

export function splitSql(sql) {
  return sql
    .split('\n')
    .filter(l => !l.trim().startsWith('--'))
    .join('\n')
    .split(/;\s*(?:\n|$)/)
    .map(s => s.replace(/--[^\n]*$/gm, '').trim())
    .filter(Boolean);
}

export function ensureSchema(env) {
  if (!env.DB) throw new Error('D1 binding DB is missing (bindings: ' + Object.keys(env).join(',') + ')');
  if (!ready) {
    ready = env.DB.batch(splitSql(INIT_SQL).map(s => env.DB.prepare(s)))
      .then(() => addMissingColumns(env.DB))
      .catch(err => { ready = null; throw err; });
  }
  return ready;
}
