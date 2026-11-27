#!/usr/bin/env node
// Web perf check at library scale: loads index.html in headless Chromium with
// a mocked API serving N synthetic items (cloned from a real export when one
// is given), then measures launch, scroll and memory with the grid visible.
//
//   node scripts/perf-web.mjs [--n 10000] [--export path/to/stello-library.json]
//
// Budgets (stello-performance-rules): launch-to-grid < 1 s, no main-thread
// stall > 50 ms while scrolling, memory < 500 MB.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => {
  if (v.startsWith('--')) a.push([v.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true]);
  return a;
}, []));
const N = parseInt(args.n || '10000', 10);

// ---- Synthetic library ----
function seedItems() {
  if (args.export && fs.existsSync(args.export)) {
    const d = JSON.parse(fs.readFileSync(args.export, 'utf8'));
    return d.items || d;
  }
  const kinds = ['link', 'product', 'tool', 'post', 'article', 'resource', 'website'];
  const cats = ['format', 'domain', 'style', 'subject', 'tool', 'mood', 'color'];
  return Array.from({ length: 500 }, (_, i) => ({
    title: `Sample item ${i} with a reasonably long title`,
    source_url: `https://example${i % 50}.com/page/${i}`,
    domain: `example${i % 50}.com`,
    summary: 'A summary sentence about the item. '.repeat(4),
    body_markdown: 'Body text. '.repeat(40),
    kind: kinds[i % kinds.length],
    tags: Array.from({ length: 14 }, (_, t) => ({ tag: `tag${(i * 7 + t) % 300}`, category: cats[t % cats.length], weight: 0.3 + (t % 7) / 10 })),
    images: i % 5 ? [{ path: `img/x/${i}.webp`, is_primary: true, width: 1200, height: 600 + (i % 7) * 100 }] : [],
    snippets: [],
    enrichment_status: 'vision_done',
  }));
}
const seed = seedItems();
const t0 = Date.parse('2026-11-27T00:00:00Z');
const ITEMS = Array.from({ length: N }, (_, i) => {
  const s = seed[i % seed.length];
  return {
    ...s,
    id: `perf-${i}`,
    slug: `perf-${i}`,
    user_id: 'perf-user',
    added_at: new Date(t0 - i * 3 * 3600 * 1000).toISOString(),
    deleted_at: null,
    enrichment_status: 'vision_done',
  };
});

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json', '.woff2': 'font/woff2', '.webmanifest': 'application/manifest+json' };

async function main() {
  const browser = await chromium.launch({ args: ['--enable-precise-memory-info', '--js-flags=--expose-gc'] });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, serviceWorkers: 'block' });
  let apiBytes = 0;
  await ctx.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.hostname !== 'stello.test') {
      if (url.hostname.includes('jsdelivr')) return route.continue().catch(() => route.fulfill({ body: '' }));
      return route.fulfill({ contentType: 'image/png', body: PNG });
    }
    const p = url.pathname;
    if (p === '/api/auth/me') return route.fulfill({ json: { user: { id: 'perf-user', email: 'perf@example.com' } } });
    if (p === '/api/items') {
      const off = +url.searchParams.get('offset') || 0, lim = +url.searchParams.get('limit') || 1000;
      const body = JSON.stringify({ items: ITEMS.slice(off, off + lim) });
      apiBytes += body.length;
      return route.fulfill({ contentType: 'application/json', body });
    }
    if (p.startsWith('/api/')) return route.fulfill({ json: {} });
    if (p.startsWith('/img/')) return route.fulfill({ contentType: 'image/png', body: PNG });
    const file = path.join(ROOT, p === '/' ? 'index.html' : p);
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return route.fulfill({ status: 404, body: '' });
    return route.fulfill({ contentType: MIME[path.extname(file)] || 'application/octet-stream', body: fs.readFileSync(file) });
  });

  const page = await ctx.newPage();
  await page.addInitScript(() => {
    window.__perf = { longTasks: [], firstCard: 0 };
    new PerformanceObserver((l) => l.getEntries().forEach(e => window.__perf.longTasks.push({ start: e.startTime, dur: e.duration }))).observe({ type: 'longtask', buffered: true });
    const mo = new MutationObserver(() => {
      if (!window.__perf.firstCard && document.querySelector('#masonry-grid .card')) { window.__perf.firstCard = performance.now(); mo.disconnect(); }
    });
    document.addEventListener('DOMContentLoaded', () => mo.observe(document.body, { childList: true, subtree: true }));
  });

  await page.goto('http://stello.test/index.html');
  await page.waitForFunction(() => window.__perf.firstCard > 0, null, { timeout: 60000 });
  // Let background paging + idle work settle.
  await page.waitForTimeout(6000);
  const launch = await page.evaluate(() => ({
    firstCard: Math.round(window.__perf.firstCard),
    items: window.StelloApp ? window.StelloApp.items().length : 0,
    cards: document.querySelectorAll('#masonry-grid .card').length,
    nodes: document.getElementsByTagName('*').length,
    longTasks: window.__perf.longTasks.map(t => Math.round(t.dur)).sort((a, b) => b - a).slice(0, 8),
    totalLong: Math.round(window.__perf.longTasks.reduce((a, t) => a + t.dur, 0)),
  }));
  const heap = async () => { await page.evaluate(() => window.gc && window.gc()); return page.evaluate(() => Math.round(performance.memory.usedJSHeapSize / 1048576)); };
  launch.heapMB = await heap();

  // Scroll: wheel down in steps, timing frames.
  await page.evaluate(() => { window.__perf.longTasks = []; });
  await page.mouse.move(700, 500);
  const scrollStart = Date.now();
  await page.evaluate(() => {
    window.__perf.frames = [];
    let last = performance.now();
    const tick = (t) => { window.__perf.frames.push(t - last); last = t; if (!window.__perf.stopFrames) requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
  });
  // A fast but human scroll: 900 px every 100 ms for 30 s.
  for (let i = 0; i < 300; i++) { await page.mouse.wheel(0, 900); await page.waitForTimeout(100); }
  await page.evaluate(() => { window.__perf.stopFrames = true; });
  await page.waitForTimeout(1500);
  const scroll = await page.evaluate(() => ({
    cards: document.querySelectorAll('#masonry-grid .card').length,
    nodes: document.getElementsByTagName('*').length,
    longTasks: window.__perf.longTasks.map(t => Math.round(t.dur)).sort((a, b) => b - a).slice(0, 8),
    over50: window.__perf.longTasks.filter(t => t.dur > 50).length,
    frames: window.__perf.frames.length,
    slowFrames: window.__perf.frames.filter(f => f > 50).length,
    p95FrameMs: Math.round([...window.__perf.frames].sort((a, b) => a - b)[Math.floor(window.__perf.frames.length * 0.95)]),
    scrollTop: Math.round(document.querySelector('.main-content').scrollTop),
    scrollHeight: document.querySelector('.main-content').scrollHeight,
  }));
  scroll.seconds = ((Date.now() - scrollStart) / 1000).toFixed(1);
  scroll.heapMB = await heap();

  // Search keystroke + filter
  await page.evaluate(() => { window.__perf.longTasks = []; });
  const search = await page.$('#search-input, input[type="search"]');
  let searchRes = null;
  if (search) {
    const s0 = Date.now();
    await search.type('sample', { delay: 40 });
    await page.waitForTimeout(800);
    searchRes = await page.evaluate(() => ({ longTasks: window.__perf.longTasks.map(t => Math.round(t.dur)).sort((a, b) => b - a).slice(0, 5) }));
    searchRes.ms = Date.now() - s0;
  }

  console.log(JSON.stringify({ N, apiMB: +(apiBytes / 1048576).toFixed(1), launch, scroll, search: searchRes }, null, 2));
  await browser.close();
}
main().catch(e => { console.error(e); process.exit(1); });
