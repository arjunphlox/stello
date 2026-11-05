/**
 * Stello auth on Cloudflare (replaces Supabase Auth).
 *
 * - Users, passkeys, sessions and WebAuthn challenges live in D1 (`env.DB`).
 * - Sessions are opaque random tokens; D1 stores only their SHA-256.
 *   Web gets an HttpOnly cookie, native apps get a bearer token.
 * - Sign in with Apple: ID tokens are verified against Apple's JWKS with
 *   WebCrypto (no Apple client secret needed: we never exchange the code).
 */

export const SESSION_COOKIE = 'stello_session';
const SESSION_TTL = 60 * 24 * 60 * 60;        // 60 days, sliding
const SESSION_RENEW_AFTER = 7 * 24 * 60 * 60; // extend when older than a week
export const CHALLENGE_TTL = 5 * 60;

const enc = new TextEncoder();
const now = () => Math.floor(Date.now() / 1000);

// ---------- encoding helpers ----------

export function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function fromB64url(str) {
  const s = str.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(s + '='.repeat((4 - (s.length % 4)) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export function randomToken(bytes = 32) {
  return b64url(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function sha256Hex(input) {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// ---------- relying party / origins ----------

/** Passkey RP ID + allowed origins for this request (localhost in dev). */
export function relyingParty(env, requestUrl) {
  const url = new URL(requestUrl);
  if (url.hostname === 'localhost' || url.hostname === '127.0.0.1') {
    return { rpID: url.hostname, origins: [url.origin] };
  }
  const rpID = env.RP_ID || url.hostname;
  return { rpID, origins: [`https://${rpID}`] };
}

// ---------- users ----------

export async function getUser(env, id) {
  return env.DB.prepare('SELECT id, email, display_name FROM users WHERE id = ?').bind(id).first();
}

/**
 * Find or create the user for a verified Apple identity. Links by email to
 * an existing user that has no Apple identity yet (e.g. migrated accounts).
 */
export async function upsertAppleUser(env, { sub, email, emailVerified, name }) {
  const bySub = await env.DB.prepare('SELECT id, email, display_name FROM users WHERE apple_sub = ?').bind(sub).first();
  if (bySub) return bySub;

  if (email && emailVerified) {
    const byEmail = await env.DB
      .prepare('SELECT id, email, display_name FROM users WHERE lower(email) = lower(?) AND apple_sub IS NULL')
      .bind(email).first();
    if (byEmail) {
      await env.DB.prepare('UPDATE users SET apple_sub = ? WHERE id = ?').bind(sub, byEmail.id).run();
      return byEmail;
    }
  }

  if (env.ALLOW_SIGNUPS === 'false') {
    throw new AuthError('New accounts are closed.', 403);
  }
  const id = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO users (id, email, display_name, apple_sub) VALUES (?, ?, ?, ?)')
    .bind(id, email || null, name || null, sub).run();
  return { id, email: email || null, display_name: name || null };
}

// ---------- sessions ----------

export async function createSession(env, userId, client = 'web') {
  const token = randomToken();
  const t = now();
  await env.DB.prepare('INSERT INTO sessions (token_hash, user_id, client, created_at, expires_at) VALUES (?, ?, ?, ?, ?)')
    .bind(await sha256Hex(token), userId, client, t, t + SESSION_TTL).run();
  return { token, expiresAt: t + SESSION_TTL };
}

export async function deleteSession(env, token) {
  if (!token) return;
  await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256Hex(token)).run();
}

/** Session token from `Authorization: Bearer` (native) or the session cookie (web). */
export function tokenFromHeaders(headers) {
  const get = (k) => (typeof headers.get === 'function' ? headers.get(k) : headers[k]) || '';
  const bearer = get('authorization').replace(/^Bearer\s+/i, '').trim();
  if (bearer) return bearer;
  const cookie = get('cookie');
  const m = cookie.match(new RegExp(`(?:^|;\\s*)${SESSION_COOKIE}=([^;]+)`));
  return m ? decodeURIComponent(m[1]) : '';
}

/** Resolve the signed-in user, or null. Extends sessions as they're used. */
export async function resolveSession(env, headers) {
  const token = tokenFromHeaders(headers);
  if (!token || !env.DB) return null;
  const hash = await sha256Hex(token);
  const row = await env.DB
    .prepare(`SELECT s.user_id, s.created_at, s.expires_at, u.email, u.display_name
              FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?`)
    .bind(hash).first();
  if (!row) return null;
  const t = now();
  if (row.expires_at < t) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(hash).run();
    return null;
  }
  if (row.expires_at - t < SESSION_TTL - SESSION_RENEW_AFTER) {
    await env.DB.prepare('UPDATE sessions SET expires_at = ? WHERE token_hash = ?').bind(t + SESSION_TTL, hash).run();
  }
  return { user: { id: row.user_id, email: row.email, display_name: row.display_name }, token };
}

export function sessionCookie(token, requestUrl, maxAge = SESSION_TTL) {
  const secure = new URL(requestUrl).protocol === 'https:' ? '; Secure' : '';
  return `${SESSION_COOKIE}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`;
}

export function clearedSessionCookie(requestUrl) {
  return sessionCookie('', requestUrl, 0);
}

// ---------- WebAuthn challenges ----------

export async function saveChallenge(env, { challenge, kind, userId = null }) {
  const id = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO auth_challenges (id, challenge, kind, user_id, expires_at) VALUES (?, ?, ?, ?, ?)')
    .bind(id, challenge, kind, userId, now() + CHALLENGE_TTL).run();
  // Opportunistic cleanup of stale challenges.
  await env.DB.prepare('DELETE FROM auth_challenges WHERE expires_at < ?').bind(now()).run();
  return id;
}

/** Single-use: deletes the challenge as it's read. */
export async function takeChallenge(env, id, kind) {
  const row = await env.DB.prepare('SELECT challenge, kind, user_id, expires_at FROM auth_challenges WHERE id = ?').bind(id).first();
  if (!row) throw new AuthError('Passkey request expired, try again.', 400, 'challenge_expired');
  await env.DB.prepare('DELETE FROM auth_challenges WHERE id = ?').bind(id).run();
  if (row.kind !== kind || row.expires_at < now()) {
    throw new AuthError('Passkey request expired, try again.', 400, 'challenge_expired');
  }
  return row;
}

// ---------- Sign in with Apple ----------

const APPLE_ISSUER = 'https://appleid.apple.com';
let appleKeysCache = { keys: null, fetchedAt: 0 };

async function appleKeys(force = false) {
  if (!force && appleKeysCache.keys && Date.now() - appleKeysCache.fetchedAt < 60 * 60 * 1000) {
    return appleKeysCache.keys;
  }
  const res = await fetch(`${APPLE_ISSUER}/auth/keys`);
  if (!res.ok) throw new AuthError('Could not reach Apple to verify sign-in.', 502);
  const { keys } = await res.json();
  appleKeysCache = { keys, fetchedAt: Date.now() };
  return keys;
}

/**
 * Verify an Apple identity token. `audiences` = allowed client ids
 * (Services ID for web, bundle id for native). Returns the claims.
 */
export async function verifyAppleIdToken(idToken, { audiences, nonce }) {
  const parts = (idToken || '').split('.');
  if (parts.length !== 3) throw new AuthError('Malformed Apple token.', 400);
  const [h, p, sig] = parts;
  const header = JSON.parse(new TextDecoder().decode(fromB64url(h)));
  const claims = JSON.parse(new TextDecoder().decode(fromB64url(p)));
  if (header.alg !== 'RS256') throw new AuthError('Unexpected Apple token algorithm.', 400);

  let jwk = (await appleKeys()).find((k) => k.kid === header.kid);
  if (!jwk) jwk = (await appleKeys(true)).find((k) => k.kid === header.kid);
  if (!jwk) throw new AuthError('Unknown Apple signing key.', 401);

  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, fromB64url(sig), enc.encode(`${h}.${p}`));
  if (!ok) throw new AuthError('Apple token signature is invalid.', 401);

  if (claims.iss !== APPLE_ISSUER) throw new AuthError('Apple token issuer mismatch.', 401);
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!aud.some((a) => audiences.includes(a))) throw new AuthError('Apple token is for another app.', 401);
  if (typeof claims.exp !== 'number' || claims.exp < now() - 60) throw new AuthError('Apple sign-in expired, try again.', 401);
  if (nonce !== undefined && claims.nonce !== nonce) throw new AuthError('Apple sign-in nonce mismatch.', 401);
  if (!claims.sub) throw new AuthError('Apple token has no subject.', 401);

  return {
    sub: claims.sub,
    email: claims.email || null,
    emailVerified: claims.email_verified === true || claims.email_verified === 'true',
  };
}

export class AuthError extends Error {
  constructor(message, status = 400, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
