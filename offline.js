/* === Stello — offline copy of the library (web) ===
 *
 * Three layers, all on this device only:
 *   1. Text of every item (IndexedDB `items`), so the grid, search and
 *      filters work with no network. ~2 KB per item, ~20 MB at 10k items.
 *   2. Images for the "offline set" (Cache Storage `stello-offline-img-v1`):
 *      every item saved in the last 4 weeks, then items the user picked with
 *      "Save Offline", newest pick first, capped at OFFLINE_CAP items.
 *   3. The app itself, cached by sw.js.
 *
 * sw.js answers /img/* from layer 2 first, so the same <img src> works
 * online and offline. Changes made offline are not queued: writes need the
 * network (see Stello.apiFetch).
 */
(function (root) {
  'use strict';

  const OFFLINE_CAP = 1000;
  const RECENT_DAYS = 28;
  const IMG_CACHE = 'stello-offline-img-v1';
  const DB_NAME = 'stello-offline';
  const DB_VERSION = 1;
  const FETCH_CONCURRENCY = 4;

  // ---- Pure helpers (also used by test/offline.test.js) ----

  function itemTime(item) {
    const t = Date.parse(item && item.added_at);
    return Number.isFinite(t) ? t : 0;
  }

  /** All image URLs one item shows (grid card + detail panel). */
  function imageUrls(item) {
    const out = new Set();
    for (const img of (Array.isArray(item.images) ? item.images : [])) {
      if (img && typeof img.path === 'string' && img.path.startsWith('/img/')) out.add(img.path);
    }
    if (typeof item.og_image_path === 'string' && item.og_image_path.startsWith('/img/')) out.add(item.og_image_path);
    return [...out];
  }

  /**
   * Which items keep their images offline. Recent items first (newest first),
   * then picks (newest pick first), at most `cap` items in all.
   * pins: Map<slug, pinnedAtMs>. Returns { slugs: Set, recent, pinned, dropped }.
   */
  function pickOfflineSet(items, pins, now = Date.now(), cap = OFFLINE_CAP) {
    const cutoff = now - RECENT_DAYS * 86400000;
    const recent = items.filter(i => !i.deleted_at && itemTime(i) >= cutoff)
      .sort((a, b) => itemTime(b) - itemTime(a));
    const slugs = new Set();
    for (const i of recent) { if (slugs.size >= cap) break; slugs.add(i.slug); }
    const recentCount = slugs.size;
    const live = new Set(items.filter(i => !i.deleted_at).map(i => i.slug));
    const picks = [...pins.entries()].filter(([s]) => live.has(s)).sort((a, b) => b[1] - a[1]);
    const dropped = [];
    for (const [s] of picks) {
      if (slugs.has(s)) continue;
      if (slugs.size >= cap) { dropped.push(s); continue; }
      slugs.add(s);
    }
    return { slugs, recent: recentCount, pinned: slugs.size - recentCount, dropped };
  }

  const api = { OFFLINE_CAP, RECENT_DAYS, IMG_CACHE, imageUrls, pickOfflineSet };

  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }

  // ---- IndexedDB ----

  let _db = null;
  function openDb() {
    if (_db) return _db;
    _db = new Promise((resolve, reject) => {
      if (!root.indexedDB) { reject(new Error('no indexedDB')); return; }
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains('items')) db.createObjectStore('items', { keyPath: 'slug' });
        if (!db.objectStoreNames.contains('pins')) db.createObjectStore('pins', { keyPath: 'slug' });
        if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta', { keyPath: 'key' });
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    _db.catch(() => { _db = null; });
    return _db;
  }

  function done(tx) {
    return new Promise((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || new Error('aborted'));
    });
  }
  function result(req) {
    return new Promise((resolve, reject) => {
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  // Fields the UI derives at load time (normalizeItem) or never needs offline.
  const SKIP_FIELDS = ['enrichment_candidates'];
  function slim(item) {
    const o = {};
    for (const k in item) if (!SKIP_FIELDS.includes(k)) o[k] = item[k];
    return o;
  }

  /** Replace the stored library with `items` (the full, freshly loaded list).
   *  Written in chunks so a 10k library never blocks the page for long; the
   *  `library` meta row is written last, so a half-written copy is ignored. */
  async function saveLibrary(userId, items) {
    if (!userId) return;
    const db = await openDb();
    let tx = db.transaction(['items', 'meta'], 'readwrite');
    tx.objectStore('meta').delete('library');
    tx.objectStore('items').clear();
    await done(tx);
    const CHUNK = 250;
    for (let i = 0; i < items.length; i += CHUNK) {
      tx = db.transaction('items', 'readwrite');
      const store = tx.objectStore('items');
      for (const item of items.slice(i, i + CHUNK)) if (item && item.slug) store.put(slim(item));
      await done(tx);
      await new Promise(r => setTimeout(r, 0)); // let input + rendering run between chunks
    }
    tx = db.transaction('meta', 'readwrite');
    tx.objectStore('meta').put({ key: 'library', userId, savedAt: Date.now(), count: items.length });
    await done(tx);
  }

  /** The stored library for this user, or null (none, or another user's). */
  async function loadLibrary(userId) {
    try {
      const db = await openDb();
      const tx = db.transaction(['items', 'meta'], 'readonly');
      const meta = await result(tx.objectStore('meta').get('library'));
      if (!meta || meta.userId !== userId) return null;
      const items = await result(tx.objectStore('items').getAll());
      return { items, savedAt: meta.savedAt };
    } catch { return null; }
  }

  let _pins = null; // Map<slug, pinnedAt>
  async function loadPins() {
    if (_pins) return _pins;
    try {
      const db = await openDb();
      const rows = await result(db.transaction('pins').objectStore('pins').getAll());
      _pins = new Map(rows.map(r => [r.slug, r.pinnedAt]));
    } catch { _pins = new Map(); }
    return _pins;
  }
  async function setPinned(slug, on) {
    const pins = await loadPins();
    const db = await openDb();
    const tx = db.transaction('pins', 'readwrite');
    if (on) { const at = Date.now(); tx.objectStore('pins').put({ slug, pinnedAt: at }); pins.set(slug, at); }
    else { tx.objectStore('pins').delete(slug); pins.delete(slug); }
    await done(tx);
  }
  function isPinned(slug) { return !!(_pins && _pins.has(slug)); }

  // ---- Images ----

  let _offlineSlugs = new Set();
  let _syncing = null;
  let _again = false;

  /** Bring the image cache in line with the offline set. Safe to call often. */
  function syncImages(items) {
    if (_syncing) { _again = items; return _syncing; }
    _syncing = (async () => {
      let next = items;
      while (next) {
        _again = false;
        await syncOnce(next).catch(err => console.warn('[offline] image sync failed', err));
        next = _again || null;
      }
    })().finally(() => { _syncing = null; });
    return _syncing;
  }

  async function syncOnce(items) {
    if (!root.caches) return;
    const pins = await loadPins();
    const set = pickOfflineSet(items, pins);
    _offlineSlugs = set.slugs;
    root.dispatchEvent(new CustomEvent('stello:offline-set', { detail: set }));

    const want = new Set();
    for (const item of items) if (set.slugs.has(item.slug)) imageUrls(item).forEach(u => want.add(u));

    const cache = await caches.open(IMG_CACHE);
    const have = new Set((await cache.keys()).map(r => new URL(r.url).pathname));
    await Promise.all([...have].filter(u => !want.has(u)).map(u => cache.delete(u)));

    const todo = [...want].filter(u => !have.has(u));
    if (!todo.length || !navigator.onLine) return;
    if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
    let i = 0;
    async function worker() {
      while (i < todo.length && navigator.onLine && !_again) {
        const url = todo[i++];
        try {
          const res = await fetch(url, { credentials: 'same-origin' });
          if (res.ok) await cache.put(url, res);
        } catch { /* offline or a missing image; next sync retries */ }
      }
    }
    await Promise.all(Array.from({ length: FETCH_CONCURRENCY }, worker));
  }

  function isOffline(slug) { return _offlineSlugs.has(slug); }
  function offlineCount() { return _offlineSlugs.size; }

  /** Sign-out: nothing of this account stays on the device. */
  async function clearAll() {
    _pins = null; _offlineSlugs = new Set();
    try { if (root.caches) await caches.delete(IMG_CACHE); } catch {}
    try {
      const db = await openDb();
      const tx = db.transaction(['items', 'pins', 'meta'], 'readwrite');
      ['items', 'pins', 'meta'].forEach(s => tx.objectStore(s).clear());
      await done(tx);
    } catch {}
  }

  // ---- App shell ----

  function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) return;
    // The desktop-context bridge and local dev serve from localhost; a cached
    // shell there would hide edits.
    const local = location.hostname === 'localhost' || location.hostname === '127.0.0.1';
    let devOptIn = false;
    try { devOptIn = localStorage.getItem('stello.sw.dev') === '1'; } catch {}
    if (local && !devOptIn) return;
    navigator.serviceWorker.register('/sw.js').then(() => navigator.serviceWorker.ready).then(reg => {
      // Tell the worker which files this page loaded, so the next offline
      // launch has the same versions (?v=…) of app.js, style.css, fonts, …
      const urls = [location.pathname === '/' ? '/' : location.pathname];
      for (const e of performance.getEntriesByType('resource')) {
        const u = new URL(e.name);
        if (u.origin === location.origin && !u.pathname.startsWith('/api/') && !u.pathname.startsWith('/img/')) urls.push(u.pathname + u.search);
        else if (u.hostname === 'cdn.jsdelivr.net') urls.push(u.href);
      }
      if (reg.active) reg.active.postMessage({ type: 'precache', urls });
    }).catch(err => console.warn('[offline] service worker failed', err));
  }

  Object.assign(api, {
    saveLibrary, loadLibrary, loadPins, setPinned, isPinned,
    syncImages, isOffline, offlineCount, clearAll, registerServiceWorker,
  });
  root.StelloOffline = api;
})(typeof self !== 'undefined' ? self : this);
