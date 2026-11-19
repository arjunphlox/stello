-- Projects + Figma plugin pairing (applied by src/lib/schema.js after 0001).
-- Every statement is idempotent.

-- One row per canvas doc. `doc` is JSON in the shape documented in
-- src/lib/projects.js. id 'library' is the library canvas (the grid's
-- second view); other ids are named projects (e.g. from FigJam Board sync).
CREATE TABLE IF NOT EXISTS projects (
  id          TEXT NOT NULL,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL DEFAULT '',
  doc         TEXT NOT NULL DEFAULT '{}',
  rev         INTEGER NOT NULL DEFAULT 1,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL,
  deleted_at  TEXT,
  PRIMARY KEY (user_id, id)
);
CREATE INDEX IF NOT EXISTS idx_projects_user_updated ON projects(user_id, updated_at);

-- Short-lived pairing codes: a plugin (Figma) shows a code, the signed-in
-- user approves it on /pair, the plugin polls and receives a device token.
-- Only hashes of the poll secret are stored; the token is handed over once.
CREATE TABLE IF NOT EXISTS device_pairings (
  code        TEXT PRIMARY KEY,
  poll_hash   TEXT NOT NULL,
  label       TEXT NOT NULL DEFAULT 'Figma plugin',
  user_id     TEXT,
  token       TEXT,
  created_at  INTEGER NOT NULL,
  approved_at INTEGER
);
