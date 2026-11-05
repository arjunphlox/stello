/**
 * /api/auth/* — Stello's own login on Cloudflare (replaces Supabase Auth).
 *
 *   GET  /api/auth/me                       → { user } or 401
 *   POST /api/auth/logout
 *   GET  /api/auth/apple/start              → redirect to Apple (web)
 *   POST /api/auth/apple/callback           ← Apple form_post (web)
 *   POST /api/auth/apple/native             { idToken, nonce, name? } → { token, user }
 *   POST /api/auth/passkey/login/options    → { challengeId, options }
 *   POST /api/auth/passkey/login/verify     { challengeId, credential, client? }
 *   POST /api/auth/passkey/register/options (signed in)
 *   POST /api/auth/passkey/register/verify  { challengeId, credential, name? }
 *   GET  /api/auth/passkeys                 (signed in) → { passkeys }
 *   DELETE /api/auth/passkeys/:id           (signed in)
 *
 * Web sessions ride an HttpOnly cookie; native apps send `client: "native"`
 * and get a bearer token back instead.
 */
import { Hono } from 'hono';
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from '@simplewebauthn/server';
import {
  AuthError, clearedSessionCookie, createSession, deleteSession, getUser,
  randomToken, relyingParty, resolveSession, saveChallenge, sessionCookie,
  sha256Hex, takeChallenge, tokenFromHeaders, upsertAppleUser, verifyAppleIdToken,
} from '../lib/auth.js';

const auth = new Hono();
const APPLE_STATE_COOKIE = 'stello_apple';

const publicUser = (u) => ({ id: u.id, email: u.email || null, name: u.display_name || null });

auth.onError((err, c) => {
  if (err instanceof AuthError) {
    return c.json({ error: err.message, code: err.code }, err.status);
  }
  console.error('auth error', err);
  return c.json({ error: 'Sign-in failed.' }, 500);
});

/** Finish a sign-in: cookie for web, bearer token for native. */
async function signedIn(c, user, client) {
  const isNative = client === 'native';
  const { token, expiresAt } = await createSession(c.env, user.id, isNative ? 'native' : 'web');
  if (isNative) return c.json({ token, expiresAt, user: publicUser(user) });
  c.header('Set-Cookie', sessionCookie(token, c.req.url));
  return c.json({ user: publicUser(user) });
}

async function requireUser(c) {
  const s = await resolveSession(c.env, c.req.raw.headers);
  if (!s) throw new AuthError('Not signed in.', 401);
  return s.user;
}

// ---------- session ----------

auth.get('/me', async (c) => {
  const s = await resolveSession(c.env, c.req.raw.headers);
  if (!s) return c.json({ user: null }, 401);
  return c.json({ user: publicUser(s.user) });
});

auth.post('/logout', async (c) => {
  await deleteSession(c.env, tokenFromHeaders(c.req.raw.headers));
  c.header('Set-Cookie', clearedSessionCookie(c.req.url));
  return c.json({ ok: true });
});

// ---------- Sign in with Apple (web) ----------

function appleRedirectURI(c) {
  return new URL('/api/auth/apple/callback', c.req.url).toString();
}

auth.get('/apple/start', async (c) => {
  const clientId = c.env.APPLE_SERVICES_ID;
  if (!clientId) throw new AuthError('Sign in with Apple is not configured yet.', 503);
  const state = randomToken(16);
  const nonce = randomToken(16);
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: appleRedirectURI(c),
    response_type: 'code id_token',
    response_mode: 'form_post',
    scope: 'name email',
    state,
    nonce,
  });
  // Apple posts back cross-site, so this short-lived cookie must be SameSite=None.
  c.header('Set-Cookie', `${APPLE_STATE_COOKIE}=${state}.${nonce}; Path=/api/auth/apple; HttpOnly; Secure; SameSite=None; Max-Age=600`);
  return c.redirect(`https://appleid.apple.com/auth/authorize?${params}`, 302);
});

auth.post('/apple/callback', async (c) => {
  const fail = (msg) => c.redirect(`/login.html?error=${encodeURIComponent(msg)}`, 302);
  const form = await c.req.parseBody();
  if (form.error) return fail(form.error === 'user_cancelled_authorize' ? '' : 'Apple sign-in was cancelled.');

  const cookie = c.req.header('cookie') || '';
  const m = cookie.match(new RegExp(`(?:^|;\\s*)${APPLE_STATE_COOKIE}=([^;]+)`));
  const [state, nonce] = (m ? m[1] : '').split('.');
  if (!state || state !== form.state) return fail('Apple sign-in expired, try again.');

  try {
    const identity = await verifyAppleIdToken(form.id_token, { audiences: [c.env.APPLE_SERVICES_ID], nonce });
    // Apple sends the name only on the very first authorization.
    let name = null;
    try {
      const u = form.user ? JSON.parse(form.user) : null;
      name = [u?.name?.firstName, u?.name?.lastName].filter(Boolean).join(' ') || null;
    } catch { /* ignore */ }
    const user = await upsertAppleUser(c.env, { ...identity, name });
    const { token } = await createSession(c.env, user.id, 'web');
    c.header('Set-Cookie', sessionCookie(token, c.req.url), { append: true });
    c.header('Set-Cookie', `${APPLE_STATE_COOKIE}=; Path=/api/auth/apple; HttpOnly; Secure; SameSite=None; Max-Age=0`, { append: true });
    return c.redirect('/?welcome=1', 302);
  } catch (err) {
    return fail(err instanceof AuthError ? err.message : 'Apple sign-in failed.');
  }
});

// ---------- Sign in with Apple (native) ----------

auth.post('/apple/native', async (c) => {
  const { idToken, nonce, name } = await c.req.json();
  if (!idToken || !nonce) throw new AuthError('Missing Apple token.', 400);
  const audiences = (c.env.APPLE_BUNDLE_IDS || 'com.phloxpage.Stello').split(',').map((s) => s.trim());
  // Native requests carry SHA-256(nonce); the app sends us the raw value.
  const identity = await verifyAppleIdToken(idToken, { audiences, nonce: await sha256Hex(nonce) });
  const user = await upsertAppleUser(c.env, { ...identity, name: name || null });
  return signedIn(c, user, 'native');
});

// ---------- Passkeys: sign in ----------

auth.post('/passkey/login/options', async (c) => {
  const { rpID } = relyingParty(c.env, c.req.url);
  const options = await generateAuthenticationOptions({ rpID, userVerification: 'preferred' });
  const challengeId = await saveChallenge(c.env, { challenge: options.challenge, kind: 'login' });
  return c.json({ challengeId, options });
});

auth.post('/passkey/login/verify', async (c) => {
  const { challengeId, credential, client } = await c.req.json();
  if (!challengeId || !credential?.id) throw new AuthError('Missing passkey response.', 400);
  const { challenge } = await takeChallenge(c.env, challengeId, 'login');

  const pk = await c.env.DB
    .prepare('SELECT id, user_id, credential_id, public_key, counter, transports FROM passkeys WHERE credential_id = ?')
    .bind(credential.id).first();
  if (!pk) throw new AuthError('This passkey isn’t linked to a Stello account.', 401, 'unknown_passkey');

  const { rpID, origins } = relyingParty(c.env, c.req.url);
  const { verified, authenticationInfo } = await verifyAuthenticationResponse({
    response: credential,
    expectedChallenge: challenge,
    expectedOrigin: origins,
    expectedRPID: rpID,
    requireUserVerification: false,
    credential: {
      id: pk.credential_id,
      publicKey: new Uint8Array(pk.public_key),
      counter: pk.counter,
      transports: pk.transports ? JSON.parse(pk.transports) : undefined,
    },
  }).catch((e) => { throw new AuthError(e.message || 'Passkey check failed.', 401); });
  if (!verified) throw new AuthError('Passkey check failed.', 401);

  await c.env.DB.prepare("UPDATE passkeys SET counter = ?, last_used_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?")
    .bind(authenticationInfo.newCounter, pk.id).run();
  const user = await getUser(c.env, pk.user_id);
  return signedIn(c, user, client);
});

// ---------- Passkeys: register + manage (signed in) ----------

auth.post('/passkey/register/options', async (c) => {
  const user = await requireUser(c);
  const { rpID } = relyingParty(c.env, c.req.url);
  const existing = await c.env.DB.prepare('SELECT credential_id, transports FROM passkeys WHERE user_id = ?').bind(user.id).all();
  const options = await generateRegistrationOptions({
    rpName: 'Stello',
    rpID,
    userID: new TextEncoder().encode(user.id),
    userName: user.email || 'Stello',
    userDisplayName: user.display_name || user.email || 'Stello',
    attestationType: 'none',
    excludeCredentials: existing.results.map((r) => ({
      id: r.credential_id,
      transports: r.transports ? JSON.parse(r.transports) : undefined,
    })),
    authenticatorSelection: { residentKey: 'required', userVerification: 'preferred' },
  });
  const challengeId = await saveChallenge(c.env, { challenge: options.challenge, kind: 'register', userId: user.id });
  return c.json({ challengeId, options });
});

auth.post('/passkey/register/verify', async (c) => {
  const user = await requireUser(c);
  const { challengeId, credential, name } = await c.req.json();
  const row = await takeChallenge(c.env, challengeId, 'register');
  if (row.user_id !== user.id) throw new AuthError('Passkey request belongs to another account.', 403);

  const { rpID, origins } = relyingParty(c.env, c.req.url);
  const { verified, registrationInfo } = await verifyRegistrationResponse({
    response: credential,
    expectedChallenge: row.challenge,
    expectedOrigin: origins,
    expectedRPID: rpID,
    requireUserVerification: false,
  }).catch((e) => { throw new AuthError(e.message || 'Passkey could not be saved.', 400); });
  if (!verified || !registrationInfo) throw new AuthError('Passkey could not be saved.', 400);

  const cred = registrationInfo.credential;
  const id = crypto.randomUUID();
  const friendly = (name || defaultPasskeyName(c.req.header('user-agent'))).slice(0, 120);
  await c.env.DB.prepare('INSERT INTO passkeys (id, user_id, credential_id, public_key, counter, transports, friendly_name) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(id, user.id, cred.id, cred.publicKey, cred.counter, JSON.stringify(cred.transports || credential.response?.transports || []), friendly)
    .run();
  return c.json({ passkey: { id, friendly_name: friendly } });
});

auth.get('/passkeys', async (c) => {
  const user = await requireUser(c);
  const { results } = await c.env.DB
    .prepare('SELECT id, friendly_name, created_at, last_used_at FROM passkeys WHERE user_id = ? ORDER BY created_at DESC')
    .bind(user.id).all();
  return c.json({ passkeys: results });
});

auth.delete('/passkeys/:id', async (c) => {
  const user = await requireUser(c);
  await c.env.DB.prepare('DELETE FROM passkeys WHERE id = ? AND user_id = ?').bind(c.req.param('id'), user.id).run();
  return c.json({ ok: true });
});

function defaultPasskeyName(ua = '') {
  if (/Stello\//.test(ua)) return /iPhone|iPad/.test(ua) ? 'Stello for iPhone' : 'Stello for Mac';
  if (/iPhone|iPad/.test(ua)) return 'iPhone';
  if (/Macintosh/.test(ua)) return 'Mac';
  if (/Android/.test(ua)) return 'Android';
  if (/Windows/.test(ua)) return 'Windows';
  return 'Passkey';
}

export default auth;
