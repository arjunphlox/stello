/**
 * Self-applying D1 schema. migrations/0001_init.sql is imported as text
 * (wrangler.jsonc `rules`) and run once per isolate. Every statement is
 * idempotent (IF NOT EXISTS), so a cold start costs one small batch.
 */
import INIT_SQL from '../../migrations/0001_init.sql';

let ready = null;

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
  if (!env.DB) throw new Error('D1 binding DB is missing');
  if (!ready) {
    ready = env.DB.batch(splitSql(INIT_SQL).map(s => env.DB.prepare(s)))
      .catch(err => { ready = null; throw err; });
  }
  return ready;
}
