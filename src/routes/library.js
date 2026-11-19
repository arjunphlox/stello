/**
 * /api/library — slim reads for the Figma plugin and the MCP connector.
 *
 *   GET  /api/library?offset=&limit=       → { items, total }  slim items, newest first
 *   GET  /api/library/search?q=&kind=&tag=&colour=&limit=   → { items }
 *   GET  /api/library/related?slug=&limit= → { related: [{ item, reasons }] }
 *   POST /api/library/match  { text, colours: ['#hex'], limit }
 *        → related for a Figma selection that isn't a Stello item
 *   POST /api/library/links  { slugs }  → { links: [{ a, b, type, value }] }
 *        Layer 1 lines among the given saves (strongest reason per pair)
 *
 * Signed in: cookie or device token (bearer). Rules only (src/lib/library.js).
 */
import { loadLibrary, search, related, pseudoItem, layer1 } from '../lib/library.js';

export default function mountLibrary(app, { requireUser }) {
  const origin = (c) => new URL(c.req.url).origin;
  const guard = async (c) => requireUser(c);

  app.get('/api/library', async (c) => {
    const userId = await guard(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const all = await loadLibrary(c.env.DB, userId, origin(c));
    const offset = Math.max(0, parseInt(c.req.query('offset') || '0', 10) || 0);
    const limit = Math.min(Math.max(parseInt(c.req.query('limit') || '2000', 10) || 2000, 1), 5000);
    return c.json({ items: all.slice(offset, offset + limit), total: all.length });
  });

  app.get('/api/library/search', async (c) => {
    const userId = await guard(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const all = await loadLibrary(c.env.DB, userId, origin(c));
    const q = c.req.query();
    return c.json({ items: search(all, { query: q.q, kind: q.kind, tag: q.tag, colour: q.colour, limit: q.limit }) });
  });

  app.get('/api/library/related', async (c) => {
    const userId = await guard(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const all = await loadLibrary(c.env.DB, userId, origin(c));
    const seed = all.find((i) => i.slug === c.req.query('slug'));
    if (!seed) return c.json({ error: 'Item not found' }, 404);
    return c.json({ related: related(all, seed, { limit: c.req.query('limit') }) });
  });

  app.post('/api/library/match', async (c) => {
    const userId = await guard(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const { text, colours, limit, exclude } = await c.req.json().catch(() => ({}));
    const hexes = (Array.isArray(colours) ? colours : []).filter((h) => /^#?[0-9a-f]{6}$/i.test(h))
      .map((h) => (h.startsWith('#') ? h : `#${h}`));
    const all = await loadLibrary(c.env.DB, userId, origin(c));
    const seed = pseudoItem({ text: String(text || '').slice(0, 4000), colours: hexes });
    return c.json({
      related: related(all, seed, { limit, exclude: Array.isArray(exclude) ? exclude : [] }),
      read_as: { words: seed.tags.map((t) => t.tag), colours: seed.colours.map((c) => c.name) },
    });
  });

  app.post('/api/library/links', async (c) => {
    const userId = await guard(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const { slugs } = await c.req.json().catch(() => ({}));
    const want = new Set((Array.isArray(slugs) ? slugs : []).slice(0, 400));
    const items = (await loadLibrary(c.env.DB, userId, origin(c))).filter((i) => want.has(i.slug));
    const links = [];
    for (let i = 0; i < items.length; i++) {
      for (let j = i + 1; j < items.length; j++) {
        const why = layer1(items[i], items[j]);
        const score = why.reduce((s, l) => s + l.w, 0);
        if (why.length && score >= 2.5) links.push({ a: items[i].slug, b: items[j].slug, type: why[0].type, value: why[0].value, score });
      }
    }
    // Keep each card's 3 strongest lines, so the board stays readable.
    links.sort((x, y) => y.score - x.score);
    const deg = new Map();
    const kept = links.filter((l) => {
      const da = deg.get(l.a) || 0, db = deg.get(l.b) || 0;
      if (da >= 3 || db >= 3) return false;
      deg.set(l.a, da + 1); deg.set(l.b, db + 1);
      return true;
    }).map(({ score, ...l }) => l);
    return c.json({ links: kept });
  });
}
