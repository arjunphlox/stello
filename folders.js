/**
 * Stello — folder sources on the web (folder engine plan, section 4b).
 *
 * Phase 2, part 1: read-only. The person adds one or more Stello folders; each
 * is indexed (item id → file path) so the Settings panel can list the folders
 * and every item's panel can show which folder holds it. Nothing here writes
 * to a folder, and the grid still reads D1.
 *
 * Folders open through File System Access, so this works in Chrome, Edge and
 * Arc on a computer. Google Drive and Dropbox come in phase 3. Folder handles
 * and the index live in IndexedDB on this browser only; the index survives a
 * reload, so panels show folders before the folder is reconnected.
 *
 * An item's folder comes from where its file sits; it is never written into
 * the file. The same item in two folders shows once and lists both (Arjun's
 * pick, Nov 28 2026). Removing a folder only forgets it here: the folder and
 * its files are never touched.
 *
 * Browser: `window.StelloFolders`. Node (tests): `require('./folders')` for
 * the pure helpers.
 */
(function (root) {
  'use strict';

  // ---------------------------------------------------------- pure helpers

  /** Item id from the start of a Stello .md file, or null. Header lines are `key: <json>`. */
  function headerId(text) {
    const src = String(text || '');
    if (!/^---\r?\n/.test(src)) return null;
    const end = src.search(/\r?\n---\r?\n/);
    const head = end < 0 ? src : src.slice(0, end);
    const m = /^id:[ \t]*("(?:[^"\\]|\\.)*"|[^\s#]+)[ \t]*\r?$/m.exec(head);
    if (!m) return null;
    let v = m[1];
    if (v.startsWith('"')) { try { v = JSON.parse(v); } catch { return null; } }
    v = String(v).trim();
    return v || null;
  }

  /** Folders Stello walks for items; media/ and projects/ hold no items, dot-folders are private. */
  function skipDir(name) {
    return !name || name.startsWith('.') || name === 'media' || name === 'projects' || name === 'node_modules';
  }

  /**
   * Item id → folders that hold it, in the order the folders were added.
   * `folders` = [{ id, name, addedAt }], `indexes` = { folderId: { path: { id } } }.
   */
  function buildLookup(folders, indexes) {
    const byItem = new Map();
    const ordered = folders.slice().sort((a, b) => (a.addedAt || 0) - (b.addedAt || 0));
    for (const f of ordered) {
      const files = (indexes[f.id] && indexes[f.id].files) || {};
      for (const [path, entry] of Object.entries(files)) {
        if (!entry || !entry.id) continue;
        let list = byItem.get(entry.id);
        if (!list) byItem.set(entry.id, (list = []));
        if (!list.some((x) => x.folderId === f.id)) list.push({ folderId: f.id, name: f.name, path });
      }
    }
    return byItem;
  }

  /** "12 min ago" style label for a scan time. */
  function agoLabel(ms, now = Date.now()) {
    if (!ms) return 'not read yet';
    const s = Math.max(0, Math.round((now - ms) / 1000));
    if (s < 60) return 'just now';
    const m = Math.round(s / 60);
    if (m < 60) return `${m} min ago`;
    const h = Math.round(m / 60);
    if (h < 24) return `${h} h ago`;
    const d = Math.round(h / 24);
    return `${d} day${d === 1 ? '' : 's'} ago`;
  }

  const pure = { headerId, skipDir, buildLookup, agoLabel };
  if (typeof window === 'undefined') {
    if (typeof module !== 'undefined') module.exports = pure;
    return;
  }

  // ---------------------------------------------------------- IndexedDB

  const DB_NAME = 'stello-folders';
  const STORES = ['folders', 'indexes'];
  let dbPromise = null;
  function db() {
    if (!dbPromise) {
      dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open(DB_NAME, 1);
        req.onupgradeneeded = () => {
          for (const s of STORES) if (!req.result.objectStoreNames.contains(s)) req.result.createObjectStore(s, { keyPath: 'id' });
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    }
    return dbPromise;
  }
  async function tx(store, mode, fn) {
    const d = await db();
    return new Promise((resolve, reject) => {
      const t = d.transaction(store, mode);
      const s = t.objectStore(store);
      const out = fn(s);
      t.oncomplete = () => resolve(out && 'result' in out ? out.result : undefined);
      t.onerror = () => reject(t.error);
      t.onabort = () => reject(t.error);
    });
  }
  const getAll = (store) => tx(store, 'readonly', (s) => s.getAll());
  const put = (store, value) => tx(store, 'readwrite', (s) => s.put(value));
  const del = (store, key) => tx(store, 'readwrite', (s) => s.delete(key));

  // ---------------------------------------------------------- state

  const supported = typeof window.showDirectoryPicker === 'function';
  let folders = [];          // [{ id, name, handle, addedAt, count, scannedAt, status, error }]
  let indexes = {};          // folderId → { id, files: { path: { id, mtime } } }
  let lookup = new Map();
  let ready = null;
  const scanning = new Set();

  function emit() {
    lookup = buildLookup(folders, indexes);
    document.dispatchEvent(new CustomEvent('stello:folderschange'));
  }

  function load() {
    if (!ready) {
      ready = (async () => {
        try {
          const [f, ix] = await Promise.all([getAll('folders'), getAll('indexes')]);
          folders = f || [];
          indexes = Object.fromEntries((ix || []).map((x) => [x.id, x]));
          for (const folder of folders) folder.status = await permission(folder, false);
        } catch (e) {
          console.warn('[folders] could not open the folder list', e);
          folders = []; indexes = {};
        }
        emit();
        // Re-read folders already allowed (Chrome keeps the grant for installed apps and "Allow on every visit").
        for (const folder of folders) if (folder.status === 'granted') scan(folder.id);
      })();
    }
    return ready;
  }

  async function permission(folder, ask) {
    if (!folder.handle || !folder.handle.queryPermission) return 'missing';
    const opts = { mode: 'read' };
    let state = await folder.handle.queryPermission(opts);
    if (state !== 'granted' && ask) state = await folder.handle.requestPermission(opts);
    return state === 'granted' ? 'granted' : 'needs-access';
  }

  function saveFolder(folder) {
    const { status, error, ...rest } = folder;
    return put('folders', rest);
  }

  // ---------------------------------------------------------- scanning

  /** Walks a folder for .md files, reading only the start of files that changed. */
  async function scan(folderId) {
    const folder = folders.find((f) => f.id === folderId);
    if (!folder || scanning.has(folderId)) return;
    scanning.add(folderId);
    folder.status = 'reading';
    folder.error = null;
    emit();
    const prev = (indexes[folderId] && indexes[folderId].files) || {};
    const files = {};
    let pending = [];
    const flush = async () => {
      const batch = pending; pending = [];
      await Promise.all(batch.map(async ({ path, handle }) => {
        try {
          const file = await handle.getFile();
          const old = prev[path];
          if (old && old.mtime === file.lastModified && old.size === file.size) { files[path] = old; return; }
          const id = headerId(await file.slice(0, 4096).text());
          if (id) files[path] = { id, mtime: file.lastModified, size: file.size };
        } catch { /* unreadable file: skip */ }
      }));
    };
    const walk = async (dir, prefix) => {
      for await (const [name, handle] of dir.entries()) {
        if (handle.kind === 'directory') {
          if (!skipDir(name)) await walk(handle, `${prefix}${name}/`);
        } else if (name.endsWith('.md') && !name.startsWith('.')) {
          pending.push({ path: `${prefix}${name}`, handle });
          if (pending.length >= 48) await flush();
        }
      }
    };
    try {
      await walk(folder.handle, '');
      await flush();
      indexes[folderId] = { id: folderId, files };
      folder.count = new Set(Object.values(files).map((e) => e.id)).size;
      folder.scannedAt = Date.now();
      folder.status = 'granted';
      await put('indexes', indexes[folderId]);
      await saveFolder(folder);
    } catch (e) {
      console.warn('[folders] read failed', e);
      folder.status = e && e.name === 'NotAllowedError' ? 'needs-access' : 'error';
      folder.error = e && e.name === 'NotFoundError' ? 'Not reachable. It may have moved: use Replace.' : 'Not reachable right now.';
    } finally {
      scanning.delete(folderId);
      emit();
    }
  }

  // ---------------------------------------------------------- actions

  async function pick() {
    try {
      return await window.showDirectoryPicker({ id: 'stello-folder', mode: 'read' });
    } catch (e) {
      if (e && e.name === 'AbortError') return null;
      throw e;
    }
  }

  async function sameAsExisting(handle, exceptId) {
    for (const f of folders) {
      if (f.id === exceptId || !f.handle || !f.handle.isSameEntry) continue;
      try { if (await f.handle.isSameEntry(handle)) return { duplicate: f }; } catch { /* ignore */ }
      // One folder inside another would count its files twice.
      try { if (f.handle.resolve && (await f.handle.resolve(handle))) return { covered: f }; } catch { /* ignore */ }
      try { if (handle.resolve && (await handle.resolve(f.handle))) return { covers: f }; } catch { /* ignore */ }
    }
    return null;
  }

  /** Add a folder: pick, remember, read. Returns the folder, or null when cancelled. */
  async function add() {
    await load();
    const handle = await pick();
    if (!handle) return null;
    const clash = await sameAsExisting(handle);
    if (clash) return clash;
    const folder = {
      id: (crypto.randomUUID && crypto.randomUUID()) || `f-${Date.now()}`,
      name: handle.name, handle, addedAt: Date.now(), count: 0, scannedAt: 0, status: 'granted',
    };
    folders.push(folder);
    await saveFolder(folder);
    emit();
    scan(folder.id);
    return folder;
  }

  /** Replace: point an entry at another folder (a moved or renamed copy). Keeps its place in the list. */
  async function replace(folderId) {
    await load();
    const folder = folders.find((f) => f.id === folderId);
    if (!folder) return null;
    const handle = await pick();
    if (!handle) return null;
    const clash = await sameAsExisting(handle, folderId);
    if (clash) return clash;
    folder.handle = handle;
    folder.name = handle.name;
    folder.status = 'granted';
    await saveFolder(folder);
    scan(folderId);
    return folder;
  }

  /** Remove: Stello forgets the folder and hides its items' folder rows. The folder and files stay as they are. */
  async function remove(folderId) {
    await load();
    folders = folders.filter((f) => f.id !== folderId);
    delete indexes[folderId];
    await Promise.all([del('folders', folderId), del('indexes', folderId)]);
    emit();
  }

  /** Ask the browser for access again (Chrome asks once per visit unless allowed on every visit). */
  async function reconnect(folderId) {
    await load();
    const folder = folders.find((f) => f.id === folderId);
    if (!folder) return;
    folder.status = await permission(folder, true);
    emit();
    if (folder.status === 'granted') scan(folderId);
  }

  function list() {
    return folders
      .slice()
      .sort((a, b) => (a.addedAt || 0) - (b.addedAt || 0))
      .map(({ handle, ...f }) => ({ ...f, reading: scanning.has(f.id) }));
  }

  /** Folders holding an item: [{ folderId, name, path }], oldest-added folder first. */
  function foldersFor(itemId) {
    return (itemId && lookup.get(itemId)) || [];
  }

  root.StelloFolders = { supported, load, list, add, replace, remove, reconnect, rescan: scan, foldersFor, agoLabel };
})(typeof window !== 'undefined' ? window : globalThis);
