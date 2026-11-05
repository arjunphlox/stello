-- Stello auth on Cloudflare D1 (replaces Supabase Auth).
-- Apply: npx wrangler d1 migrations apply stello --remote

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,            -- UUID; reuses the old Supabase user id when migrated
  email         TEXT,
  display_name  TEXT,
  apple_sub     TEXT UNIQUE,                 -- Sign in with Apple subject (stable per Apple team)
  created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX IF NOT EXISTS users_email ON users (lower(email));

CREATE TABLE IF NOT EXISTS passkeys (
  id             TEXT PRIMARY KEY,           -- UUID
  user_id        TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  credential_id  TEXT NOT NULL UNIQUE,       -- base64url WebAuthn credential id
  public_key     BLOB NOT NULL,              -- COSE public key
  counter        INTEGER NOT NULL DEFAULT 0,
  transports     TEXT,                       -- JSON array
  friendly_name  TEXT,
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  last_used_at   TEXT
);
CREATE INDEX IF NOT EXISTS passkeys_user ON passkeys (user_id);

-- Opaque session tokens; only the SHA-256 is stored.
CREATE TABLE IF NOT EXISTS sessions (
  token_hash  TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  client      TEXT NOT NULL DEFAULT 'web',   -- web | native
  created_at  INTEGER NOT NULL,              -- unix seconds
  expires_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions (user_id);

-- Short-lived WebAuthn challenges (5 minutes).
CREATE TABLE IF NOT EXISTS auth_challenges (
  id          TEXT PRIMARY KEY,
  challenge   TEXT NOT NULL,
  kind        TEXT NOT NULL,                 -- register | login
  user_id     TEXT,
  expires_at  INTEGER NOT NULL
);
