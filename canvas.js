/* Stello canvas: the library as nodes on a zoomable canvas.
   ----------------------------------------------------------------------------
   The same items the grid shows (after search and filters), placed in broad
   groups you can switch (collection, topic, kind, colour, style, place,
   source, month). Lines say why two items belong together:

   Layer 1 (computed, rules only): same colour, looks alike, same idea,
   same kind, same place, same style.
   Layer 2 (yours, plus a few computed hints): use / rejected marks,
   influence (A inspired B), contrast (vs), part of a set, questions,
   notes on part of an image; gaps (maybe-related saves and empty spots),
   a save timeline, and revisit glow / fade.

   Progressive disclosure is by zoom: far out you see colour blocks and
   group names; closer, covers and titles; close up, the full details card.
   Selecting an item focuses its lines and dims the rest.

   Rendering: one world layer moved with a CSS transform; only items in view
   get DOM nodes (spatial hash). Lines and far-out blocks are drawn on one
   screen-space <canvas>. Layout runs only when the result set or grouping
   changes; panning only moves the transform and redraws the lines in view.
   User data (moved cards, marks, links, notes) is browser-local for now, in
   the same shape as the server projects API so it can move there later. */
(function () {
  'use strict';

  const DOC_KEY = 'stello.canvas.v1';
  const VIEW_KEY = 'stello.view';           // 'grid' | 'canvas'
  const W = 274;                            // card width (world px)
  const COL_GAP = 36, ROW_GAP = 40, CL_GAP_X = 240, CL_GAP_Y = 300;
  const TITLE_H = 120;                      // room above a group for its title
  const CELL = 800;                         // spatial hash cell
  const MIN_K = 0.01, MAX_K = 2.5;
  const LOD_BLOCKS = 0.16;                  // below: colour blocks on the canvas, no DOM cards
  const LOD_DETAIL = 0.62;                  // at or above: full details card
  const LABEL_K = 0.42;                     // link labels from this zoom
  const MAX_LINKS = 420, MAX_LABELS = 90;

  // Layer 1 kinds, in tie-break order. Colours follow the Figma legend.
  const SIM = {
    place: { label: 'Same place', hint: 'city or country', color: '#e8590c', w: 3.0 },
    colour: { label: 'Same colour', hint: 'shared palette', color: '#3b5bdb', w: 1.4 },
    looks: { label: 'Looks alike', hint: 'similar look', color: null, dash: [6, 5], w: 1.6 },
    kind: { label: 'Same kind', hint: 'tool, studio, portfolio, foundry', color: '#7048e8', w: 0.8 },
    idea: { label: 'Same idea', hint: 'overlapping topic', color: '#2b8a3e', w: 1.5 },
    style: { label: 'Same style', hint: 'shared style tags', color: '#1098ad', w: 1.0 },
  };
  // Layer 2 kinds.
  const L2 = {
    influence: { label: 'Influence', hint: 'A inspired B', color: '#d6336c' },
    contrast: { label: 'Contrast', hint: 'opposite take, same problem', color: '#e8890c', dash: [3, 4] },
    part_of: { label: 'Part of', hint: 'item belongs to a set', color: '#5c6b84' },
    question: { label: 'Question', hint: 'items point to it', color: '#d9a400' },
    related: { label: 'Accepted', hint: 'maybe-related you kept', color: '#868e96', dash: [2, 4] },
  };
  const INSIGHTS = {
    marks: 'Use / rejected', notes: 'Questions, notes and sets', gaps: 'Gaps: maybe related, empty spots',
    time: 'Save timeline', glow: 'Revisits: glow and fade',
  };
  const GROUPS = {
    collection: 'Collection', topic: 'Topic', kind: 'Kind', colour: 'Colour', style: 'Style',
    place: 'Place', source: 'Source', month: 'Month saved',
  };
  const PALETTE = ['#2b8a3e', '#3b5bdb', '#7048e8', '#e8590c', '#1098ad', '#c2255c', '#5c940d', '#9c36b5', '#e67700', '#0b7285', '#a61e4d', '#364fc7'];
  const SKIP_SUBJECT = new Set(['website', 'welcome', 'home', 'homepage', 'introducing', 'index', 'page', 'github', 'the', 'free', 'team', 'open', 'new', 'best', 'list', 'official', 'online', 'platform', 'company', 'app', 'apps', 'site', 'blog', 'about', 'get', 'your', 'make']);

  let App = null;
  let doc = null;
  let undoStack = [];
  let mode = 'grid';
  let view = { x: 0, y: 0, k: 0.5 };
  const els = {};
  let set = [];                   // items on the canvas
  let setIndex = new Map();       // slug -> item
  let nodes = new Map();          // slug -> { slug, item, x, y, h, ch, dh, cl }
  let clusters = [];              // [{ key, name, sub, color, x, y, w, h, slugs, empty, ghost }]
  let hash = new Map();           // cell -> [slug]
  let worldBox = { x: 0, y: 0, w: 1, h: 1 };
  let timeline = null;            // { x, y, w, h, ... }
  let inv = new Map();            // feature -> [slug]
  let featOf = new Map();         // slug -> [{ f, type, tag }]
  let simCache = new Map();       // slug -> [{ b, type, label, s }]
  const rendered = new Map();     // slug -> element
  let sel = null;                 // selected slug
  let selNote = null;             // selected note id
  let hover = null;
  let connect = null;             // { from, kind } while picking a target
  let pinFor = null;              // slug while placing a note on its image
  let layers = {
    sim: { on: true, place: true, colour: true, looks: true, kind: true, idea: true, style: true },
    ins: { marks: true, notes: true, gaps: true, time: true, glow: true },
  };
  let raf = 0, layoutRaf = 0, dirtyLayout = true;
  let spaceDown = false;
  let lastBlocks = false;
  let theme = { text: '#eee', card: '#333', accent: '#ffc53d' };
  const noteSize = new Map();     // note id -> { w, h }, measured after notes render
  function readTheme() {
    const css = getComputedStyle(document.documentElement);
    theme = { text: css.getPropertyValue('--text').trim() || '#eee', card: css.getPropertyValue('--card-bg').trim() || '#333', accent: css.getPropertyValue('--accent').trim() || '#ffc53d' };
  }

  const esc = (s) => App.esc(String(s == null ? '' : s));
  const uid = () => Math.random().toString(36).slice(2, 10);
  const cap = (s) => String(s || '').replace(/[-_]+/g, ' ').replace(/^\w/, c => c.toUpperCase());
  function hashOf(s) { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return (h >>> 0) / 4294967295; }

  // ---------- Document (same shape as the server projects API) ----------
  function blankDoc() { return { name: 'Library canvas', groupBy: 'collection', cards: [], links: [], groups: [], notes: [], dismissed: [], layers: null }; }
  function loadDoc() {
    try { doc = JSON.parse(localStorage.getItem(DOC_KEY)); } catch { doc = null; }
    if (!doc || typeof doc !== 'object') doc = blankDoc();
    const b = blankDoc();
    Object.keys(b).forEach(k => { if (doc[k] == null) doc[k] = b[k]; });
    if (doc.layers) {
      layers.sim = Object.assign(layers.sim, doc.layers.sim || {});
      layers.ins = Object.assign(layers.ins, doc.layers.ins || {});
    }
  }
  function saveDoc() { doc.layers = layers; localStorage.setItem(DOC_KEY, JSON.stringify(doc)); }
  function change(fn, opts) {
    undoStack.push(JSON.stringify(doc));
    if (undoStack.length > 50) undoStack.shift();
    fn();
    saveDoc();
    if (opts && opts.layout) markLayout(); else schedule(true);
  }
  function undo() {
    const prev = undoStack.pop();
    if (!prev) { App.toast('Nothing to undo'); return; }
    doc = JSON.parse(prev);
    saveDoc();
    markLayout();
  }
  const cardRec = (slug) => doc.cards.find(c => c.slug === slug);
  function cardRecMake(slug) { let c = cardRec(slug); if (!c) { c = { slug }; doc.cards.push(c); } return c; }

  // ---------- Item facts ----------
  const tagsOf = (it, cat, min) => (it.tags || []).filter(t => t.category === cat && t.weight >= (min || 0)).sort((a, b) => b.weight - a.weight);
  function colours(it) { return tagsOf(it, 'color', 0.15).slice(0, 3).map(t => t.tag); }
  function kindName(it) {
    const line = App.kindLine ? App.kindLine(it) : '';
    if (line) return line.split(' · ')[0];
    return it.kind && it.kind !== 'link' ? cap(it.kind) : (it.source_url ? 'Website' : 'Note');
  }
  function placeOf(it) {
    const loc = tagsOf(it, 'location', 0.3)[0];
    return (it.location && String(it.location)) || (loc ? cap(loc.tag) : '');
  }
  function savedLabel(it) {
    const d = new Date(it.added_at);
    return isNaN(d) ? '' : 'Saved ' + d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  }
  function coverRatio(it) {
    if (it.image_width && it.image_height) return Math.max(0.5, Math.min(1.3, it.image_height / it.image_width));
    const img = (it.images || []).find(i => i.is_primary) || (it.images || [])[0];
    if (img && img.width && img.height) return Math.max(0.5, Math.min(1.3, img.height / img.width));
    return it.has_image ? 0.6 : 0.62;
  }
  function details(it) {
    const rows = [];
    const style = tagsOf(it, 'style', 0.4).slice(0, 4).map(t => t.tag).join(', ');
    const tags = tagsOf(it, 'subject', 0.5).filter(t => !SKIP_SUBJECT.has(t.tag)).slice(0, 5).map(t => t.tag).join(', ');
    const coll = tagsOf(it, 'collection').slice(0, 2).map(t => t.tag).join(', ');
    const place = placeOf(it);
    const why = tagsOf(it, 'intent').slice(0, 3).map(t => cap(t.tag).toLowerCase()).join(', ');
    if (style) rows.push(['Style', style]);
    if (tags) rows.push(['Tags', tags]);
    if (coll) rows.push(['Collection', coll]);
    if (place) rows.push(['Place', place]);
    if (why) rows.push(['Why saved', why]);
    const meta = [it.domain || App.displayLink(it) || '', kindName(it), savedLabel(it)].filter(Boolean).join(' · ');
    const note = (it.summary || '').trim();
    return { rows, meta, note, title: it.title || it.domain || 'Untitled', cols: colours(it) };
  }
  // Fixed line counts so the layout knows each card's height without measuring.
  const lines = (s, per) => (String(s).length > per ? 2 : 1);
  function detailsHeight(d) {
    let h = 14 + lines(d.title, 26) * 20 + 4 + lines(d.meta, 38) * 16;
    if (d.cols.length) h += 26;
    h += 6;
    d.rows.forEach(([, v]) => { h += lines(v, 30) * 15 + 6; });
    if (d.note) h += 8 + Math.min(3, Math.ceil(d.note.length / 44)) * 15;
    return h + 12;
  }

  // ---------- Grouping ----------
  function topicMap(items) {
    // Greedy: the subject tag shared by the most unassigned items, again and again.
    const left = new Set(items.map(i => i.slug)), out = new Map();
    const tagsBy = new Map(items.map(i => [i.slug, tagsOf(i, 'subject', 0.4).concat(tagsOf(i, 'format', 0.5)).map(t => t.tag).filter(t => !SKIP_SUBJECT.has(t) && t !== (i.domain || '').split('.')[0])]));
    const tooBroad = Math.max(3, items.length * 0.5);
    for (let round = 0; round < 24 && left.size; round++) {
      const count = new Map();
      left.forEach(s => tagsBy.get(s).forEach(t => count.set(t, (count.get(t) || 0) + 1)));
      let bt = null, bn = 1;
      count.forEach((n, t) => { if (n > bn && n <= tooBroad) { bn = n; bt = t; } });
      if (!bt) break;
      left.forEach(s => { if (tagsBy.get(s).includes(bt)) { out.set(s, bt); left.delete(s); } });
    }
    return out;
  }
  function groupKey(it, by, topics) {
    switch (by) {
      case 'collection': { const c = tagsOf(it, 'collection')[0]; return c ? c.tag : 'No collection'; }
      case 'topic': return topics.get(it.slug) || 'Other';
      case 'kind': return kindName(it);
      case 'colour': { const c = tagsOf(it, 'color', 0.15)[0]; return c ? c.tag : 'No colour'; }
      case 'style': { const s = tagsOf(it, 'style', 0.4)[0]; return s ? s.tag : 'No style'; }
      case 'place': return placeOf(it) || 'No place';
      case 'source': return (it.domain || 'No source').replace(/^www\./, '');
      case 'month': { const d = new Date(it.added_at); return isNaN(d) ? 'Undated' : d.toLocaleDateString('en-US', { month: 'long', year: 'numeric' }); }
    }
    return 'All';
  }
  function subtitleFor(items) {
    const count = new Map();
    items.forEach(it => tagsOf(it, 'subject', 0.6).concat(tagsOf(it, 'style', 0.6)).forEach(t => { if (!SKIP_SUBJECT.has(t.tag)) count.set(t.tag, (count.get(t.tag) || 0) + 1); }));
    const top = [...count.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([t]) => t);
    return `${items.length} ${items.length === 1 ? 'save' : 'saves'}${top.length ? ' · ' + top.join(', ') : ''}`;
  }

  // ---------- Similarity index (rules only) ----------
  function buildIndex() {
    inv = new Map(); featOf = new Map(); simCache = new Map();
    const add = (f, slug) => { let a = inv.get(f); if (!a) inv.set(f, a = []); a.push(slug); };
    set.forEach(it => {
      const fs = [];
      const cols = tagsOf(it, 'color', 0.3).slice(0, 2);
      cols.forEach(t => fs.push({ f: 'c:' + t.tag, type: 'colour', tag: t.tag }));
      const styles = tagsOf(it, 'style', 0.5).slice(0, 3);
      styles.forEach(t => fs.push({ f: 's:' + t.tag, type: 'style', tag: t.tag }));
      if (cols[0] && styles[0]) fs.push({ f: 'l:' + cols[0].tag + '|' + styles[0].tag, type: 'looks', tag: `${cols[0].tag}, ${styles[0].tag}` });
      const k = kindName(it);
      const fmt = tagsOf(it, 'format', 0.4)[0];
      if (k && k !== 'Website' && k !== 'Note') fs.push({ f: 'k:' + k, type: 'kind', tag: k.toLowerCase() });
      else if (fmt && fmt.tag !== 'website') fs.push({ f: 'k:' + fmt.tag, type: 'kind', tag: fmt.tag });
      const place = placeOf(it);
      if (place) fs.push({ f: 'p:' + place.toLowerCase(), type: 'place', tag: place });
      tagsOf(it, 'subject', 0.6).filter(t => !SKIP_SUBJECT.has(t.tag) && t.tag !== (it.domain || '').split('.')[0]).slice(0, 4)
        .forEach(t => fs.push({ f: 'i:' + t.tag, type: 'idea', tag: t.tag }));
      featOf.set(it.slug, fs);
      fs.forEach(x => add(x.f, it.slug));
    });
  }
  // The strongest few neighbours of one item. Generic features (shared by a big
  // share of the set) are skipped; rarer ones weigh more.
  function simFor(slug) {
    let out = simCache.get(slug);
    if (out) return out;
    const fs = featOf.get(slug) || [];
    const N = set.length;
    const cap = Math.max(40, Math.min(600, N * 0.25));
    const score = new Map();
    fs.forEach(x => {
      const post = inv.get(x.f);
      if (!post || post.length < 2 || post.length > cap) return;
      const idf = Math.log(1 + N / post.length);
      const w = SIM[x.type].w * idf;
      for (const b of post) {
        if (b === slug) continue;
        let s = score.get(b);
        if (!s) score.set(b, s = { total: 0, best: null, bw: 0 });
        s.total += w;
        if (w > s.bw) { s.bw = w; s.best = x; }
      }
    });
    out = [...score.entries()].filter(([, s]) => s.total >= 1.8)
      .sort((a, b) => b[1].total - a[1].total).slice(0, 6)
      .map(([b, s]) => ({ a: slug, b, type: s.best.type, label: s.best.tag, s: s.total }));
    simCache.set(slug, out);
    return out;
  }
  // Quiet by default: the two strongest lines per item; a selected item shows up to six.
  const linksFor = (slug, focused) => simFor(slug).filter((l, i) => focused ? true : view.k < 0.3 ? (i < 1 && l.s >= 3.2) : (i < 2 && l.s >= 2.8));
  function similarityScore(a, b) {
    const fb = new Set((featOf.get(b.slug) || featuresLoose(b)).map(x => x.f));
    let s = 0; const shared = [];
    (featOf.get(a.slug) || featuresLoose(a)).forEach(x => { if (fb.has(x.f)) { s += SIM[x.type].w; shared.push(x.tag); } });
    return { s, shared };
  }
  function featuresLoose(it) {
    const fs = [];
    tagsOf(it, 'color', 0.3).slice(0, 2).forEach(t => fs.push({ f: 'c:' + t.tag, type: 'colour', tag: t.tag }));
    tagsOf(it, 'style', 0.5).slice(0, 3).forEach(t => fs.push({ f: 's:' + t.tag, type: 'style', tag: t.tag }));
    const place = placeOf(it); if (place) fs.push({ f: 'p:' + place.toLowerCase(), type: 'place', tag: place });
    tagsOf(it, 'subject', 0.6).filter(t => !SKIP_SUBJECT.has(t.tag)).slice(0, 4).forEach(t => fs.push({ f: 'i:' + t.tag, type: 'idea', tag: t.tag }));
    const k = kindName(it); if (k && k !== 'Website' && k !== 'Note') fs.push({ f: 'k:' + k, type: 'kind', tag: k.toLowerCase() });
    return fs;
  }

  // ---------- Layout ----------
  function computeSet() {
    const base = App.filtered ? App.filtered() : App.items();
    const ids = new Set(base.map(i => i.slug));
    // Saves you accepted from "maybe related" come along with the item they relate to.
    doc.links.forEach(l => {
      if (l.kind !== 'related') return;
      if (ids.has(l.a) && !ids.has(l.b) && App.item(l.b)) { ids.add(l.b); }
    });
    set = [...ids].map(s => App.item(s)).filter(Boolean);
    setIndex = new Map(set.map(i => [i.slug, i]));
  }
  function layout() {
    dirtyLayout = false;
    computeSet();
    buildIndex();
    nodes = new Map();
    const by = doc.groupBy in GROUPS ? doc.groupBy : 'collection';
    const topics = by === 'topic' ? topicMap(set) : null;
    const groups = new Map();
    set.forEach(it => { const k = groupKey(it, by, topics); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(it); });
    let entries = [...groups.entries()].sort((a, b) => b[1].length - a[1].length);
    // Too many small groups: fold the tail into "Other".
    if (entries.length > 18) {
      const keep = entries.slice(0, 17), rest = entries.slice(17).flatMap(([, v]) => v);
      const other = keep.find(([k]) => /^(other|no )/i.test(k));
      if (other) other[1].push(...rest); else keep.push(['Other', rest]);
      entries = keep;
    }
    const isMissing = (k) => /^(no |other$|undated$)/i.test(k);
    entries.sort((a, b) => (isMissing(a[0]) - isMissing(b[0])) || b[1].length - a[1].length);

    // Per group: a loose masonry block.
    clusters = entries.map(([key, items], i) => {
      items.sort((a, b) => String(b.added_at).localeCompare(String(a.added_at)));
      const cols = Math.max(1, Math.min(16, Math.ceil(Math.sqrt(items.length * 0.9))));
      const colY = new Array(cols).fill(0).map((_, c) => (c % 2) * 56);
      const slugs = [];
      items.forEach(it => {
        const c = colY.indexOf(Math.min(...colY));
        const d = details(it);
        const ch = Math.round(W * coverRatio(it));
        const dh = detailsHeight(d);
        const jitter = Math.round((hashOf(it.slug) - 0.5) * 20);
        nodes.set(it.slug, { slug: it.slug, item: it, d, x: c * (W + COL_GAP) + jitter, y: colY[c], ch, dh, h: ch + 8 + dh, cl: i });
        colY[c] += ch + 8 + dh + ROW_GAP + Math.round(hashOf(it.slug + 'y') * 24);
        slugs.push(it.slug);
      });
      const w = cols * W + (cols - 1) * COL_GAP;
      const h = Math.max(...colY) - ROW_GAP;
      return { key, name: cap(key), sub: subtitleFor(items), color: PALETTE[i % PALETTE.length], x: 0, y: 0, w, h, slugs, items };
    });

    // Gaps per group (computed hints).
    clusters.forEach(cl => { cl.empty = emptySpot(cl); cl.ghost = ghostFor(cl); });

    // Shelf-pack the groups into rows.
    const footW = (cl) => cl.w + (cl.ghost ? 60 + W : 0);
    const footH = (cl) => TITLE_H + cl.h + (cl.empty ? 140 : 0);
    const area = clusters.reduce((s, cl) => s + footW(cl) * footH(cl), 0);
    const maxW = Math.max(2400, Math.sqrt(area) * 1.5);
    let x = 0, y = 0, rowH = 0;
    clusters.forEach(cl => {
      if (x > 0 && x + footW(cl) > maxW) { x = 0; y += rowH + CL_GAP_Y; rowH = 0; }
      cl.x = x; cl.y = y + TITLE_H;
      x += footW(cl) + CL_GAP_X;
      rowH = Math.max(rowH, footH(cl));
    });
    // Place cards, honouring cards you moved (for this grouping).
    clusters.forEach(cl => cl.slugs.forEach(s => { const n = nodes.get(s); n.x += cl.x; n.y += cl.y; }));
    doc.cards.forEach(c => { const n = nodes.get(c.slug); if (n && c.by === by && Number.isFinite(c.x)) { n.x = c.x; n.y = c.y; } });

    // Bounds and timeline below everything.
    let x0 = 0, y0 = -TITLE_H, x1 = 0, y1 = 0;
    nodes.forEach(n => { x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y - TITLE_H); x1 = Math.max(x1, n.x + W); y1 = Math.max(y1, n.y + n.h); });
    clusters.forEach(cl => { x1 = Math.max(x1, cl.x + footW(cl)); y1 = Math.max(y1, cl.y + cl.h + (cl.empty ? 140 : 0)); });
    timeline = buildTimeline(x0, y1 + 260, Math.max(1600, x1 - x0));
    if (timeline) y1 = timeline.y + timeline.h;
    worldBox = { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    rebuildHash();
    rendered.forEach(el => el.remove());
    rendered.clear();
    renderStatic();
  }
  function rebuildHash() {
    hash = new Map();
    nodes.forEach(n => {
      const cx0 = Math.floor(n.x / CELL), cx1 = Math.floor((n.x + W) / CELL);
      const cy0 = Math.floor(n.y / CELL), cy1 = Math.floor((n.y + n.h) / CELL);
      for (let cx = cx0; cx <= cx1; cx++) for (let cy = cy0; cy <= cy1; cy++) {
        const k = cx + ',' + cy; let a = hash.get(k); if (!a) hash.set(k, a = []); a.push(n.slug);
      }
    });
  }
  function inRect(x0, y0, x1, y1) {
    const out = new Set();
    for (let cx = Math.floor(x0 / CELL); cx <= Math.floor(x1 / CELL); cx++)
      for (let cy = Math.floor(y0 / CELL); cy <= Math.floor(y1 / CELL); cy++) {
        const a = hash.get(cx + ',' + cy); if (a) a.forEach(s => out.add(s));
      }
    return [...out].filter(s => { const n = nodes.get(s); return n.x < x1 && n.x + W > x0 && n.y < y1 && n.y + n.h > y0; });
  }

  // ---------- Gaps (computed) ----------
  function emptySpot(cl) {
    const n = cl.items.length;
    if (n < 3) return null;
    const withPlace = cl.items.filter(placeOf).length;
    const withWhy = cl.items.filter(i => tagsOf(i, 'intent').length).length;
    const kinds = new Map(); cl.items.forEach(i => { const k = kindName(i); kinds.set(k, (kinds.get(k) || 0) + 1); });
    const [topKind, topKindN] = [...kinds.entries()].sort((a, b) => b[1] - a[1])[0];
    const withColour = cl.items.filter(i => tagsOf(i, 'color', 0.15).length).length;
    if (topKindN === n && n >= 4) return `All ${n} here are ${topKind.toLowerCase()}${/s$/.test(topKind) ? '' : 's'}. Nothing of another kind yet.`;
    if (withPlace / n < 0.25) return `${n} saved, ${withPlace ? 'only ' + withPlace : 'none'} ${withPlace === 1 ? 'has' : 'have'} a place.`;
    if (withWhy / n < 0.25) return `Only ${withWhy} of ${n} say why they were saved.`;
    if (withColour / n < 0.5) return `${n - withColour} of ${n} have no colour tags yet.`;
    return null;
  }
  // One save from the rest of the library that fits this group but isn't shown.
  function ghostFor(cl) {
    const all = App.items();
    if (set.length >= all.length || cl.items.length < 2) return null;
    const dismissed = new Set(doc.dismissed);
    const sample = cl.items.slice(0, 24);
    const want = new Map();
    sample.forEach(it => featuresLoose(it).forEach(x => want.set(x.f, (want.get(x.f) || 0) + SIM[x.type].w)));
    let best = null;
    for (const it of all) {
      if (setIndex.has(it.slug) || dismissed.has(it.slug)) continue;
      let s = 0; const shared = [];
      featuresLoose(it).forEach(x => { const w = want.get(x.f); if (w) { s += w; shared.push(x.tag); } });
      if (!best || s > best.s) best = { it, s, shared };
    }
    if (!best || best.shared.length < 2 || best.s < Math.max(3, sample.length * 0.35)) return null;
    // Anchor: the shown item it is closest to.
    let anchor = null, as = -1;
    sample.forEach(it => { const r = similarityScore(it, best.it); if (r.s > as) { as = r.s; anchor = it; } });
    return { slug: best.it.slug, item: best.it, shared: [...new Set(best.shared)].slice(0, 3), anchor: anchor && anchor.slug };
  }

  // ---------- Timeline (computed) ----------
  function buildTimeline(x, y, w) {
    const dated = set.map(it => ({ it, t: Date.parse(it.added_at) })).filter(o => Number.isFinite(o.t));
    if (dated.length < 3) return null;
    dated.sort((a, b) => a.t - b.t);
    const t0 = new Date(dated[0].t); t0.setDate(1); t0.setHours(0, 0, 0, 0);
    const t1 = new Date(dated[dated.length - 1].t); t1.setMonth(t1.getMonth() + 1, 1); t1.setHours(0, 0, 0, 0);
    const span = t1 - t0 || 1;
    const week = 7 * 86400000;
    const bins = new Map();
    dated.forEach(o => { const b = Math.floor((o.t - t0) / week); let a = bins.get(b); if (!a) bins.set(b, a = []); a.push(o.it); });
    const months = [];
    for (let d = new Date(t0); d <= t1; d.setMonth(d.getMonth() + 1)) months.push({ t: d.getTime(), label: d.toLocaleDateString('en-US', { month: 'short' }) + (d.getMonth() === 0 ? ' ' + d.getFullYear() : '') });
    // Busiest month band.
    const perMonth = new Map();
    dated.forEach(o => { const d = new Date(o.t); const k = d.getFullYear() * 12 + d.getMonth(); perMonth.set(k, (perMonth.get(k) || 0) + 1); });
    const [bk, bn] = [...perMonth.entries()].sort((a, b) => b[1] - a[1])[0];
    const bandStart = new Date(Math.floor(bk / 12), bk % 12, 1).getTime();
    const bandEnd = new Date(Math.floor(bk / 12), bk % 12 + 1, 1).getTime();
    return { x, y, w, h: 300, t0: t0.getTime(), span, week, bins, months, band: { a: bandStart, b: bandEnd, n: bn }, drift: tasteDrift(dated), count: dated.length };
  }
  function tasteDrift(dated) {
    if (dated.length < 12) return null;
    const third = Math.floor(dated.length / 3);
    const top = (arr) => {
      const c = new Map();
      arr.forEach(o => tagsOf(o.it, 'style', 0.55).concat(tagsOf(o.it, 'subject', 0.7)).concat(tagsOf(o.it, 'color', 0.4)).forEach(t => { if (!SKIP_SUBJECT.has(t.tag)) c.set(t.tag, (c.get(t.tag) || 0) + 1); }));
      return c;
    };
    const early = top(dated.slice(0, third)), late = top(dated.slice(-third));
    const lift = (a, b) => [...a.entries()].map(([t, n]) => [t, n - (b.get(t) || 0)]).sort((x, y) => y[1] - x[1]).filter(([, d]) => d > 1).slice(0, 3).map(([t]) => t);
    const e = lift(early, late), l = lift(late, early);
    if (!e.length && !l.length) return null;
    return `Early saves lean ${e.length ? e.join(', ') : 'mixed'}. Recent saves lean ${l.length ? l.join(', ') : 'mixed'}.`;
  }

  // ---------- Build DOM ----------
  const IC = {
    caret: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 9l6 6 6-6"/></svg>',
    open: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>',
    x: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
  };
  function build() {
    const mc = document.querySelector('.main-content');
    const root = document.createElement('section');
    root.className = 'lc';
    root.setAttribute('aria-label', 'Library canvas');
    root.hidden = true;
    root.innerHTML = `
      <div class="lc-stage" tabindex="0">
        <canvas class="lc-ink" aria-hidden="true"></canvas>
        <div class="lc-world"><div class="lc-static"></div><div class="lc-cards"></div></div>
        <div class="lc-labels" aria-hidden="true"></div>
        <div class="lc-selbar" hidden></div>
        <div class="lc-hint" hidden></div>
      </div>
      <div class="lc-controls">
        <div class="lc-ctl" data-menu="group"><button type="button" class="lc-ctl-btn" data-open="group"><span class="lc-ctl-k">Group by</span> <b data-groupname></b>${IC.caret}</button>
          <div class="lc-menu" data-menu-for="group" hidden></div></div>
        <div class="lc-ctl" data-menu="sim"><button type="button" class="lc-ctl-btn" data-open="sim"><span class="lc-swatches" data-swatches></span> Similarity${IC.caret}</button>
          <div class="lc-menu" data-menu-for="sim" hidden></div></div>
        <div class="lc-ctl" data-menu="ins"><button type="button" class="lc-ctl-btn" data-open="ins">Intent, time &amp; gaps${IC.caret}</button>
          <div class="lc-menu" data-menu-for="ins" hidden></div></div>
      </div>
      <div class="lc-create" hidden>
        <button type="button" data-create="question">Question</button>
        <button type="button" data-create="note">Note</button>
        <button type="button" data-create="set">Set</button>
      </div>`;
    mc.appendChild(root);
    els.root = root;
    els.stage = root.querySelector('.lc-stage');
    els.ink = root.querySelector('.lc-ink');
    els.world = root.querySelector('.lc-world');
    els.static = root.querySelector('.lc-static');
    els.cards = root.querySelector('.lc-cards');
    els.labels = root.querySelector('.lc-labels');
    els.selbar = root.querySelector('.lc-selbar');
    els.hint = root.querySelector('.lc-hint');
    els.controls = root.querySelector('.lc-controls');
    els.create = root.querySelector('.lc-create');
    els.ctx = els.ink.getContext('2d');

    // Grid / canvas switch, right of the search field.
    const search = document.querySelector('.bar-search');
    const sw = document.createElement('div');
    sw.className = 'view-switch';
    sw.setAttribute('role', 'group');
    sw.setAttribute('aria-label', 'View');
    sw.innerHTML = `<button type="button" data-view="grid" aria-label="Grid view" title="Grid">${App.icon('squares-four')}</button><button type="button" data-view="canvas" aria-label="Canvas view" title="Canvas">${App.icon('graph')}</button>`;
    search.after(sw);
    els.switch = sw;
    // Zoom, shown in canvas view only.
    const zm = document.createElement('div');
    zm.className = 'lc-zoom';
    zm.innerHTML = `<button type="button" data-z="out" aria-label="Zoom out">−</button><button type="button" data-z="reset" class="lc-zoom-pct" aria-label="Zoom to 100%">100%</button><button type="button" data-z="in" aria-label="Zoom in">+</button><button type="button" data-z="fit" aria-label="Fit everything">Fit</button>`;
    sw.after(zm);
    els.zoom = zm;
    renderMenus();
  }

  function renderMenus() {
    els.controls.querySelector('[data-groupname]').textContent = GROUPS[doc.groupBy] || 'Collection';
    els.controls.querySelector('[data-menu-for="group"]').innerHTML = Object.entries(GROUPS)
      .map(([k, v]) => `<button type="button" class="lc-mi${k === doc.groupBy ? ' is-on' : ''}" data-group="${k}">${v}</button>`).join('');
    const sw = Object.entries(SIM).filter(([k]) => layers.sim.on && layers.sim[k]).map(([, d]) => `<i style="background:${d.color || 'var(--text)'}"></i>`).join('');
    els.controls.querySelector('[data-swatches]').innerHTML = sw;
    els.controls.querySelector('[data-menu-for="sim"]').innerHTML =
      `<label class="lc-mi lc-mi-head"><input type="checkbox" data-sim="on"${layers.sim.on ? ' checked' : ''}> <span>Show similarity lines</span></label>` +
      Object.entries(SIM).map(([k, d]) => `<label class="lc-mi"><input type="checkbox" data-sim="${k}"${layers.sim[k] ? ' checked' : ''}${layers.sim.on ? '' : ' disabled'}>
        <span class="lc-key${d.dash ? ' is-dash' : ''}" style="--c:${d.color || 'var(--text)'}"></span><span><b>${d.label}</b> <em>${d.hint}</em></span></label>`).join('') +
      `<p class="lc-menu-note">Lines appear as you zoom in. Select an item to see only its lines.</p>`;
    els.controls.querySelector('[data-menu-for="ins"]').innerHTML =
      Object.entries(INSIGHTS).map(([k, v]) => `<label class="lc-mi"><input type="checkbox" data-ins="${k}"${layers.ins[k] ? ' checked' : ''}><span>${v}</span></label>`).join('') +
      `<div class="lc-legend">${Object.entries(L2).filter(([k]) => k !== 'related').map(([, d]) => `<span><span class="lc-key${d.dash ? ' is-dash' : ''}" style="--c:${d.color}"></span>${d.label} <em>${d.hint}</em></span>`).join('')}</div>
       <p class="lc-menu-note">Double-click empty canvas to add a question, note or set. Select an item to mark it or connect it.</p>`;
  }

  // ---------- Static world layer: group titles, empty spots, ghosts, notes, timeline ----------
  function renderStatic() {
    let h = '';
    clusters.forEach(cl => {
      h += `<div class="lc-group" style="transform:translate(${cl.x}px,${cl.y - TITLE_H}px);width:${Math.max(cl.w, 320)}px">
        <h3><i style="background:${cl.color}"></i><span>${esc(cl.name)}</span></h3><p>${esc(cl.sub)}</p></div>`;
      if (cl.empty) h += `<div class="lc-empty" data-ins-part="gaps" style="transform:translate(${cl.x}px,${cl.y + cl.h + 60}px);width:${Math.max(cl.w, 300)}px"><span>Empty spot</span>${esc(cl.empty)}</div>`;
      if (cl.ghost) {
        const g = cl.ghost, it = g.item, ch = Math.round(W * coverRatio(it) * 0.62);
        h += `<div class="lc-ghost" data-ins-part="gaps" data-ghost="${esc(g.slug)}" style="transform:translate(${cl.x + cl.w + 60}px,${cl.y}px)">
          <div class="lc-ghost-head"><b>Maybe related</b> · from your library</div>
          <div class="lc-ghost-cover" style="height:${ch}px">${App.thumbHTML(it)}</div>
          <div class="lc-ghost-title">${esc(it.title || it.domain)}</div>
          <div class="lc-ghost-meta">${esc([it.domain, kindName(it), savedLabel(it).replace('Saved ', 'saved ')].filter(Boolean).join(' · '))}</div>
          <div class="lc-ghost-why">Shares: ${esc(g.shared.join(', ') || 'similar tags')}.</div>
          <div class="lc-ghost-act"><button type="button" data-accept="${esc(g.slug)}">Accept</button><button type="button" data-dismiss="${esc(g.slug)}">Dismiss</button></div></div>`;
      }
    });
    if (timeline) h += timelineHTML(timeline);
    els.static.innerHTML = h + '<div class="lc-notes"></div>';
    els.notes = els.static.querySelector('.lc-notes');
    renderNotes();
  }
  function timelineHTML(T) {
    const X = (t) => T.x + ((t - T.t0) / T.span) * T.w;
    const base = T.y + 230;
    let h = `<div class="lc-time" data-ins-part="time" style="transform:translate(${T.x}px,${T.y}px);width:${T.w}px">
      <h3>Save timeline</h3><p>When each item on this canvas was saved · ${T.count} items</p></div>`;
    h += `<div class="lc-time-band" data-ins-part="time" style="transform:translate(${X(T.band.a)}px,${T.y + 70}px);width:${Math.max(40, X(T.band.b) - X(T.band.a))}px;height:${160}px"><span>${T.band.n} saved this month, the most</span></div>`;
    h += `<div class="lc-time-axis" data-ins-part="time" style="transform:translate(${T.x}px,${base}px);width:${T.w}px"></div>`;
    T.months.forEach(m => { h += `<div class="lc-time-month" data-ins-part="time" style="transform:translate(${X(m.t)}px,${base + 10}px)">${esc(m.label)}</div>`; });
    const big = T.count > 160;
    T.bins.forEach((items, b) => {
      const x = X(T.t0 + b * T.week + T.week / 2);
      if (big) {
        const hh = Math.min(150, 6 + items.length * 3);
        const col = clusters[nodes.get(items[0].slug) ? nodes.get(items[0].slug).cl : 0];
        h += `<div class="lc-time-bar" data-ins-part="time" data-week="${b}" title="${items.length} saved" style="transform:translate(${x - 5}px,${base - hh}px);height:${hh}px;background:${col ? col.color : 'var(--text-dim)'}"></div>`;
      } else {
        items.slice(0, 8).forEach((it, i) => {
          const n = nodes.get(it.slug); const col = n ? clusters[n.cl].color : 'var(--text-dim)';
          h += `<div class="lc-time-pill" data-ins-part="time" data-slug="${esc(it.slug)}" style="transform:translate(${x}px,${base - 22 - i * 22}px);background:${col}">${esc((it.domain || it.title || '').replace(/^www\./, ''))}</div>`;
        });
      }
    });
    if (T.drift) h += `<div class="lc-drift" data-ins-part="time" style="transform:translate(${T.x + T.w * 0.42}px,${T.y + 60}px)"><span>Taste drift</span>${esc(T.drift)}</div>`;
    return h;
  }
  function renderNotes() {
    if (!els.notes) return;
    els.notes.innerHTML = doc.notes.map(n => {
      const cls = n.kind === 'question' ? 'is-question' : n.kind === 'set' ? 'is-set' : n.kind === 'region' ? 'is-region' : 'is-note';
      const label = n.kind === 'question' ? 'Question' : n.kind === 'set' ? 'Set' : n.kind === 'region' ? 'Region note' : 'Note';
      return `<div class="lc-note ${cls}${selNote === n.id ? ' is-selected' : ''}" data-ins-part="notes" data-note="${n.id}" style="transform:translate(${n.x}px,${n.y}px)">
        <div class="lc-note-head"><span>${label}</span><button type="button" class="lc-note-del" data-del-note="${n.id}" aria-label="Delete">${IC.x}</button></div>
        <div class="lc-note-text" contenteditable="true" spellcheck="true" data-placeholder="${n.kind === 'question' ? 'Ask something about these saves' : n.kind === 'set' ? 'Name this set' : 'Write a note'}">${esc(n.text || '')}</div></div>`;
    }).join('');
    measureNotes();
  }

  function measureNotes() {
    requestAnimationFrame(() => {
      if (!els.notes) return;
      els.notes.querySelectorAll('[data-note]').forEach(el => noteSize.set(el.dataset.note, { w: el.offsetWidth, h: el.offsetHeight }));
      schedule();
    });
  }

  // ---------- Cards ----------
  function cardEl(n) {
    const it = n.item, d = n.d;
    const el = document.createElement('div');
    el.className = 'lc-card';
    el.dataset.slug = n.slug;
    const sw = d.cols.map(c => `<span class="lc-sw"><i style="background:${App.colorHex ? App.colorHex(c) : App.dominantColor(it)}"></i>${esc(c)}</span>`).join('');
    const rows = d.rows.map(([k, v]) => `<div class="lc-row"><dt>${k}</dt><dd class="${lines(v, 30) > 1 ? 'l2' : ''}">${esc(v)}</dd></div>`).join('');
    const dom = (it.domain || '').replace(/^www\./, '');
    el.innerHTML = `
      <div class="lc-cover" style="height:${n.ch}px">${App.thumbHTML(it)}${dom ? `<span class="lc-dom">${esc(dom)}</span>` : ''}</div>
      <div class="lc-det" style="height:${n.dh}px">
        <div class="lc-title${lines(d.title, 26) > 1 ? ' l2' : ''}">${esc(d.title)}</div>
        <div class="lc-meta${lines(d.meta, 38) > 1 ? ' l2' : ''}">${esc(d.meta)}</div>
        ${sw ? `<div class="lc-sws">${sw}</div>` : ''}
        <dl class="lc-rows">${rows}</dl>
        ${d.note ? `<div class="lc-quote">“${esc(d.note)}”</div>` : ''}
      </div>`;
    el.style.transform = `translate(${n.x}px,${n.y}px)`;
    decorate(el, n);
    return el;
  }
  // Marks and revisit state on a card (cheap; re-run when they change).
  function decorate(el, n) {
    const rec = cardRec(n.slug);
    el.querySelectorAll('.lc-mark, .lc-visit').forEach(x => x.remove());
    el.classList.toggle('is-use', !!(rec && rec.state === 'use'));
    el.classList.toggle('is-rejected', !!(rec && rec.state === 'rejected'));
    if (rec && rec.state) {
      el.insertAdjacentHTML('afterbegin', `<div class="lc-mark" data-ins-part="marks"><b>${rec.state === 'use' ? 'Use' : 'Rejected'}</b>${rec.reason ? ' ' + esc(rec.reason) : ''}</div>`);
    }
    const v = visit(n.item);
    el.classList.toggle('is-glow', v === 'glow');
    el.classList.toggle('is-fade', v === 'fade');
    if (v) {
      const it = n.item;
      const txt = v === 'glow' ? `Opened ${it.open_count > 1 ? it.open_count + '×' : ''} recently`.replace('  ', ' ')
        : `Not opened since ${new Date(it.last_opened_at).toLocaleDateString('en-US', { month: 'short', year: 'numeric' })}`;
      el.insertAdjacentHTML('beforeend', `<div class="lc-visit" data-ins-part="glow">${esc(txt)}</div>`);
    }
  }
  function visit(it) {
    const t = Date.parse(it.last_opened_at);
    if (!Number.isFinite(t)) return null;
    const days = (Date.now() - t) / 86400000;
    if (days <= 14) return 'glow';
    if (days >= 120) return 'fade';
    return null;
  }

  // ---------- Render ----------
  function schedule(full) {
    if (full) schedule.full = true;
    if (raf) return;
    raf = requestAnimationFrame(() => { raf = 0; render(); });
  }
  function markLayout() {
    dirtyLayout = true;
    if (layoutRaf) return;
    layoutRaf = requestAnimationFrame(() => { layoutRaf = 0; if (mode === 'canvas') { layout(); schedule(true); } });
  }
  function lodFor(k) { return k < LOD_BLOCKS ? 0 : k < LOD_DETAIL ? 1 : 2; }
  function render() {
    if (mode !== 'canvas') return;
    const t0 = window.__lcPerf ? performance.now() : 0;
    if (dirtyLayout) layout();
    const r = els.stage.getBoundingClientRect();
    const k = view.k, lod = lodFor(k);
    els.world.style.transform = `translate3d(${view.x}px,${view.y}px,0) scale(${k})`;
    els.root.style.setProperty('--inv', String(1 / k));
    els.root.style.setProperty('--title-scale', String(Math.max(1, 0.55 / k)));
    els.zoom.querySelector('.lc-zoom-pct').textContent = Math.round(k * 100) + '%';
    Object.keys(INSIGHTS).forEach(p => els.root.classList.toggle('hide-' + p, !layers.ins[p]));

    // Cards in view (plus a margin), DOM only when zoomed in enough.
    const m = 300 / k;
    const x0 = (-view.x) / k - m, y0 = (-view.y) / k - m, x1 = (r.width - view.x) / k + m, y1 = (r.height - view.y) / k + m;
    // Far out, a small set still gets real cards; a big one is drawn as blocks.
    let vis = inRect(x0, y0, x1, y1);
    let blocks = lod === 0 && vis.length > 260;
    if (blocks) vis = [];
    els.stage.dataset.lod = blocks ? 0 : Math.max(1, lod);
    const want = new Set(vis);
    rendered.forEach((el, s) => { if (!want.has(s)) { el.remove(); rendered.delete(s); } });
    const frag = document.createDocumentFragment();
    vis.forEach(s => {
      let el = rendered.get(s);
      const n = nodes.get(s);
      if (!el) { el = cardEl(n); rendered.set(s, el); frag.appendChild(el); }
      else el.style.transform = `translate(${n.x}px,${n.y}px)`;
    });
    if (frag.childNodes.length) els.cards.appendChild(frag);

    // Focus: the selected (or hovered) item and what it links to.
    const focus = sel || (!blocks ? hover : null);
    lastBlocks = blocks;
    const linked = sel ? focusSet(sel) : null;
    rendered.forEach((el, s) => {
      el.classList.toggle('is-selected', s === sel);
      el.classList.toggle('is-dim', !!(linked && !linked.has(s)));
      el.classList.toggle('is-target', !!(connect && s !== connect.from));
    });
    els.root.classList.toggle('has-focus', !!linked);
    els.root.classList.toggle('is-connecting', !!(connect || pinFor));
    drawInk(r, blocks ? 0 : Math.max(1, lod), vis, focus, linked);
    if (hover && !rendered.has(hover)) hover = null;
    renderSelbar(r);
    schedule.full = false;
    if (t0) window.__lcPerf.push(performance.now() - t0);
  }
  function focusSet(slug) {
    const s = new Set([slug]);
    linksFor(slug, true).forEach(l => s.add(l.b));
    doc.links.forEach(l => { if (l.a === slug) s.add(l.b); if (l.b === slug) s.add(l.a); });
    return s;
  }

  // ---------- Ink: lines, far-out blocks ----------
  function anchor(n, toward) {
    // Edge point of the card's cover facing the other end.
    const cx = n.x + W / 2, cy = n.y + n.ch / 2;
    const dx = toward.x - cx, dy = toward.y - cy;
    if (Math.abs(dx) * n.ch > Math.abs(dy) * W) return { x: dx > 0 ? n.x + W : n.x, y: cy, nx: Math.sign(dx), ny: 0 };
    return dy > 0 ? { x: cx, y: n.y + n.h, nx: 0, ny: 1 } : { x: cx, y: n.y, nx: 0, ny: -1 };
  }
  function centreOf(id) {
    const n = nodes.get(id);
    if (n) return { x: n.x + W / 2, y: n.y + n.ch / 2, n };
    const note = doc.notes.find(x => x.id === id);
    if (note) return { x: note.x + 110, y: note.y + 40, note };
    return null;
  }
  function endpoints(a, b) {
    const A = centreOf(a), B = centreOf(b);
    if (!A || !B) return null;
    const pa = A.n ? anchor(A.n, B) : noteAnchor(A.note, B);
    const pb = B.n ? anchor(B.n, A) : noteAnchor(B.note, A);
    return { pa, pb };
  }
  function noteAnchor(note, toward) {
    const sz = noteSize.get(note.id) || { w: 220, h: 90 };
    const w = sz.w, h = sz.h;
    const cx = note.x + w / 2, cy = note.y + h / 2, dx = toward.x - cx, dy = toward.y - cy;
    if (Math.abs(dx) * h > Math.abs(dy) * w) return { x: dx > 0 ? note.x + w : note.x, y: cy, nx: Math.sign(dx), ny: 0 };
    return dy > 0 ? { x: cx, y: note.y + h, nx: 0, ny: 1 } : { x: cx, y: note.y, nx: 0, ny: -1 };
  }
  function curve(pa, pb) {
    const d = Math.max(40, Math.hypot(pb.x - pa.x, pb.y - pa.y) * 0.35);
    return [pa.x, pa.y, pa.x + pa.nx * d, pa.y + pa.ny * d, pb.x + pb.nx * d, pb.y + pb.ny * d, pb.x, pb.y];
  }
  function bez(c, t) {
    const u = 1 - t;
    return { x: u * u * u * c[0] + 3 * u * u * t * c[2] + 3 * u * t * t * c[4] + t * t * t * c[6], y: u * u * u * c[1] + 3 * u * u * t * c[3] + 3 * u * t * t * c[5] + t * t * t * c[7] };
  }
  function drawInk(r, lod, vis, focus, linked) {
    const dpr = window.devicePixelRatio || 1;
    const c = els.ink, ctx = els.ctx;
    if (c.width !== Math.round(r.width * dpr) || c.height !== Math.round(r.height * dpr)) {
      c.width = Math.round(r.width * dpr); c.height = Math.round(r.height * dpr);
      c.style.width = r.width + 'px'; c.style.height = r.height + 'px';
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, r.width, r.height);
    ctx.setTransform(dpr * view.k, 0, 0, dpr * view.k, dpr * view.x, dpr * view.y);
    const k = view.k;
    const textCol = theme.text;

    // Far out: every item as a colour block (no DOM).
    if (lod === 0) {
      const x0 = -view.x / k, y0 = -view.y / k, x1 = (r.width - view.x) / k, y1 = (r.height - view.y) / k;
      const cardCol = theme.card;
      inRect(x0, y0, x1, y1).forEach(s => {
        const n = nodes.get(s);
        const dim = linked && !linked.has(s);
        ctx.globalAlpha = dim ? 0.25 : 1;
        if (n.block === undefined) n.block = n.item.has_image && (n.item.tags || []).some(t => t.category === 'color') ? App.dominantColor(n.item) : null;
        ctx.fillStyle = n.block || cardCol;
        ctx.fillRect(n.x, n.y, W, n.ch);
        ctx.fillStyle = cardCol;
        ctx.fillRect(n.x, n.y + n.ch + 8, W, n.dh);
        if (s === sel) { ctx.globalAlpha = 1; ctx.lineWidth = 6 / k; ctx.strokeStyle = theme.accent; ctx.strokeRect(n.x - 8, n.y - 8, W + 16, n.h + 16); }
      });
      ctx.globalAlpha = 1;
    }

    const labels = [];
    const lw = (px) => px / k;
    const drawLink = (a, b, color, dash, alpha, width, arrow, label, cls) => {
      const e = endpoints(a, b);
      if (!e) return;
      const cv = curve(e.pa, e.pb);
      ctx.globalAlpha = alpha;
      ctx.strokeStyle = color || textCol;
      ctx.lineWidth = lw(width);
      ctx.setLineDash(dash ? dash.map(v => lw(v)) : []);
      ctx.beginPath(); ctx.moveTo(cv[0], cv[1]); ctx.bezierCurveTo(cv[2], cv[3], cv[4], cv[5], cv[6], cv[7]); ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = color || textCol;
      const dot = lw(3.2);
      [[cv[0], cv[1]], [cv[6], cv[7]]].forEach(([x, y], i) => {
        if (arrow && (i === 1 || arrow === 'both')) {
          const p = i === 1 ? bez(cv, 0.97) : bez(cv, 0.03);
          const ang = Math.atan2(y - p.y, x - p.x), s = lw(9);
          ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - s * Math.cos(ang - 0.45), y - s * Math.sin(ang - 0.45)); ctx.lineTo(x - s * Math.cos(ang + 0.45), y - s * Math.sin(ang + 0.45)); ctx.closePath(); ctx.fill();
        } else { ctx.beginPath(); ctx.arc(x, y, dot, 0, Math.PI * 2); ctx.fill(); }
      });
      ctx.globalAlpha = 1;
      if (label && alpha > 0.5) { const m = bez(cv, 0.5); labels.push({ x: m.x, y: m.y, text: label, color: color || textCol, cls }); }
    };

    // Layer 1: computed similarity.
    if (layers.sim.on) {
      const seen = new Set();
      let drawn = 0;
      const from = focus ? [focus] : (lod >= 1 ? vis : []);
      for (const s of from) {
        if (drawn > MAX_LINKS) break;
        for (const l of linksFor(s, s === focus)) {
          if (!layers.sim[l.type]) continue;
          const key = l.a < l.b ? l.a + '|' + l.b : l.b + '|' + l.a;
          if (seen.has(key)) continue;
          seen.add(key);
          const on = !focus || l.a === focus || l.b === focus;
          const d = SIM[l.type];
          drawLink(l.a, l.b, d.color, d.dash, on ? (focus ? 0.95 : 0.45) : 0.06, focus ? 2.2 : 1.4, false, ((k >= 0.9 && l.s >= 3.6) || (focus && on)) ? l.label : null, 'sim-' + l.type);
          drawn++;
        }
      }
    }
    // Layer 2: your links (and accepted maybes).
    doc.links.forEach(l => {
      const d = L2[l.kind] || L2.related;
      if (l.kind === 'question' || l.kind === 'part_of' ? !layers.ins.notes : !layers.ins.marks && l.kind !== 'related') return;
      if (!centreOf(l.a) || !centreOf(l.b)) return;
      const on = !focus || l.a === focus || l.b === focus;
      const label = l.kind === 'influence' ? (l.label ? 'inspired: ' + l.label : 'inspired') : l.kind === 'contrast' ? 'vs' + (l.label ? ' · ' + l.label : '') : l.kind === 'part_of' ? 'part of' : l.kind === 'related' ? (l.label ? 'maybe: ' + l.label : null) : null;
      drawLink(l.a, l.b, d.color, d.dash, on ? 0.95 : 0.12, 2, l.kind === 'influence' ? 'both' : (l.kind === 'part_of' || l.kind === 'question') ? 'end' : false, (k >= LABEL_K * 0.8 || on && focus) ? label : null, 'l2');
    });
    // Gaps: ghost to its anchor.
    if (layers.ins.gaps && lod > 0) clusters.forEach(cl => {
      if (!cl.ghost || !cl.ghost.anchor) return;
      const n = nodes.get(cl.ghost.anchor); if (!n) return;
      const gx = cl.x + cl.w + 60, gy = cl.y + 60;
      const pa = anchor(n, { x: gx, y: gy });
      const cv = curve(pa, { x: gx, y: gy, nx: -1, ny: 0 });
      ctx.strokeStyle = textCol; ctx.globalAlpha = 0.45; ctx.lineWidth = lw(1.2); ctx.setLineDash([lw(4), lw(4)]);
      ctx.beginPath(); ctx.moveTo(cv[0], cv[1]); ctx.bezierCurveTo(cv[2], cv[3], cv[4], cv[5], cv[6], cv[7]); ctx.stroke();
      ctx.setLineDash([]); ctx.globalAlpha = 1;
      if (k >= LABEL_K && cl.ghost.shared[0]) { const m = bez(cv, 0.5); labels.push({ x: m.x, y: m.y, text: 'maybe: ' + cl.ghost.shared[0], color: null, cls: 'maybe' }); }
    });
    // Region notes: a line to the point on the image.
    if (layers.ins.notes) doc.notes.forEach(note => {
      if (note.kind !== 'region' || !note.slug) return;
      const n = nodes.get(note.slug); if (!n) return;
      const px = n.x + (note.rx || 0.5) * W, py = n.y + (note.ry || 0.5) * n.ch;
      ctx.strokeStyle = '#e8890c'; ctx.lineWidth = lw(1.5); ctx.globalAlpha = 0.9;
      ctx.beginPath(); ctx.moveTo(note.x, note.y + 20); ctx.lineTo(px, py); ctx.stroke();
      ctx.beginPath(); ctx.arc(px, py, lw(10), 0, Math.PI * 2); ctx.stroke();
      ctx.globalAlpha = 1;
    });
    renderLabels(labels);
  }
  function renderLabels(list) {
    const k = view.k;
    const r = els.stage.getBoundingClientRect();
    let h = '';
    let n = 0;
    const placed = [];
    // Layer 2 labels first (they are yours), then similarity; skip any that would overlap.
    list.sort((a, b) => (a.cls === 'l2' ? 0 : 1) - (b.cls === 'l2' ? 0 : 1));
    for (const l of list) {
      const sx = l.x * k + view.x, sy = l.y * k + view.y;
      if (sx < -80 || sy < -20 || sx > r.width + 80 || sy > r.height + 20) continue;
      const w = 16 + String(l.text).length * 6.2, hh = 22;
      const box = { x0: sx - w / 2, y0: sy - hh / 2, x1: sx + w / 2, y1: sy + hh / 2 };
      if (placed.some(p => box.x0 < p.x1 + 4 && box.x1 > p.x0 - 4 && box.y0 < p.y1 + 2 && box.y1 > p.y0 - 2)) continue;
      placed.push(box);
      if (++n > MAX_LABELS) break;
      const bg = l.color ? `background:${l.color};color:#fff` : '';
      h += `<span class="lc-label ${l.cls || ''}" style="transform:translate(${sx}px,${sy}px) translate(-50%,-50%);${bg}">${esc(l.text)}</span>`;
    }
    els.labels.innerHTML = h;
  }

  // ---------- Selection bar ----------
  function renderSelbar(r) {
    const bar = els.selbar;
    if (connect || pinFor) {
      bar.hidden = true;
      els.hint.hidden = false;
      els.hint.innerHTML = pinFor ? 'Click the spot on the image for this note · <kbd>Esc</kbd> to cancel'
        : `${{ influence: 'Click the item it inspired', contrast: 'Click the item it contrasts with', part_of: 'Click a set (or empty canvas to make one)', question: 'Click a question (or empty canvas to ask one)' }[connect.kind]} · <kbd>Esc</kbd> to cancel`;
      return;
    }
    els.hint.hidden = true;
    const n = sel && nodes.get(sel);
    if (!n || lastBlocks) { bar.hidden = true; return; }
    const rec = cardRec(sel) || {};
    if (bar.dataset.for !== sel || bar.dataset.state !== (rec.state || '') || schedule.full) {
      bar.dataset.for = sel; bar.dataset.state = rec.state || '';
      bar.innerHTML = `
        <button type="button" data-act="open">${IC.open} Open</button>
        <span class="sep"></span>
        <button type="button" data-act="use" class="${rec.state === 'use' ? 'is-on use' : ''}">Use</button>
        <button type="button" data-act="rejected" class="${rec.state === 'rejected' ? 'is-on rej' : ''}">Reject</button>
        <span class="sep"></span>
        <button type="button" data-act="influence">Inspired…</button>
        <button type="button" data-act="contrast">Vs…</button>
        <button type="button" data-act="part_of">Part of…</button>
        <button type="button" data-act="question">Ask…</button>
        <button type="button" data-act="pin">Note on image</button>
        ${rec.state ? `<input class="lc-reason" type="text" placeholder="Why? (optional)" value="${esc(rec.reason || '')}" maxlength="60">` : ''}`;
    }
    bar.hidden = false;
    const k = view.k;
    let sx = n.x * k + view.x, sy = (n.y + n.h) * k + view.y + 10;
    const bw = bar.offsetWidth || 560, bh = bar.offsetHeight || 40;
    if (sy + bh > r.height - 90) sy = n.y * k + view.y - bh - 10;
    sx = Math.max(12, Math.min(r.width - bw - 12, sx));
    sy = Math.max(12, sy);
    bar.style.transform = `translate(${sx}px,${sy}px)`;
  }

  // ---------- View ----------
  function zoomAt(k, sx, sy) {
    k = Math.max(MIN_K, Math.min(MAX_K, k));
    const r = els.stage.getBoundingClientRect();
    if (sx == null) { sx = r.width / 2; sy = r.height / 2; }
    const wx = (sx - view.x) / view.k, wy = (sy - view.y) / view.k;
    view.k = k; view.x = sx - wx * k; view.y = sy - wy * k;
    schedule();
  }
  function fit(animate, box) {
    const b = box || worldBox;
    const r = els.stage.getBoundingClientRect();
    if (!r.width || !b) return;
    const padT = 120, padB = 110, padX = 48;
    const k = Math.max(MIN_K, Math.min(1, Math.min((r.width - padX * 2) / b.w, (r.height - padT - padB) / b.h)));
    view.k = k;
    view.x = padX + (r.width - padX * 2 - b.w * k) / 2 - b.x * k;
    view.y = padT + (r.height - padT - padB - b.h * k) / 2 - b.y * k;
    if (animate) animateWorld();
    schedule();
  }
  function animateWorld() {
    els.root.classList.add('is-animating');
    clearTimeout(animateWorld.t);
    animateWorld.t = setTimeout(() => { els.root.classList.remove('is-animating'); schedule(); }, 320);
  }
  function screenToWorld(cx, cy) {
    const r = els.stage.getBoundingClientRect();
    return { x: (cx - r.left - view.x) / view.k, y: (cy - r.top - view.y) / view.k };
  }
  function focusOn(slug) {
    const n = nodes.get(slug); if (!n) return;
    const r = els.stage.getBoundingClientRect();
    const k = Math.max(view.k, 0.75);
    view.k = k; view.x = r.width / 2 - (n.x + W / 2) * k; view.y = r.height / 2 - (n.y + n.h / 2) * k;
    animateWorld(); schedule();
  }

  // ---------- Mode ----------
  function setMode(m, opts) {
    mode = m === 'canvas' ? 'canvas' : 'grid';
    localStorage.setItem(VIEW_KEY, mode);
    document.documentElement.classList.toggle('view-canvas', mode === 'canvas');
    els.root.hidden = mode !== 'canvas';
    els.switch.querySelectorAll('button').forEach(b => b.classList.toggle('is-on', b.dataset.view === mode));
    if (mode === 'canvas') {
      readTheme();
      layout();
      requestAnimationFrame(() => { fit(false); if (!(opts && opts.quiet)) els.stage.focus({ preventScroll: true }); });
    } else {
      rendered.forEach(el => el.remove()); rendered.clear();
      sel = null; connect = null; pinFor = null;
    }
  }

  // ---------- Actions ----------
  function setMark(slug, state) {
    change(() => {
      const c = cardRecMake(slug);
      c.state = c.state === state ? undefined : state;
      if (!c.state) delete c.reason;
    });
    const el = rendered.get(slug); if (el) decorate(el, nodes.get(slug));
    schedule(true);
    if (cardRec(slug) && cardRec(slug).state) requestAnimationFrame(() => { const i = els.selbar.querySelector('.lc-reason'); if (i) i.focus(); });
  }
  function addLink(a, b, kind, label) {
    if (a === b) return null;
    const dup = doc.links.find(l => l.kind === kind && ((l.a === a && l.b === b) || (l.a === b && l.b === a)));
    if (dup) return dup;
    const link = { id: uid(), a, b, kind, label: label || '', source: 'canvas' };
    change(() => doc.links.push(link));
    return link;
  }
  function addNote(kind, x, y, extra) {
    const note = Object.assign({ id: uid(), kind, text: '', x: Math.round(x), y: Math.round(y) }, extra || {});
    change(() => doc.notes.push(note));
    renderNotes();
    requestAnimationFrame(() => { const t = els.notes.querySelector(`[data-note="${note.id}"] .lc-note-text`); if (t) t.focus(); });
    return note;
  }
  function askLabel(link) {
    if (!link || (link.kind !== 'influence' && link.kind !== 'contrast')) return;
    const e = endpoints(link.a, link.b); if (!e) return;
    const m = bez(curve(e.pa, e.pb), 0.5);
    const inp = document.createElement('input');
    inp.className = 'lc-label-input';
    inp.placeholder = link.kind === 'influence' ? 'What carried over?' : 'What’s the contrast?';
    inp.maxLength = 50;
    inp.style.transform = `translate(${m.x * view.k + view.x}px,${m.y * view.k + view.y}px) translate(-50%,-50%)`;
    els.stage.appendChild(inp);
    inp.focus();
    let finished = false;
    const done = (keep) => {
      if (finished) return;
      finished = true;
      const v = inp.value.trim();
      inp.remove();
      if (keep && v) change(() => { const l = doc.links.find(x => x.id === link.id); if (l) l.label = v; });
    };
    inp.addEventListener('keydown', (ev) => { ev.stopPropagation(); if (ev.key === 'Enter') done(true); if (ev.key === 'Escape') done(false); });
    inp.addEventListener('blur', () => done(true));
  }
  function completeConnect(target, at) {
    const c = connect; connect = null;
    if (!c) return;
    let to = target;
    if (!to && (c.kind === 'part_of' || c.kind === 'question') && at) {
      to = addNote(c.kind === 'part_of' ? 'set' : 'question', at.x, at.y).id;
    }
    if (!to) { schedule(true); return; }
    const link = addLink(c.from, to, c.kind);
    askLabel(link);
    schedule(true);
  }

  // ---------- Events ----------
  function bind() {
    els.switch.addEventListener('click', (e) => {
      const b = e.target.closest('[data-view]');
      if (b) setMode(b.dataset.view);
    });
    els.zoom.addEventListener('click', (e) => {
      const b = e.target.closest('[data-z]'); if (!b) return;
      if (b.dataset.z === 'in') zoomAt(view.k * 1.3);
      else if (b.dataset.z === 'out') zoomAt(view.k / 1.3);
      else if (b.dataset.z === 'reset') zoomAt(1);
      else fit(true);
      animateWorld();
    });
    // Menus
    els.controls.addEventListener('click', (e) => {
      const opener = e.target.closest('[data-open]');
      if (opener) {
        const id = opener.dataset.open;
        els.controls.querySelectorAll('.lc-menu').forEach(m => { m.hidden = m.dataset.menuFor !== id || !m.hidden; });
        return;
      }
      const g = e.target.closest('[data-group]');
      if (g) {
        doc.groupBy = g.dataset.group; saveDoc(); renderMenus();
        els.controls.querySelectorAll('.lc-menu').forEach(m => { m.hidden = true; });
        sel = null; layout(); fit(true);
      }
    });
    els.controls.addEventListener('change', (e) => {
      const t = e.target;
      if (t.dataset.sim) { layers.sim[t.dataset.sim] = t.checked; }
      if (t.dataset.ins) { layers.ins[t.dataset.ins] = t.checked; }
      saveDoc(); renderMenus();
      const id = t.dataset.sim ? 'sim' : 'ins';
      els.controls.querySelector(`[data-menu-for="${id}"]`).hidden = false;
      schedule(true);
    });
    document.addEventListener('pointerdown', (e) => {
      if (!e.target.closest('.lc-ctl')) els.controls.querySelectorAll('.lc-menu').forEach(m => { m.hidden = true; });
      if (!e.target.closest('.lc-create')) els.create.hidden = true;
    }, true);

    // Ghosts
    els.static.addEventListener('click', (e) => {
      const acc = e.target.closest('[data-accept]');
      if (acc) {
        const cl = clusters.find(c => c.ghost && c.ghost.slug === acc.dataset.accept);
        if (cl && cl.ghost.anchor) {
          const g = cl.ghost;
          change(() => doc.links.push({ id: uid(), a: g.anchor, b: g.slug, kind: 'related', label: g.shared[0] || '', source: 'maybe' }), { layout: true });
          App.toast('Kept: it now sits next to what it relates to');
        }
        return;
      }
      const dis = e.target.closest('[data-dismiss]');
      if (dis) { change(() => doc.dismissed.push(dis.dataset.dismiss), { layout: true }); return; }
      const del = e.target.closest('[data-del-note]');
      if (del) {
        const id = del.dataset.delNote;
        change(() => { doc.notes = doc.notes.filter(n => n.id !== id); doc.links = doc.links.filter(l => l.a !== id && l.b !== id); });
        renderNotes();
      }
    });
    els.static.addEventListener('input', (e) => {
      const t = e.target.closest('.lc-note-text'); if (!t) return;
      const note = doc.notes.find(n => n.id === t.closest('[data-note]').dataset.note);
      if (note) { note.text = t.textContent; saveDoc(); measureNotes(); }
    });
    els.static.addEventListener('focusin', (e) => {
      if (e.target.closest('.lc-note-text')) undoStack.push(JSON.stringify(doc));
    });
    els.static.addEventListener('keydown', (e) => { if (e.target.closest('.lc-note-text')) { e.stopPropagation(); if (e.key === 'Escape') e.target.blur(); } });

    // Selection bar
    els.selbar.addEventListener('click', (e) => {
      const b = e.target.closest('[data-act]'); if (!b || !sel) return;
      const a = b.dataset.act;
      if (a === 'open') App.openItem(sel);
      else if (a === 'use' || a === 'rejected') setMark(sel, a);
      else if (a === 'pin') { pinFor = sel; schedule(true); }
      else { connect = { from: sel, kind: a }; schedule(true); }
    });
    els.selbar.addEventListener('keydown', (e) => {
      if (!e.target.matches('.lc-reason')) return;
      e.stopPropagation();
      if (e.key === 'Enter' || e.key === 'Escape') e.target.blur();
    });
    els.selbar.addEventListener('change', (e) => {
      if (!e.target.matches('.lc-reason') || !sel) return;
      const v = e.target.value.trim(), s = sel;
      change(() => { const c = cardRecMake(s); c.reason = v; });
      const el = rendered.get(s); if (el) decorate(el, nodes.get(s));
    });
    els.selbar.addEventListener('pointerdown', (e) => e.stopPropagation());

    els.create.addEventListener('click', (e) => {
      const b = e.target.closest('[data-create]'); if (!b) return;
      const at = els.create._at;
      els.create.hidden = true;
      addNote(b.dataset.create, at.x, at.y);
      schedule(true);
    });

    // Wheel: pinch or ⌘/Ctrl-scroll zooms at the pointer; plain scroll pans.
    els.stage.addEventListener('wheel', (e) => {
      if (e.target.closest('.lc-note-text')) return;
      e.preventDefault();
      const r = els.stage.getBoundingClientRect();
      if (e.ctrlKey || e.metaKey) zoomAt(view.k * Math.exp(-e.deltaY * 0.01), e.clientX - r.left, e.clientY - r.top);
      else { view.x -= e.deltaX; view.y -= e.deltaY; schedule(); }
    }, { passive: false });

    // Touch pinch
    const touches = new Map();
    let pinch = null;
    els.stage.addEventListener('pointerdown', (e) => { if (e.pointerType === 'touch') touches.set(e.pointerId, e); }, true);
    window.addEventListener('pointermove', (e) => {
      if (!touches.has(e.pointerId)) return;
      touches.set(e.pointerId, e);
      if (touches.size !== 2) return;
      const [a, b] = [...touches.values()];
      const d = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
      const r = els.stage.getBoundingClientRect();
      const cx = (a.clientX + b.clientX) / 2 - r.left, cy = (a.clientY + b.clientY) / 2 - r.top;
      if (!pinch) pinch = { d, k: view.k }; else zoomAt(pinch.k * d / pinch.d, cx, cy);
    });
    window.addEventListener('pointerup', (e) => { touches.delete(e.pointerId); if (touches.size < 2) pinch = null; });

    els.stage.addEventListener('pointerdown', onDown);
    els.stage.addEventListener('pointermove', (e) => {
      if (e.buttons) return;
      const c = e.target.closest('.lc-card');
      const s = c ? c.dataset.slug : null;
      if (s !== hover) { hover = s; schedule(); }
    });
    els.stage.addEventListener('pointerleave', () => { if (hover) { hover = null; schedule(); } });
    els.stage.addEventListener('dblclick', (e) => {
      const card = e.target.closest('.lc-card');
      if (card) { App.openItem(card.dataset.slug); return; }
      if (e.target.closest('.lc-note, .lc-ghost, .lc-selbar, input')) return;
      const r = els.stage.getBoundingClientRect();
      els.create._at = screenToWorld(e.clientX, e.clientY);
      els.create.hidden = false;
      els.create.style.transform = `translate(${e.clientX - r.left}px,${e.clientY - r.top}px)`;
    });

    // Keys (canvas view only; fields keep their own keys).
    window.addEventListener('keydown', (e) => {
      if (mode !== 'canvas') return;
      if (e.target && e.target.matches && e.target.matches('input, textarea, [contenteditable="true"]')) return;
      if (document.querySelector('.modal-overlay:not([hidden]), .settings-modal.open')) return;
      if (e.code === 'Space') { spaceDown = true; els.stage.classList.add('is-hand'); if (e.target === els.stage || e.target === document.body) e.preventDefault(); return; }
      let handled = true;
      if ((e.key === 'z' || e.key === 'Z') && (e.metaKey || e.ctrlKey)) undo();
      else if ((e.key === '+' || e.key === '=') && !e.metaKey && !e.ctrlKey) { zoomAt(view.k * 1.3); animateWorld(); }
      else if ((e.key === '-' || e.key === '_') && !e.metaKey && !e.ctrlKey) { zoomAt(view.k / 1.3); animateWorld(); }
      else if (e.key === '0' && !e.metaKey && !e.ctrlKey) { zoomAt(1); animateWorld(); }
      else if (e.key === '!' || (e.key === '1' && e.shiftKey)) fit(true);
      else if (e.key === 'Escape') { sel = null; selNote = null; connect = null; pinFor = null; els.create.hidden = true; renderNotes(); schedule(true); }
      else if (e.key === 'Enter' && sel) App.openItem(sel);
      else if ((e.key === 'Backspace' || e.key === 'Delete') && selNote) {
        const id = selNote; selNote = null;
        change(() => { doc.notes = doc.notes.filter(n => n.id !== id); doc.links = doc.links.filter(l => l.a !== id && l.b !== id); });
        renderNotes();
      } else handled = false;
      if (handled) { e.preventDefault(); e.stopImmediatePropagation(); }
    }, true);
    window.addEventListener('keyup', (e) => { if (e.code === 'Space') { spaceDown = false; els.stage.classList.remove('is-hand'); } });
    new ResizeObserver(() => schedule()).observe(els.stage);
    new MutationObserver(() => { readTheme(); schedule(true); }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-accent'] });

    // The grid re-rendered (search, filters, new saves): follow it.
    // Only when the set of items actually changed, not on every grid reflow.
    let sig = '';
    document.addEventListener('stello:results', () => {
      const list = App.filtered ? App.filtered() : [];
      const next = list.length + ':' + list.map(i => i.slug).join(',');
      if (next === sig) return;
      sig = next;
      if (mode === 'canvas') markLayout(); else dirtyLayout = true;
    });
  }

  function onDown(e) {
    if (e.pointerType === 'touch' && !e.isPrimary) return;
    if (e.target.closest('input, button, a, [contenteditable="true"], .lc-selbar, .lc-create')) return;
    const sx = e.clientX, sy = e.clientY;
    const card = e.target.closest('.lc-card');
    const note = e.target.closest('.lc-note');

    // Picking a spot on an image for a region note.
    if (pinFor && e.button === 0) {
      e.preventDefault();
      const n = nodes.get(pinFor);
      const w = screenToWorld(sx, sy);
      const rx = Math.max(0, Math.min(1, (w.x - n.x) / W)), ry = Math.max(0, Math.min(1, (w.y - n.y) / n.ch));
      const slug = pinFor; pinFor = null;
      addNote('region', n.x + W + 40, n.y + ry * n.ch - 20, { slug, rx, ry });
      schedule(true);
      return;
    }
    // Picking a target for a link.
    if (connect && e.button === 0) {
      e.preventDefault();
      const tgt = card ? card.dataset.slug : note ? note.dataset.note : null;
      const okNote = note && ((connect.kind === 'part_of' && note.classList.contains('is-set')) || (connect.kind === 'question' && note.classList.contains('is-question')));
      if (card && (connect.kind === 'influence' || connect.kind === 'contrast')) completeConnect(tgt);
      else if (okNote) completeConnect(tgt);
      else if (!card && !note) completeConnect(null, screenToWorld(sx, sy));
      return;
    }

    // Pan: middle button, Space held, or drag on empty canvas.
    if (e.button === 1 || spaceDown || (!card && !note && !e.target.closest('.lc-ghost'))) {
      if (e.button !== 0 && e.button !== 1) return;
      e.preventDefault();
      const vx = view.x, vy = view.y;
      let moved = false;
      els.stage.classList.add('is-panning');
      return track((ev) => {
        if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 3) return;
        moved = true;
        view.x = vx + ev.clientX - sx; view.y = vy + ev.clientY - sy; schedule();
      }, () => {
        els.stage.classList.remove('is-panning');
        if (!moved && (sel || selNote)) { sel = null; selNote = null; renderNotes(); schedule(true); }
      });
    }
    if (e.button !== 0) return;

    // Note: select and drag.
    if (note) {
      const n = doc.notes.find(x => x.id === note.dataset.note); if (!n) return;
      if (e.target.closest('.lc-note-text') && selNote === n.id) return;   // editing text
      e.preventDefault();
      sel = null; selNote = n.id;
      note.classList.add('is-selected');
      const ox = n.x, oy = n.y;
      let moved = false, snap = null;
      return track((ev) => {
        if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 4) return;
        if (!moved) { moved = true; snap = JSON.stringify(doc); }
        n.x = Math.round(ox + (ev.clientX - sx) / view.k); n.y = Math.round(oy + (ev.clientY - sy) / view.k);
        note.style.transform = `translate(${n.x}px,${n.y}px)`;
        schedule();
      }, () => {
        if (moved) { undoStack.push(snap); saveDoc(); }
        renderNotes(); schedule(true);
        if (!moved) { const t = els.notes.querySelector(`[data-note="${n.id}"] .lc-note-text`); if (t) t.focus(); }
      });
    }

    // Card: select; drag moves it (remembered for this grouping).
    if (card) {
      e.preventDefault();
      const s = card.dataset.slug;
      const n = nodes.get(s);
      selNote = null;
      const ox = n.x, oy = n.y;
      let moved = false, snap = null;
      return track((ev) => {
        if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 4) return;
        if (!moved) { moved = true; snap = JSON.stringify(doc); els.root.classList.add('is-moving'); sel = s; }
        n.x = Math.round(ox + (ev.clientX - sx) / view.k); n.y = Math.round(oy + (ev.clientY - sy) / view.k);
        schedule();
      }, () => {
        els.root.classList.remove('is-moving');
        if (moved) {
          undoStack.push(snap);
          const c = cardRecMake(s); c.x = n.x; c.y = n.y; c.by = doc.groupBy;
          saveDoc(); rebuildHash();
        } else sel = sel === s ? null : s;
        renderNotes();
        schedule(true);
      });
    }
  }
  function track(move, up) {
    const m = (ev) => move(ev);
    const u = (ev) => { window.removeEventListener('pointermove', m); window.removeEventListener('pointerup', u); up && up(ev); };
    window.addEventListener('pointermove', m);
    window.addEventListener('pointerup', u);
  }

  // ---------- Boot ----------
  function init() {
    App = window.StelloApp;
    if (!App) return;
    loadDoc();
    build();
    bind();
    const q = new URLSearchParams(location.search).get('view');
    const start = q || localStorage.getItem(VIEW_KEY) || 'grid';
    setMode(start, { quiet: true });
    window.StelloCanvas = { setMode, focusOn, centerOn: (sx, sy, k) => { const w = screenToWorld(sx, sy); const r = els.stage.getBoundingClientRect(); view.k = k; view.x = r.width / 2 - w.x * k; view.y = r.height / 2 - w.y * k; schedule(); }, fit: () => fit(true), get view() { return view; }, zoomAt, select: (s) => { sel = s; schedule(true); } };
  }
  if (window.StelloApp) init();
  else document.addEventListener('stello:ready', init, { once: true });
})();
