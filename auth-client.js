/* === Stello — auth client (Cloudflare Worker login) ===
   Sign in with Apple + passkeys against /api/auth/*. Web sessions live in an
   HttpOnly cookie, so API calls just need same-origin credentials. */

(function () {
  'use strict';

  const UPSTREAM_VERSION_URL = 'https://raw.githubusercontent.com/arjunphlox/stello/main/version.json';
  let _user = null;

  // ---------- base64url <-> bytes ----------
  const toB64url = (buf) => {
    let s = '';
    for (const b of new Uint8Array(buf)) s += String.fromCharCode(b);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };
  const fromB64url = (str) => {
    const s = str.replace(/-/g, '+').replace(/_/g, '/');
    const bin = atob(s + '='.repeat((4 - (s.length % 4)) % 4));
    return Uint8Array.from(bin, (c) => c.charCodeAt(0)).buffer;
  };

  function parseRequestOptions(json) {
    if (PublicKeyCredential.parseRequestOptionsFromJSON) return PublicKeyCredential.parseRequestOptionsFromJSON(json);
    return {
      ...json,
      challenge: fromB64url(json.challenge),
      allowCredentials: (json.allowCredentials || []).map((c) => ({ ...c, id: fromB64url(c.id) })),
    };
  }

  function parseCreationOptions(json) {
    if (PublicKeyCredential.parseCreationOptionsFromJSON) return PublicKeyCredential.parseCreationOptionsFromJSON(json);
    return {
      ...json,
      challenge: fromB64url(json.challenge),
      user: { ...json.user, id: fromB64url(json.user.id) },
      excludeCredentials: (json.excludeCredentials || []).map((c) => ({ ...c, id: fromB64url(c.id) })),
    };
  }

  function credentialToJSON(cred) {
    try { if (typeof cred.toJSON === 'function') return cred.toJSON(); } catch { /* fall through */ }
    const r = cred.response;
    const response = { clientDataJSON: toB64url(r.clientDataJSON) };
    if (r.attestationObject) {
      response.attestationObject = toB64url(r.attestationObject);
      if (r.getTransports) response.transports = r.getTransports();
    } else {
      response.authenticatorData = toB64url(r.authenticatorData);
      response.signature = toB64url(r.signature);
      if (r.userHandle) response.userHandle = toB64url(r.userHandle);
    }
    return {
      id: cred.id,
      rawId: toB64url(cred.rawId),
      type: cred.type,
      response,
      clientExtensionResults: cred.getClientExtensionResults ? cred.getClientExtensionResults() : {},
      authenticatorAttachment: cred.authenticatorAttachment || undefined,
    };
  }

  async function postJSON(url, body) {
    const res = await fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(data.error || `Request failed (${res.status})`);
      err.code = data.code;
      throw err;
    }
    return data;
  }

  const isCancel = (e) => e && (e.name === 'NotAllowedError' || e.name === 'AbortError');

  // ---------- session ----------

  /** Current session ({ user }) or null. */
  async function getSession() {
    try {
      const res = await fetch('/api/auth/me', { credentials: 'same-origin' });
      if (!res.ok) { _user = null; return null; }
      const { user } = await res.json();
      _user = user;
      return user ? { user } : null;
    } catch {
      return null;
    }
  }

  function getUserId() { return _user?.id || null; }

  async function getDisplayName() {
    if (!_user) await getSession();
    return _user?.name || _user?.email || null;
  }

  /** Auth guard for protected pages: redirects to the login page when signed out. */
  async function requireAuth() {
    const session = await getSession();
    if (!session) {
      window.location.href = '/login.html';
      return null;
    }
    return session;
  }

  /** fetch() for /api/* — the session cookie rides along automatically. */
  function apiFetch(url, opts = {}) {
    return fetch(url, { credentials: 'same-origin', ...opts });
  }

  async function signOut() {
    try { await fetch('/api/auth/logout', { method: 'POST', credentials: 'same-origin' }); } catch { /* ignore */ }
    _user = null;
    window.location.href = '/login.html';
  }

  // ---------- Sign in with Apple ----------

  function signInWithApple() {
    window.location.href = '/api/auth/apple/start';
  }

  // ---------- passkeys ----------

  let _pendingAbort = null;

  function passkeysSupported() {
    return !!(window.PublicKeyCredential && navigator.credentials);
  }

  /**
   * Sign in with a passkey. { conditional: true } offers passkeys in the
   * browser's autofill (needs an input with autocomplete="username webauthn").
   * Returns { error, cancelled, code }.
   */
  async function signInWithPasskey({ conditional = false } = {}) {
    if (!passkeysSupported()) return { error: 'Passkeys are not supported in this browser.' };
    if (_pendingAbort) _pendingAbort.abort();
    const abort = new AbortController();
    _pendingAbort = abort;
    try {
      const { challengeId, options } = await postJSON('/api/auth/passkey/login/options');
      const cred = await navigator.credentials.get({
        publicKey: parseRequestOptions(options),
        signal: abort.signal,
        ...(conditional ? { mediation: 'conditional' } : {}),
      });
      if (!cred) return { error: null, cancelled: true };
      const { user } = await postJSON('/api/auth/passkey/login/verify', { challengeId, credential: credentialToJSON(cred) });
      _user = user;
      return { error: null };
    } catch (e) {
      if (isCancel(e)) return { error: null, cancelled: true };
      return { error: e.message || String(e), code: e.code };
    } finally {
      if (_pendingAbort === abort) _pendingAbort = null;
    }
  }

  /** Add a passkey to the signed-in account (Settings → Passkeys). */
  async function registerPasskey() {
    if (!passkeysSupported()) return { error: 'Passkeys are not supported in this browser.' };
    if (_pendingAbort) _pendingAbort.abort();
    try {
      const { challengeId, options } = await postJSON('/api/auth/passkey/register/options');
      const cred = await navigator.credentials.create({ publicKey: parseCreationOptions(options) });
      if (!cred) return { error: null, cancelled: true };
      await postJSON('/api/auth/passkey/register/verify', { challengeId, credential: credentialToJSON(cred) });
      return { error: null };
    } catch (e) {
      if (isCancel(e)) return { error: null, cancelled: true };
      if (e.name === 'InvalidStateError') return { error: 'This device already has a passkey for Stello.' };
      return { error: e.message || String(e) };
    }
  }

  async function listPasskeys() {
    try {
      const res = await apiFetch('/api/auth/passkeys');
      if (!res.ok) return { data: [], error: 'Could not load passkeys' };
      const { passkeys } = await res.json();
      return { data: passkeys || [], error: null };
    } catch (e) {
      return { data: [], error: e.message };
    }
  }

  async function deletePasskey(id) {
    const res = await apiFetch('/api/auth/passkeys/' + encodeURIComponent(id), { method: 'DELETE' });
    return { error: res.ok ? null : 'Could not remove passkey' };
  }

  // ---------- misc ----------

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

  /** Re-check the session when the tab comes back; bounce to login if it ended elsewhere. */
  function initAuthListener() {
    document.addEventListener('visibilitychange', async () => {
      if (document.visibilityState !== 'visible' || !_user) return;
      const s = await getSession();
      if (!s) window.location.href = '/login.html';
    });
  }

  window.Stello = {
    getSession,
    getUserId,
    getDisplayName,
    requireAuth,
    apiFetch,
    signInWithApple,
    passkeysSupported,
    signInWithPasskey,
    registerPasskey,
    listPasskeys,
    deletePasskey,
    signOut,
    checkForUpdate,
    initAuthListener,
  };
})();
