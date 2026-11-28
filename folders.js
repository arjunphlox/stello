/**
 * Stello — folder sources on the web (folder engine plan, section 4b).
 *
 * The person adds one or more Stello folders; each is indexed (item id → file
 * path) so the Settings panel can list the folders and every item's panel can
 * show which folder holds it. The grid still reads D1; the folders are kept
 * beside it (phase 2, part 2):
 *   - One folder takes new saves ("New saves go here"; the first added by default).
 *   - A new save or an edit writes the item's v2 file (src/lib/folder-write.js,
 *     served as /lib/folder-write.js). An item already in a folder is written to
 *     its main copy (the oldest-added folder holding it). Opening an item never writes.
 *   - A file changed outside Stello since Stello last wrote it is merged, never
 *     overwritten: tags and links combine, the newer value wins, both notes kept.
 *     Copies of one item in two folders merge the same way into the main copy.
 *   - Delete moves every copy to its own folder's .trash/<day>/; day folders older
 *     than 30 days are cleared on the next read.
 *   - The first time writes are possible on this browser, Stello only records what
 *     each item looks like (a baseline), so turning writes on never rewrites the folder.
 *   - Part 3: per folder, asked on Add, Stello also reads the person's own Markdown, text,
 *     CSV, bookmark and link files (src/lib/folder-ingest.js). Each new link becomes a plain
 *     link item, the same id on every device, saved as a Markdown file in that folder. A
 *     link already saved isn't added twice. The source files stay in the folder but don't
 *     show in Stello, and are never written, moved or trashed (`copiesOf` leaves them out).
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

  /** id/name/kind/aliases from a people/ or places/ file's header (one JSON value per line). */
  function headerEntity(text) {
    const id = headerId(text);
    if (!id) return null;
    const src = String(text);
    const end = src.search(/\r?\n---\r?\n/);
    const head = end < 0 ? src : src.slice(0, end);
    const val = (key) => {
      const m = new RegExp(`^${key}:[ \\t]*(.+?)[ \\t]*\\r?$`, 'm').exec(head);
      if (!m) return null;
      try { return JSON.parse(m[1]); } catch { return null; }
    };
    const aliases = val('aliases');
    return { id, name: val('name') || id, kind: val('kind') || null, aliases: Array.isArray(aliases) ? aliases : [] };
  }

  /** Item ids are UUIDs; people and places that exist only as files have person-/place- ids. */
  function isLibraryId(id) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(id || ''));
  }

  /**
   * Library items a folder holds: people and places files that aren't saves don't count.
   * Spreadsheets and exports don't show, so an item made from one counts once its own
   * Markdown file is written.
   */
  function countItems(files) {
    const ids = new Set();
    for (const e of Object.values(files || {})) if (e && isLibraryId(e.id)) ids.add(e.id.toLowerCase());
    return ids.size;
  }

  /** The person's own files a folder reads links from (part 3), when it reads them. */
  function ingestFile(name) {
    return !!name && !name.startsWith('.') && /\.(md|markdown|txt|webloc|url|csv|html?)$/i.test(name);
  }

  /** The folder that takes new saves: the one marked, else the oldest-added. */
  function savesFolder(folders) {
    const ordered = folders.slice().sort((a, b) => (a.addedAt || 0) - (b.addedAt || 0));
    return ordered.find((f) => f.takesSaves) || ordered[0] || null;
  }

  /** Folders Stello walks for items; media/ and projects/ hold no items, dot-folders are private. */
  function skipDir(name) {
    return !name || name.startsWith('.') || name === 'media' || name === 'projects' || name === 'node_modules';
  }

  /**
   * Item id → folders that hold it, in the order the folders were added.
   * `folders` = [{ id, name, addedAt }], `indexes` = { folderId: { files: { path: { id } }, found? } }.
   * A Stello file is a copy ({ folderId, name, path }); a file of the person's own that
   * lists the item's link is marked `found: true` (Stello never writes or moves those).
   */
  function buildLookup(folders, indexes) {
    const byItem = new Map();
    const ordered = folders.slice().sort((a, b) => (a.addedAt || 0) - (b.addedAt || 0));
    const note = (id, loc) => {
      let list = byItem.get(id);
      if (!list) byItem.set(id, (list = []));
      if (!list.some((x) => x.folderId === loc.folderId && !!x.found === !!loc.found)) list.push(loc);
    };
    for (const f of ordered) {
      const files = (indexes[f.id] && indexes[f.id].files) || {};
      for (const [path, entry] of Object.entries(files)) {
        if (entry && entry.id) note(entry.id, { folderId: f.id, name: f.name, path });
      }
    }
    for (const f of ordered) {
      const found = (indexes[f.id] && indexes[f.id].found) || {};
      for (const [path, rec] of Object.entries(found)) {
        for (const l of (rec && rec.links) || []) if (l && l.id) note(l.id, { folderId: f.id, name: f.name, path, found: true });
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

  const pure = { headerId, headerEntity, isLibraryId, countItems, ingestFile, savesFolder, skipDir, buildLookup, agoLabel };
  if (typeof window === 'undefined') {
    if (typeof module !== 'undefined') module.exports = pure;
    return;
  }

  // ---------------------------------------------------------- IndexedDB

  const DB_NAME = 'stello-folders';
  // v2 (part 2): `written` = per item what Stello last wrote ({ id, fp, folderId, path, mtime, size }),
  // `meta` = small flags ({ id: 'baseline', at }).
  const STORES = ['folders', 'indexes', 'written', 'meta'];
  let dbPromise = null;
  function db() {
    if (!dbPromise) {
      dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open(DB_NAME, 2);
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
  const get = (store, key) => tx(store, 'readonly', (s) => s.get(key));
  const put = (store, value) => tx(store, 'readwrite', (s) => s.put(value));
  const putMany = (store, values) => tx(store, 'readwrite', (s) => { for (const v of values) s.put(v); });
  const del = (store, key) => tx(store, 'readwrite', (s) => s.delete(key));

  // ---------------------------------------------------------- state

  const supported = typeof window.showDirectoryPicker === 'function';
  let folders = [];          // [{ id, name, handle, addedAt, takesSaves, count, scannedAt, status, error }]
  let indexes = {};          // folderId → { id, files: { path: { id, mtime, size, ent? } } }
  let lookup = new Map();
  let ready = null;
  const scanning = new Set();
  // While a folder is being read: paths Stello wrote (entry) or moved away (null) meanwhile.
  const duringScan = new Map();

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
          for (const folder of folders) {
            folder.status = await permission(folder, false);
            if (indexes[folder.id]) folder.count = countItems(indexes[folder.id].files);
          }
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

  // Read and write: Stello writes saves, edits and .trash moves (part 2). A folder
  // allowed read-only in part 1 asks once more.
  async function permission(folder, ask) {
    if (!folder.handle || !folder.handle.queryPermission) return 'missing';
    const opts = { mode: 'readwrite' };
    let state = await folder.handle.queryPermission(opts);
    if (state !== 'granted' && ask) state = await folder.handle.requestPermission(opts);
    return state === 'granted' ? 'granted' : 'needs-access';
  }

  function saveFolder(folder) {
    const { status, error, ...rest } = folder;
    return put('folders', rest);
  }

  // ---------------------------------------------------------- file helpers

  /** Directory handle for a folder-relative dir path, created when `create`. */
  async function dirAt(root, dirPath, create) {
    let dir = root;
    for (const seg of String(dirPath || '').split('/').filter(Boolean)) dir = await dir.getDirectoryHandle(seg, { create });
    return dir;
  }
  const split = (path) => { const i = path.lastIndexOf('/'); return [i < 0 ? '' : path.slice(0, i), path.slice(i + 1)]; };
  async function fileAt(root, path, create = false) {
    const [d, n] = split(path);
    return (await dirAt(root, d, create)).getFileHandle(n, { create });
  }
  async function readText(root, path) {
    try { const f = await (await fileAt(root, path)).getFile(); return { text: await f.text(), mtime: f.lastModified, size: f.size }; }
    catch { return null; }
  }
  /** Writes through the browser's swap file, so a cut-off write never leaves half a file. */
  async function writeFile(root, path, data) {
    const h = await fileAt(root, path, true);
    const w = await h.createWritable();
    await w.write(data);
    await w.close();
    const f = await h.getFile();
    return { mtime: f.lastModified, size: f.size };
  }
  async function exists(root, path) {
    try { await fileAt(root, path); return true; } catch { return false; }
  }
  /** Moves a file inside one folder (copy then remove where the browser has no move()). */
  async function moveFile(root, from, to) {
    const src = await fileAt(root, from);
    const [d, n] = split(to);
    const dest = await dirAt(root, d, true);
    if (typeof src.move === 'function') {
      try { await src.move(dest, n); return; } catch { /* fall back to copy */ }
    }
    const file = await src.getFile();
    const w = await (await dest.getFileHandle(n, { create: true })).createWritable();
    await w.write(file);
    await w.close();
    const [fd, fn] = split(from);
    await (await dirAt(root, fd, false)).removeEntry(fn);
  }

  let writer = null;
  /** The shared writer (src/lib/folder-write.js), loaded the first time Stello writes. */
  function lib() {
    if (!writer) writer = import(new URL('lib/folder-write.js', document.baseURI).href);
    return writer;
  }
  let ingester = null;
  /** The shared reader of the person's own files (src/lib/folder-ingest.js). */
  function ingestLib() {
    if (!ingester) ingester = import(new URL('lib/folder-ingest.js', document.baseURI).href);
    return ingester;
  }

  // ---------------------------------------------------------- scanning

  /** Walks a folder for .md files, reading only the start of files that changed. */
  async function scan(folderId) {
    const folder = folders.find((f) => f.id === folderId);
    if (!folder || scanning.has(folderId)) return;
    scanning.add(folderId);
    duringScan.set(folderId, new Map());
    folder.status = 'reading';
    folder.error = null;
    emit();
    const prev = (indexes[folderId] && indexes[folderId].files) || {};
    const prevFound = (indexes[folderId] && indexes[folderId].found) || {};
    const ingest = !!folder.ingest;
    const files = {};
    // The person's own files (part 3, when the folder reads them): unchanged ones keep
    // their links; changed ones are marked stale and read in full by ingestFolder.
    const found = {};
    const changed = new Set();
    let pending = [];
    const maybeFound = (path, file) => {
      if (!ingest || file.size > 20 * 1024 * 1024) return;
      const old = prevFound[path];
      if (old && old.mtime === file.lastModified && old.size === file.size && !old.stale) { found[path] = old; return; }
      found[path] = { mtime: file.lastModified, size: file.size, links: (old && old.links) || [], stale: true };
      if (old && old.self) found[path].self = old.self;
    };
    const flush = async () => {
      const batch = pending; pending = [];
      await Promise.all(batch.map(async ({ path, handle }) => {
        try {
          const file = await handle.getFile();
          if (!path.endsWith('.md')) { maybeFound(path, file); return; }
          const old = prev[path];
          const isEntity = /^(people|places)\//.test(path);
          // A written note Stello made into an item: still read for the links it lists.
          const self = ingest && prevFound[path] && prevFound[path].self;
          if (old && old.mtime === file.lastModified && old.size === file.size && !(isEntity && !old.ent)) {
            files[path] = old;
            if (self && self === old.id) maybeFound(path, file);
            return;
          }
          const kept = prevFound[path];
          if (kept && kept.mtime === file.lastModified && kept.size === file.size && !kept.stale) { if (ingest) found[path] = kept; return; }
          const head = await file.slice(0, 4096).text();
          const id = headerId(head);
          if (!id) { maybeFound(path, file); return; }
          const entry = { id, mtime: file.lastModified, size: file.size };
          if (isEntity) entry.ent = headerEntity(head);
          files[path] = entry;
          changed.add(id);
          if (self && self === id) maybeFound(path, file);
        } catch { /* unreadable file: skip */ }
      }));
    };
    const walk = async (dir, prefix) => {
      for await (const [name, handle] of dir.entries()) {
        if (handle.kind === 'directory') {
          if (!skipDir(name)) await walk(handle, `${prefix}${name}/`);
        } else if ((name.endsWith('.md') && !name.startsWith('.')) || (ingest && ingestFile(name))) {
          pending.push({ path: `${prefix}${name}`, handle });
          if (pending.length >= 48) await flush();
        }
      }
    };
    try {
      await walk(folder.handle, '');
      await flush();
      // Writes and .trash moves Stello made while the read ran win over what it saw.
      for (const [path, entry] of duringScan.get(folderId) || []) { if (entry) files[path] = entry; else delete files[path]; }
      indexes[folderId] = { id: folderId, files, found };
      folder.count = countItems(files);
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
      duringScan.delete(folderId);
      emit();
    }
    if (folder.status === 'granted') {
      clearTrash(folder).catch((e) => console.warn('[folders] trash clear-out failed', e));
      if (changed.size) mergeCopies(changed, folderId).catch((e) => console.warn('[folders] merge failed', e));
      if (folder.ingest) ingestFolder(folderId).catch((e) => console.warn('[folders] reading files failed', e));
    }
  }

  // ---------------------------------------------------------- the person's own files (part 3)

  // The app hands over the library once it is fully in memory: { items(), push(changes), added(rows) }.
  let host = null;
  const ingesting = new Set();
  const ingestAgain = new Set();
  // Item id → the folder whose spreadsheet or export it came from: its Markdown file goes there.
  const origin = new Map();

  /** The library is in memory: read the files of folders that turn them into items. */
  function setLibrary(h) {
    host = h;
    for (const f of folders) if (f.ingest && indexes[f.id]) ingestFolder(f.id).catch((e) => console.warn('[folders] reading files failed', e));
  }

  /**
   * Reads the changed files of a folder that turns its other files into items, and adds
   * an item for every link the library doesn't hold yet (no AI, no page reads: plain links
   * the Mac sorts later). A link already saved just gains this file in its Folder row.
   * A link that leaves a file keeps its item (Arjun's pick); only the Folder row goes.
   */
  async function ingestFolder(folderId) {
    const folder = folders.find((f) => f.id === folderId);
    const ix = indexes[folderId];
    if (!host || !folder || !folder.ingest || !ix || !ix.found || !folder.handle) return 0;
    if (ingesting.has(folderId)) { ingestAgain.add(folderId); return 0; }
    const stale = Object.entries(ix.found).filter(([, r]) => r.stale);
    if (!stale.length) return 0;
    ingesting.add(folderId);
    let made = 0;
    try {
      const I = await ingestLib();
      const byKey = new Map();
      const ids = new Set();
      for (const it of host.items()) {
        if (!it || !it.id) continue;
        ids.add(String(it.id).toLowerCase());
        if (it.source_url) byKey.set(I.normaliseUrl(it.source_url), it.id);
      }
      const now = new Date().toISOString();
      const fresh = new Map();
      const undo = [];
      const notes = [];
      for (const [path, rec] of stale) {
        const r = await readText(folder.handle, path);
        if (!r) continue;
        // A note with real writing of its own is an item itself (its links still are too).
        if (!rec.self && I.isWrittenNote(path, r.text)) {
          const id = await I.noteItemId(path);
          const note = I.noteItem(path, r.text, { id, modified: r.mtime, now });
          if (note) {
            notes.push({ path, note, read: r });
            if (!ids.has(id)) fresh.set(id, note.change);
          }
        }
        const before = new Set((rec.links || []).map((l) => l.key));
        const links = I.readLinks(path, r.text, { modified: r.mtime });
        const out = [];
        for (const l of links) {
          let id = byKey.get(l.key);
          if (!id) {
            id = await I.linkItemId(l.key);
            // A link this file listed before whose item was deleted in Stello stays deleted.
            if (!ids.has(id) && !before.has(l.key) && !fresh.has(id)) fresh.set(id, I.linkChange(l, { id, now }));
          }
          out.push({ key: l.key, id });
        }
        undo.push([path, rec]);
        ix.found[path] = { mtime: r.mtime, size: r.size, links: out };
        if (rec.self) ix.found[path].self = rec.self;
      }
      // New items go up 100 at a time. Their clock is the oldest possible, so a link another
      // device already made into an item (and maybe sorted) is never overwritten.
      const changes = [...fresh.values()].map((c) => ({ ...c, clock: 1 }));
      const rows = [];
      try {
        for (let i = 0; i < changes.length; i += 100) {
          const batch = changes.slice(i, i + 100);
          const res = await host.push(batch);
          if (!res || !Array.isArray(res.results)) throw new Error('push failed');
          const applied = new Set(res.results.filter((x) => x.status === 'applied').map((x) => x.id));
          for (const c of batch) if (applied.has(c.id)) { origin.set(c.id, folderId); rows.push({ id: c.id, ...c.fields }); }
        }
      } catch (e) {
        // Offline or signed out: the files stay to read next time (a re-sent link is a no-op).
        for (const [path, rec] of undo) ix.found[path] = rec;
        throw e;
      }
      // Written notes get Stello's details at their top, before the grid shows them.
      for (const { path, note, read } of notes) {
        const item = rows.find((x) => x.id === note.id) || host.items().find((x) => x && x.id === note.id);
        if (!item) continue;
        try {
          if (await writeNote(folder, path, note, read, item)) ix.found[path].self = note.id;
        } catch (e) { console.warn('[folders] could not add details to a note', path, e); }
      }
      if (rows.length) { made += rows.length; host.added(rows); }
      folder.count = countItems(ix.files);
      await put('indexes', ix);
      await saveFolder(folder);
      emit();
    } finally {
      ingesting.delete(folderId);
    }
    if (ingestAgain.delete(folderId)) made += await ingestFolder(folderId);
    return made;
  }

  /**
   * Adds Stello's details at the top of a written note, keeping its text and its own
   * details. Skipped when the file changed since it was read (the next read tries again).
   */
  async function writeNote(folder, path, note, read, item) {
    if (!writable(folder)) return false;
    const now = await readText(folder.handle, path);
    if (!now || now.text !== read.text) return false;
    const W = await lib();
    const out = W.itemFile(item, { ...folderContext(folder.id), existing: { path, header: note.extra, body: note.body } });
    const stat = await writeFile(folder.handle, path, out.text);
    noteIndexed(folder.id, path, item.id, stat);
    origin.set(item.id, folder.id);
    await put('written', { id: item.id, fp: W.fingerprint(item), folderId: folder.id, path, mtime: stat.mtime, size: stat.size, extra: null });
    if (indexes[folder.id].found && indexes[folder.id].found[path]) Object.assign(indexes[folder.id].found[path], { mtime: stat.mtime, size: stat.size });
    return true;
  }

  /** Turn reading the folder's other files on or off. Off keeps the items already made. */
  async function setIngest(folderId, on) {
    await load();
    const folder = folders.find((f) => f.id === folderId);
    if (!folder || !!folder.ingest === !!on) return;
    folder.ingest = !!on;
    if (!on && indexes[folderId]) { delete indexes[folderId].found; await put('indexes', indexes[folderId]); }
    await saveFolder(folder);
    emit();
    if (on && folder.status === 'granted') scan(folderId);
  }

  /** Removes .trash/<day> folders older than 30 days. */
  async function clearTrash(folder) {
    const W = await lib();
    let trash;
    try { trash = await folder.handle.getDirectoryHandle(W.TRASH_DIR); } catch { return; }
    for await (const [name, handle] of trash.entries()) {
      if (handle.kind === 'directory' && W.trashExpired(name)) await trash.removeEntry(name, { recursive: true });
    }
  }

  // ---------------------------------------------------------- writing

  // 'reading' is a granted folder being re-read: writes go ahead meanwhile.
  const writable = (f) => f && (f.status === 'granted' || f.status === 'reading') && f.handle;
  let writeChain = Promise.resolve();
  /** One write at a time, so two edits to one item never race. */
  const serial = (fn) => (writeChain = writeChain.then(fn, fn));

  /** Entities and used paths for one folder, from its index. */
  function folderContext(folderId) {
    const files = (indexes[folderId] && indexes[folderId].files) || {};
    const entities = [];
    const paths = new Set();
    for (const [path, e] of Object.entries(files)) {
      paths.add(path.toLowerCase());
      if (e.ent) entities.push({ ...e.ent, type: path.startsWith('places/') ? 'place' : 'person', path });
    }
    return { entities, paths };
  }

  function noteIndexed(folderId, path, id, stat) {
    const ix = indexes[folderId] || (indexes[folderId] = { id: folderId, files: {} });
    ix.files[path] = { ...(ix.files[path] || {}), id, mtime: stat.mtime, size: stat.size };
    if (duringScan.has(folderId)) duringScan.get(folderId).set(path, ix.files[path]);
  }

  /** Copies an item's images into media/ (skipping ones already there). */
  async function copyMedia(root, media) {
    for (const m of media) {
      if (await exists(root, m.file)) continue;
      try {
        const url = /^https?:/i.test(m.remote) ? m.remote : new URL(m.remote, location.origin).href;
        const res = await fetch(url, { credentials: 'same-origin' });
        if (!res.ok) continue;
        await writeFile(root, m.file, await res.blob());
      } catch { /* an image that can't be fetched stays a link in the header */ }
    }
  }

  /**
   * Writes one item (sync API shape) to its main copy, or to the new-saves folder when no
   * folder holds it. Returns { folderId, path } or null when nothing could be written.
   */
  async function writeItem(item, fp) {
    const W = await lib();
    const where = copiesOf(item.id).find((l) => writable(folders.find((f) => f.id === l.folderId)));
    const from = origin.get(item.id) && folders.find((f) => f.id === origin.get(item.id));
    const target = where ? folders.find((f) => f.id === where.folderId) : writable(from) ? from : savesFolder(folders.filter(writable));
    if (!target || !writable(target)) return null;
    const root = target.handle;
    const ctx = folderContext(target.id);
    let existing = null;
    let current = null;
    if (where) {
      current = await readText(root, where.path);
      const copy = current && W.readCopy(current.text);
      if (copy) existing = { path: where.path, ...copy };
    }
    const out = W.itemFile(item, { ...ctx, existing });
    let text = out.text;
    // Notes a merge brought in from outside Stello (D1 doesn't hold them), kept on later writes.
    let extra = null;
    if (existing) {
      // Overwrite only a file Stello wrote last; anything else changed outside Stello is merged.
      const last = await get('written', item.id);
      const ours = last && last.path === where.path && last.folderId === target.id && last.mtime === current.mtime && last.size === current.size;
      if (!ours) {
        const edited = Date.parse(item.updated_at || '') || Date.now();
        const merged = W.mergeCopies({ header: out.header, body: out.body, mtime: edited }, { ...existing, mtime: current.mtime });
        text = W.copyText(merged);
        const mine = String(out.body || '').trim();
        if (merged.body !== mine) extra = mine && merged.body.startsWith(`${mine}\n\n`) ? merged.body.slice(mine.length + 2) : merged.body;
      } else if (last.extra) {
        extra = last.extra;
        text = W.copyText({ header: out.header, body: W.mergeNotes(String(out.body || '').trim(), extra) });
      }
      if (text === current.text) {
        await put('written', { id: item.id, fp, folderId: target.id, path: where.path, mtime: current.mtime, size: current.size, extra });
        return { folderId: target.id, path: where.path };
      }
    }
    for (const e of out.entities) {
      if (!(await exists(root, e.path))) noteIndexed(target.id, e.path, e.id, await writeFile(root, e.path, e.text));
      const ix = indexes[target.id].files[e.path];
      if (ix) ix.ent = { id: e.id, name: e.header.name, kind: e.header.kind, aliases: e.header.aliases || [] };
    }
    await copyMedia(root, out.media);
    const stat = await writeFile(root, out.path, text);
    noteIndexed(target.id, out.path, item.id, stat);
    await put('written', { id: item.id, fp, folderId: target.id, path: out.path, mtime: stat.mtime, size: stat.size, extra });
    await put('indexes', indexes[target.id]);
    target.count = countItems(indexes[target.id].files);
    return { folderId: target.id, path: out.path };
  }

  /** An item was saved or edited in Stello. Writes it when what a file holds changed. */
  function itemChanged(item) {
    if (!item || !item.id || !folders.some(writable)) return Promise.resolve(null);
    return serial(async () => {
      const W = await lib();
      // Turned on by syncLibrary first; items just made from a folder's files are written anyway.
      if (!(await get('meta', 'baseline')) && !origin.has(item.id)) return null;
      const fp = W.fingerprint(item);
      const last = await get('written', item.id);
      if (last && last.fp === fp) return null;
      try {
        const r = await writeItem(item, fp);
        if (r) emit();
        return r;
      } catch (e) {
        console.warn('[folders] write failed', item.id, e);
        return null;
      }
    });
  }

  /**
   * The whole library is in memory. The first time writes are possible on this browser this
   * only records each item's fingerprint (nothing is written). After that it writes items
   * whose fingerprint changed since Stello last saw them (edits made on another device).
   */
  function syncLibrary(items) {
    if (!folders.some(writable)) return Promise.resolve(0);
    return serial(async () => {
      const W = await lib();
      const baseline = await get('meta', 'baseline');
      if (!baseline) {
        const rows = items.filter((i) => i && i.id).map((i) => ({ id: i.id, fp: W.fingerprint(i) }));
        await putMany('written', rows);
        await put('meta', { id: 'baseline', at: Date.now(), items: rows.length });
        return 0;
      }
      const known = new Map((await getAll('written')).map((r) => [r.id, r]));
      let wrote = 0;
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (!item || !item.id) continue;
        const fp = W.fingerprint(item);
        const last = known.get(item.id);
        if (last && last.fp === fp) continue;
        try { if (await writeItem(item, fp)) wrote++; } catch (e) { console.warn('[folders] write failed', item.id, e); }
        if (i % 200 === 199) await new Promise((r) => setTimeout(r, 0)); // stay out of the way of scrolling
      }
      if (wrote) emit();
      return wrote;
    });
  }

  /**
   * Copies of one item in two folders: a copy that changed in `changedFolderId` is merged
   * into the main copy (oldest-added folder). A change to the main copy itself pulls
   * nothing in, so an edit made in Stello is never undone by an older copy elsewhere.
   */
  function mergeCopies(ids, changedFolderId) {
    return serial(async () => {
      const W = await lib();
      let merged = 0;
      for (const id of ids) {
        const locs = copiesOf(id).filter((l) => writable(folders.find((f) => f.id === l.folderId)));
        if (locs.length < 2 || locs[0].folderId === changedFolderId || !locs.some((l) => l.folderId === changedFolderId)) continue;
        const main = folders.find((f) => f.id === locs[0].folderId);
        const first = await readText(main.handle, locs[0].path);
        let acc = first && W.readCopy(first.text);
        if (!acc) continue;
        acc = { ...acc, mtime: first.mtime };
        for (const l of locs.slice(1)) {
          const r = await readText(folders.find((f) => f.id === l.folderId).handle, l.path);
          const copy = r && W.readCopy(r.text);
          if (copy) acc = { ...W.mergeCopies(acc, { ...copy, mtime: r.mtime }), mtime: Math.max(acc.mtime, r.mtime) };
        }
        const text = W.copyText(acc);
        if (text === first.text) continue;
        const stat = await writeFile(main.handle, locs[0].path, text);
        noteIndexed(main.id, locs[0].path, id, stat);
        merged++;
      }
      if (merged) { for (const f of folders) if (indexes[f.id]) await put('indexes', indexes[f.id]); emit(); }
      return merged;
    });
  }

  /** Deleted in Stello: every copy goes to its own folder's .trash/<day>/, with its images. */
  function itemDeleted(itemId) {
    const locs = copiesOf(itemId);
    if (!locs.length) return Promise.resolve(0);
    return serial(async () => {
      const W = await lib();
      let moved = 0;
      for (const l of locs) {
        const folder = folders.find((f) => f.id === l.folderId);
        if (!writable(folder)) continue;
        try {
          const r = await readText(folder.handle, l.path);
          const copy = r && W.readCopy(r.text);
          const dir = l.path.split('/').slice(0, -1);
          const media = new Set();
          for (const img of (copy && copy.header.images) || []) {
            if (!img || !img.file) continue;
            const parts = [...dir];
            for (const seg of String(img.file).split('/')) { if (seg === '..') parts.pop(); else if (seg && seg !== '.') parts.push(seg); }
            if (parts[0] === 'media') media.add(parts.join('/'));
          }
          await moveFile(folder.handle, l.path, W.trashPath(l.path));
          for (const m of media) { try { await moveFile(folder.handle, m, W.trashPath(m)); } catch { /* already gone */ } }
          delete indexes[folder.id].files[l.path];
          if (duringScan.has(folder.id)) duringScan.get(folder.id).set(l.path, null);
          folder.count = countItems(indexes[folder.id].files);
          await put('indexes', indexes[folder.id]);
          moved++;
        } catch (e) {
          console.warn('[folders] move to .trash failed', l.path, e);
        }
      }
      await del('written', itemId);
      emit();
      return moved;
    });
  }

  // ---------------------------------------------------------- actions

  async function pick() {
    try {
      return await window.showDirectoryPicker({ id: 'stello-folder', mode: 'readwrite' });
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

  /**
   * Add a folder: pick, then `choose(name)` asks what to read from it (resolves true for
   * "also its other files", false for Stello items only, null to cancel), remember, read.
   * Returns the folder, a clash, or null when cancelled.
   */
  async function add(choose) {
    await load();
    const handle = await pick();
    if (!handle) return null;
    const clash = await sameAsExisting(handle);
    if (clash) return clash;
    const ingest = typeof choose === 'function' ? await choose(handle.name) : false;
    if (ingest == null) return null;
    const folder = {
      id: (crypto.randomUUID && crypto.randomUUID()) || `f-${Date.now()}`,
      name: handle.name, handle, addedAt: Date.now(), takesSaves: !folders.length, count: 0, scannedAt: 0, status: 'granted',
      ingest: !!ingest,
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
    const wasSaves = savesFolder(folders) && savesFolder(folders).id === folderId;
    folders = folders.filter((f) => f.id !== folderId);
    delete indexes[folderId];
    await Promise.all([del('folders', folderId), del('indexes', folderId)]);
    // The next folder in the list takes new saves.
    if (wasSaves && folders.length) await setSavesFolder(savesFolder(folders.map((f) => ({ ...f, takesSaves: false }))).id);
    emit();
  }

  /** Marks the folder that takes new saves. */
  async function setSavesFolder(folderId) {
    await load();
    for (const f of folders) {
      const on = f.id === folderId;
      if (!!f.takesSaves !== on) { f.takesSaves = on; await saveFolder(f); }
    }
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
    const saves = savesFolder(folders);
    return folders
      .slice()
      .sort((a, b) => (a.addedAt || 0) - (b.addedAt || 0))
      .map(({ handle, ...f }) => ({ ...f, ingest: !!f.ingest, takesSaves: !!saves && saves.id === f.id, reading: scanning.has(f.id) || ingesting.has(f.id) }));
  }

  /** Folders holding an item: [{ folderId, name, path, found? }], oldest-added folder first. */
  function foldersFor(itemId) {
    return (itemId && lookup.get(itemId)) || [];
  }

  /** Only the item's Stello files: the person's own files are never written or moved. */
  function copiesOf(itemId) {
    return foldersFor(itemId).filter((l) => !l.found);
  }

  root.StelloFolders = {
    supported, load, list, add, replace, remove, reconnect, rescan: scan, foldersFor, agoLabel,
    setSavesFolder, itemChanged, itemDeleted, syncLibrary, setLibrary, setIngest,
  };
})(typeof window !== 'undefined' ? window : globalThis);
