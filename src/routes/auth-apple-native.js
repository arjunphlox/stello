/**
 * POST /api/auth/apple/native — the Apple app signs into the same Stello account
 * as the web, once, and gets a long-lived device token for /api/sync/*.
 *
 * Body: { identityToken, nonce?, deviceName? }
 *   identityToken  from ASAuthorizationAppleIDCredential (audience = app bundle id,
 *                  listed in the APPLE_APP_IDS var)
 *   nonce          the raw nonce the app hashed into the request, if it set one
 * Reply: { token, expiresAt, userId }
 *
 * Same Apple `sub` → same account as Sign in with Apple on the web
 * (resolveAppleAccount links or creates it). Helpers come from step 1's auth.js.
 */
import auth from '../lib/auth.js';

const { verifyAppleIdentityToken, appleAudiences, resolveAppleAccount, createSession } = auth;

export default async function appleNative(c) {
  let body;
  try { body = await c.req.json(); } catch { return c.json({ error: 'invalid JSON' }, 400); }
  const idToken = body?.identityToken;
  if (typeof idToken !== 'string' || idToken.length < 20) return c.json({ error: 'identityToken required' }, 400);

  let claims;
  try {
    claims = await verifyAppleIdentityToken(idToken, {
      audiences: appleAudiences(c.env, 'app'),
      nonce: typeof body.nonce === 'string' ? body.nonce : undefined,
    });
  } catch (err) {
    console.warn('apple native sign-in rejected', err?.message);
    return c.json({ error: 'Apple sign-in could not be verified' }, 401);
  }

  const account = await resolveAppleAccount(c.env, claims);
  const userId = typeof account === 'string' ? account : account?.id ?? account?.userId;
  if (!userId) return c.json({ error: 'no account for this Apple ID' }, 403);

  const label = typeof body.deviceName === 'string' ? body.deviceName.slice(0, 80) : 'Apple device';
  const { token, expiresAt } = await createSession(c.env, userId, { kind: 'device', label });
  return c.json({ token, expiresAt, userId });
}
