/* === Stello — iCloud client (CloudKit JS) ===
 *
 * Stello's data lives in the user's private iCloud database, written by the
 * Mac/iPhone apps through SwiftData + CloudKit. The web app:
 *   - signs in with Apple ID (CloudKit JS, no Stello server login),
 *   - READS the SwiftData mirror zone (CD_Item, CD_Tag, CD_ItemImage, CD_Snippet)
 *     with change tokens, cached in IndexedDB so later visits fetch only changes,
 *   - WRITES nothing to that zone. Saves/edits go to a `StelloInbox` record in
 *     the default zone; the apps apply them (on-device fetch + tagging) and
 *     delete the request. SwiftData's mirror layout is internal, so the apps
 *     stay the only writers of real items.
 */
(function () {
  'use strict';

  // ---- configuration ----
  const CONFIG = Object.assign({
    containerIdentifier: 'iCloud.com.phloxpage.Stello',
    // CloudKit Console → Tokens & Keys → API token (sign-in callback: postMessage).
    // Designed to be public; restricted to Stello's allowed origins.
    apiToken: 'REPLACE_WITH_CLOUDKIT_API_TOKEN',
    // Xcode builds sync to Development; switch to 'production' after the
    // schema is deployed and the apps ship through TestFlight/App Store.
    environment: 'development',
  }, window.STELLO_CLOUDKIT || {});

  const MIRROR_ZONE = { zoneName: 'com.apple.coredata.cloudkit.zone' };
  const INBOX_TYPE = 'StelloInbox';
  const UPSTREAM_VERSION_URL = 'https://raw.githubusercontent.com/arjunphlox/stello/main/version.json';
  const CACHE_VERSION = 1;
  // Heavy fields stay out of the library sync; images load lazily per card.
  const ITEM_KEYS = [
    'CD_entityName', 'CD_id', 'CD_slug', 'CD_title', 'CD_sourceURL', 'CD_domain', 'CD_author',
    'CD_summary', 'CD_bodyMarkdown', 'CD_status', 'CD_needsReview', 'CD_addedAt', 'CD_updatedAt',
    'CD_analyzedAt', 'CD_enrichmentStatus', 'CD_enrichmentError', 'CD_kind', 'CD_metadataJSON',
    'CD_name', 'CD_category', 'CD_weight', 'CD_source', 'CD_item',
    'CD_isPrimary', 'CD_width', 'CD_height', 'CD_label', 'CD_role',
    'CD_text', 'CD_mediaType',
  ];

  let _container = null;
  let _user = null;
  let _loadPromise = null;

  function loadCloudKitJS() {
    if (window.CloudKit) return Promise.resolve(window.CloudKit);
    if (_loadPromise) return _loadPromise;
    _loadPromise = new Promise((resolve, reject) => {
      window.addEventListener('cloudkitloaded', () => resolve(window.CloudKit), { once: true });
      const s = document.createElement('script');
      s.src = 'https://cdn.apple-cloudkit.com/ck/2/cloudkit.js';
      s.async = true;
      s.onerror = () => reject(new Error('Could not load CloudKit JS'));
      document.head.appendChild(s);
    });
    return _loadPromise;
  }

  /**
   * Configure CloudKit once. `buttons` names elements CloudKit renders its own
   * Apple ID sign-in / sign-out buttons into ({ signIn, signOut } element ids).
   */
  async function getContainer(buttons = {}) {
    const CloudKit = await loadCloudKitJS();
    if (_container) return _container;
    const apiTokenAuth = { apiToken: CONFIG.apiToken, persist: true };
    if (buttons.signIn) apiTokenAuth.signInButton = { id: buttons.signIn, theme: 'white-with-outline' };
    if (buttons.signOut) apiTokenAuth.signOutButton = { id: buttons.signOut, theme: 'white-with-outline' };
    CloudKit.configure({
      containers: [{ containerIdentifier: CONFIG.containerIdentifier, apiTokenAuth, environment: CONFIG.environment }],
    });
    _container = CloudKit.getDefaultContainer();
    return _container;
  }

  // ---------- auth ----------

  /** Signed-in iCloud user ({ user }) or null. */
  async function getSession(buttons) {
    const container = await getContainer(buttons);
    const identity = await container.setUpAuth();
    _user = identity ? { id: identity.userRecordName, name: displayName(identity) } : null;
    return _user ? { user: _user } : null;
  }

  function displayName(identity) {
    const n = identity.nameComponents;
    return n ? [n.givenName, n.familyName].filter(Boolean).join(' ') || null : null;
  }

  /** Login page: resolves once the user signs in with the rendered Apple ID button. */
  async function waitForSignIn(buttons) {
    const container = await getContainer(buttons);
    const existing = await container.setUpAuth();
    const identity = existing || await container.whenUserSignsIn();
    _user = { id: identity.userRecordName, name: displayName(identity) };
    return _user;
  }

  async function requireAuth(buttons) {
    try {
      const session = await getSession(buttons);
      if (session) return session;
    } catch (e) {
      console.error('iCloud sign-in check failed:', e);
    }
    window.location.href = '/login.html';
    return null;
  }

  function getUserId() { return _user?.id || null; }
  async function getDisplayName() { return _user?.name || null; }

  /** Bounce to the login page when the Apple ID session ends (sign-out button). */
  async function initAuthListener() {
    const container = await getContainer();
    container.whenUserSignsOut().then(() => {
      clearCache().finally(() => { window.location.href = '/login.html'; });
    });
  }

  // ---------- IndexedDB cache ----------

  function idb() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open('stello-icloud', CACHE_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains('records')) db.createObjectStore('records', { keyPath: 'recordName' });
        if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta');
        if (!db.objectStoreNames.contains('images')) db.createObjectStore('images');
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  function tx(db, store, mode, fn) {
    return new Promise((resolve, reject) => {
      const t = db.transaction(store, mode);
      const result = fn(t.objectStore(store));
      t.oncomplete = () => resolve(result && 'result' in result ? result.result : undefined);
      t.onerror = () => reject(t.error);
    });
  }

  async function clearCache() {
    const db = await idb();
    await Promise.all(['records', 'meta', 'images'].map((s) => tx(db, s, 'readwrite', (os) => os.clear())));
  }

  // ---------- library sync ----------

  /** Flatten CloudKit `{ fields: { CD_x: { value } } }` into `{ x: value }`. */
  function flatten(record) {
    const out = { recordName: record.recordName, recordType: record.recordType };
    for (const [k, v] of Object.entries(record.fields || {})) {
      out[k.startsWith('CD_') ? k.slice(3) : k] = v && v.value;
    }
    return out;
  }

  /**
   * Sync the mirror zone into IndexedDB, then return web-shaped items.
   * `onCached(items)` fires first with whatever was cached, so the grid can
   * render instantly on repeat visits.
   */
  async function loadLibrary({ onCached } = {}) {
    const db = await idb();
    const cached = await tx(db, 'records', 'readonly', (os) => os.getAll());
    if (cached && cached.length && onCached) onCached(assemble(cached));

    const container = await getContainer();
    const database = container.privateCloudDatabase;
    let syncToken = await tx(db, 'meta', 'readonly', (os) => os.get('syncToken'));

    for (;;) {
      let response;
      try {
        response = await database.fetchRecordZoneChanges({
          zoneID: MIRROR_ZONE,
          syncToken: syncToken || undefined,
          desiredKeys: ITEM_KEYS,
          resultsLimit: 400,
        });
      } catch (e) {
        // Expired token → start over from scratch.
        if (syncToken && /SYNC|TOKEN|ZONE_NOT_FOUND/i.test(String(e.ckErrorCode || e.message))) {
          await clearCache();
          syncToken = null;
          continue;
        }
        throw e;
      }
      if (response.hasErrors) {
        const err = response.errors[0];
        if (String(err.ckErrorCode) === 'ZONE_NOT_FOUND') break; // empty library: apps never synced
        throw err;
      }
      const zone = response.zones[0];
      const changes = zone.records || [];
      await tx(db, 'records', 'readwrite', (os) => {
        for (const r of changes) {
          if (r.deleted) os.delete(r.recordName);
          else os.put(flatten(r));
        }
      });
      syncToken = zone.syncToken;
      await tx(db, 'meta', 'readwrite', (os) => os.put(syncToken, 'syncToken'));
      if (!zone.moreComing) break;
    }

    const all = await tx(db, 'records', 'readonly', (os) => os.getAll());
    return assemble(all);
  }

  const toISO = (ms) => (typeof ms === 'number' ? new Date(ms).toISOString() : ms || null);

  /** Join mirror records into the web app's item rows (see normalizeItem in app.js). */
  function assemble(records) {
    const items = new Map();
    const children = [];
    for (const r of records) {
      const type = r.recordType || ('CD_' + r.entityName);
      if (type === 'CD_Item') items.set(r.recordName, r);
      else children.push(r);
    }

    const rows = new Map();
    for (const [recordName, r] of items) {
      rows.set(recordName, {
        ck_record: recordName,
        id: r.id,
        slug: r.slug || r.id || recordName,
        title: r.title || '',
        source_url: r.sourceURL || null,
        domain: r.domain || null,
        author: r.author || null,
        summary: r.summary || null,
        body_markdown: r.bodyMarkdown || null,
        status: r.status || 'active',
        needs_review: !!r.needsReview,
        added_at: toISO(r.addedAt),
        updated_at: toISO(r.updatedAt),
        analyzed_at: toISO(r.analyzedAt),
        enrichment_status: r.enrichmentStatus || 'complete',
        enrichment_error: r.enrichmentError || null,
        kind: r.kind || 'link',
        metadata: r.metadataJSON || null,
        tags: [],
        images: [],
        snippets: [],
      });
    }

    for (const c of children) {
      const row = rows.get(c.item);
      if (!row) continue;
      const type = c.recordType || ('CD_' + c.entityName);
      if (type === 'CD_Tag') {
        row.tags.push({ tag: c.name, category: c.category, weight: c.weight ?? 0.5, source: c.source });
      } else if (type === 'CD_ItemImage') {
        row.images.push({
          ck: c.recordName,
          path: imagePlaceholder(c.recordName),
          source: c.source,
          is_primary: !!c.isPrimary,
          width: c.width || null,
          height: c.height || null,
          role: c.role,
          label: c.label || null,
        });
      } else if (type === 'CD_Snippet') {
        row.snippets.push({ text: c.text, source: c.source, added_at: toISO(c.addedAt) });
      }
    }

    for (const row of rows.values()) {
      row.tags.sort((a, b) => (b.weight || 0) - (a.weight || 0));
      row.images.sort((a, b) => Number(b.is_primary) - Number(a.is_primary));
    }
    return [...rows.values()];
  }

  // ---------- lazy images ----------

  // Cards render `<img src="data:…#ck=<recordName>">`; the hydrator swaps in
  // the real bytes when the card nears the viewport. Bytes are cached as blobs.
  const BLANK = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
  function imagePlaceholder(recordName) { return `${BLANK}#ck=${recordName}`; }
  function recordFromSrc(src) {
    const m = /#ck=(.+)$/.exec(src || '');
    return m ? m[1] : null;
  }

  const objectURLs = new Map();
  const pending = new Map();

  async function imageURL(recordName) {
    if (objectURLs.has(recordName)) return objectURLs.get(recordName);
    if (pending.has(recordName)) return pending.get(recordName);
    const p = (async () => {
      const db = await idb();
      let blob = await tx(db, 'images', 'readonly', (os) => os.get(recordName));
      if (!blob) {
        const container = await getContainer();
        const res = await container.privateCloudDatabase.fetchRecords(
          [{ recordName, zoneID: MIRROR_ZONE }],
          { desiredKeys: ['CD_data', 'CD_data_ckAsset'] },
        );
        const fields = res.records?.[0]?.fields || {};
        if (fields.CD_data_ckAsset?.value?.downloadURL) {
          const url = fields.CD_data_ckAsset.value.downloadURL.replace('${f}', 'image');
          blob = await (await fetch(url)).blob();
        } else if (fields.CD_data?.value) {
          const bin = atob(fields.CD_data.value);
          blob = new Blob([Uint8Array.from(bin, (ch) => ch.charCodeAt(0))]);
        }
        if (blob) await tx(db, 'images', 'readwrite', (os) => os.put(blob, recordName));
      }
      const url = blob ? URL.createObjectURL(blob) : null;
      objectURLs.set(recordName, url);
      return url;
    })().finally(() => pending.delete(recordName));
    pending.set(recordName, p);
    return p;
  }

  let observer = null;
  /** Watch `root` for placeholder images and load them as they near the viewport. */
  function hydrateImages(root = document.body) {
    if (!observer) {
      observer = new IntersectionObserver((entries) => {
        for (const e of entries) {
          if (!e.isIntersecting) continue;
          const img = e.target;
          observer.unobserve(img);
          const rec = recordFromSrc(img.getAttribute('src'));
          if (!rec) continue;
          imageURL(rec).then((url) => {
            if (url) img.src = url;
            else img.parentElement?.classList.add('img-error');
          }).catch(() => img.parentElement?.classList.add('img-error'));
        }
      }, { rootMargin: '800px 0px' });
    }
    const scan = (node) => {
      if (node.tagName === 'IMG' && recordFromSrc(node.getAttribute('src'))) observer.observe(node);
      node.querySelectorAll?.('img[src*="#ck="]').forEach((img) => observer.observe(img));
    };
    scan(root);
    new MutationObserver((muts) => {
      for (const m of muts) {
        if (m.type === 'attributes') scan(m.target);
        m.addedNodes.forEach((n) => n.nodeType === 1 && scan(n));
      }
    }).observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
  }

  // ---------- inbox (web → apps) ----------

  /**
   * Queue a change for the Mac/iPhone app to apply.
   *   action: 'capture' { url, note? } | 'update' { itemID, changes } |
   *           'delete' { itemID } | 'reenrich' { itemID }
   *   changes (update): why_saved[], what_works, new_snippets[], removed_snippets[],
   *           primary_image (record name), remove_images[] (record names),
   *           add_image (bytes in the `image` asset field)
   * Returns the request id so the UI can show a pending state.
   */
  async function enqueue(action, payload, attachment) {
    const container = await getContainer();
    const requestID = crypto.randomUUID();
    const fields = {
      action: { value: action },
      payload: { value: JSON.stringify(payload || {}) },
      createdAt: { value: Date.now() },
      origin: { value: 'web' },
    };
    // Optional image bytes (manual upload) ride along as a CloudKit asset.
    if (attachment) fields.image = { value: attachment };
    const res = await container.privateCloudDatabase.saveRecords([{
      recordType: INBOX_TYPE,
      recordName: requestID,
      fields,
    }]);
    if (res.hasErrors) throw res.errors[0];
    return requestID;
  }

  /** Requests the apps haven't processed yet (for "processing" cards). */
  async function pendingRequests() {
    const container = await getContainer();
    const res = await container.privateCloudDatabase.performQuery(
      { recordType: INBOX_TYPE, sortBy: [{ fieldName: 'createdAt', ascending: false }] },
    );
    if (res.hasErrors) return [];
    return (res.records || []).map((r) => {
      const f = flatten(r);
      let payload = {};
      try { payload = JSON.parse(f.payload || '{}'); } catch { /* ignore */ }
      return { id: r.recordName, action: f.action, payload, createdAt: f.createdAt };
    });
  }

  // ---------- misc ----------

  async function checkForUpdate(currentVersion) {
    try {
      const res = await fetch(UPSTREAM_VERSION_URL, { cache: 'no-store' });
      if (!res.ok) return null;
      const remote = await res.json();
      if (remote.version !== currentVersion) {
        return {
          available: true, latest: remote.version, current: currentVersion,
          changelog: remote.changelog, migration: remote.migration,
          breaking_changes: remote.breaking_changes || [],
        };
      }
      return { available: false };
    } catch {
      return null;
    }
  }

  window.Stello = {
    config: CONFIG,
    getContainer,
    getSession,
    waitForSignIn,
    requireAuth,
    getUserId,
    getDisplayName,
    initAuthListener,
    loadLibrary,
    hydrateImages,
    imageURL,
    enqueue,
    pendingRequests,
    clearCache,
    checkForUpdate,
  };
})();
