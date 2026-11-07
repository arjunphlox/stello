-- Stello on Cloudflare D1 (SQLite). Replaces Supabase Postgres + Auth.
-- Applied automatically by the Worker (src/lib/schema.js runs these
-- idempotent statements once per isolate), so no `wrangler d1 migrations`
-- step is needed. Keep this file and schema.js in step.
--
-- Conventions
--   * ids are TEXT UUIDs. Item ids are the old Supabase UUIDs (the Apple app
--     uses the same ids, so app<->web sync matches rows by id).
--   * JSON columns (tags, images, snippets, …) are TEXT holding JSON.
--   * updated_at / deleted_at / created_at on auth + sync tables are epoch ms.
--     added_at / analyzed_at stay ISO-8601 strings (the frontend reads them).
--   * Every item write bumps users.sync_seq and stamps items.seq with the new
--     value (src/lib/db.js does it), so sync can ask "what changed after N".

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  email         TEXT UNIQUE COLLATE NOCASE,
  display_name  TEXT,
  password_hash TEXT,                          -- pbkdf2$sha256$iter$salt$hash, null = no password
  sync_seq      INTEGER NOT NULL DEFAULT 0,     -- per-user change counter
  created_at    INTEGER NOT NULL
);

-- One row per way to sign in. provider 'apple' → subject is Apple's stable
-- user id (`sub`), never the email (Hide My Email can change).
CREATE TABLE IF NOT EXISTS identities (
  provider   TEXT NOT NULL,
  subject    TEXT NOT NULL,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email      TEXT,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (provider, subject)
);
CREATE INDEX IF NOT EXISTS idx_identities_user ON identities(user_id);

-- Web sessions (cookie) and device tokens (bearer, for the Apple apps).
-- Only the SHA-256 of the token is stored.
CREATE TABLE IF NOT EXISTS sessions (
  token_hash   TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL DEFAULT 'web',     -- 'web' | 'device'
  label        TEXT,
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER,
  expires_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

-- Short-lived OAuth state for Sign in with Apple (web redirect flow).
CREATE TABLE IF NOT EXISTS auth_states (
  state      TEXT PRIMARY KEY,
  nonce      TEXT NOT NULL,
  mode       TEXT NOT NULL DEFAULT 'login',     -- 'login' | 'link'
  user_id    TEXT,                              -- set when mode = 'link'
  return_to  TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS items (
  id                    TEXT PRIMARY KEY,
  user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  slug                  TEXT NOT NULL,
  title                 TEXT NOT NULL DEFAULT '',
  source_url            TEXT,
  domain                TEXT,
  author                TEXT,
  summary               TEXT,
  body_markdown         TEXT,
  og_image_path         TEXT,
  status                TEXT NOT NULL DEFAULT 'active',
  location              TEXT,
  needs_review          INTEGER NOT NULL DEFAULT 1,
  link_last_checked     TEXT,
  added_at              TEXT NOT NULL,
  analyzed_at           TEXT,
  updated_at            INTEGER NOT NULL,
  enrichment_status     TEXT NOT NULL DEFAULT 'pending',
  tags                  TEXT NOT NULL DEFAULT '[]',
  images                TEXT NOT NULL DEFAULT '[]',
  snippets              TEXT NOT NULL DEFAULT '[]',
  enrichment_candidates TEXT NOT NULL DEFAULT '{}',
  enrichment_error      TEXT,
  -- native card kinds (shared with the Apple apps)
  kind                  TEXT,
  metadata              TEXT,                         -- JSON
  cover_aspect          REAL,
  -- sync
  seq                   INTEGER NOT NULL DEFAULT 0,
  field_clock           TEXT NOT NULL DEFAULT '{}',  -- {"title": epoch_ms, …}
  deleted_at            INTEGER,                      -- soft delete; content purged after 30 days
  purged_at             INTEGER,                      -- tombstone: content cleared, row kept
  UNIQUE (user_id, slug)
);
CREATE INDEX IF NOT EXISTS idx_items_user_added ON items(user_id, added_at DESC);
CREATE INDEX IF NOT EXISTS idx_items_user_seq ON items(user_id, seq);
CREATE INDEX IF NOT EXISTS idx_items_enrichment ON items(enrichment_status, added_at);
CREATE INDEX IF NOT EXISTS idx_items_deleted ON items(deleted_at) WHERE deleted_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS user_settings (
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  setting_key   TEXT NOT NULL,
  setting_value TEXT NOT NULL,                   -- JSON
  PRIMARY KEY (user_id, setting_key)
);

CREATE TABLE IF NOT EXISTS batch_jobs (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'pending',
  total_items     INTEGER NOT NULL DEFAULT 0,
  completed_items INTEGER NOT NULL DEFAULT 0,
  failed_items    INTEGER NOT NULL DEFAULT 0,
  urls            TEXT NOT NULL DEFAULT '[]',
  results         TEXT NOT NULL DEFAULT '[]',
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_batch_jobs_status ON batch_jobs(status, created_at);
