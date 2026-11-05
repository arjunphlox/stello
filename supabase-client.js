/* === Stello — Supabase Client === */

(function () {
  'use strict';

  // Supabase configuration — publishable key is safe to expose (RLS protects data)
  const SUPABASE_URL = window.STELLO_SUPABASE_URL || 'https://ngncjtzsqrrfrhgammne.supabase.co';
  const SUPABASE_ANON_KEY = window.STELLO_SUPABASE_ANON_KEY || 'sb_publishable_r7udhKoy2jEtBrcbKY1wGg_LFn-wMjR';

  // Upstream version check URL (Arjun's repo)
  const UPSTREAM_VERSION_URL = 'https://raw.githubusercontent.com/arjunphlox/stello/main/version.json';

  let _client = null;
  let _session = null;

  /** Initialize the Supabase client (lazy, singleton) */
  function getClient() {
    if (_client) return _client;
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      console.warn('Stello: Supabase URL or anon key not configured.');
      return null;
    }
    _client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    return _client;
  }

  /** Get current session, or null if not authenticated */
  async function getSession() {
    const client = getClient();
    if (!client) return null;
    const { data: { session } } = await client.auth.getSession();
    _session = session;
    return session;
  }

  /** Get user ID from current session */
  function getUserId() {
    return _session?.user?.id || null;
  }

  /** Get display name from profile */
  async function getDisplayName() {
    const client = getClient();
    const userId = getUserId();
    if (!client || !userId) return null;
    const { data } = await client
      .from('profiles')
      .select('display_name')
      .eq('id', userId)
      .single();
    return data?.display_name || _session?.user?.email || null;
  }

  /**
   * Auth guard — redirects to login.html if no session.
   * Call at the top of init() on protected pages.
   * Returns the session if authenticated.
   */
  async function requireAuth() {
    const session = await getSession();
    if (!session) {
      window.location.href = '/login.html';
      return null;
    }
    return session;
  }

  /**
   * Fetch wrapper that adds auth headers automatically.
   * Use instead of fetch() for all /api/* calls.
   */
  async function apiFetch(url, opts = {}) {
    const token = _session?.access_token;
    const headers = { ...opts.headers };
    if (token) {
      headers['Authorization'] = 'Bearer ' + token;
    }
    return fetch(url, { ...opts, headers });
  }

  /**
   * Sign in with Apple OAuth via Supabase.
   */
  async function signInWithApple() {
    const client = getClient();
    if (!client) return;
    const { error } = await client.auth.signInWithOAuth({
      provider: 'apple',
      options: { redirectTo: window.location.origin + '/api/auth-callback' }
    });
    if (error) console.error('Apple sign-in error:', error.message);
  }

  /**
   * Sign in with email and password.
   */
  async function signInWithEmail(email, password) {
    const client = getClient();
    if (!client) return { error: 'Client not initialized' };
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) return { error: error.message };
    _session = data.session;
    return { error: null };
  }

  /**
   * Sign up with email and password.
   */
  async function signUpWithEmail(email, password) {
    const client = getClient();
    if (!client) return { error: 'Client not initialized' };
    const { data, error } = await client.auth.signUp({ email, password });
    if (error) return { error: error.message };
    return { error: null, needsConfirmation: !data.session };
  }

  /**
   * Send a password-reset email. The link in the email points the user at
   * `/reset-password.html`, where supabase-js auto-detects the recovery
   * hash and sets up a temporary session for `updatePassword()`.
   * Note: the redirect URL must be allowlisted in Supabase
   * (Authentication → URL Configuration → Redirect URLs).
   */
  async function requestPasswordReset(email) {
    const client = getClient();
    if (!client) return { error: 'Client not initialized' };
    const { error } = await client.auth.resetPasswordForEmail(email, {
      redirectTo: window.location.origin + '/reset-password.html'
    });
    if (error) return { error: error.message };
    return { error: null };
  }

  /**
   * Update the current user's password. Used on `/reset-password.html`
   * after a recovery link has established a session via the URL hash.
   */
  async function updatePassword(newPassword) {
    const client = getClient();
    if (!client) return { error: 'Client not initialized' };
    const { error } = await client.auth.updateUser({ password: newPassword });
    if (error) return { error: error.message };
    return { error: null };
  }

  /**
   * Sign out and redirect to login.
   */
  async function signOut() {
    const client = getClient();
    if (client) await client.auth.signOut();
    _session = null;
    window.location.href = '/login.html';
  }

  /**
   * Check for upstream version updates.
   * Returns { available, latest, current, changelog, migration } or null.
   */
  async function checkForUpdate(currentVersion) {
    try {
      const res = await fetch(UPSTREAM_VERSION_URL, { cache: 'no-store' });
      if (!res.ok) return null;
      const remote = await res.json();
      if (remote.version !== currentVersion) {
        return {
          available: true,
          latest: remote.version,
          current: currentVersion,
          changelog: remote.changelog,
          migration: remote.migration,
          breaking_changes: remote.breaking_changes || []
        };
      }
      return { available: false };
    } catch {
      return null;
    }
  }

  // Listen for auth state changes (token refresh, sign out from another tab)
  function initAuthListener() {
    const client = getClient();
    if (!client) return;
    client.auth.onAuthStateChange((event, session) => {
      _session = session;
      if (event === 'SIGNED_OUT') {
        window.location.href = '/login.html';
      }
    });
  }

  // Expose on window for other scripts
  window.Stello = {
    getClient,
    getSession,
    getUserId,
    getDisplayName,
    requireAuth,
    apiFetch,
    signInWithApple,
    signInWithEmail,
    signUpWithEmail,
    requestPasswordReset,
    updatePassword,
    signOut,
    checkForUpdate,
    initAuthListener
  };
})();
