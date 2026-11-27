/**
 * The library as the Figma plugin and the MCP connector see it: slim items,
 * search, and "related" by the Layer 1 rules of the Exploration canvas
 * (same colour, same style, same idea, same kind, same place, same source).
 * Rules only, no AI.
 *
 * COLOR_MAP is a copy of app.js's swatch map (colour tag name → hex), used to
 * turn colours picked up from Figma fills into Stello colour tags.
 */

export const COLOR_MAP = {
  // Reds / pinks
  red: '#c0392b', crimson: '#dc143c', burgundy: '#800020', maroon: '#800000',
  scarlet: '#ff2400', ruby: '#e0115f', cherry: '#de3163', rose: '#ff007f',
  blush: '#de5d83', coral: '#ff7f50', salmon: '#fa8072', pink: '#e8909c',
  magenta: '#c20078', fuchsia: '#c154c1', mauve: '#e0b0ff', dusty_rose: '#dcae96',
  'dusty-rose': '#dcae96', raspberry: '#e30b5c', wine: '#722f37', terracotta: '#e2725b',
  // Oranges
  orange: '#e67e22', tangerine: '#ff9966', peach: '#ffcba4', apricot: '#fbceb1',
  amber: '#ffbf00', rust: '#b7410e', copper: '#b87333', burnt_orange: '#cc5500',
  'burnt-orange': '#cc5500', sienna: '#a0522d',
  // Yellows
  yellow: '#f1c40f', gold: '#ffd700', golden: '#daa520', mustard: '#e1ad01',
  lemon: '#fff44f', cream: '#fffdd0', butter: '#ffff99', saffron: '#f4c430',
  honey: '#eb9605', wheat: '#f5deb3', sand: '#c2b280',
  // Greens
  green: '#27ae60', emerald: '#50c878', lime: '#32cd32', olive: '#808000',
  sage: '#bcb88a', mint: '#98ff98', teal: '#008080', forest: '#228b22',
  'forest-green': '#228b22', jade: '#00a86b', chartreuse: '#7fff00',
  moss: '#8a9a5b', avocado: '#568203', pistachio: '#93c572', seafoam: '#93e9be',
  // Blues
  blue: '#2980b9', navy: '#001f3f', cobalt: '#0047ab', royal: '#4169e1',
  'royal-blue': '#4169e1', sky: '#87ceeb', 'sky-blue': '#87ceeb',
  azure: '#007fff', cerulean: '#007ba7', turquoise: '#40e0d0', aqua: '#00ffff',
  indigo: '#4b0082', periwinkle: '#ccccff', slate: '#708090', 'slate-blue': '#6a5acd',
  steel: '#4682b4', 'steel-blue': '#4682b4', powder: '#b0e0e6', 'powder-blue': '#b0e0e6',
  // Purples
  purple: '#8e44ad', violet: '#7f00ff', lavender: '#b57edc', plum: '#8e4585',
  lilac: '#c8a2c8', amethyst: '#9966cc', orchid: '#da70d6', grape: '#6f2da8',
  eggplant: '#614051', mulberry: '#c54b8c',
  // Browns
  brown: '#795548', chocolate: '#7b3f00', coffee: '#6f4e37', mocha: '#967969',
  tan: '#d2b48c', taupe: '#483c32', caramel: '#ffd59a', cinnamon: '#d2691e',
  walnut: '#773f1a', chestnut: '#954535', espresso: '#3c1414', umber: '#635147',
  // Neutrals
  black: '#1a1a1a', charcoal: '#36454f', 'dark-gray': '#555555',
  gray: '#888888', grey: '#888888', silver: '#c0c0c0', 'light-gray': '#d3d3d3',
  white: '#f5f5f5', ivory: '#fffff0', bone: '#e3dac9', pearl: '#eae0c8',
  beige: '#f5f5dc', off_white: '#faf0e6', 'off-white': '#faf0e6',
  };

const SLIM_COLS = 'slug, title, kind, domain, source_url, author, location, summary, og_image_path, tags, added_at, last_opened_at, cover_aspect';
const STOP = new Set('a an and the of for to in on with by from at is are this that your my our it its as or be how what why new'.split(' '));

function parseTags(v) {
  if (Array.isArray(v)) return v;
  try { const t = JSON.parse(v || '[]'); return Array.isArray(t) ? t : []; } catch { return []; }
}

export function colourHex(name) {
  const n = String(name || '').toLowerCase().trim();
  if (!n) return null;
  const tries = [n, n.replace(/[\s-]+/g, '_'), n.replace(/[\s_]+/g, '-'), ...n.split(/[\s_-]+/).reverse()];
  for (const t of tries) if (COLOR_MAP[t]) return COLOR_MAP[t];
  return null;
}

function rgb(hex) {
  const h = String(hex).replace('#', '');
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
}
function dist(a, b) {
  const [r1, g1, b1] = rgb(a), [r2, g2, b2] = rgb(b);
  const rm = (r1 + r2) / 2; // "redmean" approximation of perceived distance
  return Math.sqrt((2 + rm / 256) * (r1 - r2) ** 2 + 4 * (g1 - g2) ** 2 + (2 + (255 - rm) / 256) * (b1 - b2) ** 2);
}
/** True when two hexes are close enough to call "the same colour". */
export function sameColour(a, b) { return !!a && !!b && dist(a, b) < 90; }

/** The API shape: what a card needs, nothing heavy. `origin` makes image URLs absolute. */
export function slimItem(row, origin = '') {
  const tags = parseTags(row.tags).filter((t) => t && t.tag)
    .sort((a, b) => (b.weight || 0) - (a.weight || 0));
  const colours = tags.filter((t) => t.category === 'color').map((t) => ({ name: t.tag, hex: colourHex(t.tag) }));
  const img = row.og_image_path || null;
  return {
    slug: row.slug,
    title: row.title || row.slug,
    kind: row.kind && row.kind !== 'link' ? row.kind : null,
    domain: row.domain || null,
    source_url: row.source_url || null,
    author: row.author || null,
    place: row.location || (tags.find((t) => t.category === 'location') || {}).tag || null,
    summary: row.summary ? String(row.summary).slice(0, 280) : null,
    added_at: row.added_at || null,
    last_opened_at: row.last_opened_at || null,
    aspect: row.cover_aspect || null,
    tags: tags.filter((t) => !['color', 'intent', 'collection'].includes(t.category)).slice(0, 12)
      .map((t) => ({ tag: t.tag, category: t.category || null })),
    colours,
    image: img ? origin + img : null,
    figma_image: img && img.startsWith('/img/') ? `${origin}${img}?format=figma` : null,
    stello_url: `${origin}/detail.html?slug=${encodeURIComponent(row.slug)}`,
  };
}

export async function loadLibrary(db, userId, origin = '') {
  const { results } = await db.prepare(
    `SELECT ${SLIM_COLS} FROM items
      WHERE user_id = ? AND deleted_at IS NULL AND purged_at IS NULL
      ORDER BY added_at DESC`
  ).bind(userId).all();
  return (results || []).map((r) => slimItem(r, origin));
}

export function words(text) {
  return String(text || '').toLowerCase().split(/[^a-z0-9À-ɏ]+/)
    .filter((w) => w.length > 2 && !STOP.has(w));
}

/** Plain search: every query word must hit the title, domain, author, tags or summary. */
export function search(items, { query = '', kind = null, tag = null, colour = null, limit = 30 } = {}) {
  const q = words(query);
  const hex = colour ? (colour.startsWith('#') ? colour : colourHex(colour)) : null;
  const out = [];
  for (const it of items) {
    if (kind && it.kind !== kind) continue;
    if (tag && !it.tags.some((t) => t.tag.toLowerCase() === tag.toLowerCase())) continue;
    if (hex && !it.colours.some((c) => sameColour(c.hex, hex))) continue;
    let score = 0;
    if (q.length) {
      const title = it.title.toLowerCase();
      const hay = [it.domain, it.author, it.place, it.summary, ...it.tags.map((t) => t.tag)]
        .filter(Boolean).join(' ').toLowerCase();
      let all = true;
      for (const w of q) {
        if (title.includes(w)) score += 3;
        else if (hay.includes(w)) score += 1;
        else { all = false; break; }
      }
      if (!all) continue;
    }
    out.push({ it, score });
  }
  out.sort((a, b) => b.score - a.score);
  return out.slice(0, Math.min(Math.max(+limit || 30, 1), 200)).map((x) => x.it);
}

const IDEA = new Set(['subject', 'domain', 'mood', 'tool', 'format']);

/**
 * Layer 1 links between two items, strongest first: [{ type, value }].
 * type: 'same_colour' | 'same_style' | 'same_idea' | 'same_place' | 'same_kind' | 'same_source'
 */
export function layer1(a, b) {
  const out = [];
  for (const ca of a.colours) {
    const cb = b.colours.find((c) => c.name === ca.name || sameColour(c.hex, ca.hex));
    if (cb) { out.push({ type: 'same_colour', value: ca.name, w: 3 }); break; }
  }
  const tb = new Map(b.tags.map((t) => [t.tag.toLowerCase(), t.category]));
  for (const t of a.tags) {
    const cat = tb.get(t.tag.toLowerCase());
    if (cat == null && !tb.has(t.tag.toLowerCase())) continue;
    if (t.category === 'style') out.push({ type: 'same_style', value: t.tag, w: 2.5 });
    else if (IDEA.has(t.category) || !t.category) out.push({ type: 'same_idea', value: t.tag, w: 1.5 });
  }
  if (a.place && b.place && a.place.toLowerCase() === b.place.toLowerCase()) out.push({ type: 'same_place', value: a.place, w: 2 });
  if (a.domain && b.domain && a.domain === b.domain) out.push({ type: 'same_source', value: a.domain, w: 1.5 });
  if (a.kind && a.kind === b.kind) out.push({ type: 'same_kind', value: a.kind, w: 1 });
  return out.sort((x, y) => y.w - x.w);
}

/** Saves most related to `seed` (an item), with the reasons that link them. */
export function related(items, seed, { limit = 12, exclude = [] } = {}) {
  const skip = new Set([seed.slug, ...exclude]);
  const scored = [];
  for (const it of items) {
    if (skip.has(it.slug)) continue;
    const links = layer1(seed, it);
    if (!links.length) continue;
    const score = links.reduce((s, l) => s + l.w, 0);
    if (score < 2) continue;
    scored.push({ item: it, score, reasons: links.slice(0, 3).map(({ type, value }) => ({ type, value })) });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, Math.min(Math.max(+limit || 12, 1), 50));
}

/**
 * Related for something that isn't a Stello item (a Figma selection): its
 * words (layer names, text) and fill colours become a pseudo-item.
 */
export function pseudoItem({ text = '', colours = [] } = {}) {
  const named = [];
  for (const hex of colours.slice(0, 8)) {
    let best = null, bestD = Infinity;
    for (const [name, h] of Object.entries(COLOR_MAP)) {
      const d = dist(hex, h);
      if (d < bestD) { bestD = d; best = name; }
    }
    if (best && bestD < 90) named.push({ name: best.replace(/[_-]/g, ' '), hex });
  }
  return {
    slug: '\u0000selection', title: '', kind: null, domain: null, place: null,
    tags: [...new Set(words(text))].slice(0, 30).map((w) => ({ tag: w, category: null })),
    colours: named,
  };
}
