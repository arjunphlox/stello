const { createClient } = require('@supabase/supabase-js');

/**
 * OAuth callback — Supabase redirects here after Apple sign-in. Best-effort
 * code exchange, then redirect to the app where the client-side auth guard
 * picks up the session. ?welcome=1 triggers the post-login stagger reveal.
 *
 * Faithful port of the Vercel handler (behavior unchanged).
 */
module.exports = async function handler(req, res) {
  const { code } = req.query;

  if (code) {
    const supabase = createClient(
      req.env.SUPABASE_URL,
      req.env.SUPABASE_ANON_KEY
    );
    try {
      await supabase.auth.exchangeCodeForSession(code);
    } catch { /* best-effort — client completes PKCE */ }
  }

  res.writeHead(302, { Location: '/?welcome=1' });
  res.end();
};
