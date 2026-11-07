// Minimal D1-shaped wrapper over node:sqlite, for unit tests of src/lib/sync.js.
import { DatabaseSync } from 'node:sqlite';

export function makeD1(schemaSql) {
  const raw = new DatabaseSync(':memory:');
  raw.exec(schemaSql);
  const prep = (sql) => {
    const bound = { sql, args: [] };
    const api = {
      bind: (...args) => {
        // Same limit as D1, so tests catch statements that would fail there.
        if (args.length > 100) throw new Error(`D1_ERROR: too many SQL variables (${args.length})`);
        bound.args = args;
        return api;
      },
      all: async () => ({ results: raw.prepare(sql).all(...bound.args) }),
      first: async () => raw.prepare(sql).get(...bound.args) ?? null,
      run: async () => runOne(bound),
      _bound: bound,
    };
    return api;
  };
  const runOne = ({ sql, args }) => {
    const info = raw.prepare(sql).run(...args);
    return { meta: { changes: Number(info.changes) } };
  };
  return {
    raw,
    prepare: prep,
    batch: async (stmts) => {
      raw.exec('BEGIN');
      try {
        const out = stmts.map((s) => runOne(s._bound));
        raw.exec('COMMIT');
        return out;
      } catch (e) {
        raw.exec('ROLLBACK');
        throw e;
      }
    },
  };
}

// Step 1's items/users shape (0001_init.sql), reduced to what sync touches.
export const SCHEMA = `
CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT, sync_seq INTEGER NOT NULL DEFAULT 0);
CREATE TABLE items (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL, slug TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
  source_url TEXT, domain TEXT, author TEXT, summary TEXT, body_markdown TEXT,
  status TEXT DEFAULT 'active', needs_review INTEGER DEFAULT 1, kind TEXT NOT NULL DEFAULT 'link',
  enrichment_status TEXT DEFAULT 'pending', added_at TEXT, analyzed_at TEXT, updated_at INTEGER,
  cover_aspect REAL NOT NULL DEFAULT 0, metadata TEXT, tags TEXT DEFAULT '[]', images TEXT DEFAULT '[]',
  snippets TEXT DEFAULT '[]', seq INTEGER NOT NULL DEFAULT 0, field_clock TEXT, deleted_at INTEGER,
  purged_at INTEGER
);
CREATE INDEX idx_items_user_seq ON items(user_id, seq);
INSERT INTO users (id, email) VALUES ('u1', 'a@example.com'), ('u2', 'b@example.com');
`;
