/* Stello canvas: the library as nodes on a zoomable canvas.
   ----------------------------------------------------------------------------
   The same items the grid shows (after search and filters), placed in broad
   groups you can switch (topic, kind, colour, style, place,
   source, month). Lines say why two items belong together:

   Layer 1 (computed, rules only): same colour, looks alike, same idea,
   same kind, same place, same style.
   Layer 2 (yours, plus a few computed hints): use / rejected marks,
   influence (A inspired B), contrast (vs), part of a set, questions,
   notes on part of an image; gaps (maybe-related saves and empty spots),
   and revisit glow / fade.

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

  // Several canvases: `library` (the first one, kept under its old keys) and
  // named ones, each a project on the server (/api/projects/:id).
  const CUR_KEY = 'stello.canvas.current';
  let curId = localStorage.getItem(CUR_KEY) || 'library';
  const docKey = () => curId === 'library' ? 'stello.canvas.v1' : 'stello.canvas.doc.' + curId;
  const revKey = () => curId === 'library' ? 'stello.canvas.rev' : 'stello.canvas.rev.' + curId;
  const apiPath = () => '/api/projects/' + encodeURIComponent(curId);
  const isLocalId = () => curId.startsWith('local-');
  const VIEW_KEY = 'stello.view';           // 'grid' | 'canvas'
  const W = 274;                            // card width (world px)
  const COL_GAP = 28, ROW_GAP = 28, CL_GAP_X = 200, CL_GAP_Y = 220;
  const TITLE_H = 120;                      // room above a group for its title
  const CELL = 800;                         // spatial hash cell
  const MIN_K = 0.01, MAX_K = 2.5;
  const LOD_BLOCKS = 0.16;                  // below: colour blocks on the canvas, no DOM cards
  const LOD_DETAIL = 0.62;                  // at or above: full details card
  const LABEL_K = 0.42;                     // link labels from this zoom
  const MAX_LINKS = 420, MAX_LABELS = 90;
  const DOM_CAP = 240;                      // more cards than this in view: paint them on the canvas
  // Families: similar items inside a group sit close together on a tint.
  const FAM_MAX = 12, FAM_GAP_X = 76, FAM_GAP_Y = 64, FAM_CAP = 40, F_COL = 16, F_ROW = 16, FAM_PAD = 18;
  const NEAR = 720;                         // drag reveal radius (world px)
  const STRAIGHT = 230;                     // closer than this: one straight segment

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
    glow: 'Revisits: glow and fade',
  };
  const GROUPS = {
    topic: 'Topic', kind: 'Kind', colour: 'Colour', style: 'Style',
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
  let inv = new Map();            // feature -> [slug]
  let featOf = new Map();         // slug -> [{ f, type, tag }]
  let simCache = new Map();       // slug -> [{ b, type, label, s }]
  const rendered = new Map();     // slug -> element
  let sel = null;                 // selected slug
  let lastPointer = 'mouse';      // pointer type of the last press on the canvas
  let reasonFor = null;           // marked card whose "Why?" field is open
  let selNote = null;             // selected note id
  let hover = null;
  let hoverGhost = null;
  let hoverDrop = null;
  let overCanvas = false;           // card a grid drag would group with
  let dragging = null;            // slug being dragged
  let suggest = null;             // { slugs, box, name, fam } while dragging close to another item
  let near = [];                  // [{ b, s, label, type, d }] while dragging
  let families = [];              // [{ cl, tag, type, color, slugs, loose, box }]
  let linkCount = new Map();
  const openDet = new Set();      // cards with their details card open
  let boxLod = 2;                 // zoom level the family boxes were measured at      // slug -> number of your links
  let connect = null;             // { from, kind } while picking a target
  let pinFor = null;              // slug while placing a note on its image
  let layers = {
    sim: { on: true, always: false, place: true, colour: true, looks: true, kind: true, idea: true, style: true },
    ins: { marks: true, notes: true, gaps: true, glow: true },
  };
  let raf = 0, layoutRaf = 0, dirtyLayout = true;
  const touchPts = new Map();     // pointerId -> { x, y } for fingers on the canvas
  let pinch = null;               // { d, k, wx, wy } at pinch start
  let active = null;              // { id, cancel } the single-pointer action in progress
  let inertia = 0;                // rAF id of a touch pan's glide
  let camSet = false;             // the camera has been placed once this session
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
  // v2: the canvas starts empty and holds only what you drag in. Older docs
  // (v1, auto-filled with the whole library) are cleared once: their cards,
  // groups and free notes go; links stay but show only between dropped items.
  const DOC_V = 2;
  function blankDoc() { return { v: DOC_V, name: 'Library canvas', groupBy: 'kind', cards: [], links: [], groups: [], notes: [], dismissed: [], layers: null }; }
  function upgrade(d) {
    if (d.v === DOC_V) return false;
    if (curId !== 'library') { d.v = DOC_V; return false; }   // named canvases were never auto-filled
    d.v = DOC_V; d.cards = []; d.groups = []; d.notes = [];
    return true;
  }
  let upgraded = false;
  function loadDoc() {
    try { doc = JSON.parse(localStorage.getItem(docKey())); } catch { doc = null; }
    if (!doc || typeof doc !== 'object') doc = blankDoc();
    const b = blankDoc();
    if (doc.v == null) doc.v = 1;
    Object.keys(b).forEach(k => { if (doc[k] == null) doc[k] = b[k]; });
    if (upgrade(doc)) { upgraded = true; localStorage.setItem(docKey(), JSON.stringify(doc)); }
    if (doc.layers) {
      layers.sim = Object.assign(layers.sim, doc.layers.sim || {});
      layers.ins = Object.assign(layers.ins, doc.layers.ins || {});
    }
  }
  function saveDoc() { doc.layers = layers; localStorage.setItem(docKey(), JSON.stringify(doc)); queuePush(); }

  // ---------- Sync with D1 (/api/projects/library) ----------
  // The server keeps marks, links, notes and the grouping; this device keeps
  // its own hand-placed positions (`by`) and layer toggles. Positions from
  // other clients (FigJam, MCP) use other coordinates, so they never move
  // cards here. A stale rev gets 409 and we adopt the server copy.
  let rev = +(localStorage.getItem(revKey()) || 0), pushTimer = 0, pushing = false, dirty = false;
  const canSync = () => !isLocalId() && !!(window.Stello && Stello.apiFetch && Stello.getUserId && Stello.getUserId());
  function toServer(d) {
    return {
      v: DOC_V, name: d.name, groupBy: d.groupBy,
      cards: d.cards.map(c => {
        const o = { slug: c.slug, x: Math.round(c.x || 0), y: Math.round(c.y || 0) };
        if (c.state) o.state = c.state;
        if (c.reason) o.note = c.reason;
        return o;
      }),
      links: d.links.map(l => ({ id: l.id, a: l.a, b: l.b, kind: l.kind === 'related' ? 'maybe' : l.kind, label: l.label || undefined, source: 'web' })),
      groups: d.groups, notes: d.notes, dismissed: d.dismissed,
    };
  }
  function fromServer(sd) {
    const local = new Map(doc.cards.map(c => [c.slug, c]));
    const next = blankDoc();
    next.name = sd.name || next.name;
    next.groupBy = Object.prototype.hasOwnProperty.call(GROUPS, sd.groupBy) ? sd.groupBy : doc.groupBy;
    next.cards = (sd.cards || []).map(c => {
      const o = { slug: c.slug };
      const l = local.get(c.slug);
      if (l && l.by && Math.round(l.x) === Math.round(c.x) && Math.round(l.y) === Math.round(c.y)) { o.x = l.x; o.y = l.y; o.by = l.by; }
      else if (Number.isFinite(c.x) && Number.isFinite(c.y) && (c.x || c.y)) { o.x = c.x; o.y = c.y; o.by = next.groupBy; }
      if (c.state) o.state = c.state;
      if (c.note) o.reason = c.note;
      return o;
    });
    next.links = (sd.links || []).map(l => ({ ...l, kind: l.kind === 'maybe' ? 'related' : l.kind }));
    next.groups = sd.groups || []; next.notes = sd.notes || []; next.dismissed = sd.dismissed || [];
    next.layers = doc.layers;
    if (sd.v !== DOC_V) { next.v = 1; upgrade(next); upgraded = true; }
    return next;
  }
  function adopt(project) {
    rev = project.rev || 0; localStorage.setItem(revKey(), String(rev));
    doc = fromServer(project.doc || {});
    localStorage.setItem(docKey(), JSON.stringify(doc));
  }
  async function pullDoc() {
    if (!canSync()) return;
    try {
      const body = await Stello.apiGet(apiPath());
      const p = body && body.project;
      if (!p) return;
      if (p.rev > rev && !dirty) { adopt(p); markLayout(); afterLoad(); }
      else if (p.rev === rev && p.doc && p.doc.v !== DOC_V) { adopt(p); markLayout(); afterLoad(); }
      else if (p.rev < rev || (p.rev === 0 && (doc.cards.length || doc.links.length || doc.notes.length))) { rev = p.rev; queuePush(); }
    } catch { /* offline: keep the local copy */ }
  }
  // A doc cleared by the v2 upgrade is written back once, so every device agrees.
  function afterLoad() {
    if (upgraded) { upgraded = false; queuePush(); }
    renderDocName(); rememberCanvas(curId, doc.name);
    if (mode !== 'grid') { markGrid(); emptyState(); }
  }
  function queuePush() {
    if (!canSync()) return;
    dirty = true;
    clearTimeout(pushTimer);
    pushTimer = setTimeout(pushDoc, 1200);
  }
  async function pushDoc() {
    if (pushing) { queuePush(); return; }
    pushing = true; dirty = false;
    try {
      const res = await Stello.apiFetch(apiPath(), {
        method: 'PUT', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rev, doc: toServer(doc) }),
      });
      const body = await res.json().catch(() => null);
      if (res.ok && body && body.project) { rev = body.project.rev; localStorage.setItem(revKey(), String(rev)); }
      else if (res.status === 409 && body && body.project) {
        adopt(body.project); markLayout(); afterLoad();
        App.toast('Canvas changed on another device; showing the latest copy');
      }
    } catch { dirty = true; /* offline: retry on the next change */ }
    pushing = false;
  }
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
    const place = placeOf(it);
    const why = tagsOf(it, 'intent').slice(0, 3).map(t => cap(t.tag).toLowerCase()).join(', ');
    if (style) rows.push(['Style', style]);
    if (tags) rows.push(['Tags', tags]);
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
      if (!layers.sim[x.type]) return;
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
    (featOf.get(a.slug) || featuresLoose(a)).forEach(x => { if (layers.sim[x.type] && fb.has(x.f)) { s += SIM[x.type].w; shared.push(x.tag); } });
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
    // The canvas holds only what you dragged onto it (not the grid's filters).
    const ids = new Set(doc.cards.filter(c => App.item(c.slug)).map(c => c.slug));
    set = [...ids].map(s => App.item(s)).filter(Boolean);
    setIndex = new Map(set.map(i => [i.slug, i]));
  }
  function layout() {
    dirtyLayout = false;
    if (els.empty) emptyState();
    computeSet();
    buildIndex();
    nodes = new Map();
    const by = doc.groupBy in GROUPS ? doc.groupBy : 'kind';
    const topics = by === 'topic' ? topicMap(set) : null;
    const groups = new Map();
    // Your groups stay together: every member goes where the first one goes.
    const pinned = new Map();
    (doc.groups || []).forEach(g => {
      const first = (g.slugs || []).map(x => setIndex.get(x)).find(Boolean);
      if (!first) return;
      const k = groupKey(first, by, topics);
      g.slugs.forEach(x => { if (setIndex.has(x) && !pinned.has(x)) pinned.set(x, k); });
    });
    set.forEach(it => { const k = pinned.get(it.slug) || groupKey(it, by, topics); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(it); });
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

    // Per group: families of similar items, each a tight block on a tint,
    // packed with air between them. Closeness carries the relationship, so
    // no lines are needed until you ask for them.
    families = [];
    clusters = entries.map(([key, items], i) => {
      items.sort((a, b) => String(b.added_at).localeCompare(String(a.added_at)));
      const fams = familiesOf(items);
      const blocks = fams.map(f => {
        const m = f.items.length;
        const cols = f.loose ? Math.max(1, Math.min(8, Math.ceil(Math.sqrt(m * 0.8)))) : Math.max(1, Math.min(4, Math.ceil(Math.sqrt(m * 0.8))));
        const cg = f.loose ? COL_GAP : F_COL, rg = f.loose ? ROW_GAP : F_ROW;
        const colY = new Array(cols).fill(0).map((_, c) => f.loose ? Math.round(hashOf(f.items[0].slug + c) * 40) : 0);
        const pos = [];
        f.items.forEach(it => {
          const c = colY.indexOf(Math.min(...colY));
          const ch = Math.round(W * coverRatio(it));
          pos.push({ it, d: details(it), ch, x: c * (W + cg), y: colY[c] });
          colY[c] += ch + rg;
        });
        return { f, pos, w: cols * W + (cols - 1) * cg, h: Math.max(...colY) - rg + (f.loose && fams.length === 1 ? 0 : FAM_CAP) };
      });
      // Skyline-pack the families inside the group: each drops to the lowest
      // spot it fits, which leaves the uneven, maze-like gaps between them.
      const area = blocks.reduce((t, b) => t + (b.w + FAM_GAP_X) * (b.h + FAM_GAP_Y), 0);
      const maxW = Math.max(Math.max(...blocks.map(b => b.w)), Math.sqrt(area) * 1.35);
      const at = skyline(blocks, maxW, FAM_GAP_X, FAM_GAP_Y);
      let gw = 0, gh = 0;
      const slugs = [];
      blocks.forEach((b, bi) => {
        const fx = at[bi].x, top = at[bi].y + (b.f.loose && fams.length === 1 ? 0 : FAM_CAP);
        const fam = { cl: i, tag: b.f.tag, type: b.f.type, loose: b.f.loose, gid: b.f.gid || null, slugs: [], box: null };
        fam.color = b.f.type === 'user' ? 'accent' : b.f.type ? (SIM[b.f.type].color || null) : null;
        families.push(fam);
        b.pos.forEach(p => {
          const jitter = b.f.loose ? Math.round((hashOf(p.it.slug) - 0.5) * 18) : 0;
          nodes.set(p.it.slug, { slug: p.it.slug, item: p.it, d: p.d, x: fx + p.x + jitter, y: top + p.y, ch: p.ch, h: p.ch, cl: i, fam: families.length - 1 });
          fam.slugs.push(p.it.slug); slugs.push(p.it.slug);
        });
        gw = Math.max(gw, fx + b.w); gh = Math.max(gh, at[bi].y + b.h);
      });
      return { key, name: cap(key), sub: subtitleFor(items), color: PALETTE[i % PALETTE.length], x: 0, y: 0, w: gw, h: gh, slugs, items };
    });

    // Gaps per group (computed hints).
    clusters.forEach(cl => { cl.empty = null; cl.ghost = null; });

    // Shelf-pack the groups into rows.
    const footW = (cl) => cl.w + (cl.ghost ? 60 + W : 0);
    const footH = (cl) => TITLE_H + cl.h + (cl.empty ? 140 : 0);
    const area = clusters.reduce((s, cl) => s + (footW(cl) + CL_GAP_X) * (footH(cl) + CL_GAP_Y), 0);
    const maxW = Math.max(2400, Math.max(...clusters.map(footW)), Math.sqrt(area) * 1.4);
    const gat = skyline(clusters.map(cl => ({ w: footW(cl), h: footH(cl) })), maxW, CL_GAP_X, CL_GAP_Y);
    clusters.forEach((cl, ci) => { cl.x = gat[ci].x; cl.y = gat[ci].y + TITLE_H; });
    // Place cards, honouring cards you moved (for this grouping).
    clusters.forEach(cl => cl.slugs.forEach(s => { const n = nodes.get(s); n.x += cl.x; n.y += cl.y; }));
    families.forEach(famBox);
    // Cards stay where you put them. The auto arrangement above is only for
    // cards without a spot yet (after a Group by change); once laid out they
    // keep that spot, so a new drop never reshuffles the others.
    let placedAny = false, wrote = false;
    const unplaced = [];
    doc.cards.forEach(c => {
      const n = nodes.get(c.slug); if (!n) return;
      if (c.by === by && Number.isFinite(c.x)) { n.x = c.x; n.y = c.y; placedAny = true; }
      else unplaced.push([c, n]);
    });
    if (placedAny && unplaced.length) {
      // New arrivals from elsewhere (another device, the MCP): a column to the
      // right of what is already placed, never on top of it.
      const unp = new Set(unplaced.map(([c]) => c.slug));
      let mx = -Infinity, my = Infinity;
      doc.cards.forEach(c => { const n = nodes.get(c.slug); if (n && !unp.has(c.slug)) { mx = Math.max(mx, n.x + W); my = Math.min(my, n.y); } });
      unplaced.forEach(([, n]) => { n.x = -1e7; n.y = -1e7; });
      rebuildHash();
      unplaced.forEach(([, n]) => { const p = freeSpot(mx + 160, my, n.h); n.x = p.x; n.y = p.y; rebuildHash(); });
    }
    unplaced.forEach(([c, n]) => { c.x = n.x; c.y = n.y; c.by = by; wrote = true; });
    if (placedAny) settleSpatial();
    if (wrote) { localStorage.setItem(docKey(), JSON.stringify(doc)); queuePush(); }

    // Bounds.
    let x0 = 0, y0 = -TITLE_H, x1 = 0, y1 = 0;
    nodes.forEach(n => { x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y - TITLE_H); x1 = Math.max(x1, n.x + W); y1 = Math.max(y1, n.y + n.h); });
    clusters.forEach(cl => { x1 = Math.max(x1, cl.x + footW(cl)); y1 = Math.max(y1, cl.y + cl.h + (cl.empty ? 140 : 0)); });
    worldBox = { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    rebuildHash();
    // Keep cards that are still here so they can glide to their new spots.
    rendered.forEach((el, slug) => { if (!nodes.has(slug)) { el.remove(); rendered.delete(slug); } });
    renderStatic();
  }
  // With cards where you put them, closeness decides what reads as a group:
  // a similarity family keeps only its members that sit together, and each
  // broad group gets one caption per spot where its cards actually are.
  function settleSpatial() {
    rebuildHash();
    const comps = (slugs, gap) => {
      const left = new Set(slugs), out = [];
      while (left.size) {
        const first = left.values().next().value; left.delete(first);
        const comp = [first], q = [first];
        while (q.length) {
          const n = nodes.get(q.pop());
          inRect(n.x - gap, n.y - gap, n.x + W + gap, n.y + n.h + gap).forEach(b => { if (left.has(b)) { left.delete(b); comp.push(b); q.push(b); } });
        }
        out.push(comp);
      }
      return out.sort((a, b) => b.length - a.length);
    };
    families.forEach((f, fi) => {
      if (f.loose || f.type === 'user' || f.slugs.length < 2) return;
      const cs = comps(f.slugs, 90);
      const keep = cs[0].length >= 2 ? new Set(cs[0]) : new Set();
      f.slugs.forEach(sl => { if (!keep.has(sl)) nodes.get(sl).fam = -1; });
      f.slugs = [...keep];
    });
    families.forEach(famBox);
    const next = [];
    clusters.forEach(cl => {
      comps(cl.slugs, 240).forEach((sl, ci) => {
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        sl.forEach(x => { const n = nodes.get(x); x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y); x1 = Math.max(x1, n.x + W); y1 = Math.max(y1, n.y + n.h); });
        const items = sl.map(x => nodes.get(x).item);
        const c = { ...cl, x: x0, y: y0, w: x1 - x0, h: y1 - y0, slugs: sl, items, sub: subtitleFor(items) };
        if (ci > 0) { c.empty = null; c.ghost = null; }
        else { c.empty = null; c.ghost = null; }
        next.push(c);
      });
    });
    clusters = next;
    clusters.forEach((cl, i) => cl.slugs.forEach(x => { nodes.get(x).cl = i; }));
    families.forEach(f => { if (f.slugs.length) f.cl = nodes.get(f.slugs[0]).cl; });
  }
  // Greedy cover: the most telling shared feature first (rarer in the library,
  // stronger type, more members), up to FAM_MAX items per family. What is left
  // over is the loose family.
  // Bottom-left skyline packing: blocks in order, each at the lowest y it fits.
  function skyline(blocks, maxW, gx, gy) {
    let sky = [{ x: 0, w: Infinity, y: 0 }];
    return blocks.map(b => {
      let best = null;
      for (let i = 0; i < sky.length; i++) {
        const x = sky[i].x;
        if (x > 0 && x + b.w > maxW) break;
        let y = 0;
        for (let j = i; j < sky.length && sky[j].x < x + b.w; j++) y = Math.max(y, sky[j].y);
        if (!best || y < best.y - 1) best = { x, y };
      }
      if (!best) best = { x: 0, y: Math.max(...sky.map(sg => sg.y)) };
      // Raise the skyline over [x, x + w + gap).
      const x0 = best.x, x1 = best.x + b.w + gx, top = best.y + b.h + gy;
      const next = [];
      sky.forEach(sg => {
        const a = sg.x, z = sg.x + sg.w;
        if (z <= x0 || a >= x1) { next.push(sg); return; }
        if (a < x0) next.push({ x: a, w: x0 - a, y: sg.y });
        if (z > x1) next.push({ x: x1, w: z - x1, y: sg.y });
      });
      next.push({ x: x0, w: x1 - x0, y: top });
      next.sort((p, q) => p.x - q.x);
      sky = next.reduce((acc, sg) => { const l = acc[acc.length - 1]; if (l && l.y === sg.y && l.x + l.w === sg.x) l.w += sg.w; else acc.push({ ...sg }); return acc; }, []);
      return best;
    });
  }
  function familiesOf(items) {
    const N = set.length;
    const by = new Map();
    items.forEach(it => (featOf.get(it.slug) || []).forEach(x => {
      if (!layers.sim.on || !layers.sim[x.type]) return;
      let e = by.get(x.f); if (!e) by.set(x.f, e = { x, slugs: [] }); e.slugs.push(it.slug);
    }));
    const cands = [...by.values()].filter(e => e.slugs.length >= 2 && e.slugs.length < Math.max(3, items.length * 0.9))
      .map(e => ({ ...e, score: SIM[e.x.type].w * Math.log(1 + N / (inv.get(e.x.f) || e.slugs).length) * Math.log2(1 + Math.min(e.slugs.length, FAM_MAX)) }))
      .sort((a, b) => b.score - a.score);
    const taken = new Set(), out = [];
    const bySlug = new Map(items.map(it => [it.slug, it]));
    // Groups you made come first.
    (doc.groups || []).forEach(g => {
      const part = (g.slugs || []).filter(s => bySlug.has(s) && !taken.has(s));
      if (part.length < 2) return;
      part.forEach(s => taken.add(s));
      out.push({ tag: g.name || 'Group', type: 'user', gid: g.id, items: part.map(s => bySlug.get(s)) });
    });
    for (const c of cands) {
      let free = c.slugs.filter(s => !taken.has(s));
      while (free.length >= 2) {
        const part = free.slice(0, FAM_MAX);
        if (part.length < 2) break;
        part.forEach(s => taken.add(s));
        out.push({ tag: c.x.tag, type: c.x.type, items: part.map(s => bySlug.get(s)) });
        free = free.slice(FAM_MAX);
      }
    }
    out.sort((a, b) => (b.type === 'user') - (a.type === 'user') || b.items.length - a.items.length);
    const rest = items.filter(it => !taken.has(it.slug));
    if (rest.length) out.push({ tag: null, type: null, loose: true, items: rest });
    return out;
  }
  // How tall a card looks at the current zoom (details shrink at mid zoom).
  function visH(n) { return n.h; }
  function famBox(f) {
    if (!f || !f.slugs.length) { if (f) f.box = null; return; }
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    f.slugs.forEach(s => { if (s === dragging && f.slugs.length > 1) return; const n = nodes.get(s); x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y); x1 = Math.max(x1, n.x + W); y1 = Math.max(y1, n.y + visH(n)); });
    f.box = { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  }
  // After a move: leave the family if dropped clear of it, join one if dropped on it.
  function refamily(n) {
    const cx = n.x + W / 2, cy = n.y + n.ch / 2;
    const inside = (f, pad) => f.box && cx > f.box.x - pad && cx < f.box.x + f.box.w + pad && cy > f.box.y - pad && cy < f.box.y + f.box.h + pad;
    const cur = families[n.fam];
    if (cur) {
      cur.slugs = cur.slugs.filter(s => s !== n.slug); famBox(cur);
      if (inside(cur, 60) || (cur.loose && !families.some(f => f !== cur && !f.loose && inside(f, 0)))) { cur.slugs.push(n.slug); famBox(cur); return; }
    }
    const to = families.findIndex(f => f !== cur && !f.loose && inside(f, 0));
    n.fam = to >= 0 ? to : -1;
    if (to >= 0) { families[to].slugs.push(n.slug); famBox(families[to]); }
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

  // ---------- Build DOM ----------
  const IC = {
    caret: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 9l6 6 6-6"/></svg>',
    open: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>',
    x: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    split: '<svg viewBox="0 0 256 256" width="18" height="18" fill="none" stroke="currentColor" stroke-width="16" stroke-linejoin="round"><rect x="32" y="48" width="192" height="160" rx="16"/><path d="M128 48v160"/></svg>',
    info: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M5 7h14M5 12h14M5 17h9"/></svg>',
    link: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h7v10h9"/></svg>',
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
        <div class="lc-fams"></div>
        <div class="lc-labels" aria-hidden="true"></div>
        <div class="lc-selbar" hidden></div>
        <div class="lc-hint" hidden></div>
        <div class="lc-empty-state" hidden>
          <div class="lc-empty-icon">${App.icon('graph')}</div>
          <p class="lc-empty-title">Your canvas is empty</p>
          <p class="lc-empty-sub">Drag items here from the grid (on touch, press and hold a card first). Drop one next to another to group them.</p>
          <button type="button" data-split>Open split view</button>
        </div>
      </div>
      <div class="lc-controls">
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
    els.fams = root.querySelector('.lc-fams');
    els.selbar = root.querySelector('.lc-selbar');
    els.hint = root.querySelector('.lc-hint');
    els.controls = root.querySelector('.lc-controls');
    els.create = root.querySelector('.lc-create');
    els.empty = root.querySelector('.lc-empty-state');
    els.empty.querySelector('[data-split]').addEventListener('click', () => setMode('split'));
    els.ctx = els.ink.getContext('2d');

    // Grid / canvas switch, right of the account button (bar order: account,
    // views, canvas name, search, filter, add; zoom at the far right).
    const acct = document.getElementById('settings-btn') || document.querySelector('.bar-search');
    const sw = document.createElement('div');
    sw.className = 'view-switch';
    sw.setAttribute('role', 'group');
    sw.setAttribute('aria-label', 'View');
    sw.innerHTML = `<button type="button" data-view="grid" aria-label="Grid view" title="Grid">${App.icon('squares-four')}</button><button type="button" data-view="split" aria-label="Split view: grid and canvas" title="Split">${IC.split}</button><button type="button" data-view="canvas" aria-label="Canvas view" title="Canvas">${App.icon('graph')}</button>`;
    acct.after(sw);
    els.switch = sw;
    // Zoom, shown in canvas view only.
    const zm = document.createElement('div');
    zm.className = 'lc-zoom';
    zm.innerHTML = `<button type="button" data-z="out" aria-label="Zoom out">−</button><button type="button" data-z="reset" class="lc-zoom-pct" aria-label="Zoom to 100%">100%</button><button type="button" data-z="in" aria-label="Zoom in">+</button><button type="button" data-z="fit" aria-label="Fit everything">Fit</button>`;
    sw.parentElement.appendChild(zm);
    els.zoom = zm;
    // This canvas: its name (click to rename) and a chevron for canvases and export.
    const dp = document.createElement('div');
    dp.className = 'lc-doc';
    dp.innerHTML = `<button type="button" class="lc-doc-name" data-doc="rename" title="Rename this canvas"></button><input class="lc-doc-input" type="text" maxlength="80" aria-label="Canvas name" hidden><button type="button" class="lc-doc-more" data-doc="menu" aria-label="Canvases and export" aria-haspopup="menu">${IC.caret}</button><div class="lc-doc-menu" role="menu" hidden></div>`;
    els.docpill = dp;
    // Export: its own button beside the name.
    const ex = document.createElement('div');
    ex.className = 'lc-exp';
    ex.innerHTML = `<button type="button" class="lc-exp-btn" data-doc="export" aria-label="Export this canvas" title="Export" aria-haspopup="menu">${App.icon('share')}</button><div class="lc-doc-menu lc-exp-menu" role="menu" hidden></div>`;
    els.exp = ex;
    const box = document.createElement('div');
    box.className = 'lc-docbox';
    box.append(dp, ex);
    els.docbox = box;
    renderDocName();
    renderMenus();
  }

  function renderMenus() {
    const sw = Object.entries(SIM).filter(([k]) => layers.sim.on && layers.sim[k]).map(([, d]) => `<i style="background:${d.color || 'var(--text)'}"></i>`).join('');
    els.controls.querySelector('[data-swatches]').innerHTML = sw;
    els.controls.querySelector('[data-menu-for="sim"]').innerHTML =
      `<label class="lc-mi lc-mi-head"><input type="checkbox" data-sim="on"${layers.sim.on ? ' checked' : ''}> <span>Sort by similarity</span></label>` +
      Object.entries(SIM).map(([k, d]) => `<label class="lc-mi"><input type="checkbox" data-sim="${k}"${layers.sim[k] ? ' checked' : ''}${layers.sim.on ? '' : ' disabled'}>
        <span class="lc-key${d.dash ? ' is-dash' : ''}" style="--c:${d.color || 'var(--text)'}"></span><span><b>${d.label}</b> <em>${d.hint}</em></span></label>`).join('') +
      `<label class="lc-mi lc-mi-head"><input type="checkbox" data-sim="always"${layers.sim.always ? ' checked' : ''}${layers.sim.on ? '' : ' disabled'}> <span>Always show lines</span></label>` +
      `<p class="lc-menu-note">Similar items sit together on a tint, named by what they share. Hover, select or drag an item to see its lines.</p>`;
    els.controls.querySelector('[data-menu-for="ins"]').innerHTML =
      Object.entries(INSIGHTS).map(([k, v]) => `<label class="lc-mi"><input type="checkbox" data-ins="${k}"${layers.ins[k] ? ' checked' : ''}><span>${v}</span></label>`).join('') +
      `<div class="lc-legend">${Object.entries(L2).filter(([k]) => k !== 'related').map(([, d]) => `<span><span class="lc-key${d.dash ? ' is-dash' : ''}" style="--c:${d.color}"></span>${d.label} <em>${d.hint}</em></span>`).join('')}</div>
       <p class="lc-menu-note">Double-click empty canvas to add a question, note or set. Select an item to mark it or connect it.</p>`;
  }

  // ---------- Static world layer: group titles, empty spots, ghosts, notes ----------
  // Groups have no captions in the world any more: their names are pills in
  // screen space (renderFams), so they stay one size at every zoom.
  function renderStatic() {
    els.static.innerHTML = '<div class="lc-notes"></div>';
    els.notes = els.static.querySelector('.lc-notes');
    renderNotes();
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
  // A card is its cover. A click on it (or its info button) opens the card in
  // place: the details grow out of the same card, over what is below (no reflow).
  function cardEl(n) {
    const it = n.item;
    const el = document.createElement('div');
    el.className = 'lc-card';
    el.dataset.slug = n.slug;
    const dom = (it.domain || '').replace(/^www\./, '');
    const noImg = !it.has_image;
    el.innerHTML = `
      <div class="lc-cover" style="height:${n.ch}px">${App.thumbHTML(it)}${noImg ? `<span class="lc-name">${esc(it.title || dom)}</span>` : ''}
        <span class="lc-pills">${dom ? `<span class="lc-dom">${esc(dom)}</span>` : ''}<button type="button" class="lc-info" data-info aria-label="Details" title="Details">${IC.info}</button></span></div>`;
    el.style.transform = `translate(${n.x}px,${n.y}px)`; el._x = n.x; el._y = n.y;
    if (openDet.has(n.slug)) toggleDet(el, n, true);
    decorate(el, n);
    return el;
  }
  function detHTML(n) {
    const d = n.d;
    const sw = d.cols.map(c => `<span class="lc-sw"><i style="background:${App.colorHex ? App.colorHex(c) : App.dominantColor(n.item)}"></i>${esc(c)}</span>`).join('');
    const rows = d.rows.map(([k, v]) => `<div class="lc-row"><dt>${k}</dt><dd>${esc(v)}</dd></div>`).join('');
    return `<div class="lc-title">${esc(d.title)}</div><div class="lc-meta">${esc(d.meta)}</div>
      ${sw ? `<div class="lc-sws">${sw}</div>` : ''}<dl class="lc-rows">${rows}</dl>
      ${d.note ? `<div class="lc-quote">“${esc(d.note)}”</div>` : ''}`;
  }
  function toggleDet(el, n, on) {
    let det = el.querySelector('.lc-det');
    if (on == null) on = !det;
    if (on && !det) { det = document.createElement('div'); det.className = 'lc-det'; det.innerHTML = detHTML(n); el.appendChild(det); }
    if (!on && det) det.remove();
    el.classList.toggle('has-det', on);
    if (on) openDet.add(n.slug); else openDet.delete(n.slug);
  }
  // Opened by a click: if the card is too small on screen to read its details
  // (zoomed out, or on a phone), fly in until it is, keeping it in view.
  function openReadable(el, n) {
    toggleDet(el, n, true);
    const r = stageRect();
    if (W * view.k >= 230) return;
    const k = Math.min(1, Math.max(view.k, (Math.min(r.width, 420) - 48) / W));
    requestAnimationFrame(() => {
      const h = el.offsetHeight || n.h;
      const top = Math.max(24, Math.min(r.height * 0.18, r.height - 120 - h * k));
      flyTo({ k, x: r.width / 2 - (n.x + W / 2) * k, y: top - n.y * k });
    });
  }
  // A click on empty canvas folds every open card back to its cover.
  function closeAllDet() {
    [...openDet].forEach(s => { const el = rendered.get(s); if (el) toggleDet(el, nodes.get(s), false); });
    openDet.clear();
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
    el.querySelectorAll('.lc-links').forEach(x => x.remove());
    const lc = linkCount.get(n.slug);
    if (lc) el.querySelector('.lc-cover').insertAdjacentHTML('beforeend', `<span class="lc-links" data-ins-part="marks" title="Your links: hover to see them">${IC.link}${lc}</span>`);
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
    layoutRaf = requestAnimationFrame(() => { layoutRaf = 0; if (mode !== 'grid') { layout(); schedule(true); } });
  }
  function lodFor(k) { return k < LOD_BLOCKS ? 0 : k < LOD_DETAIL ? 1 : 2; }
  function render() {
    if (mode === 'grid') return;
    const t0 = window.__lcPerf ? performance.now() : 0;
    if (dirtyLayout) layout();
    const r = stageRect();
    const k = view.k, lod = lodFor(k);
    els.world.style.transform = `translate3d(${view.x}px,${view.y}px,0) scale(${k})`;
    // Text, labels and controls on the canvas stay one size at every zoom:
    // they are counter-scaled by 1/k (CSS `scale: var(--ik)`). Too small a card
    // to hold its pills hides them instead.
    if (render.k !== k) { render.k = k; els.world.style.setProperty('--ik', (1 / k).toFixed(4)); }
    const tiny = W * k < 120;
    if (render.tiny !== tiny) { render.tiny = tiny; els.stage.classList.toggle('is-tiny', tiny); }
    const pct = Math.round(k * 100) + '%';
    if (render.pct !== pct) { render.pct = pct; els.zoom.querySelector('.lc-zoom-pct').textContent = pct; }
    if (schedule.full) Object.keys(INSIGHTS).forEach(p => els.root.classList.toggle('hide-' + p, !layers.ins[p]));

    // Cards in view (plus a margin), DOM only when zoomed in enough.
    const m = 300 / k;
    const x0 = (-view.x) / k - m, y0 = (-view.y) / k - m, x1 = (r.width - view.x) / k + m, y1 = (r.height - view.y) / k + m;
    // Far out, a small set still gets real cards; a big one is drawn as blocks.
    let vis = inRect(x0, y0, x1, y1);
    let blocks = vis.length > DOM_CAP;
    if (blocks) vis = [];
    els.stage.dataset.lod = blocks ? 0 : Math.max(1, lod);
    const bl = blocks ? 0 : Math.max(1, lod);
    if (bl !== boxLod) { boxLod = bl; families.forEach(famBox); }
    const want = new Set(vis);
    // Moving: keep what is there, add a few new cards per frame. Still: tidy up.
    if (!moving || blocks || rendered.size > DOM_CAP * 1.5) rendered.forEach((el, s) => { if (!want.has(s)) { el.remove(); rendered.delete(s); } });
    const frag = document.createDocumentFragment();
    let made = 0, more = false;
    let added = false;
    for (const s of vis) {
      let el = rendered.get(s);
      const n = nodes.get(s);
      if (!el) {
        if (moving && made >= 24) { more = true; continue; }
        el = cardEl(n); rendered.set(s, el); frag.appendChild(el); made++; added = true;
        if (dropAnim && dropAnim.slug === s) {
          const d = dropAnim; dropAnim = null;
          el.style.transform = `translate(${n.x}px,${n.y + 12}px) scale(0.94)`; el.style.opacity = '0';
          requestAnimationFrame(() => requestAnimationFrame(() => { el.classList.add('is-landing'); el.style.transform = `translate(${n.x}px,${n.y}px)`; el.style.opacity = ''; setTimeout(() => el.classList.remove('is-landing'), 480); }));
        }
      } else if (el._x !== n.x || el._y !== n.y) { el.style.transform = `translate(${n.x}px,${n.y}px)`; el._x = n.x; el._y = n.y; }
    }
    if (frag.childNodes.length) els.cards.appendChild(frag);
    if (more) schedule();

    if (schedule.full) {
      linkCount = new Map();
      doc.links.forEach(l => [l.a, l.b].forEach(x => linkCount.set(x, (linkCount.get(x) || 0) + 1)));
      rendered.forEach((el, s) => decorate(el, nodes.get(s)));
    }
    // Focus: the selected (or hovered) item or note and what it links to.
    const focus = dragging || sel || selNote || hover;
    const nearSet = new Set(near.map(x => x.b));
    lastBlocks = blocks;
    const linked = sel ? focusSet(sel) : null;
    const stateKey = [sel, connect && connect.from, near.map(x => x.b).join(), linked ? linked.size : 0].join('|');
    if (added || schedule.full || stateKey !== render.stateKey) {
      render.stateKey = stateKey;
      rendered.forEach((el, s) => {
        el.classList.toggle('is-selected', s === sel);
        el.classList.toggle('is-dim', !!(linked && !linked.has(s)));
        el.classList.toggle('is-target', !!(connect && s !== connect.from));
        el.classList.toggle('is-near', nearSet.has(s));
      });
    }
    els.root.classList.toggle('has-focus', !!linked);
    els.root.classList.toggle('is-connecting', !!(connect || pinFor));
    drawInk(r, blocks ? 0 : Math.max(1, lod), vis, focus, linked);
    renderFams(r, linked);
    if (hover && !blocks && !rendered.has(hover) && !doc.notes.some(n => n.id === hover)) hover = null;
    renderSelbar(r);
    schedule.full = false;
    if (t0) window.__lcPerf.push(performance.now() - t0);
  }
  let stageBox = null;
  function stageRect() {
    if (!stageBox) { const b = els.stage.getBoundingClientRect(); stageBox = { left: b.left, top: b.top, width: b.width, height: b.height }; }
    return stageBox;
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
    const w = sz.w / view.k, h = sz.h / view.k;   // notes stay one size on screen
    const cx = note.x + w / 2, cy = note.y + h / 2, dx = toward.x - cx, dy = toward.y - cy;
    if (Math.abs(dx) * h > Math.abs(dy) * w) return { x: dx > 0 ? note.x + w : note.x, y: cy, nx: Math.sign(dx), ny: 0 };
    return dy > 0 ? { x: cx, y: note.y + h, nx: 0, ny: 1 } : { x: cx, y: note.y, nx: 0, ny: -1 };
  }
  // Straight runs with 90° bends and rounded corners; one straight segment
  // when the two ends are close.
  function route(pa, pb) {
    const dx = pb.x - pa.x, dy = pb.y - pa.y;
    if (Math.hypot(dx, dy) < STRAIGHT || Math.abs(dx) < 3 || Math.abs(dy) < 3) return [pa, pb];
    if (pa.nx && pb.nx) { const mx = (pa.x + pb.x) / 2; return [pa, { x: mx, y: pa.y }, { x: mx, y: pb.y }, pb]; }
    if (pa.ny && pb.ny) { const my = (pa.y + pb.y) / 2; return [pa, { x: pa.x, y: my }, { x: pb.x, y: my }, pb]; }
    if (pa.nx) return [pa, { x: pb.x, y: pa.y }, pb];
    return [pa, { x: pa.x, y: pb.y }, pb];
  }
  function strokeRoute(ctx, pts) {
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length - 1; i++) {
      const p = pts[i], a = pts[i - 1], b = pts[i + 1];
      const r = Math.min(18, Math.hypot(p.x - a.x, p.y - a.y) / 2, Math.hypot(b.x - p.x, b.y - p.y) / 2);
      ctx.arcTo(p.x, p.y, b.x, b.y, r);
    }
    const z = pts[pts.length - 1];
    ctx.lineTo(z.x, z.y);
    ctx.stroke();
  }
  function routeMid(pts) {
    let best = 0, bi = 0;
    for (let i = 0; i < pts.length - 1; i++) { const d = Math.hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y); if (d > best) { best = d; bi = i; } }
    return { x: (pts[bi].x + pts[bi + 1].x) / 2, y: (pts[bi].y + pts[bi + 1].y) / 2 };
  }
  const imgCache = new Map();
  let imgPending = 0;
  function thumbImg(it) {
    let im = imgCache.get(it.slug);
    if (im === undefined) {
      if (!it.has_image || !it.image_path || imgPending > 32) return null;
      im = new Image();
      im.decoding = 'async';
      imgPending++;
      im.onload = () => { imgPending--; im._ok = true; schedule(); };
      im.onerror = () => { imgPending--; imgCache.set(it.slug, null); };
      im.src = it.image_path;
      imgCache.set(it.slug, im);
      if (imgCache.size > 5000) imgCache.delete(imgCache.keys().next().value);
    }
    return im && im._ok ? im : null;
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

    // Family tints and captions (behind everything).
    if (layers.sim.on && k >= 0.05) {
      const vx0 = -view.x / k, vy0 = -view.y / k, vx1 = (r.width - view.x) / k, vy1 = (r.height - view.y) / k;
      const fs = Math.max(15, 12 / k);
      ctx.font = `500 ${fs}px Inter, system-ui, sans-serif`;
      ctx.textBaseline = 'alphabetic';
      families.forEach(f => {
        const b = f.box;
        if (!b || f.loose || f.slugs.length < 2) return;
        if (b.x + b.w + FAM_PAD < vx0 || b.x - FAM_PAD > vx1 || b.y + b.h + FAM_PAD < vy0 || b.y - FAM_CAP > vy1) return;
        const col = f.color === 'accent' ? theme.accent : f.color || textCol;
        const dim = linked && !f.slugs.some(s => linked.has(s));
        ctx.globalAlpha = dim ? 0.03 : 0.09;
        ctx.fillStyle = col;
        ctx.beginPath(); ctx.roundRect(b.x - FAM_PAD, b.y - FAM_PAD, b.w + FAM_PAD * 2, b.h + FAM_PAD * 2, 22); ctx.fill();
      });
      ctx.globalAlpha = 1;
    }

    // Many cards in view: paint them here (cover images on the GPU canvas,
    // colour blocks when tiny) instead of thousands of DOM nodes.
    if (lod === 0) {
      const x0 = -view.x / k, y0 = -view.y / k, x1 = (r.width - view.x) / k, y1 = (r.height - view.y) / k;
      const cardCol = theme.card;
      const pics = W * k >= 16;
      inRect(x0, y0, x1, y1).forEach(s => {
        const n = nodes.get(s);
        const dim = linked && !linked.has(s);
        ctx.globalAlpha = dim ? 0.25 : 1;
        const im = pics ? thumbImg(n.item) : null;
        if (im) ctx.drawImage(im, n.x, n.y, W, n.ch);
        else {
          if (n.block === undefined) n.block = n.item.has_image && (n.item.tags || []).some(t => t.category === 'color') ? App.dominantColor(n.item) : null;
          ctx.fillStyle = n.block || cardCol;
          ctx.fillRect(n.x, n.y, W, n.ch);
        }
        if (s === sel || s === hover) { ctx.globalAlpha = 1; ctx.lineWidth = (s === sel ? 3 : 1.5) / k; ctx.strokeStyle = s === sel ? theme.accent : textCol; ctx.strokeRect(n.x - 4 / k, n.y - 4 / k, W + 8 / k, n.h + 8 / k); }
      });
      ctx.globalAlpha = 1;
    }

    const labels = [];
    const lw = (px) => px / k;
    if (hoverDrop && nodes.get(hoverDrop)) {
      const n = nodes.get(hoverDrop), f = families[n.fam];
      const b = f && !f.loose && f.box ? f.box : { x: n.x, y: n.y, w: W, h: n.h };
      const p = 16;
      ctx.globalAlpha = 1; ctx.strokeStyle = theme.accent; ctx.lineWidth = lw(2); ctx.setLineDash([lw(6), lw(5)]);
      ctx.beginPath(); ctx.roundRect(b.x - p, b.y - p, b.w + p * 2, b.h + p * 2, 20); ctx.stroke(); ctx.setLineDash([]);
      labels.push({ x: b.x + b.w / 2, y: b.y - p - 14 / k, text: f && !f.loose ? 'Drop to add to ' + cap(f.tag) : 'Drop to group', color: theme.accent, cls: 'l2 is-suggest' });
    }
    if (suggest) {
      const b = suggest.box, p = 16;
      ctx.globalAlpha = 1; ctx.strokeStyle = theme.accent; ctx.lineWidth = lw(2); ctx.setLineDash([lw(6), lw(5)]);
      ctx.beginPath(); ctx.roundRect(b.x - p, b.y - p, b.w + p * 2, b.h + p * 2, 20); ctx.stroke(); ctx.setLineDash([]);
      ctx.globalAlpha = 0.06; ctx.fillStyle = theme.accent; ctx.fill(); ctx.globalAlpha = 1;
      labels.push({ x: b.x + b.w / 2, y: b.y - p - 14 / k, text: (suggest.joining ? 'Drop to add to ' : 'Drop to group · ') + suggest.name, color: theme.accent, cls: 'l2 is-suggest' });
    }
    const drawLink = (a, b, color, dash, alpha, width, arrow, label, cls) => {
      const e = endpoints(a, b);
      if (!e) return;
      const pts = route(e.pa, e.pb);
      ctx.globalAlpha = alpha;
      ctx.strokeStyle = color || textCol;
      ctx.lineWidth = lw(width);
      ctx.setLineDash(dash ? dash.map(v => lw(v)) : []);
      strokeRoute(ctx, pts);
      ctx.setLineDash([]);
      ctx.fillStyle = color || textCol;
      const ends = [[pts[0], pts[1]], [pts[pts.length - 1], pts[pts.length - 2]]];
      ends.forEach(([p, q], i) => {
        if (arrow && (i === 1 || arrow === 'both')) {
          const ang = Math.atan2(p.y - q.y, p.x - q.x), s = lw(9);
          ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x - s * Math.cos(ang - 0.45), p.y - s * Math.sin(ang - 0.45)); ctx.lineTo(p.x - s * Math.cos(ang + 0.45), p.y - s * Math.sin(ang + 0.45)); ctx.closePath(); ctx.fill();
        } else { ctx.beginPath(); ctx.arc(p.x, p.y, lw(3.2), 0, Math.PI * 2); ctx.fill(); }
      });
      ctx.globalAlpha = 1;
      if (label && alpha > 0.5) { const m = routeMid(pts); labels.push({ x: m.x, y: m.y, text: label, color: color || textCol, cls }); }
    };
    const always = layers.sim.always;
    const touches = (l) => focus && (l.a === focus || l.b === focus);

    // Layer 1: computed similarity. Hidden until you hover, select or drag,
    // unless "always" is on.
    if (layers.sim.on && dragging) {
      near.forEach(x => {
        const d = SIM[x.type];
        const a = Math.max(0.3, 1 - x.d / NEAR);
        drawLink(dragging, x.b, d.color, d.dash, a, 1.4 + a, false, x.d < NEAR * 0.65 ? x.label : null, 'sim-' + x.type);
      });
    } else if (layers.sim.on && (focus || always)) {
      const seen = new Set();
      let drawn = 0;
      const from = focus && nodes.has(focus) ? [focus] : (always && lod >= 1 ? vis : []);
      for (const s of from) {
        if (drawn > MAX_LINKS) break;
        for (const l of linksFor(s, s === focus)) {
          if (!layers.sim[l.type]) continue;
          const key = l.a < l.b ? l.a + '|' + l.b : l.b + '|' + l.a;
          if (seen.has(key)) continue;
          seen.add(key);
          const on = touches(l);
          const d = SIM[l.type];
          drawLink(l.a, l.b, d.color, d.dash, on ? 0.95 : 0.4, on ? 2 : 1.3, false, on || (k >= 0.9 && l.s >= 3.6) ? l.label : null, 'sim-' + l.type);
          drawn++;
        }
      }
    }
    // Layer 2: your links (and accepted maybes), shown for the item in focus.
    doc.links.forEach(l => {
      const d = L2[l.kind] || L2.related;
      if (l.kind === 'question' || l.kind === 'part_of' ? !layers.ins.notes : !layers.ins.marks && l.kind !== 'related') return;
      if (!centreOf(l.a) || !centreOf(l.b)) return;
      const on = touches(l);
      if (!on && !always) return;
      const label = l.kind === 'influence' ? (l.label ? 'inspired: ' + l.label : 'inspired') : l.kind === 'contrast' ? 'vs' + (l.label ? ' · ' + l.label : '') : l.kind === 'part_of' ? 'part of' : l.kind === 'related' ? (l.label ? 'maybe: ' + l.label : null) : null;
      drawLink(l.a, l.b, d.color, d.dash, on || !focus ? 0.95 : 0.12, 2, l.kind === 'influence' ? 'both' : (l.kind === 'part_of' || l.kind === 'question') ? 'end' : false, (on || k >= LABEL_K) ? label : null, 'l2');
    });
    // Gaps: ghost to its anchor.
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
    const r = stageRect();
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
      const bg = l.color ? `background:${l.color};color:${/is-suggest/.test(l.cls) ? 'var(--accent-contrast)' : '#fff'}` : '';
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
    // Actions live in the card menu (right-click, or press and hold on touch),
    // the same menu as the grid. This bar is only the "Why?" field for a mark.
    const rec = cardRec(sel) || {};
    if (reasonFor !== sel || !rec.state) { bar.hidden = true; return; }
    if (bar.dataset.for !== sel || bar.dataset.state !== (rec.state || '')) {
      bar.dataset.for = sel; bar.dataset.state = rec.state || '';
      bar.innerHTML = `<span class="lc-reason-k">${rec.state === 'use' ? 'Use' : 'Rejected'}</span><input class="lc-reason" type="text" placeholder="Why? (optional)" value="${esc(rec.reason || '')}" maxlength="60">`;
    }
    bar.hidden = false;
    const k = view.k;
    const el = rendered.get(sel);
    const hh = el ? el.offsetHeight : n.h;
    let sx = n.x * k + view.x, sy = n.y * k + view.y + hh * k + 10;
    const bw = bar.offsetWidth || 560, bh = bar.offsetHeight || 40;
    if (sy + bh > r.height - 90) sy = n.y * k + view.y - bh - 10;
    sx = Math.max(12, Math.min(r.width - bw - 12, sx));
    sy = Math.max(12, sy);
    bar.style.transform = `translate(${sx}px,${sy}px)`;
  }

  // ---------- View ----------
  // ---------- Camera ----------
  // One source of truth: `view`. Gestures write it directly; buttons and keys
  // tween it in rAF (zoom in log space), so cards, tints and lines move together.
  const ZOOM_STEPS = [0.02, 0.03, 0.05, 0.08, 0.125, 0.25, 0.5, 1, 2];
  let tween = null;
  function viewAt(k, sx, sy, from) {
    const v = from || view;
    k = Math.max(MIN_K, Math.min(MAX_K, k));
    const r = stageRect();
    if (sx == null) { sx = r.width / 2; sy = r.height / 2; }
    const wx = (sx - v.x) / v.k, wy = (sy - v.y) / v.k;
    return { k, x: sx - wx * k, y: sy - wy * k };
  }
  function zoomAt(k, sx, sy, animate) {
    const base = tween ? tween.to : view;
    const to = viewAt(k, sx, sy, base);
    if (animate) return flyTo(to);
    stopTween();
    view.k = to.k; view.x = to.x; view.y = to.y;
    gesture();
    schedule();
  }
  function stepZoom(dir, sx, sy) {
    const k = (tween ? tween.to : view).k;
    const next = dir > 0 ? ZOOM_STEPS.find(z => z > k * 1.01) || MAX_K : [...ZOOM_STEPS].reverse().find(z => z < k / 1.01) || MIN_K;
    zoomAt(next, sx, sy, true);
  }
  function stopTween() { if (tween) { cancelAnimationFrame(tween.raf); tween = null; } }
  function flyTo(to, ms) {
    stopTween();
    const from = { ...view }, dur = ms || 280, t0 = performance.now();
    // Interpolate the world point under the screen centre and log(k), so zooms feel even.
    const r = stageRect();
    const cx = r.width / 2, cy = r.height / 2;
    const fw = { x: (cx - from.x) / from.k, y: (cy - from.y) / from.k }, tw = { x: (cx - to.x) / to.k, y: (cy - to.y) / to.k };
    const lk0 = Math.log(from.k), lk1 = Math.log(to.k);
    tween = { to };
    const step = (now) => {
      const t = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - t, 3);
      const k = Math.exp(lk0 + (lk1 - lk0) * e);
      const wx = fw.x + (tw.x - fw.x) * e, wy = fw.y + (tw.y - fw.y) * e;
      view.k = k; view.x = cx - wx * k; view.y = cy - wy * k;
      if (t >= 1) { view.k = to.k; view.x = to.x; view.y = to.y; tween = null; settle(); render(); return; }
      gesture(); render();
      tween.raf = requestAnimationFrame(step);
    };
    tween.raf = requestAnimationFrame(step);
  }
  // While the camera moves, only transforms and ink update; card swaps and
  // other DOM work wait until it has been still for a moment.
  let moving = false, settleT = 0;
  function gesture() { moving = true; clearTimeout(settleT); settleT = setTimeout(settle, 140); }
  function settle() { moving = false; schedule(true); }
  function fitView(box) {
    const b = box || worldBox;
    const r = stageRect();
    if (!r.width || !b) return null;
    const padT = 120, padB = 110, padX = 48;
    const k = Math.max(MIN_K, Math.min(1, Math.min((r.width - padX * 2) / b.w, (r.height - padT - padB) / b.h)));
    return { k, x: padX + (r.width - padX * 2 - b.w * k) / 2 - b.x * k, y: padT + (r.height - padT - padB - b.h * k) / 2 - b.y * k };
  }
  function fit(animate, box) {
    const to = fitView(box); if (!to) return;
    if (animate) return flyTo(to, 360);
    stopTween(); view.k = to.k; view.x = to.x; view.y = to.y; schedule(true);
  }
  function fitSelection() {
    const n = sel && nodes.get(sel);
    if (!n) return fit(true);
    fit(true, { x: n.x - 200, y: n.y - 200, w: W + 400, h: n.h + 400 });
  }
  function screenToWorld(cx, cy) {
    const r = stageRect();
    return { x: (cx - r.left - view.x) / view.k, y: (cy - r.top - view.y) / view.k };
  }
  function focusOn(slug) {
    const n = nodes.get(slug); if (!n) return;
    const r = stageRect();
    const k = Math.max(view.k, 0.75);
    flyTo({ k, x: r.width / 2 - (n.x + W / 2) * k, y: r.height / 2 - (n.y + n.h / 2) * k });
  }

  // ---------- Mode ----------
  // ---------- Mode: grid | split | canvas ----------
  // Split puts the grid on the left half and the canvas on the right; you drag
  // items from the grid onto the canvas. Canvas alone fills the column.
  const MODES = ['grid', 'split', 'canvas'];
  let gridScroll = 0;
  const mainEl = () => document.querySelector('.main-content');
  function setMode(m, opts) {
    let next = MODES.includes(m) ? m : 'grid';
    if (next === 'split' && isPhone()) next = 'canvas';
    const prev = mode;
    const mc = mainEl();
    if (prev === 'grid' && mc) gridScroll = mc.scrollTop;
    mode = next;
    localStorage.setItem(VIEW_KEY, mode);
    const html = document.documentElement;
    html.classList.toggle('view-canvas', mode === 'canvas');
    html.classList.toggle('view-split', mode === 'split');
    // Where the canvas lives: inside the grid column (canvas) or beside it (split).
    if (mode === 'split') { if (els.root.parentElement !== mc.parentElement) mc.after(els.root); }
    else if (els.root.parentElement !== mc) mc.appendChild(els.root);
    els.root.hidden = mode === 'grid';
    // Zoom sits in the bottom bar in canvas view, inside the canvas panel in split.
    if (mode === 'split') { if (els.zoom.parentElement !== els.root) els.root.appendChild(els.zoom); if (els.docbox.parentElement !== els.root) els.root.appendChild(els.docbox); }
    else {
      const bar0 = els.switch.parentElement;
      if (bar0 && bar0.lastElementChild !== els.zoom) bar0.appendChild(els.zoom);
      // Canvas view: the canvas name follows the view switch.
      const bar = document.querySelector('.bottom-bar');
      if (bar && els.docbox.previousElementSibling !== els.switch) els.switch.after(els.docbox);
    }
    closeDocMenu();
    els.switch.querySelectorAll('button').forEach(b => b.classList.toggle('is-on', b.dataset.view === mode));
    stageBox = null;
    if (mode === 'grid') {
      rendered.forEach(el => el.remove()); rendered.clear();
      sel = null; connect = null; pinFor = null; stopTween();
      if (mc && prev === 'canvas') mc.scrollTop = gridScroll;
      return;
    }
    if (mc && mode === 'split' && prev === 'canvas') mc.scrollTop = gridScroll;
    readTheme();
    layout();
    rendered.forEach(el => el.remove()); rendered.clear();
    // Keep the camera where you left it; fit only the first time there is something to show.
    requestAnimationFrame(() => { stageBox = null; if (!camSet && nodes.size) { fit(false); camSet = true; } render(); markGrid(); });
    if (!(opts && opts.quiet)) els.stage.focus({ preventScroll: true });
  }
  // Grid cards already on the canvas carry a small mark (split view).
  function markGrid() {
    const on = new Set(doc.cards.map(c => c.slug));
    const mc = mainEl(); if (!mc) return;
    mc.querySelectorAll('.grid-container .card[data-slug]').forEach(el => el.classList.toggle('on-canvas', on.has(el.dataset.slug)));
  }
  function emptyState() {
    if (!els.empty) return;
    const empty = !doc.cards.some(c => App.item(c.slug));
    els.empty.hidden = !empty || mode === 'grid';
    els.empty.querySelector('[data-split]').hidden = mode !== 'canvas' || isPhone();
    els.empty.querySelector('.lc-empty-sub').textContent = isPhone()
      ? 'In the grid, press and hold an item, then drag it here. Drop one next to another to group them.'
      : 'Drag items here from the grid (on touch, press and hold a card first). Drop one next to another to group them.';
  }

  // ---------- Bringing items in: drag from the grid ----------
  let dropAnim = null;            // { slug, x, y } world point a dropped card flies from
  // A card lands where you drop it. Dropped on or right next to a card, it
  // snaps beside that card and joins its group. Nothing else moves.
  function freeSpot(x, y, h) {
    for (let i = 0; i < 40; i++) {
      const hit = inRect(x - 10, y - 10, x + W + 10, y + h + 10);
      if (!hit.length) return { x, y };
      y = Math.max(...hit.map(b => { const m = nodes.get(b); return m.y + m.h; })) + F_ROW;
    }
    return { x, y };
  }
  function addToCanvas(slugs, at, quiet) {
    slugs = slugs.filter(s => App.item(s) && !cardRec(s));
    if (!slugs.length) return '';
    let said = '';
    if (!at) { const r = stageRect(); at = screenToWorld(r.left + r.width / 2, r.top + r.height / 2); }
    const near = nearestAt(at, SNAP_GAP);
    const by = doc.groupBy in GROUPS ? doc.groupBy : 'kind';
    change(() => {
      let y = null;
      slugs.forEach((s, i) => {
        const h = Math.round(W * coverRatio(App.item(s)));
        let x;
        if (near) { x = at.x > near.x + W / 2 ? near.x + W + F_COL : near.x - W - F_COL; if (y == null) y = near.y; }
        else { x = Math.round(at.x - W / 2); if (y == null) y = Math.round(at.y - h / 2); }
        const p = freeSpot(x, y, h);
        doc.cards.push({ slug: s, x: p.x, y: p.y, by });
        nodes.set(s, { slug: s, item: App.item(s), x: p.x, y: p.y, h, ch: h, fam: -1, cl: 0 });  // reserve the spot for the next one
        rebuildHash();
        y = p.y + h + F_ROW;
        if (i === 0 && near) y = p.y;
      });
      if (near) {
        const f = families[near.fam];
        let g = f && f.gid && doc.groups.find(x => x.id === f.gid);
        if (!g) {
          const base = f && !f.loose && f.slugs.length > 1 ? f.slugs : [near.slug];
          const sh = similarityScore(App.item(slugs[0]), near.item).shared;
          g = { id: uid(), name: f && !f.loose && f.tag ? cap(f.tag) : (sh[0] ? cap(sh[0]) : 'New group'), slugs: [...base] };
          doc.groups.push(g);
        }
        slugs.forEach(s => { if (!g.slugs.includes(s)) g.slugs.push(s); });
        said = g.name;
        if (!quiet) App.toast(`Added to ${g.name}`);
      } else if (!quiet) App.toast(slugs.length > 1 ? `Added ${slugs.length} items` : 'Added to the canvas');
    }, { layout: true });
    layout(); schedule(true);
    dropAnim = { slug: slugs[0] };
    camSet = true;
    markGrid(); emptyState();
    return said || true;
  }
  // ---------- Canvases: name, new, switch, delete, export ----------
  function renderDocName() {
    if (!els.docpill) return;
    els.docpill.querySelector('.lc-doc-name').textContent = doc.name || 'Untitled canvas';
  }
  function closeDocMenu() {
    if (!els.docpill) return;
    els.docpill.querySelector('.lc-doc-menu').hidden = true; els.docpill.classList.remove('is-open');
    els.exp.querySelector('.lc-exp-menu').hidden = true; els.exp.classList.remove('is-open');
  }
  function startRename() {
    const btn = els.docpill.querySelector('.lc-doc-name'), inp = els.docpill.querySelector('.lc-doc-input');
    closeDocMenu();
    inp.value = doc.name || ''; inp.placeholder = 'Name this canvas';
    inp.style.width = Math.max(140, btn.offsetWidth + 24) + 'px';
    btn.hidden = true; inp.hidden = false; inp.focus(); inp.select();
    els.docpill.classList.add('is-editing');
  }
  function endRename(ok) {
    const btn = els.docpill.querySelector('.lc-doc-name'), inp = els.docpill.querySelector('.lc-doc-input');
    if (inp.hidden) return;
    const v = inp.value.trim();
    inp.hidden = true; btn.hidden = false; els.docpill.classList.remove('is-editing');
    if (ok && v && v !== doc.name) { change(() => { doc.name = v; }); rememberCanvas(curId, v); renderDocName(); App.toast('Saved'); }
  }
  // Canvases this device knows about, so the list works offline too.
  const LIST_KEY = 'stello.canvas.list';
  function knownCanvases() { try { return JSON.parse(localStorage.getItem(LIST_KEY)) || []; } catch { return []; } }
  function rememberCanvas(id, name, drop) {
    const l = knownCanvases().filter(c => c.id !== id);
    if (!drop) l.unshift({ id, name: name || 'Untitled canvas' });
    localStorage.setItem(LIST_KEY, JSON.stringify(l.slice(0, 100)));
  }
  async function listCanvases() {
    let list = knownCanvases();
    if (window.Stello && Stello.getUserId && Stello.getUserId()) {
      try {
        const body = await Stello.apiGet('/api/projects');
        if (body && body.projects) {
          const local = list.filter(c => c.id.startsWith('local-'));
          list = body.projects.map(p => ({ id: p.id, name: p.name || (p.id === 'library' ? 'Library canvas' : 'Untitled canvas'), cards: p.cards }));
          list = list.concat(local);
          localStorage.setItem(LIST_KEY, JSON.stringify(list.map(({ id, name }) => ({ id, name }))));
        }
      } catch { /* offline: the device list */ }
    }
    if (!list.some(c => c.id === 'library')) list.push({ id: 'library', name: curId === 'library' ? doc.name : 'Library canvas' });
    if (!list.some(c => c.id === curId)) list.unshift({ id: curId, name: doc.name });
    return list;
  }
  async function flushPush() {
    if (!canSync() || !dirty) return;
    clearTimeout(pushTimer);
    await pushDoc();
  }
  async function switchCanvas(id) {
    if (id === curId) return;
    await flushPush();
    curId = id; localStorage.setItem(CUR_KEY, id);
    rev = +(localStorage.getItem(revKey()) || 0); dirty = false; undoStack = [];
    sel = null; selNote = null; connect = null; pinFor = null; camSet = false;
    rendered.forEach(el => el.remove()); rendered.clear();
    loadDoc();
    renderDocName(); renderMenus();
    layout(); schedule(true); markGrid(); emptyState();
    requestAnimationFrame(() => { if (nodes.size) { fit(false); camSet = true; } else { view.x = 0; view.y = 0; } render(); });
    await pullDoc();
    renderDocName(); markGrid(); emptyState();
    if (!camSet && nodes.size) { fit(false); camSet = true; }
  }
  async function newCanvas(copy) {
    await flushPush();
    const fresh = blankDoc();
    fresh.name = copy ? `${doc.name || 'Canvas'} copy` : 'Untitled canvas';
    if (copy) { const d = JSON.parse(JSON.stringify(doc)); Object.assign(fresh, d, { name: fresh.name, v: DOC_V }); }
    let id = 'local-' + uid();
    if (window.Stello && Stello.getUserId && Stello.getUserId()) {
      try {
        const res = await Stello.apiFetch('/api/projects', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ doc: toServer(fresh) }) });
        const body = await res.json().catch(() => null);
        if (res.ok && body && body.project) { id = body.project.id; localStorage.setItem('stello.canvas.rev.' + id, String(body.project.rev || 0)); }
      } catch { /* offline: a device-only canvas */ }
    }
    localStorage.setItem(id === 'library' ? 'stello.canvas.v1' : 'stello.canvas.doc.' + id, JSON.stringify(fresh));
    rememberCanvas(id, fresh.name);
    await switchCanvas(id);
    if (!copy) startRename();
    else App.toast('Saved as a new canvas');
  }
  async function deleteCanvas() {
    if (curId === 'library') return;
    const id = curId;
    if (canSync()) { try { await Stello.apiFetch('/api/projects/' + encodeURIComponent(id), { method: 'DELETE' }); } catch { /* keep going locally */ } }
    localStorage.removeItem('stello.canvas.doc.' + id); localStorage.removeItem('stello.canvas.rev.' + id);
    rememberCanvas(id, null, true);
    dirty = false;
    await switchCanvas('library');
    App.toast('Canvas deleted');
  }
  async function openDocMenu() {
    const menu = els.docpill.querySelector('.lc-doc-menu');
    if (!menu.hidden) { closeDocMenu(); return; }
    closeDocMenu();
    const draw = (list) => {
      menu.innerHTML = `<div class="lc-doc-sec">Canvases</div>
        ${list.map(c => `<button type="button" class="lc-mi${c.id === curId ? ' is-on' : ''}" data-open-canvas="${esc(c.id)}" role="menuitemradio" aria-checked="${c.id === curId}">${esc(c.id === curId ? doc.name : c.name)}${c.cards != null ? `<em>${c.cards}</em>` : ''}</button>`).join('')}
        <button type="button" class="lc-mi" data-doc="new">+ New canvas</button>
        <button type="button" class="lc-mi" data-doc="copy">Save as a new canvas</button>
        <button type="button" class="lc-mi" data-doc="rename">Rename</button>
        ${curId !== 'library' ? '<button type="button" class="lc-mi is-danger" data-doc="delete">Delete this canvas</button>' : ''}`;
    };
    draw(knownCanvases().length ? knownCanvases() : [{ id: curId, name: doc.name }]);
    menu.hidden = false; els.docpill.classList.add('is-open');
    draw(await listCanvases());
  }
  function openExpMenu() {
    const menu = els.exp.querySelector('.lc-exp-menu');
    if (!menu.hidden) { closeDocMenu(); return; }
    closeDocMenu();
    const F = (window.StelloCanvasExport && StelloCanvasExport.FORMATS) || {};
    menu.innerHTML = `<div class="lc-doc-sec">Export</div>` + Object.entries(F).map(([k, v]) => `<button type="button" class="lc-mi" data-export="${k}" role="menuitem">${esc(v.label)}<em>${esc(v.hint)}</em></button>`).join('');
    menu.hidden = false; els.exp.classList.add('is-open');
  }
  // The canvas as plain data for the exporters: cards at their spots, groups
  // with their pills, links and notes.
  function exportModel() {
    const cards = [];
    nodes.forEach(n => {
      const rec = cardRec(n.slug) || {};
      cards.push({ slug: n.slug, item: n.item, x: n.x, y: n.y, w: W, h: n.ch, state: rec.state || null, reason: rec.reason || '', image: n.item.has_image ? n.item.image_path : null, groups: [] });
    });
    const bySlug = new Map(cards.map(c => [c.slug, c]));
    const groups = [];
    families.forEach(f => {
      if (!f.box || f.loose || f.slugs.length < 2) return;
      const meta = famMeta(f);
      const pills = meta.pills.map(p => p.text);
      f.slugs.forEach(sl => { const c = bySlug.get(sl); if (c) c.groups.push(pills[0]); });
      const col = f.color === 'accent' ? theme.accent : f.color || theme.text;
      groups.push({ x: f.box.x - FAM_PAD, y: f.box.y - FAM_PAD, w: f.box.w + FAM_PAD * 2, h: f.box.h + FAM_PAD * 2, pills, user: f.type === 'user', slugs: [...f.slugs], tint: hexA(col, 0.12) });
    });
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    cards.forEach(c => { x0 = Math.min(x0, c.x); y0 = Math.min(y0, c.y); x1 = Math.max(x1, c.x + c.w); y1 = Math.max(y1, c.y + c.h); });
    groups.forEach(g => { x0 = Math.min(x0, g.x); y0 = Math.min(y0, g.y - 40); x1 = Math.max(x1, g.x + g.w); y1 = Math.max(y1, g.y + g.h); });
    doc.notes.forEach(n => { x0 = Math.min(x0, n.x || 0); y0 = Math.min(y0, n.y || 0); x1 = Math.max(x1, (n.x || 0) + 220); y1 = Math.max(y1, (n.y || 0) + 80); });
    if (!Number.isFinite(x0)) { x0 = 0; y0 = 0; x1 = 400; y1 = 300; }
    const label = (id) => { const c = bySlug.get(id); if (c) return c.item.title || c.item.domain || id; const n = doc.notes.find(x => x.id === id); return n ? `“${n.text || n.kind}”` : id; };
    const centre = (id) => { const c = bySlug.get(id); if (c) return { x: c.x + c.w / 2, y: c.y + c.h / 2 }; const n = doc.notes.find(x => x.id === id); return n ? { x: (n.x || 0) + 110, y: (n.y || 0) + 35 } : null; };
    const links = doc.links.filter(l => (bySlug.has(l.a) || doc.notes.some(n => n.id === l.a)) && (bySlug.has(l.b) || doc.notes.some(n => n.id === l.b)))
      .map(l => ({ ...l, color: (L2[l.kind] && L2[l.kind].color) || '#888888' }));
    return { name: doc.name || 'Untitled canvas', doc: toServer(doc), cards, bySlug, groups, links, notes: doc.notes.slice(), bounds: { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }, label, centre };
  }
  function hexA(c, a) {
    const m = /^#?([0-9a-f]{6})$/i.exec(String(c).trim());
    if (!m) return `rgba(255,197,61,${a})`;
    const v = parseInt(m[1], 16);
    return `rgba(${v >> 16},${(v >> 8) & 255},${v & 255},${a})`;
  }
  async function exportAs(fmt) {
    closeDocMenu();
    if (!nodes.size) { App.toast('Nothing on this canvas to export yet'); return; }
    if (!window.StelloCanvasExport) { App.toast('Export is still loading, try again'); return; }
    try { await StelloCanvasExport.run(fmt, exportModel(), App.toast); }
    catch (err) { console.error(err); App.toast('Export failed: ' + (err && err.message || 'unknown error')); }
  }
  function bindDoc() {
    const dp = els.docbox, inp = dp.querySelector('.lc-doc-input');
    dp.addEventListener('pointerdown', (e) => e.stopPropagation());
    dp.addEventListener('click', (e) => {
      const b = e.target.closest('[data-doc], [data-open-canvas], [data-export]'); if (!b) return;
      if (b.dataset.openCanvas) { closeDocMenu(); switchCanvas(b.dataset.openCanvas); return; }
      if (b.dataset.export) { exportAs(b.dataset.export); return; }
      const a = b.dataset.doc;
      if (a === 'rename') startRename();
      else if (a === 'menu') openDocMenu();
      else if (a === 'export') openExpMenu();
      else if (a === 'new') { closeDocMenu(); newCanvas(false); }
      else if (a === 'copy') { closeDocMenu(); newCanvas(true); }
      else if (a === 'delete') {
        if (b.dataset.step !== '1') { b.dataset.step = '1'; b.textContent = 'Click again to delete'; return; }
        closeDocMenu(); deleteCanvas();
      }
    });
    inp.addEventListener('keydown', (e) => { e.stopPropagation(); if (e.key === 'Enter') endRename(true); if (e.key === 'Escape') endRename(false); });
    inp.addEventListener('blur', () => endRename(true));
    document.addEventListener('pointerdown', (e) => { if (!e.target.closest('.lc-docbox')) closeDocMenu(); }, true);
  }

  // ---------- Group pills ----------
  // A group's name and what its members share, as pills on the top-left of
  // its tint, in screen space. Your group: its name first (accent), then the
  // shared traits. A similarity group: one pill per trait all members share.
  // A dashed "+ maybe" pill offers one more save from the library that fits.
  const famEls = new Map();      // family index -> element
  const looseFeat = new Map();   // slug -> features, for the library scan
  function featLoose(it) { let f = looseFeat.get(it.slug); if (!f) { f = featuresLoose(it); looseFeat.set(it.slug, f); } return f; }
  let scanBudget = 0;             // library scans (maybe pills) allowed this frame
  function famMeta(f) {
    const sig = f.slugs.join(',') + '|' + f.tag + '|' + f.type + '|' + doc.dismissed.length + '|' + set.length;
    if (f._sig === sig && (f._meta.ghost !== undefined || scanBudget <= 0)) return f._meta;
    f._sig = sig;
    const pills = [];
    if (f.type === 'user') pills.push({ text: cap(f.tag || 'Group'), cls: 'is-name' });
    // Traits every member shares, strongest first.
    let common = null;
    f.slugs.forEach(sl => {
      const fs = new Map((featOf.get(sl) || []).filter(x => layers.sim[x.type]).map(x => [x.f, x]));
      if (!common) common = fs; else common.forEach((v, key) => { if (!fs.has(key)) common.delete(key); });
    });
    const traits = [...(common ? common.values() : [])].sort((a, b) => SIM[b.type].w - SIM[a.type].w);
    if (f.type !== 'user' && f.tag) {
      const i = traits.findIndex(x => x.tag === f.tag);
      if (i > 0) traits.unshift(traits.splice(i, 1)[0]);
      else if (i < 0) traits.unshift({ tag: f.tag, type: f.type });
    }
    const seen = new Set(pills.map(p => p.text.toLowerCase()));
    traits.forEach(x => {
      if (pills.length >= 4 || seen.has(String(x.tag).toLowerCase())) return;
      seen.add(String(x.tag).toLowerCase());
      pills.push({ text: cap(x.tag), cls: 'is-trait', color: (SIM[x.type] && SIM[x.type].color) || theme.text, title: SIM[x.type] ? SIM[x.type].label : '' });
    });
    if (!pills.length) pills.push({ text: 'Group', cls: 'is-name' });
    // One maybe-related save, scanning the library once per change of the group.
    let ghost = null;
    if (layers.ins.gaps && f.slugs.length >= 2 && scanBudget <= 0) ghost = undefined;   // next frame
    else if (layers.ins.gaps && f.slugs.length >= 2) {
      scanBudget--;
      const all = App.items(), dismissed = new Set(doc.dismissed), want = new Map();
      f.slugs.slice(0, 24).forEach(sl => { const it = App.item(sl); if (it) featLoose(it).forEach(x => want.set(x.f, (want.get(x.f) || 0) + SIM[x.type].w)); });
      let best = null;
      for (const it of all) {
        if (setIndex.has(it.slug) || dismissed.has(it.slug)) continue;
        let sc = 0; const shared = [];
        featLoose(it).forEach(x => { const w = want.get(x.f); if (w) { sc += w; shared.push(x.tag); } });
        if (!best || sc > best.s) best = { it, s: sc, shared };
      }
      if (best && best.shared.length >= 2 && best.s >= Math.max(3, f.slugs.length * 0.35)) ghost = { slug: best.it.slug, title: best.it.title || best.it.domain || 'Untitled', shared: [...new Set(best.shared)].slice(0, 3) };
    }
    f._meta = { pills, ghost };
    return f._meta;
  }
  function shortTitle(t) {
    t = String(t).split(/\s[|•·–—-]\s/)[0].trim();
    if (t.length <= 24) return t;
    const cut = t.slice(0, 24); const sp = cut.lastIndexOf(' ');
    return (sp > 10 ? cut.slice(0, sp) : cut) + '…';
  }
  function renderFams(r, linked) {
    const k = view.k, show = layers.sim.on && k >= 0.04 && mode !== 'grid';
    const seen = new Set();
    scanBudget = moving ? 0 : 2;
    let pending = false;
    if (show) families.forEach((f, fi) => {
      const b = f.box;
      if (!b || f.loose || f.slugs.length < 2) return;
      const sx = (b.x - FAM_PAD) * k + view.x, sy = (b.y - FAM_PAD) * k + view.y;
      const w = (b.w + FAM_PAD * 2) * k;
      if (seen.size >= 80) return;
      if (w < 40 || sx > r.width || sy > r.height + 40 || sx + w < 0 || sy + (b.h + FAM_PAD * 2) * k < -40) return;
      let el = famEls.get(fi);
      const meta = famMeta(f);
      if (meta.ghost === undefined) pending = true;
      const key = JSON.stringify(meta) + (dragging ? 'd' : '');
      if (!el) { el = document.createElement('div'); el.className = 'lc-fam'; el.dataset.fam = fi; els.fams.appendChild(el); famEls.set(fi, el); }
      if (el._key !== key) {
        el._key = key;
        el.innerHTML = meta.pills.map(p => `<button type="button" class="lc-pill ${p.cls}"${p.title ? ` title="${esc(p.title)}"` : ''} data-rename="${fi}">${p.color ? `<i style="background:${p.color}"></i>` : ''}${esc(p.text)}</button>`).join('') +
          (meta.ghost ? `<button type="button" class="lc-pill is-maybe" data-maybe="${fi}" title="Maybe related: shares ${esc(meta.ghost.shared.join(', '))}. Click to add.">+ Maybe: ${esc(shortTitle(meta.ghost.title))}</button><button type="button" class="lc-pill is-maybe-x" data-dismiss="${esc(meta.ghost.slug)}" aria-label="Not related" title="Not related">${IC.x}</button>` : '');
      }
      el.style.transform = `translate(${Math.round(sx)}px,${Math.round(sy - 8)}px) translateY(-100%)`;
      el.style.maxWidth = Math.max(120, w + 160) + 'px';
      el.classList.toggle('is-dim', !!(linked && !f.slugs.some(x => linked.has(x))));
      seen.add(fi);
    });
    famEls.forEach((el, fi) => { if (!seen.has(fi)) { el.remove(); famEls.delete(fi); } });
    if (pending && !moving) setTimeout(() => schedule(), 50);
  }
  function bindFams() {
    els.fams.addEventListener('pointerdown', (e) => e.stopPropagation());
    els.fams.addEventListener('click', (e) => {
      const rn = e.target.closest('[data-rename]');
      if (rn) { const b = rn.getBoundingClientRect(); renameFamily(+rn.dataset.rename, b.left + 10, b.top + b.height / 2); return; }
      const mb = e.target.closest('[data-maybe]');
      if (mb) {
        const f = families[+mb.dataset.maybe], meta = f && f._meta; if (!meta || !meta.ghost) return;
        const g = meta.ghost, anchorSlug = f.slugs[f.slugs.length - 1], an = nodes.get(anchorSlug);
        change(() => { doc.links.push({ id: uid(), a: anchorSlug, b: g.slug, kind: 'related', label: g.shared[0] || '', source: 'maybe' }); });
        addToCanvas([g.slug], an ? { x: an.x + W + 10, y: an.y + 10 } : null);
        return;
      }
      const dis = e.target.closest('[data-dismiss]');
      if (dis) { change(() => doc.dismissed.push(dis.dataset.dismiss)); schedule(true); }
    });
  }
  function renameFamily(fi, cx, cy) {
    const f = families[fi];
    const r = stageRect();
    const inp = document.createElement('input');
    inp.className = 'lc-label-input';
    inp.value = cap(f.tag || ''); inp.maxLength = 40; inp.placeholder = 'Group name';
    inp.style.transform = `translate(${cx - r.left}px,${cy - r.top}px) translate(-20%,-50%)`;
    els.stage.appendChild(inp); inp.focus(); inp.select();
    let done = false;
    const finish = (ok) => {
      if (done) return; done = true; inp.remove();
      const name = inp.value.trim(); if (!ok || !name) return;
      change(() => {
        let g = f.gid && doc.groups.find(x => x.id === f.gid);
        if (!g) { g = { id: uid(), name, slugs: [...f.slugs] }; doc.groups.push(g); f.gid = g.id; f.type = 'user'; f.color = 'accent'; }
        g.name = name; f.tag = name;
      });
      schedule(true);
    };
    inp.addEventListener('keydown', (ev) => { ev.stopPropagation(); if (ev.key === 'Enter') finish(true); if (ev.key === 'Escape') finish(false); });
    inp.addEventListener('blur', () => finish(true));
  }
  function removeFromCanvas(slug) {
    change(() => {
      doc.cards = doc.cards.filter(c => c.slug !== slug);
      doc.groups.forEach(g => { g.slugs = g.slugs.filter(x => x !== slug); });
      doc.groups = doc.groups.filter(g => g.slugs.length > 1);
    }, { layout: true });
    sel = null; relayoutAnim(); markGrid(); emptyState();
  }
  function nearestAt(at, gap) {
    let best = null;
    inRect(at.x - gap, at.y - gap, at.x + gap, at.y + gap).forEach(s => {
      const n = nodes.get(s);
      const dx = Math.max(0, n.x - at.x, at.x - (n.x + W)), dy = Math.max(0, n.y - at.y, at.y - (n.y + n.h));
      const d = Math.hypot(dx, dy);
      if (d <= gap && (!best || d < best.d)) best = { n, d };
    });
    return best && best.n;
  }
  // Cards glide to their new spots when the layout changes.
  function relayoutAnim() {
    els.root.classList.add('is-relayout');
    clearTimeout(relayoutAnim.t);
    relayoutAnim.t = setTimeout(() => els.root.classList.remove('is-relayout'), 520);
  }
  // ---------- Phones: carry an item from the grid to the canvas ----------
  // No split view on a phone. Press and hold a grid card: it lifts; start
  // moving and the canvas fades in under it, so you place it exactly. Let go
  // on the canvas to drop it (near a card it groups), on the Cancel pill to
  // put it back. Then you are back in the grid where you were (or stay on the
  // canvas, by preference). Held and released without moving: the card menu.
  const PHONE_MQ = window.matchMedia('(max-width: 768px)');
  const isPhone = () => PHONE_MQ.matches;
  const RETURN_KEY = 'stello.canvas.mobileReturn';   // 'grid' | 'canvas'
  let carry = null;                // { from } while a card is carried from the grid
  function carryUI(on) {
    document.documentElement.classList.toggle('is-carrying', on);
    if (on && !els.cancel) {
      const c = document.createElement('div');
      c.className = 'lc-carry-top';
      c.innerHTML = `<span class="lc-carry-name"></span><span class="lc-carry-cancel" data-cancel>${IC.x} Cancel</span>`;
      document.body.appendChild(c); els.cancel = c;
    }
    if (on && els.atoast) els.atoast.classList.remove('is-on');
    if (els.cancel) {
      els.cancel.hidden = !on;
      els.cancel.querySelector('.lc-carry-name').textContent = 'Adding to ' + (doc.name || 'canvas');
    }
  }
  function actionToast(text, actions) {
    let t = els.atoast;
    if (!t) { t = document.createElement('div'); t.className = 'lc-atoast'; t.setAttribute('role', 'status'); document.body.appendChild(t); els.atoast = t; }
    t.innerHTML = `<span>${esc(text)}</span>` + actions.map((a, i) => `<button type="button" data-i="${i}">${esc(a.label)}</button>`).join('');
    t.onclick = (e) => { const b = e.target.closest('[data-i]'); if (!b) return; t.classList.remove('is-on'); actions[+b.dataset.i].run(); };
    t.classList.add('is-on');
    clearTimeout(t._t); t._t = setTimeout(() => t.classList.remove('is-on'), 5000);
  }
  // Edge auto-pan while carrying: near a stage edge the canvas slides along.
  let edgeRaf = 0, edgePt = null;
  function edgePan() {
    edgeRaf = 0;
    if (!carry || !edgePt) return;
    const r = els.stage.getBoundingClientRect(), E = 44, sp = 9;
    let dx = 0, dy = 0;
    if (edgePt.x < r.left + E) dx = sp; else if (edgePt.x > r.right - E) dx = -sp;
    if (edgePt.y < r.top + E + 40) dy = sp; else if (edgePt.y > r.bottom - E - 60) dy = -sp;
    if (dx || dy) { view.x += dx; view.y += dy; gesture(); schedule(); }
    edgeRaf = requestAnimationFrame(edgePan);
  }
  // "Add to canvas" from the card menu: next to the item most like it.
  function addAuto(slug) {
    if (cardRec(slug)) { if (mode === 'grid') setMode(isPhone() ? 'canvas' : 'split'); requestAnimationFrame(() => { focusOn(slug); sel = slug; schedule(true); }); return; }
    if (mode === 'grid') { layout(); }
    const it = App.item(slug); if (!it) return;
    let best = null;
    nodes.forEach(n => { const sc = similarityScore(it, n.item).s; if (sc > 0 && (!best || sc > best.s)) best = { n, s: sc }; });
    let at;
    if (best) at = { x: best.n.x + W * 1.5 + SNAP_GAP + 20, y: best.n.y + 40 };
    else if (nodes.size) at = { x: worldBox.x + worldBox.w + W / 2 + 80, y: worldBox.y + TITLE_H + 120 };
    else at = { x: W / 2, y: 160 };
    addToCanvas([slug], at);
    if (mode === 'grid') actionToast(`Added to ${doc.name || 'canvas'}`, [{ label: 'Undo', run: () => { undo(); markGrid(); } }, { label: 'Open canvas', run: () => { setMode(isPhone() ? 'canvas' : 'split'); requestAnimationFrame(() => { focusOn(slug); }); } }]);
  }

  // Several items at once (grid selection → Add to Canvas): a small block of
  // up to four columns, right of what's already there. One undo step.
  function addMany(list) {
    const slugs = (list || []).filter(s => App.item(s) && !cardRec(s));
    if (!slugs.length) { App.toast('Already on the canvas'); return 0; }
    if (mode === 'grid') layout();
    const by = doc.groupBy in GROUPS ? doc.groupBy : 'kind';
    const x0 = nodes.size ? Math.round(worldBox.x + worldBox.w + 120) : 0;
    const y0 = nodes.size ? Math.round(worldBox.y + TITLE_H) : 80;
    const cols = Math.max(1, Math.min(4, Math.ceil(Math.sqrt(slugs.length))));
    const colY = new Array(cols).fill(y0);
    change(() => {
      slugs.forEach((s) => {
        const it = App.item(s);
        const h = Math.round(W * coverRatio(it));
        let c = 0;
        for (let i = 1; i < cols; i++) if (colY[i] < colY[c]) c = i;
        const p = freeSpot(x0 + c * (W + F_COL), colY[c], h);
        doc.cards.push({ slug: s, x: p.x, y: p.y, by });
        nodes.set(s, { slug: s, item: it, x: p.x, y: p.y, h, ch: h, fam: -1, cl: 0 });
        rebuildHash();
        colY[c] = p.y + h + F_ROW;
      });
    }, { layout: true });
    layout(); schedule(true);
    camSet = true;
    markGrid(); emptyState();
    const where = doc.name || 'canvas';
    actionToast(`Added ${slugs.length === 1 ? '1 item' : slugs.length + ' items'} to ${where}`, [
      { label: 'Undo', run: () => { undo(); markGrid(); } },
      ...(mode !== 'grid' ? [] : [{ label: 'Open canvas', run: () => { setMode(isPhone() ? 'canvas' : 'split'); requestAnimationFrame(() => focusOn(slugs[0])); } }]),
    ]);
    return slugs.length;
  }

  function bindGridDrag() {
    const mc = mainEl(); if (!mc) return;
    const active = () => mode === 'split' || (mode === 'grid' && isPhone());
    // The browser's own image drag would swallow the pointer events.
    mc.addEventListener('dragstart', (e) => { if (active() && e.target.closest && e.target.closest('.grid-container .card')) e.preventDefault(); });
    // Touch: a plain swipe scrolls the grid; press and hold a card to pick it up.
    let held = false, lastType = 'mouse';
    mc.addEventListener('touchmove', (e) => { if (held) e.preventDefault(); }, { passive: false });
    // A long press would also open the browser's (or our) menu: the hold owns it.
    mc.addEventListener('contextmenu', (e) => { if (active() && lastType !== 'mouse' && e.target.closest('.grid-container .card')) { e.preventDefault(); e.stopPropagation(); } });
    mc.addEventListener('pointerdown', (e) => {
      lastType = e.pointerType;
      if (!active() || e.button !== 0 || !e.isPrimary) return;
      const phoneFlow = mode === 'grid';
      if (phoneFlow && e.pointerType === 'mouse') return;
      const card = e.target.closest('.grid-container .card[data-slug]');
      if (!card || e.target.closest('button, a, input')) return;
      const slug = card.dataset.slug, sx = e.clientX, sy = e.clientY, id = e.pointerId;
      const touch = e.pointerType !== 'mouse';
      let ghost = null, over = false, onCancel = false, holdT = 0, last = e, liftX = sx, liftY = sy;
      const pick = () => {
        holdT = 0; held = true;
        card.classList.add('is-picked');
        if (navigator.vibrate) navigator.vibrate(8);
        liftX = last.clientX; liftY = last.clientY;
        move(last, true);
      };
      if (touch) holdT = setTimeout(pick, 320);
      const move = (ev, force) => {
        if (ev.pointerId !== id) return;
        last = ev;
        if (touch && !held) {
          // Moved before the hold: it's a scroll, let the grid have it.
          if (Math.hypot(ev.clientX - sx, ev.clientY - sy) > 8) cleanup();
          return;
        }
        if (!ghost) {
          if (!force && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 6) return;
          const r = card.getBoundingClientRect();
          const w = Math.min(phoneFlow ? 150 : 180, r.width), h = r.height * (w / r.width);
          ghost = document.createElement('div');
          ghost.className = 'lc-drag-ghost';
          ghost.style.cssText = `width:${w}px;height:${h}px;`;
          const img = card.querySelector('img');
          ghost.innerHTML = img ? `<img src="${img.currentSrc || img.src}" alt="">` : App.thumbHTML(App.item(slug));
          if (cardRec(slug)) ghost.classList.add('is-on');
          document.body.appendChild(ghost);
          document.documentElement.classList.add('is-dragging-in');
        }
        ghost.style.transform = `translate(${ev.clientX - 30}px,${ev.clientY - 30}px) rotate(-2deg)`;
        // Phone: once the lifted card starts to travel, the canvas comes in under it.
        if (phoneFlow && !carry && Math.hypot(ev.clientX - liftX, ev.clientY - liftY) > 12) {
          carry = { from: 'grid' };
          setMode('canvas', { quiet: true, carry: true });
          carryUI(true);
          stageBox = null;
        }
        if (phoneFlow && !carry) return;
        const r = els.stage.getBoundingClientRect();
        const cr = els.cancel && carry ? els.cancel.querySelector('[data-cancel]').getBoundingClientRect() : null;
        const nowCancel = !!(cr && ev.clientX >= cr.left - 12 && ev.clientX <= cr.right + 12 && ev.clientY >= cr.top - 12 && ev.clientY <= cr.bottom + 12);
        if (nowCancel !== onCancel) { onCancel = nowCancel; els.cancel.classList.toggle('is-hot', onCancel); ghost.classList.toggle('is-cancel', onCancel); }
        const now = !onCancel && ev.clientX >= r.left && ev.clientX <= r.right && ev.clientY >= r.top && ev.clientY <= r.bottom;
        if (now !== over) { over = now; els.stage.classList.toggle('is-drop-target', over && !carry); }
        if (over) { const w = screenToWorld(ev.clientX, ev.clientY); const nn = nearestAt(w, SNAP_GAP); hoverDrop = nn ? nn.slug : null; schedule(); }
        else if (hoverDrop) { hoverDrop = null; schedule(); }
        if (carry) { edgePt = { x: ev.clientX, y: ev.clientY }; if (!edgeRaf) edgeRaf = requestAnimationFrame(edgePan); }
      };
      const cleanup = () => {
        clearTimeout(holdT); held = false; card.classList.remove('is-picked');
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        window.removeEventListener('pointercancel', cancel);
      };
      const endCarry = (dropped) => {
        const was = carry; carry = null; edgePt = null;
        if (edgeRaf) { cancelAnimationFrame(edgeRaf); edgeRaf = 0; }
        carryUI(false);
        if (!was) return;
        const stay = localStorage.getItem(RETURN_KEY) === 'canvas';
        if (!dropped) { setMode('grid', { quiet: true }); return; }
        if (stay) return;
        // Let the card land, then go back to where you were in the grid.
        setTimeout(() => {
          setMode('grid', { quiet: true });
          const where = doc.name || 'canvas';
          actionToast(dropped === 'have' ? 'Already on the canvas' : typeof dropped === 'string' ? `Added to ${dropped} in ${where}` : `Added to ${where}`, [
            ...(dropped === 'have' ? [] : [{ label: 'Undo', run: () => { undo(); markGrid(); } }]),
            { label: 'Open canvas', run: () => { setMode('canvas'); requestAnimationFrame(() => focusOn(slug)); } },
          ]);
        }, 650);
      };
      const cancel = (ev) => {
        if (ev.pointerId !== id) return;
        cleanup();
        if (ghost) { ghost.remove(); document.documentElement.classList.remove('is-dragging-in'); els.stage.classList.remove('is-drop-target'); hoverDrop = null; schedule(); }
        endCarry(false);
      };
      const up = (ev) => {
        if (ev.pointerId !== id) return;
        const wasHeld = held;
        cleanup();
        if (!ghost) return;
        ghost.remove();
        document.documentElement.classList.remove('is-dragging-in');
        els.stage.classList.remove('is-drop-target');
        hoverDrop = null;
        // The grid would open the item on this click; it was a drag.
        window.addEventListener('click', (ce) => { ce.stopPropagation(); ce.preventDefault(); }, { capture: true, once: true });
        // Phone: held and let go without moving it: the card menu.
        if (phoneFlow && !carry) { if (wasHeld && App.openCardMenu) App.openCardMenu(slug, ev.clientX, ev.clientY); return; }
        let dropped = false;
        if (over) {
          if (cardRec(slug)) { dropped = 'have'; if (!carry) App.toast('Already on the canvas'); focusOn(slug); sel = slug; schedule(true); }
          else dropped = addToCanvas([slug], screenToWorld(ev.clientX, ev.clientY), !!carry) || false;
        }
        if (carry) endCarry(dropped);
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
      window.addEventListener('pointercancel', cancel);
    });
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
    askReason(slug);
  }
  // The "Why?" field under a marked card (web counterpart of the Apple prompt).
  function askReason(slug) {
    if (!(cardRec(slug) && cardRec(slug).state)) { reasonFor = null; schedule(true); return; }
    sel = slug; reasonFor = slug; schedule(true);
    requestAnimationFrame(() => requestAnimationFrame(() => { const i = els.selbar.querySelector('.lc-reason'); if (i) i.focus(); }));
  }
  // The card menu: the grid's right-click menu, with the canvas actions
  // slotted in (Apple apps: the canvas card's context menu).
  function openMenu(slug, x, y) {
    if (!App.openCardMenu || !nodes.get(slug)) return;
    sel = slug; selNote = null; schedule(true);
    const rec = cardRec(slug) || {};
    const fresh = () => nodes.get(slug) && rendered.get(slug);
    App.openCardMenu(slug, x, y, {
      top: [{ id: 'lc-details', label: openDet.has(slug) ? 'Hide Details' : 'Show Details' }],
      bottom: [
        { divider: true },
        { id: 'lc-use', label: 'Use', checked: rec.state === 'use' },
        { id: 'lc-rejected', label: 'Rejected', checked: rec.state === 'rejected' },
        ...(rec.state ? [{ id: 'lc-why', label: 'Why…' }] : []),
        { id: 'lc-link', label: 'Link', sub: [
          { id: 'lc-influence', label: 'Inspired…' },
          { id: 'lc-contrast', label: 'Vs…' },
          { id: 'lc-part_of', label: 'Part of…' },
          { id: 'lc-question', label: 'Ask…' },
        ] },
        { id: 'lc-pin', label: 'Note on Image…' },
        { divider: true },
        { id: 'lc-remove', label: 'Remove from Canvas', danger: true },
      ],
      onAction(a, s) {
        if (!a.startsWith('lc-')) return false;
        a = a.slice(3);
        if (a === 'details') { const el = fresh(); if (el) { if (openDet.has(s)) toggleDet(el, nodes.get(s), false); else openReadable(el, nodes.get(s)); } schedule(true); }
        else if (a === 'use' || a === 'rejected') setMark(s, a);
        else if (a === 'why') askReason(s);
        else if (a === 'pin') { sel = s; pinFor = s; schedule(true); }
        else if (a === 'remove') removeFromCanvas(s);
        else { sel = s; connect = { from: s, kind: a }; schedule(true); }
        return true;
      },
    });
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
    const m = routeMid(route(e.pa, e.pb));
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
      if (b.dataset.z === 'in') stepZoom(1);
      else if (b.dataset.z === 'out') stepZoom(-1);
      else if (b.dataset.z === 'reset') zoomAt(1, null, null, true);
      else fit(true);
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
        // Group by arranges the canvas into those groups (undo puts it back).
        undoStack.push(JSON.stringify(doc));
        doc.groupBy = g.dataset.group; saveDoc(); renderMenus();
        els.controls.querySelectorAll('.lc-menu').forEach(m => { m.hidden = true; });
        sel = null; relayoutAnim(); layout(); fit(true);
      }
    });
    els.controls.addEventListener('change', (e) => {
      const t = e.target;
      if (t.dataset.sim) { layers.sim[t.dataset.sim] = t.checked; }
      if (t.dataset.sim && t.dataset.sim !== 'always') markLayout();
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
          change(() => { doc.links.push({ id: uid(), a: g.anchor, b: g.slug, kind: 'related', label: g.shared[0] || '', source: 'maybe' }); });
          const an = nodes.get(g.anchor);
          addToCanvas([g.slug], an ? { x: an.x + W + 10, y: an.y + 10 } : null);
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
    els.selbar.addEventListener('keydown', (e) => {
      if (!e.target.matches('.lc-reason')) return;
      e.stopPropagation();
      if (e.key === 'Enter' || e.key === 'Escape') e.target.blur();
    });
    els.selbar.addEventListener('focusout', () => { setTimeout(() => { if (!els.selbar.contains(document.activeElement)) { reasonFor = null; schedule(true); } }, 0); });
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
    // Figma rules: two-finger scroll pans, pinch (ctrlKey on Chrome/Firefox,
    // gesture events on Safari) or ⌘/Ctrl + wheel zooms at the pointer.
    els.stage.addEventListener('wheel', (e) => {
      if (e.target.closest('.lc-note-text, .lc-det')) return;
      e.preventDefault();
      stopInertia();
      const r = stageRect();
      const unit = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? r.height : 1;
      let dx = e.deltaX * unit, dy = e.deltaY * unit;
      if (e.ctrlKey || e.metaKey) {
        // Trackpad pinch sends small fractional deltas; a mouse wheel sends big steps.
        const d = Math.max(-60, Math.min(60, dy));
        zoomAt(view.k * Math.exp(-d * (e.ctrlKey && Math.abs(dy) < 50 ? 0.012 : 0.006)), e.clientX - r.left, e.clientY - r.top);
      } else {
        if (e.shiftKey && !dx) { dx = dy; dy = 0; }
        stopTween();
        view.x -= dx; view.y -= dy; gesture(); schedule();
      }
    }, { passive: false });
    // ---- Pinch (touch) and Safari trackpad pinch ----
    // One owner per gesture. A two-finger pinch cancels whatever the first
    // finger started (pan, card drag) and computes the camera from the state
    // at pinch start, so the world point between your fingers stays between
    // them: no drift, no fighting handlers. Safari also fires gesture events
    // for touch pinches; those are ignored while fingers are down.
    els.stage.addEventListener('pointerdown', (e) => {
      if (e.pointerType !== 'touch') return;
      stopInertia();
      touchPts.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (touchPts.size === 2) {
        if (active) active.cancel();
        stopTween();
        stageBox = null;
        const [a, b] = [...touchPts.values()], r = stageRect();
        const c = { x: (a.x + b.x) / 2 - r.left, y: (a.y + b.y) / 2 - r.top };
        pinch = { d: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)), k: view.k, wx: (c.x - view.x) / view.k, wy: (c.y - view.y) / view.k };
        els.stage.classList.add('is-panning');
      }
    }, true);
    window.addEventListener('pointermove', (e) => {
      if (!touchPts.has(e.pointerId)) return;
      touchPts.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (!pinch || touchPts.size < 2) return;
      const [a, b] = [...touchPts.values()], r = stageRect();
      const cx = (a.x + b.x) / 2 - r.left, cy = (a.y + b.y) / 2 - r.top;
      const k = Math.max(MIN_K, Math.min(MAX_K, pinch.k * Math.hypot(a.x - b.x, a.y - b.y) / pinch.d));
      view.k = k; view.x = cx - pinch.wx * k; view.y = cy - pinch.wy * k;
      gesture(); schedule();
    }, { passive: true });
    const touchUp = (e) => {
      if (!touchPts.delete(e.pointerId)) return;
      if (touchPts.size < 2 && pinch) { pinch = null; els.stage.classList.remove('is-panning'); }
    };
    window.addEventListener('pointerup', touchUp);
    window.addEventListener('pointercancel', touchUp);
    let gp = null;
    els.stage.addEventListener('gesturestart', (e) => {
      e.preventDefault();
      if (touchPts.size) { gp = null; return; }
      stopTween(); stageBox = null;
      const r = stageRect(), cx = e.clientX - r.left, cy = e.clientY - r.top;
      gp = { k: view.k, cx, cy, wx: (cx - view.x) / view.k, wy: (cy - view.y) / view.k };
    }, { passive: false });
    els.stage.addEventListener('gesturechange', (e) => {
      e.preventDefault();
      if (!gp || touchPts.size) return;
      const k = Math.max(MIN_K, Math.min(MAX_K, gp.k * e.scale));
      view.k = k; view.x = gp.cx - gp.wx * k; view.y = gp.cy - gp.wy * k;
      gesture(); schedule();
    }, { passive: false });
    els.stage.addEventListener('gestureend', (e) => { e.preventDefault(); gp = null; }, { passive: false });
    // Page zoom never starts from the canvas or its controls.
    els.root.addEventListener('gesturestart', (e) => e.preventDefault(), { passive: false });
    if (window.visualViewport) visualViewport.addEventListener('resize', () => { stageBox = null; });

    els.stage.addEventListener('click', (e) => {
      const b = e.target.closest('[data-info]'); if (!b) return;
      e.stopPropagation();
      const el = b.closest('.lc-card'); const n = el && nodes.get(el.dataset.slug);
      if (!n) return;
      if (openDet.has(n.slug)) toggleDet(el, n, false); else openReadable(el, n);
      sel = openDet.has(n.slug) ? n.slug : (sel === n.slug ? null : sel);
      schedule(true);
    });
    els.stage.addEventListener('contextmenu', (e) => {
      const s = hitSlug(e);
      e.preventDefault(); e.stopPropagation();   // the grid's menu handler would close it
      if (!s || connect || pinFor) { App.closeCardMenu && App.closeCardMenu(); return; }
      // Press-and-hold on touch already opened it from the pointer handler.
      if (lastPointer !== 'mouse') return;
      openMenu(s, e.clientX, e.clientY);
    });
    els.stage.addEventListener('pointerenter', () => { overCanvas = true; });
    els.stage.addEventListener('pointerleave', () => { overCanvas = false; });
    els.stage.addEventListener('pointerdown', onDown);
    els.stage.addEventListener('pointermove', (e) => {
      if (e.buttons) return;
      const cs = moving ? hover : hitSlug(e);
      const nt = e.target.closest('.lc-note');
      const g = e.target.closest('.lc-ghost');
      const s = cs || (nt ? nt.dataset.note : null);
      const gs = g ? g.dataset.ghost : null;
      if (s !== hover || gs !== hoverGhost) { hover = s; hoverGhost = gs; schedule(); }
    });
    els.stage.addEventListener('pointerleave', () => { if (hover) { hover = null; schedule(); } });
    els.stage.addEventListener('dblclick', (e) => {
      // Double-click a group's name to rename it.
      const w = screenToWorld(e.clientX, e.clientY);
      const hs = hitSlug(e);
      if (hs) { App.openItem(hs); return; }
      if (e.target.closest('.lc-note, .lc-ghost, .lc-selbar, input')) return;
      const r = stageRect();
      els.create._at = screenToWorld(e.clientX, e.clientY);
      els.create.hidden = false;
      els.create.style.transform = `translate(${e.clientX - r.left}px,${e.clientY - r.top}px)`;
    });

    // Keys (canvas view only; fields keep their own keys).
    window.addEventListener('keydown', (e) => {
      if (mode === 'grid') return;
      // Split: the canvas takes keys only while you are working in it.
      if (mode === 'split' && !overCanvas && !els.root.contains(document.activeElement)) return;
      if (e.target && e.target.matches && e.target.matches('input, textarea, [contenteditable="true"]')) return;
      if (document.querySelector('.modal-overlay:not([hidden]), .settings-modal.open')) return;
      if (e.code === 'Space') { spaceDown = true; els.stage.classList.add('is-hand'); if (e.target === els.stage || e.target === document.body) e.preventDefault(); return; }
      let handled = true;
      if ((e.key === 'z' || e.key === 'Z') && (e.metaKey || e.ctrlKey)) undo();
      else if (e.key === '+' || e.key === '=') stepZoom(1);
      else if (e.key === '-' || e.key === '_') stepZoom(-1);
      else if (e.key === '0' || e.key === ')' || e.code === 'Digit0') zoomAt(1, null, null, true);
      else if (e.code === 'Digit1' && e.shiftKey) fit(true);
      else if (e.code === 'Digit2' && e.shiftKey) fitSelection();
      else if (e.key.startsWith('Arrow') && !sel) { const d = e.shiftKey ? 400 : 80; flyTo({ ...view, x: view.x + (e.key === 'ArrowLeft' ? d : e.key === 'ArrowRight' ? -d : 0), y: view.y + (e.key === 'ArrowUp' ? d : e.key === 'ArrowDown' ? -d : 0) }, 160); }
      else if (e.key === 'Escape') { sel = null; selNote = null; connect = null; pinFor = null; els.create.hidden = true; renderNotes(); schedule(true); }
      else if (e.key === 'Enter' && sel) App.openItem(sel);
      else if ((e.key === 'ContextMenu' || (e.shiftKey && e.key === 'F10')) && sel && rendered.get(sel)) { const b = rendered.get(sel).getBoundingClientRect(); openMenu(sel, b.left + 16, b.top + 16); }
      else if ((e.key === 'Backspace' || e.key === 'Delete') && sel && !selNote) removeFromCanvas(sel);
      else if ((e.key === 'Backspace' || e.key === 'Delete') && selNote) {
        const id = selNote; selNote = null;
        change(() => { doc.notes = doc.notes.filter(n => n.id !== id); doc.links = doc.links.filter(l => l.a !== id && l.b !== id); });
        renderNotes();
      } else handled = false;
      if (handled) { e.preventDefault(); e.stopImmediatePropagation(); }
    }, true);
    window.addEventListener('keyup', (e) => { if (e.code === 'Space') { spaceDown = false; els.stage.classList.remove('is-hand'); } });
    // The stage changed size (split <-> canvas, panel, rotation): keep what was
    // in the middle in the middle, instead of letting the view jump.
    let lastSize = null;
    new ResizeObserver(() => {
      stageBox = null;
      const r = stageRect();
      if (!r.width) return;
      if (lastSize && camSet) { view.x += (r.width - lastSize.w) / 2; view.y += (r.height - lastSize.h) / 2; }
      lastSize = { w: r.width, h: r.height };
      schedule();
    }).observe(els.stage);
    window.addEventListener('resize', () => { stageBox = null; });
    new MutationObserver(() => { readTheme(); schedule(true); }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-accent'] });

    // The grid re-rendered (search, filters, new saves): follow it.
    // Only when the set of items actually changed, not on every grid reflow.
    let sig = '';
    document.addEventListener('stello:results', () => {
      const list = App.filtered ? App.filtered() : [];
      const next = list.length + ':' + list.map(i => i.slug).join(',');
      if (mode !== 'grid') markGrid();
      if (next === sig) return;
      sig = next;
    });
  }

  // A card under the pointer: its element, or (when cards are painted on the
  // canvas because too many are in view) the node under that point.
  function hitSlug(e) {
    const c = e.target.closest && e.target.closest('.lc-card');
    if (c) return c.dataset.slug;
    if (!lastBlocks || !e.target.closest('.lc-stage') || e.target.closest('.lc-note, .lc-ghost, .lc-selbar')) return null;
    const w = screenToWorld(e.clientX, e.clientY);
    const hit = inRect(w.x - 1, w.y - 1, w.x + 1, w.y + 1);
    return hit.length ? hit[hit.length - 1] : null;
  }
  function onDown(e) {
    lastPointer = e.pointerType;
    if (e.pointerType === 'touch' && (!e.isPrimary || touchPts.size > 1)) return;
    stopInertia();
    if (e.target.closest('input, button, a, [contenteditable="true"], .lc-selbar, .lc-create')) return;
    const sx = e.clientX, sy = e.clientY;
    const cardSlug = hitSlug(e);
    const card = cardSlug ? { dataset: { slug: cardSlug } } : null;
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
      stopTween();
      const vx = view.x, vy = view.y;
      let moved = false;
      const samples = [];
      els.stage.classList.add('is-panning');
      return track(e, (ev) => {
        if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < (e.pointerType === 'touch' ? 6 : 3)) return;
        moved = true;
        view.x = vx + ev.clientX - sx; view.y = vy + ev.clientY - sy;
        samples.push({ t: ev.timeStamp, x: ev.clientX, y: ev.clientY }); if (samples.length > 6) samples.shift();
        gesture(); schedule();
      }, (ev) => {
        els.stage.classList.remove('is-panning');
        if (!moved && (sel || selNote || openDet.size)) { sel = null; selNote = null; closeAllDet(); renderNotes(); schedule(true); }
        if (moved && e.pointerType === 'touch' && samples.length > 1) {
          const a = samples[0], b = samples[samples.length - 1], dt = b.t - a.t;
          if (dt > 0 && ev.timeStamp - b.t < 60) glide((b.x - a.x) / dt, (b.y - a.y) / dt);
        }
      }, () => { els.stage.classList.remove('is-panning'); });
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
      return track(e, (ev) => {
        if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 4) return;
        if (!moved) { moved = true; snap = JSON.stringify(doc); }
        n.x = Math.round(ox + (ev.clientX - sx) / view.k); n.y = Math.round(oy + (ev.clientY - sy) / view.k);
        note.style.transform = `translate(${n.x}px,${n.y}px)`;
        schedule();
      }, () => {
        if (moved) { undoStack.push(snap); saveDoc(); }
        renderNotes(); schedule(true);
        if (!moved) { const t = els.notes.querySelector(`[data-note="${n.id}"] .lc-note-text`); if (t) t.focus(); }
      }, () => { n.x = ox; n.y = oy; renderNotes(); schedule(true); });
    }

    // Card: select; drag moves it (remembered for this grouping).
    if (card) {
      e.preventDefault();
      const s = card.dataset.slug;
      const n = nodes.get(s);
      selNote = null;
      const ox = n.x, oy = n.y;
      let moved = false, snap = null, held = false;
      // Touch and pen: press and hold opens the card menu (mouse: right-click).
      let hold = e.pointerType !== 'mouse' ? setTimeout(() => { hold = 0; if (!moved) { held = true; openMenu(s, sx, sy); } }, 500) : 0;
      return track(e, (ev) => {
        if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < (e.pointerType === 'touch' ? 8 : 4)) return;
        if (held) return;
        if (hold) { clearTimeout(hold); hold = 0; }
        if (!moved) { App.closeCardMenu && App.closeCardMenu(); moved = true; snap = JSON.stringify(doc); els.root.classList.add('is-moving'); sel = s; dragging = s; }
        n.x = Math.round(ox + (ev.clientX - sx) / view.k); n.y = Math.round(oy + (ev.clientY - sy) / view.k);
        near = nearOf(n);
        suggest = suggestOf(n);
        if (families[n.fam]) famBox(families[n.fam]);
        schedule();
      }, () => {
        if (hold) { clearTimeout(hold); hold = 0; }
        els.root.classList.remove('is-moving');
        dragging = null; near = [];
        const sug = suggest; suggest = null;
        if (moved) {
          undoStack.push(snap);
          const c = cardRecMake(s); c.x = n.x; c.y = n.y; c.by = doc.groupBy;
          if (sug) acceptSuggest(n, sug); else refamily(n);
          saveDoc(); rebuildHash();
        } else if (!held) {
          // A click opens the card in place to show its details; again closes it.
          const el = rendered.get(s);
          const open = !openDet.has(s);
          if (el) { if (open) openReadable(el, n); else toggleDet(el, n, false); }
          sel = open ? s : (sel === s ? null : sel);
        }
        renderNotes();
        schedule(true);
      }, () => {
        // A second finger landed: this was the start of a pinch, not a drag.
        if (hold) { clearTimeout(hold); hold = 0; }
        els.root.classList.remove('is-moving');
        dragging = null; near = []; suggest = null;
        n.x = ox; n.y = oy;
        if (families[n.fam]) famBox(families[n.fam]);
        schedule(true);
      });
    }
  }
  // Dragged close to another item (or a family): offer a group, shown as a
  // dotted rectangle around what would be grouped. Dropping accepts it.
  const SNAP_GAP = 56;
  function suggestOf(n) {
    let best = null;
    inRect(n.x - SNAP_GAP, n.y - SNAP_GAP, n.x + W + SNAP_GAP, n.y + n.h + SNAP_GAP).forEach(b => {
      if (b === n.slug) return;
      const m = nodes.get(b);
      const gx = Math.max(0, Math.max(m.x - (n.x + W), n.x - (m.x + W)));
      const gy = Math.max(0, Math.max(m.y - (n.y + n.h), n.y - (m.y + m.h)));
      const g = Math.hypot(gx, gy);
      if (g <= SNAP_GAP && (!best || g < best.g)) best = { b, g, m };
    });
    if (!best) return null;
    const fam = families[best.m.fam];
    const same = fam && !fam.loose && best.m.fam === n.fam;
    if (same) return null;
    const members = fam && !fam.loose ? fam.slugs.filter(x => x !== n.slug) : [best.b];
    const all = [...members, n.slug];
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    all.forEach(x => { const q = nodes.get(x); x0 = Math.min(x0, q.x); y0 = Math.min(y0, q.y); x1 = Math.max(x1, q.x + W); y1 = Math.max(y1, q.y + q.h); });
    let name = fam && !fam.loose ? cap(fam.tag) : null;
    if (!name) { const sh = similarityScore(n.item, best.m.item).shared; name = sh[0] ? cap(sh[0]) : 'New group'; }
    return { slugs: all, box: { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }, name, fam: fam && !fam.loose ? best.m.fam : -1, with: best.b, joining: !!(fam && !fam.loose) };
  }
  function acceptSuggest(n, sg) {
    const cur = families[n.fam];
    if (cur) { cur.slugs = cur.slugs.filter(x => x !== n.slug); famBox(cur); }
    let f = families[sg.fam];
    if (f) {
      // Joining a family: it becomes one of your groups, named as it was.
      let g = f.gid && doc.groups.find(x => x.id === f.gid);
      if (!g) { g = { id: uid(), name: sg.name, slugs: [...f.slugs] }; doc.groups.push(g); f.gid = g.id; f.type = 'user'; f.color = 'accent'; f.tag = sg.name; }
      if (!g.slugs.includes(n.slug)) g.slugs.push(n.slug);
      f.slugs.push(n.slug); n.fam = sg.fam;
    } else {
      const other = nodes.get(sg.with), of = families[other.fam];
      if (of) { of.slugs = of.slugs.filter(x => x !== sg.with); famBox(of); }
      const g = { id: uid(), name: sg.name, slugs: [sg.with, n.slug] };
      doc.groups.push(g);
      families.push({ cl: other.cl, tag: sg.name, type: 'user', color: 'accent', gid: g.id, slugs: [sg.with, n.slug], box: null });
      n.fam = other.fam = families.length - 1;
      f = families[n.fam];
    }
    famBox(f);
    App.toast(sg.joining ? `Added to ${sg.name}` : `Grouped as ${sg.name}`);
  }
  // While dragging: related items within reach, nearer ones first.
  function nearOf(n) {
    const out = [];
    const cx = n.x + W / 2, cy = n.y + n.ch / 2;
    inRect(n.x - NEAR, n.y - NEAR, n.x + W + NEAR, n.y + n.h + NEAR).forEach(b => {
      if (b === n.slug) return;
      const m = nodes.get(b);
      const d = Math.max(0, Math.hypot(m.x + W / 2 - cx, m.y + m.ch / 2 - cy) - W);
      if (d > NEAR) return;
      const fa = featOf.get(n.slug) || [], fb = new Set((featOf.get(b) || []).map(x => x.f));
      let s = 0, best = null;
      fa.forEach(x => { if (layers.sim[x.type] && fb.has(x.f)) { const w = SIM[x.type].w; s += w; if (!best || w > SIM[best.type].w) best = x; } });
      if (s >= 1.4) out.push({ b, s, d, type: best.type, label: best.tag });
    });
    return out.sort((a, b) => (b.s - b.d / 300) - (a.s - a.d / 300)).slice(0, 10);
  }
  // Follow one pointer until it lifts. Moves from other pointers are ignored;
  // a pinch (or pointercancel) calls `cancel` instead of `up`.
  function track(e, move, up, cancel) {
    const id = e.pointerId;
    const m = (ev) => { if (ev.pointerId === id) move(ev); };
    const stop = () => {
      window.removeEventListener('pointermove', m);
      window.removeEventListener('pointerup', u);
      window.removeEventListener('pointercancel', c);
      if (active && active.id === id) active = null;
    };
    const u = (ev) => { if (ev.pointerId !== id) return; stop(); up && up(ev); };
    const c = (ev) => { if (ev.pointerId !== id) return; stop(); cancel ? cancel() : up && up(ev); };
    window.addEventListener('pointermove', m);
    window.addEventListener('pointerup', u);
    window.addEventListener('pointercancel', c);
    active = { id, cancel: () => { stop(); cancel && cancel(); } };
  }
  function stopInertia() { if (inertia) { cancelAnimationFrame(inertia); inertia = 0; } }
  // A flicked touch pan keeps gliding and slows down, like a native scroll view.
  function glide(vx, vy) {
    stopInertia();
    let last = performance.now();
    const step = (now) => {
      const dt = Math.min(32, now - last); last = now;
      view.x += vx * dt; view.y += vy * dt;
      const f = Math.pow(0.994, dt); vx *= f; vy *= f;
      gesture(); render();
      inertia = Math.hypot(vx, vy) > 0.02 ? requestAnimationFrame(step) : 0;
    };
    if (Math.hypot(vx, vy) > 0.15) inertia = requestAnimationFrame(step);
  }

  // ---------- Boot ----------
  function init() {
    App = window.StelloApp;
    if (!App) return;
    loadDoc();
    build();
    bind();
    bindFams();
    bindDoc();
    bindGridDrag();
    const q = new URLSearchParams(location.search).get('view');
    const start = q || localStorage.getItem(VIEW_KEY) || 'grid';
    setMode(start, { quiet: true });
    pullDoc();
    window.addEventListener('focus', () => { if (!dirty && !pushing) pullDoc(); });
    window.StelloCanvas = { setMode, addAuto, addMany, ownsTouchHold: () => mode === 'split' || (mode === 'grid' && isPhone()), has: (s) => !!cardRec(s), setReturn: (v) => localStorage.setItem(RETURN_KEY, v), focusOn, centerOn: (sx, sy, k) => { const w = screenToWorld(sx, sy); const r = stageRect(); view.k = k; view.x = r.width / 2 - w.x * k; view.y = r.height / 2 - w.y * k; schedule(); }, fit: () => fit(true), get view() { return view; }, zoomAt, stepZoom, flyTo, select: (s) => { sel = s; schedule(true); } };
  }
  if (window.StelloApp) init();
  else document.addEventListener('stello:ready', init, { once: true });
})();
