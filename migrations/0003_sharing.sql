-- Audience sharing (docs/plans/audience-sharing.md), applied by src/lib/schema.js
-- after 0001 and 0002. Every statement is idempotent.
--
-- Audiences and private places live in user_settings (key 'sharing'), synced to
-- the Apple apps like the profile. Each item lists its audiences in
-- items.audiences (a synced JSON field, see src/lib/sync.js). Share links live
-- only here: the Apple apps read and write them through /api/share-links.

CREATE TABLE IF NOT EXISTS share_links (
  id             TEXT PRIMARY KEY,                -- UUID
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  audience_id    TEXT NOT NULL,
  label          TEXT NOT NULL DEFAULT '',
  filter         TEXT NOT NULL DEFAULT '{}',      -- JSON: kinds, tags, collection, project, from, to
  token_hash     TEXT NOT NULL,                   -- SHA-256 of the current token
  token_version  INTEGER NOT NULL DEFAULT 1,      -- bump = rotate (old URL stops working)
  expires_at     INTEGER,                         -- epoch ms, null = never
  revoked_at     INTEGER,                         -- epoch ms
  view_count     INTEGER NOT NULL DEFAULT 0,
  last_viewed_at INTEGER,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_share_links_token ON share_links(token_hash);
CREATE INDEX IF NOT EXISTS idx_share_links_user ON share_links(user_id, created_at);

-- Server-side secrets the Worker makes for itself (the share-link token key when
-- no SHARE_SECRET is set with `wrangler secret put`).
CREATE TABLE IF NOT EXISTS app_secrets (
  name       TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
