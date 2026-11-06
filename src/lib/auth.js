/**
 * Stello accounts on D1 — replaces Supabase Auth.
 *
 * One Stello account (users row) can have several ways in (identities):
 *   - 'email'  → subject = lower-cased email, password hash on users
 *   - 'apple'  → subject = Apple's stable user id (`sub` claim). Never keyed
 *                by email: Hide My Email addresses can change.
 *
 * Sessions: a random 32-byte token. The browser holds it in an HttpOnly
 * cookie; the Apple apps hold a long-lived "device" token sent as a bearer.
 * Only the SHA-256 of a token is stored.
 */

const COOKIE = 'stello_session';
const WEB_TTL_MS = 90 * 24 * 3600 * 1000;
const DEVICE_TTL_MS = 365 * 24 * 3600 * 1000;
const TOUCH_EVERY_MS = 3600 * 1000;
const PBKDF2_ITER = 100000;               // Workers' WebCrypto cap
const APPLE_ISS = 'https://appleid.apple.com';
const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';

const enc = new TextEncoder();

function b64url(bytes) {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlDecode(str) {
  const s = str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4);
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function randomToken(bytes = 32) {
  return b64url(crypto.getRandomValues(new Uint8Array(bytes)));
}
async function sha256(str) {
  return b64url(await crypto.subtle.digest('SHA-256', enc.encode(str)));
}
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---------------------------------------------------------------- passwords

async function pbkdf2(password, salt, iter) {
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: iter }, key, 256);
  return b64url(bits);
}

async function hashPassword(password) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return `pbkdf2$sha256$${PBKDF2_ITER}$${b64url(salt)}$${await pbkdf2(password, salt, PBKDF2_ITER)}`;
}

async function verifyPassword(password, stored) {
  if (!stored || typeof stored !== 'string') return false;
  const [scheme, hash, iter, salt, expected] = stored.split('$');
  if (scheme !== 'pbkdf2' || hash !== 'sha256') return false;
  const got = await pbkdf2(password, b64urlDecode(salt), parseInt(iter, 10));
  return timingSafeEqual(got, expected);
}

// ---------------------------------------------------------------- sessions

async function createSession(env, userId, { kind = 'web', label = null } = {}) {
  const token = randomToken();
  const now = Date.now();
  const ttl = kind === 'device' ? DEVICE_TTL_MS : WEB_TTL_MS;
  await env.DB.prepare(
    `INSERT INTO sessions (token_hash, user_id, kind, label, created_at, last_used_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).bind(await sha256(token), userId, kind, label, now, now, now + ttl).run();
  return { token, expiresAt: now + ttl };
}

async function revokeSession(env, token) {
  if (!token) return;
  await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256(token)).run();
}

function readCookie(header, name) {
  if (!header) return null;
  for (const part of header.split(/;\s*/)) {
    const i = part.indexOf('=');
    if (i > 0 && part.slice(0, i) === name) return decodeURIComponent(part.slice(i + 1));
  }
  return null;
}

/** Token from `Authorization: Bearer …` (apps) or the session cookie (web). */
function tokenFromHeaders(get) {
  const auth = get('authorization') || '';
  if (/^Bearer\s+/i.test(auth)) {
    const t = auth.replace(/^Bearer\s+/i, '').trim();
    if (t && t !== 'undefined' && t !== 'null') return t;
  }
  return readCookie(get('cookie'), COOKIE);
}

/**
 * Resolve the signed-in user for a request. `get(name)` reads a header.
 * Returns { id, email, display_name, sessionKind } or null.
 */
async function userFromHeaders(env, get) {
  const token = tokenFromHeaders(get);
  if (!token) return null;
  const hash = await sha256(token);
  const row = await env.DB.prepare(
    `SELECT s.user_id, s.kind, s.expires_at, s.last_used_at, u.email, u.display_name
       FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = ?`
  ).bind(hash).first();
  if (!row) return null;
  const now = Date.now();
  if (row.expires_at < now) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(hash).run();
    return null;
  }
  if (!row.last_used_at || now - row.last_used_at > TOUCH_EVERY_MS) {
    await env.DB.prepare('UPDATE sessions SET last_used_at = ? WHERE token_hash = ?').bind(now, hash).run();
  }
  return { id: row.user_id, email: row.email, display_name: row.display_name, sessionKind: row.kind };
}

/** For Hono routes: returns the user id or null. */
async function requireUser(c) {
  const user = await userFromHeaders(c.env, (n) => c.req.header(n));
  return user ? user.id : null;
}

function sessionCookie(token, maxAgeMs) {
  const maxAge = Math.floor(maxAgeMs / 1000);
  return `${COOKIE}=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAge}`;
}
function clearCookie() {
  return `${COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
}

// ---------------------------------------------------------------- Apple

let appleKeys = null;          // { keys, fetchedAt }

async function getAppleKey(kid, { refresh = false } = {}) {
  if (refresh || !appleKeys || Date.now() - appleKeys.fetchedAt > 6 * 3600 * 1000) {
    const r = await fetch(APPLE_KEYS_URL);
    if (!r.ok) throw new Error(`Apple keys fetch failed: ${r.status}`);
    appleKeys = { keys: (await r.json()).keys || [], fetchedAt: Date.now() };
  }
  const jwk = appleKeys.keys.find(k => k.kid === kid);
  if (!jwk && !refresh) return getAppleKey(kid, { refresh: true });
  return jwk || null;
}

/**
 * Verify an Apple identity token (JWT, RS256) — used by the web callback and
 * by the Apple apps (native Sign in with Apple posts its identityToken).
 *
 *   audiences: allowed `aud` values (web Services ID, app bundle ids)
 *   nonce:     expected `nonce` claim as-is (web: we send it raw)
 *   rawNonce:  native apps send SHA-256(raw) to Apple; pass the raw value
 *              here and the claim is checked against its SHA-256 hex
 *
 * Returns the claims ({ sub, email, email_verified, is_private_email, … }).
 * Throws on anything invalid.
 */
async function verifyAppleIdentityToken(idToken, { audiences, nonce, rawNonce } = {}) {
  const parts = String(idToken || '').split('.');
  if (parts.length !== 3) throw new Error('malformed token');
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[0])));
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
  if (header.alg !== 'RS256') throw new Error('unexpected alg');
  const jwk = await getAppleKey(header.kid);
  if (!jwk) throw new Error('unknown signing key');
  const key = await crypto.subtle.importKey(
    'jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5', key, b64urlDecode(parts[2]), enc.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) throw new Error('bad signature');
  const now = Math.floor(Date.now() / 1000);
  if (claims.iss !== APPLE_ISS) throw new Error('bad issuer');
  const auds = (audiences || []).filter(Boolean);
  if (!auds.length || !auds.includes(claims.aud)) throw new Error(`bad audience ${claims.aud}`);
  if (typeof claims.exp !== 'number' || claims.exp < now - 60) throw new Error('token expired');
  if (nonce != null && claims.nonce !== nonce) throw new Error('nonce mismatch');
  if (rawNonce != null) {
    const hex = [...new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(rawNonce)))]
      .map(b => b.toString(16).padStart(2, '0')).join('');
    if (claims.nonce !== hex) throw new Error('nonce mismatch');
  }
  if (!claims.sub) throw new Error('no subject');
  return claims;
}

function appleAudiences(env, which = 'all') {
  const web = (env.APPLE_SERVICES_ID || '').trim();
  const apps = (env.APPLE_APP_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
  if (which === 'web') return [web].filter(Boolean);
  if (which === 'app') return apps;
  return [web, ...apps].filter(Boolean);
}

// ---------------------------------------------------------------- accounts

function signupAllowed(env) {
  return String(env.ALLOW_SIGNUP || '').toLowerCase() === 'true';
}

async function findUserByEmail(env, email) {
  if (!email) return null;
  return env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(String(email).trim().toLowerCase()).first();
}

async function createUser(env, { email = null, displayName = null, passwordHash = null, id = null } = {}) {
  const uid = id || crypto.randomUUID();
  const now = Date.now();
  const em = email ? String(email).trim().toLowerCase() : null;
  const stmts = [
    env.DB.prepare(
      'INSERT INTO users (id, email, display_name, password_hash, created_at) VALUES (?, ?, ?, ?, ?)'
    ).bind(uid, em, displayName || em, passwordHash, now),
  ];
  if (em) {
    stmts.push(env.DB.prepare(
      'INSERT OR IGNORE INTO identities (provider, subject, user_id, email, created_at) VALUES (?, ?, ?, ?, ?)'
    ).bind('email', em, uid, em, now));
  }
  await env.DB.batch(stmts);
  return { id: uid, email: em };
}

async function linkIdentity(env, userId, provider, subject, email = null) {
  await env.DB.prepare(
    `INSERT INTO identities (provider, subject, user_id, email, created_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT (provider, subject) DO UPDATE SET email = excluded.email`
  ).bind(provider, subject, userId, email, Date.now()).run();
}

async function userIdForIdentity(env, provider, subject) {
  const row = await env.DB.prepare(
    'SELECT user_id FROM identities WHERE provider = ? AND subject = ?'
  ).bind(provider, subject).first();
  return row ? row.user_id : null;
}

/**
 * Map verified Apple claims to a Stello account:
 *   1. a known Apple `sub` → that account
 *   2. `linkUserId` given (signed-in user pressed "Link Apple ID") → link
 *   3. Apple says the email is verified and it matches an account → link
 *   4. otherwise create a new account (only if sign-up is open)
 * Returns { userId, created, linked } or { error }.
 */
async function resolveAppleAccount(env, claims, { linkUserId = null, displayName = null } = {}) {
  const sub = claims.sub;
  const email = claims.email ? String(claims.email).toLowerCase() : null;
  const known = await userIdForIdentity(env, 'apple', sub);
  if (known) {
    if (linkUserId && known !== linkUserId) return { error: 'This Apple ID is already linked to another Stello account.' };
    return { userId: known, created: false, linked: false };
  }
  if (linkUserId) {
    await linkIdentity(env, linkUserId, 'apple', sub, email);
    return { userId: linkUserId, created: false, linked: true };
  }
  const verified = claims.email_verified === true || claims.email_verified === 'true';
  if (email && verified) {
    const existing = await findUserByEmail(env, email);
    if (existing) {
      await linkIdentity(env, existing.id, 'apple', sub, email);
      return { userId: existing.id, created: false, linked: true };
    }
  }
  if (!signupAllowed(env)) return { error: 'No Stello account matches this Apple ID. Sign in with email first, then link Apple ID in Settings.' };
  const user = await createUser(env, { email: verified && !claims.is_private_email ? email : null, displayName: displayName || email });
  await linkIdentity(env, user.id, 'apple', sub, email);
  return { userId: user.id, created: true, linked: true };
}

module.exports = {
  COOKIE, WEB_TTL_MS, DEVICE_TTL_MS,
  randomToken, sha256,
  hashPassword, verifyPassword,
  createSession, revokeSession, userFromHeaders, requireUser, tokenFromHeaders,
  sessionCookie, clearCookie,
  verifyAppleIdentityToken, appleAudiences,
  signupAllowed, findUserByEmail, createUser, linkIdentity, userIdForIdentity, resolveAppleAccount,
};
