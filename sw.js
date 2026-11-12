/* === Stello — service worker (offline app shell + offline images) ===
 *
 *   pages, app.js, style.css, fonts, icons → network first, cached copy
 *                                            when offline or slow (4 s)
 *   /img/*                                 → offline image cache first
 *                                            (filled by offline.js), else network
 *   /api/*                                 → never touched (always network)
 *
 * The page posts { type: 'precache', urls } after load (offline.js), so the
 * shell cache holds exactly the files that page used.
 */
const SHELL = 'stello-shell-v1';
const IMG = 'stello-offline-img-v1';
const NETWORK_TIMEOUT_MS = 4000;

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(SHELL).then((c) => c.add(new Request('/', { cache: 'reload' }))).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('stello-shell-') && key !== SHELL) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type !== 'precache' || !Array.isArray(data.urls)) return;
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL);
    const want = new Set(data.urls.map((u) => new URL(u, self.location.origin).href));
    want.add(new URL('/', self.location.origin).href);
    const have = new Set((await cache.keys()).map((r) => r.url));
    for (const url of want) {
      if (have.has(url)) continue;
      try {
        const res = await fetch(url, { credentials: 'same-origin' });
        if (res.ok && !res.redirected) await cache.put(url, res);
      } catch { /* try again on the next load */ }
    }
    // Drop superseded versions (old ?v=…).
    for (const url of have) if (!want.has(url)) await cache.delete(url);
  })());
});

function isShellRequest(url) {
  if (url.origin === self.location.origin) {
    return !url.pathname.startsWith('/api/') && !url.pathname.startsWith('/img/');
  }
  return url.hostname === 'cdn.jsdelivr.net';
}

async function networkFirst(request, cacheKey) {
  const cache = await caches.open(SHELL);
  const network = fetch(request).then((res) => {
    if (res.ok && !res.redirected) cache.put(cacheKey, res.clone()).catch(() => {});
    return res;
  });
  const timeout = new Promise((resolve) => setTimeout(resolve, NETWORK_TIMEOUT_MS, null));
  try {
    const res = await Promise.race([network, timeout]);
    if (res) return res;
  } catch { /* offline */ }
  const cached = await cache.match(cacheKey, { ignoreSearch: cacheKey === '/' });
  if (cached) return cached;
  return network; // nothing cached: wait for (or fail with) the network
}

async function imageFirst(request) {
  const url = new URL(request.url);
  const cached = await caches.open(IMG).then((c) => c.match(url.pathname)).catch(() => null);
  return cached || fetch(request);
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (url.origin === self.location.origin && url.pathname.startsWith('/img/')) {
    event.respondWith(imageFirst(request));
    return;
  }
  if (!isShellRequest(url)) return;

  if (request.mode === 'navigate') {
    // Only the grid page works offline; '/?panel=slug' links land there too.
    const key = url.origin === self.location.origin && (url.pathname === '/' || url.pathname === '/index.html') ? '/' : null;
    if (key) { event.respondWith(networkFirst(request, key)); return; }
    event.respondWith(fetch(request).catch(async () => (await caches.open(SHELL)).match('/', { ignoreSearch: true }) || Response.error()));
    return;
  }
  event.respondWith(networkFirst(request, request.url));
});
