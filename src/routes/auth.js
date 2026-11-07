/**
 * /api/auth/* — Stello accounts (replaces Supabase Auth).
 *
 *   GET  /api/auth/config           → { apple, signup } for the login page
 *   GET  /api/auth/me               → current user, linked sign-in methods
 *   POST /api/auth/login            { email, password }
 *   POST /api/auth/signup           { email, password }   (only if ALLOW_SIGNUP=true)
 *   POST /api/auth/logout
 *   POST /api/auth/password         { password, current_password? }  set / change
 *   GET  /api/auth/apple/start      ?mode=link to link Apple to the signed-in account
 *   POST /api/auth/apple/callback   Apple's form_post return (id_token + state)
 *   GET  /api/auth/magic?token=     one-time sign-in link (minted by the admin route)
 *
 * The Apple apps sign in through POST /api/auth/apple/native (sync thread).
 */
const auth = require('../lib/auth');

const APPLE_AUTHORIZE = 'https://appleid.apple.com/auth/authorize';
const STATE_TTL_MS = 10 * 60 * 1000;
const RECENT_SESSION_MS = 15 * 60 * 1000;

function origin(c) {
  return new URL(c.req.url).origin;
}

function isEmail(s) {
  return typeof s === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s.trim());
}

async function readBody(c) {
  const ct = (c.req.header('content-type') || '').toLowerCase();
  if (ct.includes('application/json')) return c.req.json().catch(() => ({}));
  const form = await c.req.parseBody().catch(() => ({}));
  return form || {};
}

async function startSession(c, userId, status = 200, body = { ok: true }) {
  const { token } = await auth.createSession(c.env, userId, { kind: 'web' });
  c.header('Set-Cookie', auth.sessionCookie(token, auth.WEB_TTL_MS));
  return c.json(body, status);
}

function redirectWithSession(c, token, location) {
  return new Response(null, {
    status: 303,
    headers: { Location: location, 'Set-Cookie': auth.sessionCookie(token, auth.WEB_TTL_MS) },
  });
}

function loginError(c, message) {
  const u = new URL('/login.html', origin(c));
  u.searchParams.set('error', message);
  return c.redirect(u.toString(), 303);
}

function safeReturnTo(v) {
  return typeof v === 'string' && v.startsWith('/') && !v.startsWith('//') ? v : '/?welcome=1';
}

module.exports = function mountAuth(app) {
  app.get('/api/auth/config', (c) => c.json({
    apple: !!(c.env.APPLE_SERVICES_ID || '').trim(),
    signup: auth.signupAllowed(c.env),
  }));

  app.get('/api/auth/me', async (c) => {
    const user = await auth.userFromHeaders(c.env, (n) => c.req.header(n));
    if (!user) return c.json({ user: null }, 401);
    const [{ results: ids }, row] = await Promise.all([
      c.env.DB.prepare('SELECT provider, email, created_at FROM identities WHERE user_id = ?').bind(user.id).all(),
      c.env.DB.prepare('SELECT password_hash IS NOT NULL AS has_password FROM users WHERE id = ?').bind(user.id).first(),
    ]);
    return c.json({
      user: { id: user.id, email: user.email, display_name: user.display_name },
      identities: ids.map(i => ({ provider: i.provider, email: i.email })),
      has_password: !!row?.has_password,
    });
  });

  app.post('/api/auth/login', async (c) => {
    const { email, password } = await readBody(c);
    if (!isEmail(email) || !password) return c.json({ error: 'Enter your email and password.' }, 400);
    const user = await auth.findUserByEmail(c.env, email);
    const ok = user && await auth.verifyPassword(String(password), user.password_hash);
    if (!ok) return c.json({ error: 'Email or password is wrong.' }, 401);
    return startSession(c, user.id);
  });

  app.post('/api/auth/signup', async (c) => {
    if (!auth.signupAllowed(c.env)) return c.json({ error: 'Sign-up is closed.' }, 403);
    const { email, password } = await readBody(c);
    if (!isEmail(email)) return c.json({ error: 'Enter a valid email.' }, 400);
    if (!password || String(password).length < 8) return c.json({ error: 'Use at least 8 characters.' }, 400);
    if (await auth.findUserByEmail(c.env, email)) return c.json({ error: 'That email already has an account.' }, 409);
    const user = await auth.createUser(c.env, { email, passwordHash: await auth.hashPassword(String(password)) });
    return startSession(c, user.id, 201);
  });

  app.post('/api/auth/logout', async (c) => {
    await auth.revokeSession(c.env, auth.tokenFromHeaders((n) => c.req.header(n)));
    c.header('Set-Cookie', auth.clearCookie());
    return c.json({ ok: true });
  });

  app.post('/api/auth/password', async (c) => {
    const token = auth.tokenFromHeaders((n) => c.req.header(n));
    const user = await auth.userFromHeaders(c.env, (n) => c.req.header(n));
    if (!user) return c.json({ error: 'Not signed in' }, 401);
    const { password, current_password } = await readBody(c);
    if (!password || String(password).length < 8) return c.json({ error: 'Use at least 8 characters.' }, 400);
    const row = await c.env.DB.prepare('SELECT password_hash FROM users WHERE id = ?').bind(user.id).first();
    const sess = await c.env.DB.prepare('SELECT created_at FROM sessions WHERE token_hash = ?')
      .bind(await auth.sha256(token)).first();
    // Changing an existing password needs the old one, unless the session is
    // fresh (just signed in with Apple or a one-time link: the recovery path).
    const fresh = sess && Date.now() - sess.created_at < RECENT_SESSION_MS;
    if (row?.password_hash && !fresh) {
      if (!current_password || !(await auth.verifyPassword(String(current_password), row.password_hash))) {
        return c.json({ error: 'Current password is wrong.' }, 403);
      }
    }
    const stmts = [
      c.env.DB.prepare('UPDATE users SET password_hash = ? WHERE id = ?').bind(await auth.hashPassword(String(password)), user.id),
    ];
    if (user.email) {
      stmts.push(c.env.DB.prepare(
        'INSERT OR IGNORE INTO identities (provider, subject, user_id, email, created_at) VALUES (?, ?, ?, ?, ?)'
      ).bind('email', user.email, user.id, user.email, Date.now()));
    }
    await c.env.DB.batch(stmts);
    return c.json({ ok: true });
  });

  // ---- Sign in with Apple (web: redirect + form_post, no client secret needed:
  // we verify Apple's signed id_token instead of exchanging the code).
  app.get('/api/auth/apple/start', async (c) => {
    const clientId = (c.env.APPLE_SERVICES_ID || '').trim();
    if (!clientId) return loginError(c, 'Sign in with Apple is not set up yet.');
    const mode = c.req.query('mode') === 'link' ? 'link' : 'login';
    let linkUser = null;
    if (mode === 'link') {
      linkUser = await auth.userFromHeaders(c.env, (n) => c.req.header(n));
      if (!linkUser) return loginError(c, 'Sign in first, then link your Apple ID.');
    }
    const state = auth.randomToken(24);
    const nonce = auth.randomToken(24);
    const now = Date.now();
    await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM auth_states WHERE created_at < ?').bind(now - STATE_TTL_MS),
      c.env.DB.prepare(
        'INSERT INTO auth_states (state, nonce, mode, user_id, return_to, created_at) VALUES (?, ?, ?, ?, ?, ?)'
      ).bind(state, nonce, mode, linkUser?.id || null, safeReturnTo(c.req.query('return_to')), now),
    ]);
    const u = new URL(APPLE_AUTHORIZE);
    u.searchParams.set('client_id', clientId);
    u.searchParams.set('redirect_uri', `${origin(c)}/api/auth/apple/callback`);
    u.searchParams.set('response_type', 'code id_token');
    u.searchParams.set('response_mode', 'form_post');
    u.searchParams.set('scope', 'name email');
    u.searchParams.set('state', state);
    u.searchParams.set('nonce', nonce);
    return c.redirect(u.toString(), 302);
  });

  app.post('/api/auth/apple/callback', async (c) => {
    const body = await readBody(c);
    console.log('apple callback', { hasToken: !!body.id_token, hasState: !!body.state, error: body.error || null, firstAuth: !!body.user });
    if (body.error) return loginError(c, body.error === 'user_cancelled_authorize' ? 'Apple sign-in was cancelled.' : `Apple: ${body.error}`);
    const st = body.state && await c.env.DB.prepare('SELECT * FROM auth_states WHERE state = ?').bind(String(body.state)).first();
    if (!st || Date.now() - st.created_at > STATE_TTL_MS) return loginError(c, 'Sign-in expired. Try again.');
    await c.env.DB.prepare('DELETE FROM auth_states WHERE state = ?').bind(st.state).run();

    let claims;
    try {
      claims = await auth.verifyAppleIdentityToken(body.id_token, {
        audiences: auth.appleAudiences(c.env, 'web'),
        nonce: st.nonce,
      });
    } catch (err) {
      console.warn('apple callback: token rejected', err.message);
      return loginError(c, 'Apple sign-in could not be verified.');
    }

    // Apple sends the name only on the very first authorization.
    let displayName = null;
    try {
      const u = body.user ? JSON.parse(body.user) : null;
      if (u?.name) displayName = [u.name.firstName, u.name.lastName].filter(Boolean).join(' ') || null;
    } catch { /* ignore */ }

    const result = await auth.resolveAppleAccount(c.env, claims, {
      linkUserId: st.mode === 'link' ? st.user_id : null,
      displayName,
    });
    if (result.error) return loginError(c, result.error);
    const { token } = await auth.createSession(c.env, result.userId, { kind: 'web' });
    const to = st.mode === 'link' ? '/?linked=apple' : (st.return_to || '/?welcome=1');
    return redirectWithSession(c, token, to);
  });

  // ---- One-time sign-in link (admin-minted; recovery + first sign-in after migration)
  app.get('/api/auth/magic', async (c) => {
    const token = c.req.query('token') || '';
    const hash = await auth.sha256(token);
    const row = await c.env.DB.prepare(
      "SELECT state, user_id, created_at FROM auth_states WHERE state = ? AND mode = 'magic'"
    ).bind(hash).first();
    if (!row || Date.now() - row.created_at > 30 * 60 * 1000) return loginError(c, 'That sign-in link has expired.');
    await c.env.DB.prepare('DELETE FROM auth_states WHERE state = ?').bind(hash).run();
    const { token: session } = await auth.createSession(c.env, row.user_id, { kind: 'web' });
    return redirectWithSession(c, session, '/reset-password.html');
  });
};
