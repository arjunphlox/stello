/* === Stello — auth client (Stello accounts on the Worker; replaces supabase-client.js) ===
 *
 * The session lives in an HttpOnly cookie set by /api/auth/*, so the browser
 * never holds a token. Same-origin fetches send it automatically.
 */
(function () {
  'use strict';

  const UPSTREAM_VERSION_URL = 'https://raw.githubusercontent.com/arjunphlox/stello/main/version.json';

  let _session = null;          // { user: { id, email, display_name }, identities, has_password }
  let _loaded = false;

  async function postJson(url, body) {
    try {
      const res = await fetch(url, {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {}),
      });
      const data = await res.json().catch(() => ({}));
      return res.ok ? { data, error: null } : { data, error: data.error || `Request failed (${res.status})` };
    } catch (err) {
      return { data: null, error: 'Network error. Check your connection.' };
    }
  }

  /** Current session (cached after the first call), or null when signed out. */
  async function getSession({ refresh = false } = {}) {
    if (_loaded && !refresh) return _session;
    try {
      const res = await fetch('/api/auth/me', { credentials: 'same-origin' });
      _session = res.ok ? await res.json() : null;
    } catch {
      _session = null;
    }
    _loaded = true;
    return _session;
  }

  function getUserId() {
    return _session?.user?.id || null;
  }

  async function getDisplayName() {
    const s = await getSession();
    return s?.user?.display_name || s?.user?.email || null;
  }

  /** Auth guard for protected pages: redirects to login when signed out. */
  async function requireAuth() {
    const session = await getSession();
    if (!session) {
      window.location.href = '/login.html';
      return null;
    }
    return session;
  }

  /** fetch() for /api/* calls; a 401 sends the user back to sign in. */
  async function apiFetch(url, opts = {}) {
    const res = await fetch(url, { credentials: 'same-origin', ...opts });
    if (res.status === 401 && _loaded && _session) {
      _session = null;
      window.location.href = '/login.html';
    }
    return res;
  }

  /** JSON GET helper: resolves to the parsed body or null. */
  async function apiGet(url) {
    const res = await apiFetch(url);
    if (!res.ok) return null;
    return res.json().catch(() => null);
  }

  async function getAuthConfig() {
    try {
      const res = await fetch('/api/auth/config');
      return res.ok ? await res.json() : { apple: false, signup: false };
    } catch {
      return { apple: false, signup: false };
    }
  }

  /** Full-page redirect to Apple. `link: true` adds Apple to the signed-in account. */
  function signInWithApple({ link = false } = {}) {
    window.location.href = '/api/auth/apple/start' + (link ? '?mode=link' : '');
  }

  async function signInWithEmail(email, password) {
    const { error } = await postJson('/api/auth/login', { email, password });
    if (!error) _loaded = false;
    return { error };
  }

  async function signUpWithEmail(email, password) {
    const { error } = await postJson('/api/auth/signup', { email, password });
    if (!error) _loaded = false;
    return { error, needsConfirmation: false };
  }

  /** No reset emails yet: recovery is "sign in with Apple, then set a password". */
  async function requestPasswordReset() {
    return { error: 'Sign in with Apple, then set a new password in Settings.' };
  }

  async function updatePassword(newPassword, currentPassword) {
    const { error } = await postJson('/api/auth/password', {
      password: newPassword,
      current_password: currentPassword || undefined,
    });
    return { error };
  }

  async function signOut() {
    await postJson('/api/auth/logout');
    _session = null;
    window.location.href = '/login.html';
  }

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
          breaking_changes: remote.breaking_changes || [],
        };
      }
      return { available: false };
    } catch {
      return null;
    }
  }

  // Cookie sessions don't need a client-side refresh listener; kept for callers.
  function initAuthListener() {}

  window.Stello = {
    getSession,
    getUserId,
    getDisplayName,
    requireAuth,
    apiFetch,
    apiGet,
    getAuthConfig,
    signInWithApple,
    signInWithEmail,
    signUpWithEmail,
    requestPasswordReset,
    updatePassword,
    signOut,
    checkForUpdate,
    initAuthListener,
  };
})();
