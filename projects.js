/* === Stello — Projects canvas ===
 *
 * A project is a board beside the library. The library grid, search and
 * filters stay on the left and are how you pick items: drag cards straight
 * onto the board, press + on a card, or Shift/⌘-click several and add them
 * together.
 *
 * The board is a real canvas: pan, zoom (pinch, ⌘/Ctrl-scroll, buttons, fit),
 * marquee and multi-select, snap to the dot grid, a minimap. Cards carry the
 * same facts as library cards (domain, kind, tags) and show more as you zoom.
 *
 * Arrangement and suggestions are rules only (shared tags, kind, source,
 * colour, links), never AI:
 *   - a placed card lands next to its most similar card, and its closest
 *     unplaced saves appear around it as ghosts you can keep with one click;
 *   - Tidy and Cluster (by topic, kind, source, colour) lay the board out
 *     in labelled groups;
 *   - quiet action chips read the board ("4 share typographic: Group",
 *     "UI SDK links 3 items: Arrange around", …).
 *
 * Intent: when you place or link, one optional inline line asks what it's
 * for. That answer is the item's intent for this project.
 *
 * Rendering scales with the screen: the board is one GPU-composited layer
 * (translate + scale) and only cards in view exist in the DOM.
 *
 * Storage (for now): this browser's localStorage, `stello.projects.v0`.
 */
(function () {
  'use strict';

  const STORE_KEY = 'stello.projects.v0';
  const OPEN_KEY = 'stello.projects.open';
  const CARD_W = 200;
  const SNAP = 24;
  const GAP = 24;
  const CULL = 300;               // screen px kept rendered around the view
  const MIN_K = 0.2, MAX_K = 2.5;
  const GHOSTS = 5;
  const TAG_SKIP = new Set(['color', 'intent', 'collection']);

  let App = null;
  let data = { projects: [], currentId: null };
  let view = { x: 0, y: 0, k: 1 };
  const els = {};
  const rendered = new Map();     // slug -> card element (in view only)
  const heights = new Map();      // `${slug}|${lod}` -> measured card height
  const sel = new Set();          // selected board cards
  const picked = new Set();       // library cards picked with Shift/⌘-click
  let ghosts = [];                // [{ slug, x, y, from }] related saves offered around a card
  let editing = null;             // { kind: 'card', slug } | { kind: 'link', id }
  let noteQueue = [];             // slugs to ask "what for" next
  let renderRaf = 0;
  let spaceDown = false;
  let lod = 1;

  // ---------- Store ----------
  function load() {
    try { data = JSON.parse(localStorage.getItem(STORE_KEY)) || data; } catch { /* default */ }
    if (!Array.isArray(data.projects)) data = { projects: [], currentId: null };
    data.projects.forEach(p => { p.groups = p.groups || []; p.links = p.links || []; p.dismissed = p.dismissed || []; });
  }
  function save() { localStorage.setItem(STORE_KEY, JSON.stringify(data)); }
  function current() { return data.projects.find(p => p.id === data.currentId) || null; }
  function uid() { return Math.random().toString(36).slice(2, 10); }
  const esc = (s) => App.esc(String(s == null ? '' : s));
  const cardOf = (p, slug) => p.cards.find(c => c.slug === slug);
  const onBoard = (slug) => { const p = current(); return !!(p && cardOf(p, slug)); };

  // ---------- Similarity (rules only) ----------
  function features(item) {
    const tags = new Set();
    (item.tags || []).forEach(t => { if (t.weight >= 0.5 && !TAG_SKIP.has(t.category)) tags.add(String(t.tag).toLowerCase()); });
    const col = (item.tags || []).filter(t => t.category === 'color').sort((a, b) => b.weight - a.weight)[0];
    return { tags, kind: item.kind && item.kind !== 'link' ? item.kind : null, domain: item.domain || null, color: col ? col.tag : null };
  }
  const featCache = new WeakMap();
  function feat(item) { let f = featCache.get(item); if (!f) { f = features(item); featCache.set(item, f); } return f; }
  function similarity(a, b) {
    const fa = feat(a), fb = feat(b);
    let s = 0;
    fa.tags.forEach(t => { if (fb.tags.has(t)) s += 1; });
    if (fa.domain && fa.domain === fb.domain) s += 1.5;
    if (fa.kind && fa.kind === fb.kind) s += 0.7;
    if (fa.color && fa.color === fb.color) s += 0.5;
    return s;
  }
  // One pass over the library: the closest saves to `item` that aren't on the board.
  function relatedTo(item, n) {
    const p = current();
    const out = [];
    for (const it of App.items()) {
      if (it.slug === item.slug || cardOf(p, it.slug)) continue;
      const s = similarity(item, it);
      if (s < 2.5) continue;
      out.push({ it, s });
    }
    out.sort((a, b) => b.s - a.s);
    return out.slice(0, n).map(o => o.it);
  }

  // ---------- Geometry ----------
  function coverH(item) {
    let r = 0.7;
    if (item && item.has_image && item.image_width && item.image_height) r = item.image_height / item.image_width;
    else if (item && !item.has_image) r = 0.6;
    return Math.round(CARD_W * Math.max(0.5, Math.min(1.25, r)));
  }
  const META_EST = [0, 72, 72];   // zooming in adds detail on the cover, never height
  function boxOf(c) {
    const item = App.item(c.slug);
    const h = heights.get(c.slug + '|' + lod) || (coverH(item) + META_EST[lod]);
    return { x: c.x, y: c.y, w: CARD_W, h, cx: c.x + CARD_W / 2, cy: c.y + h / 2 };
  }
  function overlaps(a, b, gap) {
    return a.x < b.x + b.w + gap && a.x + a.w + gap > b.x && a.y < b.y + b.h + gap && a.y + a.h + gap > b.y;
  }
  const snap = (v) => Math.round(v / SNAP) * SNAP;
  // Nearest free spot to (x, y) for a card of height h, searching outward on the snap grid.
  function findFree(x, y, h, skip) {
    const p = current();
    const boxes = p.cards.filter(c => !(skip && skip.has(c.slug))).map(boxOf)
      .concat(ghosts.map(g => ({ x: g.x, y: g.y, w: CARD_W, h: coverH(App.item(g.slug)) + META_EST[lod] })));
    const free = (bx, by) => !boxes.some(b => overlaps({ x: bx, y: by, w: CARD_W, h }, b, GAP - 1));
    x = snap(x); y = snap(y);
    if (free(x, y)) return { x, y };
    for (let r = 1; r < 60; r++) {
      const cand = [];
      for (let i = -r; i <= r; i++) {
        cand.push([x + i * SNAP, y - r * SNAP], [x + i * SNAP, y + r * SNAP], [x - r * SNAP, y + i * SNAP], [x + r * SNAP, y + i * SNAP]);
      }
      cand.sort((a, b) => Math.hypot(a[0] - x, a[1] - y) - Math.hypot(b[0] - x, b[1] - y));
      for (const [cx, cy] of cand) if (free(cx, cy)) return { x: cx, y: cy };
    }
    return { x, y };
  }
  function edgePoint(b, tx, ty) {
    const dx = tx - b.cx, dy = ty - b.cy;
    const sx = dx ? (b.w / 2 + 6) / Math.abs(dx) : Infinity;
    const sy = dy ? (b.h / 2 + 6) / Math.abs(dy) : Infinity;
    const k = Math.min(sx, sy, 1);
    return { x: b.cx + dx * k, y: b.cy + dy * k };
  }
  function screenToWorld(px, py) {
    const r = els.stage.getBoundingClientRect();
    return { x: (px - r.left - view.x) / view.k, y: (py - r.top - view.y) / view.k };
  }
  function worldToScreen(x, y) { return { x: x * view.k + view.x, y: y * view.k + view.y }; }
  function bounds(boxes) {
    if (!boxes.length) return null;
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    boxes.forEach(b => { x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y); x1 = Math.max(x1, b.x + b.w); y1 = Math.max(y1, b.y + b.h); });
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  }

  // ---------- DOM ----------
  const IC = {
    minus: '<svg viewBox="0 0 256 256" fill="currentColor"><path d="M224,128a8,8,0,0,1-8,8H40a8,8,0,0,1,0-16H216A8,8,0,0,1,224,128Z"/></svg>',
    fit: '<svg viewBox="0 0 256 256" fill="currentColor"><path d="M216,48V88a8,8,0,0,1-16,0V56H168a8,8,0,0,1,0-16h40A8,8,0,0,1,216,48ZM88,200H56V168a8,8,0,0,0-16,0v40a8,8,0,0,0,8,8H88a8,8,0,0,0,0-16Zm120-40a8,8,0,0,0-8,8v32H168a8,8,0,0,0,0,16h40a8,8,0,0,0,8-8V168A8,8,0,0,0,208,160ZM88,40H48a8,8,0,0,0-8,8V88a8,8,0,0,0,16,0V56H88a8,8,0,0,0,0-16Z"/></svg>',
    caret: '<svg viewBox="0 0 256 256" fill="currentColor"><path d="M213.66,101.66l-80,80a8,8,0,0,1-11.32,0l-80-80A8,8,0,0,1,53.66,90.34L128,164.69l74.34-74.35a8,8,0,0,1,11.32,11.32Z"/></svg>',
    check: '<svg viewBox="0 0 256 256" fill="currentColor"><path d="M229.66,77.66l-128,128a8,8,0,0,1-11.32,0l-56-56a8,8,0,0,1,11.32-11.32L96,188.69,218.34,66.34a8,8,0,0,1,11.32,11.32Z"/></svg>',
  };

  function build() {
    const layout = document.querySelector('.main-layout');
    const root = document.createElement('section');
    root.className = 'canvas-view';
    root.hidden = true;
    root.setAttribute('aria-label', 'Project board');
    root.innerHTML = `
      <div class="canvas-stage" tabindex="0">
        <div class="canvas-world">
          <div class="canvas-frames"></div>
          <svg class="canvas-links" width="1" height="1" overflow="visible" aria-hidden="true"></svg>
          <div class="canvas-ghosts"></div>
          <div class="canvas-cards"></div>
          <div class="canvas-labels"></div>
        </div>
        <div class="canvas-chips"></div>
        <div class="canvas-marquee" hidden></div>
        <div class="canvas-empty" hidden>
          <div class="canvas-empty-title">Drag cards here from your library</div>
          <div class="canvas-empty-text">Or press + on a card, or Shift-click several and add them together. Related saves gather around what you place.</div>
        </div>
      </div>

      <header class="canvas-header">
        <button type="button" class="canvas-title" aria-haspopup="true" aria-expanded="false">
          <span class="canvas-title-text"></span><sup class="canvas-title-count"></sup>
          <span class="canvas-caret" aria-hidden="true">${IC.caret}</span>
        </button>
        <div class="canvas-menu" role="menu" hidden></div>
      </header>
      <button type="button" class="canvas-close" title="Close board" aria-label="Close board">${App.icon('x')}</button>

      <div class="canvas-toolbar" role="toolbar" aria-label="Board tools">
        <div class="tb-group">
          <button type="button" class="tb-btn" data-act="zoom-out" title="Zoom out (−)" aria-label="Zoom out">${IC.minus}</button>
          <button type="button" class="tb-btn tb-zoom" data-act="zoom-reset" title="Reset to 100% (0)">100%</button>
          <button type="button" class="tb-btn" data-act="zoom-in" title="Zoom in (+)" aria-label="Zoom in">${App.icon('plus')}</button>
          <button type="button" class="tb-btn" data-act="fit" title="Fit board (Shift 1)" aria-label="Fit board">${IC.fit}</button>
        </div>
        <div class="tb-group">
          <button type="button" class="tb-btn tb-text" data-act="tidy" title="Lay out groups and loose cards neatly">Tidy</button>
          <div class="tb-drop">
            <button type="button" class="tb-btn tb-text" data-act="cluster" aria-haspopup="true">Cluster<span class="tb-caret">${IC.caret}</span></button>
            <div class="tb-menu" hidden>
              <button type="button" data-by="topic">By topic</button>
              <button type="button" data-by="kind">By kind</button>
              <button type="button" data-by="domain">By source</button>
              <button type="button" data-by="color">By colour</button>
            </div>
          </div>
          <button type="button" class="tb-btn tb-text" data-act="export" title="Download the board as a Markdown brief">Export</button>
        </div>
      </div>

      <div class="canvas-pickbar" hidden>
        <span class="pickbar-count"></span>
        <button type="button" class="pickbar-add">Add to board</button>
        <button type="button" class="pickbar-clear">Clear</button>
      </div>

      <canvas class="canvas-minimap" width="176" height="112" aria-label="Minimap"></canvas>

      <div class="canvas-start" hidden>
        <div class="canvas-start-card">
          <div class="canvas-start-title">Start a project</div>
          <p class="canvas-start-text">A board beside your library. Drag saves in, link them, and say what each is for. Stello gathers related saves and suggests how to group them.</p>
          <form class="canvas-start-form">
            <input type="text" class="canvas-start-input" placeholder="Project name, e.g. Café rebrand" maxlength="60" aria-label="Project name" required>
            <button type="submit" class="canvas-start-btn">Create</button>
          </form>
          <button type="button" class="canvas-start-cancel" hidden>Cancel</button>
        </div>
      </div>
    `;
    layout.insertBefore(root, document.getElementById('panels-container'));
    const q = (s) => root.querySelector(s);
    Object.assign(els, {
      root, stage: q('.canvas-stage'), world: q('.canvas-world'), frames: q('.canvas-frames'),
      links: q('.canvas-links'), ghosts: q('.canvas-ghosts'), cards: q('.canvas-cards'), labels: q('.canvas-labels'),
      chips: q('.canvas-chips'), marquee: q('.canvas-marquee'), empty: q('.canvas-empty'),
      title: q('.canvas-title'), titleText: q('.canvas-title-text'), titleCount: q('.canvas-title-count'), menu: q('.canvas-menu'),
      zoomLabel: q('.tb-zoom'), clusterMenu: q('.tb-menu'), pickbar: q('.canvas-pickbar'), pickCount: q('.pickbar-count'),
      minimap: q('.canvas-minimap'), start: q('.canvas-start'), startForm: q('.canvas-start-form'),
      startInput: q('.canvas-start-input'), startCancel: q('.canvas-start-cancel'),
    });

    // Library side: one floating "+" over the hovered grid card, and a style
    // sheet that marks cards already on the board / picked for adding.
    els.gridAdd = document.createElement('button');
    els.gridAdd.type = 'button';
    els.gridAdd.className = 'grid-add-btn';
    els.gridAdd.hidden = true;
    document.body.appendChild(els.gridAdd);
    els.gridStyle = document.createElement('style');
    document.head.appendChild(els.gridStyle);
  }

  // ---------- Open / close ----------
  function open() {
    els.root.hidden = false;
    document.documentElement.classList.add('canvas-open');
    document.getElementById('projects-btn')?.classList.add('is-active');
    localStorage.setItem(OPEN_KEY, '1');
    requestAnimationFrame(() => (current() ? showProject() : showStart(false)));
  }
  function close() {
    els.root.hidden = true;
    document.documentElement.classList.remove('canvas-open');
    document.getElementById('projects-btn')?.classList.remove('is-active');
    localStorage.removeItem(OPEN_KEY);
    picked.clear();
    els.gridAdd.hidden = true;
    paintGridMarks();
  }
  function showStart(cancellable) {
    els.start.hidden = false;
    els.startCancel.hidden = !cancellable;
    els.startInput.value = '';
    setTimeout(() => els.startInput.focus(), 30);
  }
  function createProject(name) {
    const p = { id: uid(), name: name.trim(), createdAt: new Date().toISOString(), cards: [], links: [], groups: [], dismissed: [] };
    data.projects.unshift(p);
    data.currentId = p.id;
    save();
    els.start.hidden = true;
    showProject();
  }
  function showProject() {
    const p = current();
    if (!p) return showStart(false);
    els.start.hidden = true;
    els.titleText.textContent = p.name;
    sel.clear(); ghosts = []; editing = null;
    rendered.forEach(el => el.remove());
    rendered.clear();
    if (p.cards.length) fit(false); else { const r = els.stage.getBoundingClientRect(); view = { x: r.width * 0.25, y: r.height * 0.3, k: 1 }; }
    render();
    paintGridMarks();
  }

  // ---------- Rendering ----------
  function schedule() {
    if (renderRaf) return;
    renderRaf = requestAnimationFrame(() => { renderRaf = 0; render(); });
  }
  function lodFor(k) { return k < 0.45 ? 0 : k < 1.2 ? 1 : 2; }

  function render() {
    const p = current();
    if (!p || els.root.hidden) return;
    const newLod = lodFor(view.k);
    if (newLod !== lod) {
      lod = newLod;
      els.stage.dataset.lod = String(lod);
    }
    els.world.style.transform = `translate3d(${view.x}px, ${view.y}px, 0) scale(${view.k})`;
    const dot = SNAP * view.k;
    els.stage.style.backgroundSize = `${dot}px ${dot}px`;
    els.stage.style.backgroundPosition = `${view.x}px ${view.y}px`;
    els.stage.classList.toggle('dots-off', dot < 8);
    els.zoomLabel.textContent = Math.round(view.k * 100) + '%';
    els.titleCount.textContent = p.cards.length ? String(p.cards.length) : '';
    els.empty.hidden = p.cards.length > 0 || ghosts.length > 0;

    // Cards in view only.
    const r = els.stage.getBoundingClientRect();
    const w0 = screenToWorld(r.left - CULL, r.top - CULL), w1 = screenToWorld(r.right + CULL, r.bottom + CULL);
    const keep = new Set();
    p.cards.forEach(c => {
      const b = boxOf(c);
      if (b.x + b.w < w0.x || b.x > w1.x || b.y + b.h < w0.y || b.y > w1.y) return;
      keep.add(c.slug);
      let el = rendered.get(c.slug);
      if (!el) {
        el = cardEl(c);
        if (!el) return;
        rendered.set(c.slug, el);
        els.cards.appendChild(el);
      }
      el.style.transform = `translate3d(${c.x}px, ${c.y}px, 0)`;
      el.classList.toggle('is-selected', sel.has(c.slug));
    });
    rendered.forEach((el, slug) => { if (!keep.has(slug)) { el.remove(); rendered.delete(slug); } });
    measure();
    renderGhosts();
    renderFrames(p);
    renderLinks(p);
    renderChips(p);
    drawMinimap(p);
  }

  // Heights depend on zoom detail and text; measure once per card per detail level.
  function measure() {
    let changed = false;
    rendered.forEach((el, slug) => {
      const key = slug + '|' + lod;
      if (heights.has(key)) return;
      const h = el.offsetHeight;
      if (h) { heights.set(key, h); changed = true; }
    });
    return changed;
  }
  function forgetHeight(slug) { [0, 1, 2].forEach(l => heights.delete(slug + '|' + l)); }

  function cardEl(c) {
    const item = App.item(c.slug);
    if (!item) return null;
    const el = document.createElement('div');
    el.className = 'cv-card';
    el.dataset.slug = c.slug;
    fillCard(el, c, item);
    return el;
  }
  function fillCard(el, c, item) {
    const link = App.displayLink(item);
    const kind = App.kindLine(item);
    const tags = App.visibleTags(item).sort((a, b) => b.weight - a.weight).slice(0, 5);
    const isEditing = editing && editing.kind === 'card' && editing.slug === c.slug;
    el.innerHTML = `
      <div class="cv-cover" style="height:${coverH(item)}px">${App.thumbHTML(item)}<div class="cv-tags">${tags.map(t => `<span class="cv-tag">${esc(t.tag)}</span>`).join('')}</div></div>
      <div class="cv-meta">
        <div class="cv-title">${esc(item.title || item.slug)}</div>
        <div class="cv-facts"><span class="cv-kind" aria-hidden="true">${App.glyphSVG(item)}</span>${link ? `<a class="cv-link" href="${esc(item.source_url || '#')}" target="_blank" rel="noopener">${esc(link)}</a>` : ''}${kind ? `<span class="cv-kindline">${esc(kind)}</span>` : ''}</div>
        ${isEditing
          ? `<input class="cv-note-input" type="text" maxlength="80" placeholder="What’s this here for?" value="${esc(c.note || '')}" aria-label="What’s this here for?">`
          : `<button type="button" class="cv-note${c.note ? '' : ' is-empty'}">${c.note ? esc(c.note) : 'What’s it for?'}</button>`}
      </div>
      <span class="cv-handle" title="Drag to link" aria-hidden="true"></span>`;
    if (isEditing) bindNoteInput(el.querySelector('.cv-note-input'), c.slug);
  }
  function refreshCard(slug) {
    const p = current();
    const el = rendered.get(slug);
    const c = cardOf(p, slug);
    if (el && c) { fillCard(el, c, App.item(slug)); forgetHeight(slug); }
  }

  function renderGhosts() {
    els.ghosts.innerHTML = ghosts.map(g => {
      const item = App.item(g.slug);
      if (!item) return '';
      const link = App.displayLink(item);
      return `<div class="cv-card cv-ghost" data-ghost="${esc(g.slug)}" style="transform:translate3d(${g.x}px, ${g.y}px, 0)">
        <div class="cv-cover" style="height:${coverH(item)}px">${App.thumbHTML(item)}</div>
        <div class="cv-meta">
          <div class="cv-title">${esc(item.title || item.slug)}</div>
          <div class="cv-facts"><span class="cv-kind" aria-hidden="true">${App.glyphSVG(item)}</span>${link ? `<span class="cv-link">${esc(link)}</span>` : ''}</div>
          <div class="cv-why">${esc(g.why)}</div>
        </div>
        <button type="button" class="cv-ghost-add">${App.icon('plus')}<span>Add</span></button>
      </div>`;
    }).join('');
  }

  function renderFrames(p) {
    els.frames.innerHTML = p.groups.map(g => {
      const boxes = g.slugs.map(s => cardOf(p, s)).filter(Boolean).map(boxOf);
      const b = bounds(boxes);
      if (!b) return '';
      const pad = 20;
      return `<div class="cv-frame" data-group="${g.id}" style="transform:translate3d(${b.x - pad}px, ${b.y - pad}px, 0);width:${b.w + pad * 2}px;height:${b.h + pad * 2}px">
        <button type="button" class="cv-frame-label" data-group="${g.id}">${esc(g.name)}<span>${boxes.length}</span></button>
      </div>`;
    }).join('');
  }

  function renderLinks(p) {
    let lines = '', labels = '';
    p.links.forEach(l => {
      const a = cardOf(p, l.a), b = cardOf(p, l.b);
      if (!a || !b) return;
      const A = boxOf(a), B = boxOf(b);
      const p1 = edgePoint(A, B.cx, B.cy), p2 = edgePoint(B, A.cx, A.cy);
      const hot = sel.has(l.a) || sel.has(l.b);
      lines += `<line class="${hot ? 'is-hot' : ''}" x1="${p1.x}" y1="${p1.y}" x2="${p2.x}" y2="${p2.y}"/>`;
      const mx = (p1.x + p2.x) / 2, my = (p1.y + p2.y) / 2;
      const isEditing = editing && editing.kind === 'link' && editing.id === l.id;
      labels += isEditing
        ? `<input class="cv-link-input" data-link="${l.id}" type="text" maxlength="60" placeholder="How do these connect?" value="${esc(l.label || '')}" style="transform:translate3d(${mx}px, ${my}px, 0) translate(-50%, -50%)">`
        : `<button type="button" class="cv-link-label${l.label ? '' : ' is-empty'}" data-link="${l.id}" style="transform:translate3d(${mx}px, ${my}px, 0) translate(-50%, -50%)" title="${l.label ? 'Edit' : 'Say how these connect'}">${l.label ? esc(l.label) : '+'}</button>`;
    });
    els.links.innerHTML = lines + '<line class="cv-draft" x1="0" y1="0" x2="0" y2="0" style="display:none"/>';
    // Keep a focused link input alive across re-renders.
    const focused = document.activeElement && document.activeElement.classList.contains('cv-link-input') ? document.activeElement.dataset.link : null;
    if (focused && editing && editing.id === focused) {
      const existing = els.labels.querySelector('.cv-link-input');
      const tmp = document.createElement('div'); tmp.innerHTML = labels;
      const fresh = tmp.querySelector('.cv-link-input');
      if (existing && fresh) existing.style.transform = fresh.style.transform;
      els.labels.querySelectorAll('.cv-link-label').forEach(n => n.remove());
      tmp.querySelectorAll('.cv-link-label').forEach(n => els.labels.appendChild(n));
      return;
    }
    els.labels.innerHTML = labels;
    const inp = els.labels.querySelector('.cv-link-input');
    if (inp) bindLinkInput(inp);
  }

  // ---------- Suggested actions (rules over what's on the board) ----------
  function actions(p) {
    const out = [];
    const items = p.cards.map(c => App.item(c.slug)).filter(Boolean);
    const grouped = new Set(p.groups.flatMap(g => g.slugs));

    // 1. Several loose cards share a tag → group them.
    const byTag = new Map();
    items.forEach(it => {
      if (grouped.has(it.slug)) return;
      feat(it).tags.forEach(t => { if (!byTag.has(t)) byTag.set(t, []); byTag.get(t).push(it.slug); });
    });
    let best = null;
    byTag.forEach((slugs, tag) => { if (slugs.length >= 3 && (!best || slugs.length > best.slugs.length)) best = { tag, slugs }; });
    if (best) out.push({
      key: 'group:' + best.tag, slugs: best.slugs,
      text: `${best.slugs.length} share “${best.tag}”`, btn: 'Group them',
      run: () => makeGroup(best.tag, best.slugs),
    });

    // 2. A hub: one card linked to three or more.
    const deg = new Map();
    p.links.forEach(l => { deg.set(l.a, (deg.get(l.a) || 0) + 1); deg.set(l.b, (deg.get(l.b) || 0) + 1); });
    deg.forEach((n, slug) => {
      if (n < 3) return;
      const it = App.item(slug);
      out.push({
        key: 'hub:' + slug, slugs: [slug],
        text: `${short(it && it.title)} links ${n} items`, btn: 'Arrange around it',
        run: () => arrangeHub(slug),
      });
    });

    // 3. Links that say the same thing → group what they connect.
    const byLabel = new Map();
    p.links.forEach(l => { const k = (l.label || '').trim().toLowerCase(); if (!k) return; if (!byLabel.has(k)) byLabel.set(k, []); byLabel.get(k).push(l); });
    byLabel.forEach((ls, k) => {
      if (ls.length < 2) return;
      const slugs = [...new Set(ls.flatMap(l => [l.a, l.b]))];
      out.push({ key: 'label:' + k, slugs, text: `${ls.length} links say “${ls[0].label}”`, btn: 'Group these', run: () => makeGroup(ls[0].label, slugs) });
    });

    // 4. One card selected → its related saves.
    if (sel.size === 1 && !ghosts.length) {
      const slug = [...sel][0];
      out.push({ key: 'related:' + slug, slugs: [slug], text: 'Related saves', btn: 'Show around it', run: () => showGhosts(slug), sticky: true });
    }

    // 5. Placed without a reason.
    const missing = p.cards.filter(c => !c.note).map(c => c.slug);
    if (missing.length >= 2) out.push({
      key: 'notes', slugs: missing, text: `${missing.length} have no “what for”`, btn: 'Add reasons',
      run: () => { noteQueue = missing.slice(1); startNote(missing[0]); },
    });

    // At most two at a time, so the board stays quiet.
    return out.filter(a => a.sticky || !p.dismissed.includes(a.key)).slice(0, 2);
  }
  const short = (t) => { t = String(t || 'This'); return t.length > 22 ? t.slice(0, 21) + '…' : t; };

  let chipActions = [];
  function renderChips(p) {
    chipActions = actions(p);
    const r = els.stage.getBoundingClientRect();
    els.chips.innerHTML = chipActions.map((a, i) => {
      // Sit just above the cards the action is about; board-level ones go top-centre.
      let sx = r.width / 2, sy = 92;
      const boxes = a.slugs.map(s => cardOf(p, s)).filter(Boolean).map(boxOf);
      const b = bounds(boxes);
      if (b) {
        const s = worldToScreen(b.x + b.w / 2, b.y);
        sx = s.x; sy = s.y - 14;
      }
      sx = Math.max(140, Math.min(r.width - 140, sx));
      sy = Math.max(92 + i * 0, Math.min(r.height - 120, sy));
      return `<div class="cv-chip" data-i="${i}" style="transform:translate3d(${Math.round(sx)}px, ${Math.round(sy)}px, 0) translate(-50%, -100%)">
        <span class="cv-chip-text">${esc(a.text)}</span>
        <button type="button" class="cv-chip-btn" data-i="${i}">${esc(a.btn)}</button>
        ${a.sticky ? '' : `<button type="button" class="cv-chip-x" data-i="${i}" aria-label="Dismiss">${App.icon('x')}</button>`}
      </div>`;
    }).join('');
    // Spread chips that land on top of each other.
    // Board chrome counts as taken space too.
    const placed = ['.canvas-header', '.canvas-close', '.canvas-toolbar', '.canvas-minimap']
      .map(s => els.root.querySelector(s)).filter(n => n && !n.hidden).map(n => n.getBoundingClientRect())
      .concat([...els.frames.querySelectorAll('.cv-frame-label')].map(n => n.getBoundingClientRect()))
      .concat([...rendered.values()].map(n => n.getBoundingClientRect()));
    const top = els.stage.getBoundingClientRect().top + 8;
    const hits = (rect, dy) => placed.some(o => !(rect.right + 6 < o.left || rect.left - 6 > o.right || rect.bottom + dy + 6 < o.top || rect.top + dy - 6 > o.bottom));
    const sr = els.stage.getBoundingClientRect();
    els.chips.querySelectorAll('.cv-chip').forEach(ch => {
      let rect = ch.getBoundingClientRect();
      // Keep the whole chip inside the board horizontally.
      const dx = rect.left < sr.left + 8 ? sr.left + 8 - rect.left : rect.right > sr.right - 8 ? sr.right - 8 - rect.right : 0;
      if (dx) { ch.style.marginLeft = dx + 'px'; rect = ch.getBoundingClientRect(); }
      let dy = 0;
      // Prefer moving up (chips sit above what they describe), then down; if
      // there's no clear spot in the board, leave the chip out.
      const bottom = els.stage.getBoundingClientRect().bottom - 8;
      const ok = (d) => !hits(rect, d) && rect.top + d >= top && rect.bottom + d <= bottom;
      let found = ok(0);
      for (let i = 1; !found && i < 30; i++) { dy = i <= 12 ? -i * 30 : (i - 12) * 30; found = ok(dy); }
      if (!found) { ch.remove(); return; }
      if (dy) ch.style.marginTop = dy + 'px';
      const r2 = ch.getBoundingClientRect();
      placed.push(r2);
    });
  }

  // ---------- Minimap ----------
  function drawMinimap(p) {
    const cv = els.minimap;
    const ctx = cv.getContext('2d');
    const dpr = window.devicePixelRatio || 1;
    const W = 176, H = 112;
    if (cv.width !== W * dpr) { cv.width = W * dpr; cv.height = H * dpr; }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const boxes = p.cards.map(boxOf);
    const r = els.stage.getBoundingClientRect();
    const vw0 = screenToWorld(r.left, r.top), vw1 = screenToWorld(r.right, r.bottom);
    const viewBox = { x: vw0.x, y: vw0.y, w: vw1.x - vw0.x, h: vw1.y - vw0.y };
    const b = bounds(boxes.concat([viewBox]));
    els.minimap.hidden = !boxes.length;
    if (!b) return;
    const s = Math.min((W - 12) / b.w, (H - 12) / b.h);
    const ox = 6 + (W - 12 - b.w * s) / 2 - b.x * s, oy = 6 + (H - 12 - b.h * s) / 2 - b.y * s;
    const css = getComputedStyle(els.root);
    ctx.fillStyle = css.getPropertyValue('--text-secondary') || '#888';
    ctx.globalAlpha = 0.55;
    p.cards.forEach((c, i) => {
      const bx = boxes[i];
      ctx.fillStyle = sel.has(c.slug) ? (css.getPropertyValue('--accent') || '#fc3') : (css.getPropertyValue('--text-secondary') || '#888');
      ctx.fillRect(ox + bx.x * s, oy + bx.y * s, Math.max(2, bx.w * s), Math.max(2, bx.h * s));
    });
    ctx.globalAlpha = 1;
    ctx.strokeStyle = css.getPropertyValue('--accent') || '#fc3';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(ox + viewBox.x * s, oy + viewBox.y * s, viewBox.w * s, viewBox.h * s);
    els.minimap._map = { s, ox, oy };
  }

  // ---------- View ----------
  function zoomAt(k, sx, sy) {
    k = Math.max(MIN_K, Math.min(MAX_K, k));
    const r = els.stage.getBoundingClientRect();
    if (sx == null) { sx = r.width / 2; sy = r.height / 2; }
    const wx = (sx - view.x) / view.k, wy = (sy - view.y) / view.k;
    view.k = k;
    view.x = sx - wx * k;
    view.y = sy - wy * k;
    schedule();
  }
  function fit(animate) {
    const p = current();
    const b = bounds(p.cards.map(boxOf).concat(ghosts.map(g => ({ x: g.x, y: g.y, w: CARD_W, h: coverH(App.item(g.slug)) + META_EST[lod] }))));
    if (!b) return;
    const r = els.stage.getBoundingClientRect();
    const padT = 150, padB = 100, padX = 56;     // room for the header, group labels, chips and toolbar
    const k = Math.max(MIN_K, Math.min(1.2, Math.min((r.width - padX * 2) / b.w, (r.height - padT - padB) / b.h)));
    view.k = k;
    view.x = padX + (r.width - padX * 2 - b.w * k) / 2 - b.x * k;
    view.y = padT + (r.height - padT - padB - b.h * k) / 2 - b.y * k;
    if (animate) animateWorld();
    schedule();
  }
  function animateWorld() {
    els.root.classList.add('is-animating');
    clearTimeout(animateWorld.t);
    // Chips are placed from on-screen positions, so place them again once the move settles.
    animateWorld.t = setTimeout(() => { els.root.classList.remove('is-animating'); schedule(); }, 320);
  }

  // ---------- Placing ----------
  // Add library items. With a drop point they land there; otherwise next to
  // their most similar card on the board.
  function addItems(slugs, at) {
    const p = current();
    if (!p) return;
    slugs = slugs.filter(s => App.item(s) && !cardOf(p, s));
    if (!slugs.length) return;
    const placedNow = [];
    slugs.forEach((slug, i) => {
      const item = App.item(slug);
      const h = coverH(item) + META_EST[lod];
      let pos;
      if (at) {
        pos = findFree(at.x - CARD_W / 2 + i * (CARD_W + GAP), at.y - 40, h);
      } else {
        let bestC = null, bestS = 0;
        p.cards.forEach(c => { const s = similarity(item, App.item(c.slug) || {}); if (s > bestS) { bestS = s; bestC = c; } });
        if (bestC) { const b = boxOf(bestC); pos = findFree(b.x + b.w + GAP, b.y, h); }
        else {
          const r = els.stage.getBoundingClientRect();
          const w = screenToWorld(r.left + r.width * 0.35, r.top + r.height * 0.35);
          pos = findFree(w.x, w.y, h);
        }
      }
      const c = { slug, x: pos.x, y: pos.y, note: '' };
      p.cards.push(c);
      placedNow.push(slug);
      ghosts = ghosts.filter(g => g.slug !== slug);
    });
    save();
    sel.clear(); placedNow.forEach(s => sel.add(s));
    paintGridMarks();
    animateWorld();
    render();
    ensureVisible(placedNow);
    // One item: ask what it's for inline, and gather its related saves around it.
    if (placedNow.length > 1) ghosts = [];
    if (placedNow.length === 1) {
      showGhosts(placedNow[0], 4);
      startNote(placedNow[0]);
    } else {
      App.toast(`Added ${placedNow.length} to ${p.name}`);
    }
  }
  function ensureVisible(slugs) {
    const p = current();
    const b = bounds(slugs.map(s => cardOf(p, s)).filter(Boolean).map(boxOf));
    if (!b) return;
    const r = els.stage.getBoundingClientRect();
    const s0 = worldToScreen(b.x, b.y), s1 = worldToScreen(b.x + b.w, b.y + b.h);
    if (s0.x > 0 && s0.y > 90 && s1.x < r.width && s1.y < r.height - 80) return;
    view.x += r.width / 2 - (s0.x + s1.x) / 2;
    view.y += r.height / 2 - (s0.y + s1.y) / 2;
    animateWorld();
    schedule();
  }

  // Related saves as ghosts in a ring around a card.
  function showGhosts(slug, n) {
    const p = current();
    const c = cardOf(p, slug);
    const item = App.item(slug);
    if (!c || !item) return;
    ghosts = [];
    const rel = relatedTo(item, n || GHOSTS);
    if (!rel.length) { App.toast('No close matches in your library yet'); render(); return; }
    const b = boxOf(c);
    const fa = feat(item);
    rel.forEach((it, i) => {
      const ang = -Math.PI / 2 + (i + 0.5) * (2 * Math.PI / rel.length) + Math.PI / rel.length;
      const rad = Math.max(b.w, b.h) * 0.9 + 140;
      const h = coverH(it) + META_EST[lod];
      const pos = findFree(b.cx + Math.cos(ang) * rad - CARD_W / 2, b.cy + Math.sin(ang) * rad - h / 2, h);
      const fb = feat(it);
      const shared = [...fa.tags].filter(t => fb.tags.has(t)).slice(0, 2);
      const why = fa.domain && fa.domain === fb.domain ? `Same source` : shared.length ? `Shares ${shared.join(', ')}` : (fa.kind && fa.kind === fb.kind ? 'Same kind' : 'Similar');
      ghosts.push({ slug: it.slug, x: pos.x, y: pos.y, from: slug, why });
    });
    animateWorld();
    render();
  }
  function keepGhost(slug) {
    const g = ghosts.find(x => x.slug === slug);
    const p = current();
    if (!g || !p) return;
    p.cards.push({ slug, x: g.x, y: g.y, note: '' });
    ghosts = ghosts.filter(x => x.slug !== slug);
    // A kept ghost is linked to the card it was suggested for.
    p.links.push({ id: uid(), a: g.from, b: slug, label: '' });
    save();
    paintGridMarks();
    sel.clear(); sel.add(slug);
    render();
    startNote(slug);
  }

  // ---------- Arranging ----------
  function setPositions(map) {
    const p = current();
    p.cards.forEach(c => { const m = map.get(c.slug); if (m) { c.x = m.x; c.y = m.y; } });
    save();
    animateWorld();
    render();
  }
  // Pack slugs as a masonry block of up to `cols` columns at (x, y); returns its size.
  function packBlock(slugs, x, y, cols, out) {
    cols = Math.max(1, Math.min(cols, slugs.length));
    const colH = new Array(cols).fill(0);
    slugs.forEach(slug => {
      const c = cardOf(current(), slug);
      const h = boxOf(c).h;
      let ci = 0;
      for (let i = 1; i < cols; i++) if (colH[i] < colH[ci]) ci = i;
      out.set(slug, { x: x + ci * (CARD_W + GAP), y: snap(y + colH[ci]) });
      colH[ci] += snap(h + GAP * 1.75);
    });
    return { w: cols * (CARD_W + GAP) - GAP, h: Math.max(...colH) - GAP };
  }
  // Lay blocks left to right, wrapping into rows.
  function layoutBlocks(blocks, origin) {
    const out = new Map();
    const maxW = 4 * (CARD_W + GAP) * 2;
    let x = origin.x, y = origin.y, rowH = 0;
    blocks.forEach(bl => {
      const cols = bl.slugs.length > 6 ? 3 : bl.slugs.length > 2 ? 2 : 1;
      const w = cols * (CARD_W + GAP);
      if (x > origin.x && x + w > origin.x + maxW) { x = origin.x; y += rowH + 96; rowH = 0; }
      const size = packBlock(bl.slugs, x, y, cols, out);
      x += size.w + 96;
      rowH = Math.max(rowH, size.h);
    });
    return out;
  }
  // Order loose cards so linked ones sit together.
  function linkOrder(slugs) {
    const p = current();
    const set = new Set(slugs), seen = new Set(), out = [];
    const nb = new Map();
    p.links.forEach(l => { if (set.has(l.a) && set.has(l.b)) { (nb.get(l.a) || nb.set(l.a, []).get(l.a)).push(l.b); (nb.get(l.b) || nb.set(l.b, []).get(l.b)).push(l.a); } });
    slugs.forEach(s => {
      if (seen.has(s)) return;
      const q = [s]; seen.add(s);
      while (q.length) { const x = q.shift(); out.push(x); (nb.get(x) || []).forEach(y => { if (!seen.has(y)) { seen.add(y); q.push(y); } }); }
    });
    return out;
  }
  function origin() {
    const p = current();
    const b = bounds(p.cards.map(boxOf));
    return b ? { x: snap(b.x), y: snap(b.y) } : { x: 0, y: 0 };
  }
  function refit() { render(); fit(true); }
  function tidy() {
    const p = current();
    if (!p || !p.cards.length) return;
    ghosts = [];
    render();   // measure real card heights before laying out
    const grouped = new Set();
    const blocks = p.groups.map(g => { g.slugs = g.slugs.filter(s => cardOf(p, s)); g.slugs.forEach(s => grouped.add(s)); return { slugs: linkOrder(g.slugs) }; }).filter(b => b.slugs.length);
    const loose = linkOrder(p.cards.map(c => c.slug).filter(s => !grouped.has(s)));
    if (loose.length) blocks.push({ slugs: loose });
    setPositions(layoutBlocks(blocks, origin()));
    p.groups = p.groups.filter(g => g.slugs.length);
    save();
    fit(true);
    requestAnimationFrame(refit);   // again once heights at the new zoom are measured
  }
  function clusterKey(item, by, topics) {
    const f = feat(item);
    if (by === 'kind') return f.kind ? (App.kindLine(item) || f.kind).split(' · ')[0] : 'Links';
    if (by === 'domain') return f.domain ? f.domain.replace(/^www\./, '') : 'No source';
    if (by === 'color') return f.color || 'No colour';
    return topics.get(item.slug) || 'Other';
  }
  // Topics: repeatedly take the tag shared by the most unassigned cards.
  function topicsFor(slugs) {
    const left = new Set(slugs), out = new Map();
    for (;;) {
      const count = new Map();
      left.forEach(s => feat(App.item(s)).tags.forEach(t => count.set(t, (count.get(t) || 0) + 1)));
      let bt = null, bn = 1;
      count.forEach((n, t) => { if (n > bn) { bn = n; bt = t; } });
      if (!bt) break;
      left.forEach(s => { if (feat(App.item(s)).tags.has(bt)) { out.set(s, bt); left.delete(s); } });
    }
    return out;
  }
  function cluster(by) {
    const p = current();
    if (!p || !p.cards.length) return;
    const slugs = p.cards.map(c => c.slug);
    const topics = by === 'topic' ? topicsFor(slugs) : null;
    const groups = new Map();
    slugs.forEach(s => { const k = clusterKey(App.item(s), by, topics); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(s); });
    const sorted = [...groups.entries()].sort((a, b) => b[1].length - a[1].length);
    // Singletons go together at the end rather than as one-card groups.
    const singles = sorted.filter(([, s]) => s.length === 1).flatMap(([, s]) => s);
    p.groups = sorted.filter(([, s]) => s.length > 1).map(([name, s]) => ({ id: uid(), name: cap(name), slugs: s }));
    if (singles.length) p.groups.push({ id: uid(), name: 'Other', slugs: singles });
    save();
    tidy();
  }
  const cap = (s) => String(s).replace(/[-_]+/g, ' ').replace(/^\w/, c => c.toUpperCase());
  function makeGroup(name, slugs) {
    const p = current();
    p.groups.forEach(g => { g.slugs = g.slugs.filter(s => !slugs.includes(s)); });
    p.groups = p.groups.filter(g => g.slugs.length);
    const g = { id: uid(), name: cap(name), slugs: slugs.slice() };
    p.groups.push(g);
    // Pull the members together where the first one is.
    const first = boxOf(cardOf(p, slugs[0]));
    const skip = new Set(slugs);
    const tmp = new Map();
    packBlock(slugs, first.x, first.y, slugs.length > 4 ? 3 : 2, tmp);
    // Move other cards out of the block's way.
    const block = bounds([...tmp.entries()].map(([s, pos]) => ({ x: pos.x, y: pos.y, w: CARD_W, h: boxOf(cardOf(p, s)).h })));
    p.cards.forEach(c => {
      if (skip.has(c.slug)) return;
      const b = boxOf(c);
      if (overlaps(b, block, 40)) tmp.set(c.slug, { x: snap(block.x + block.w + 96), y: b.y });
    });
    setPositions(tmp);
  }
  function arrangeHub(slug) {
    const p = current();
    const hub = boxOf(cardOf(p, slug));
    const nbs = p.links.filter(l => l.a === slug || l.b === slug).map(l => (l.a === slug ? l.b : l.a));
    const out = new Map();
    const rad = 320 + nbs.length * 18;
    nbs.forEach((s, i) => {
      const ang = -Math.PI / 2 + i * (2 * Math.PI / nbs.length);
      const h = boxOf(cardOf(p, s)).h;
      out.set(s, { x: snap(hub.cx + Math.cos(ang) * rad - CARD_W / 2), y: snap(hub.cy + Math.sin(ang) * rad - h / 2) });
    });
    setPositions(out);
  }

  // ---------- Intent (inline) ----------
  function startNote(slug) {
    editing = { kind: 'card', slug };
    refreshCard(slug);
    const el = rendered.get(slug);
    const inp = el && el.querySelector('.cv-note-input');
    if (inp) setTimeout(() => inp.focus(), 20);
  }
  function bindNoteInput(inp, slug) {
    let done = false;
    const finish = (saveIt) => {
      if (done) return;
      done = true;
      const p = current();
      const c = p && cardOf(p, slug);
      if (c && saveIt) { c.note = inp.value.trim(); save(); }
      editing = null;
      refreshCard(slug);
      if (noteQueue.length && saveIt) { const next = noteQueue.shift(); if (cardOf(p, next)) { ensureVisible([next]); startNote(next); } }
      else noteQueue = [];
      schedule();
    };
    inp.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') { e.preventDefault(); finish(true); }
      if (e.key === 'Escape') { e.preventDefault(); finish(false); }
    });
    inp.addEventListener('blur', () => finish(!!inp.value.trim()));
    inp.addEventListener('pointerdown', (e) => e.stopPropagation());
  }
  function bindLinkInput(inp) {
    const id = inp.dataset.link;
    let done = false;
    const finish = (saveIt) => {
      if (done) return;
      done = true;
      const p = current();
      const l = p && p.links.find(x => x.id === id);
      if (l && saveIt) { l.label = inp.value.trim(); save(); }
      editing = null;
      render();
    };
    inp.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') { e.preventDefault(); finish(true); }
      if (e.key === 'Escape') { e.preventDefault(); finish(false); }
    });
    inp.addEventListener('blur', () => finish(!!inp.value.trim()));
    inp.addEventListener('pointerdown', (e) => e.stopPropagation());
    setTimeout(() => inp.focus(), 20);
  }

  // ---------- Export ----------
  function exportBrief() {
    const p = current();
    if (!p) return;
    const line = (c) => {
      const it = App.item(c.slug) || {};
      const url = it.source_url ? `(${it.source_url})` : '';
      return `- ${url ? `[${it.title || c.slug}]${url}` : (it.title || c.slug)}${c.note ? ` — ${c.note}` : ''}`;
    };
    const grouped = new Set();
    let md = `# ${p.name}\n\n`;
    p.groups.forEach(g => {
      md += `## ${g.name}\n\n` + g.slugs.map(s => cardOf(p, s)).filter(Boolean).map(c => { grouped.add(c.slug); return line(c); }).join('\n') + '\n\n';
    });
    const loose = p.cards.filter(c => !grouped.has(c.slug));
    if (loose.length) md += (p.groups.length ? '## Other\n\n' : '') + loose.map(line).join('\n') + '\n\n';
    const named = p.links.filter(l => l.label);
    if (named.length) {
      md += '## Connections\n\n' + named.map(l => `- ${(App.item(l.a) || {}).title} ↔ ${(App.item(l.b) || {}).title}: ${l.label}`).join('\n') + '\n';
    }
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([md], { type: 'text/markdown' }));
    a.download = p.name.replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '-').toLowerCase() + '.md';
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  // ---------- Project menu ----------
  function renderMenu() {
    const p = current();
    els.menu.innerHTML = data.projects.map(x => `
      <button type="button" class="canvas-menu-item${p && x.id === p.id ? ' is-current' : ''}" data-id="${x.id}" role="menuitem">
        <span>${esc(x.name)}</span><span class="canvas-menu-count">${x.cards.length}</span>
      </button>`).join('') +
      `<div class="canvas-menu-sep"></div>
       <button type="button" class="canvas-menu-item" data-act="new" role="menuitem">${App.icon('plus')}<span>New project</span></button>
       ${p ? `<button type="button" class="canvas-menu-item" data-act="rename" role="menuitem"><span>Rename</span></button>
       <button type="button" class="canvas-menu-item is-danger" data-act="delete" role="menuitem"><span>Delete “${esc(p.name)}”</span></button>` : ''}`;
  }
  function toggleMenu(force) {
    const show = typeof force === 'boolean' ? force : els.menu.hidden;
    if (show) renderMenu();
    els.menu.hidden = !show;
    els.title.setAttribute('aria-expanded', String(show));
  }

  // ---------- Library grid integration ----------
  function paintGridMarks() {
    const p = current();
    const open = !els.root.hidden;
    const sel1 = (s) => `#masonry-grid .card[data-slug="${CSS.escape(s)}"]`;
    let css = '';
    if (open && p && p.cards.length) css += p.cards.map(c => sel1(c.slug)).join(',') + '{opacity:.45}';
    if (open && picked.size) css += [...picked].map(s => sel1(s) + ' .card-visual-area').join(',') + '{outline:2px solid var(--accent);outline-offset:3px}';
    els.gridStyle.textContent = css;
    els.pickbar.hidden = !(open && picked.size);
    els.pickCount.textContent = `${picked.size} selected in library`;
  }
  function bindGrid() {
    const grid = document.getElementById('masonry-grid');
    if (!grid) return;
    const active = () => !els.root.hidden && !!current();
    let drag = null, suppressClick = false;

    // Shift/⌘-click picks cards; a plain click still opens the item panel.
    grid.addEventListener('click', (e) => {
      if (!active()) return;
      if (suppressClick) { suppressClick = false; e.stopPropagation(); e.preventDefault(); return; }
      const card = e.target.closest('.card');
      if (!card || !(e.shiftKey || e.metaKey || e.ctrlKey)) return;
      e.stopPropagation(); e.preventDefault();
      const s = card.dataset.slug;
      if (picked.has(s)) picked.delete(s); else picked.add(s);
      paintGridMarks();
    }, true);
    grid.addEventListener('dragstart', (e) => { if (active()) e.preventDefault(); }, true);

    // Hover: one "+" button over the card.
    let hoverCard = null;
    grid.addEventListener('pointerover', (e) => {
      if (!active() || drag) return;
      const card = e.target.closest('.card');
      if (!card || card === hoverCard) return;
      hoverCard = card;
      const r = card.querySelector('.card-visual-area').getBoundingClientRect();
      const on = onBoard(card.dataset.slug);
      els.gridAdd.innerHTML = on ? `${IC.check}<span>On board</span>` : `${App.icon('plus')}<span>Add</span>`;
      els.gridAdd.classList.toggle('is-on', on);
      els.gridAdd.dataset.slug = card.dataset.slug;
      els.gridAdd.style.transform = `translate3d(${Math.round(r.left + 8)}px, ${Math.round(r.top + 8)}px, 0)`;
      els.gridAdd.hidden = false;
    });
    document.querySelector('.main-content').addEventListener('scroll', () => { els.gridAdd.hidden = true; hoverCard = null; }, { passive: true });
    grid.addEventListener('pointerleave', (e) => {
      if (e.relatedTarget === els.gridAdd || els.gridAdd.contains(e.relatedTarget)) return;
      els.gridAdd.hidden = true; hoverCard = null;
    });
    els.gridAdd.addEventListener('click', () => {
      const s = els.gridAdd.dataset.slug;
      if (onBoard(s)) { sel.clear(); sel.add(s); ensureVisible([s]); render(); return; }
      addItems(picked.has(s) ? [...picked] : [s]);
      if (picked.has(s)) { picked.clear(); }
      els.gridAdd.hidden = true; hoverCard = null;
      paintGridMarks();
    });

    // Drag cards from the grid onto the board.
    grid.addEventListener('pointerdown', (e) => {
      if (!active() || e.button !== 0) return;
      const card = e.target.closest('.card');
      if (!card) return;
      const sx = e.clientX, sy = e.clientY;
      const slug = card.dataset.slug;
      const group = picked.has(slug) ? [...picked] : [slug];
      drag = { started: false };
      const move = (ev) => {
        if (!drag.started) {
          if (Math.hypot(ev.clientX - sx, ev.clientY - sy) < 6) return;
          drag.started = true;
          els.gridAdd.hidden = true;
          const ghost = document.createElement('div');
          ghost.className = 'grid-drag-ghost';
          const thumb = card.querySelector('.card-thumb, .card-glyph-tile');
          ghost.innerHTML = (thumb ? thumb.outerHTML : '') + (group.length > 1 ? `<span class="grid-drag-count">${group.length}</span>` : '');
          document.body.appendChild(ghost);
          drag.ghost = ghost;
          document.documentElement.classList.add('is-grid-dragging');
        }
        drag.ghost.style.transform = `translate3d(${ev.clientX - 60}px, ${ev.clientY - 40}px, 0) rotate(-2deg)`;
        const r = els.stage.getBoundingClientRect();
        els.stage.classList.toggle('is-drop-target', ev.clientX > r.left && ev.clientX < r.right && ev.clientY > r.top && ev.clientY < r.bottom);
      };
      const up = (ev) => {
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        if (drag && drag.started) {
          suppressClick = true;
          setTimeout(() => { suppressClick = false; }, 0);
          drag.ghost.remove();
          document.documentElement.classList.remove('is-grid-dragging');
          els.stage.classList.remove('is-drop-target');
          const r = els.stage.getBoundingClientRect();
          if (ev.clientX > r.left && ev.clientX < r.right && ev.clientY > r.top && ev.clientY < r.bottom) {
            addItems(group, screenToWorld(ev.clientX, ev.clientY));
            if (group.length > 1) picked.clear();
            paintGridMarks();
          }
        }
        drag = null;
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
    });
  }

  // ---------- Board interactions ----------
  function bind() {
    els.root.querySelector('.canvas-close').addEventListener('click', close);
    els.title.addEventListener('click', (e) => { e.stopPropagation(); toggleMenu(); });
    els.menu.addEventListener('click', (e) => {
      const b = e.target.closest('.canvas-menu-item');
      if (!b) return;
      toggleMenu(false);
      const p = current();
      if (b.dataset.id) { data.currentId = b.dataset.id; save(); return showProject(); }
      if (b.dataset.act === 'new') return showStart(true);
      if (b.dataset.act === 'rename') {
        const name = window.prompt('Project name', p.name);
        if (name && name.trim()) { p.name = name.trim(); save(); els.titleText.textContent = p.name; }
        return;
      }
      if (b.dataset.act === 'delete') {
        data.projects = data.projects.filter(x => x.id !== p.id);
        data.currentId = data.projects[0] ? data.projects[0].id : null;
        save();
        paintGridMarks();
        return data.currentId ? showProject() : showStart(false);
      }
    });
    document.addEventListener('click', (e) => {
      if (!els.menu.hidden && !e.target.closest('.canvas-header')) toggleMenu(false);
      if (!els.clusterMenu.hidden && !e.target.closest('.tb-drop')) els.clusterMenu.hidden = true;
    });
    els.startForm.addEventListener('submit', (e) => { e.preventDefault(); const n = els.startInput.value.trim(); if (n) createProject(n); });
    els.startCancel.addEventListener('click', () => { els.start.hidden = true; });

    // Toolbar
    els.root.querySelector('.canvas-toolbar').addEventListener('click', (e) => {
      const b = e.target.closest('[data-act], [data-by]');
      if (!b) return;
      if (b.dataset.by) { els.clusterMenu.hidden = true; return cluster(b.dataset.by); }
      switch (b.dataset.act) {
        case 'zoom-in': zoomAt(view.k * 1.25); animateWorld(); break;
        case 'zoom-out': zoomAt(view.k / 1.25); animateWorld(); break;
        case 'zoom-reset': zoomAt(1); animateWorld(); break;
        case 'fit': fit(true); break;
        case 'tidy': tidy(); break;
        case 'cluster': els.clusterMenu.hidden = !els.clusterMenu.hidden; break;
        case 'export': exportBrief(); break;
      }
    });
    els.pickbar.addEventListener('click', (e) => {
      if (e.target.closest('.pickbar-add')) { addItems([...picked]); picked.clear(); paintGridMarks(); }
      if (e.target.closest('.pickbar-clear')) { picked.clear(); paintGridMarks(); }
    });

    // Chips
    els.chips.addEventListener('click', (e) => {
      const btn = e.target.closest('.cv-chip-btn, .cv-chip-x');
      if (!btn) return;
      const a = chipActions[+btn.dataset.i];
      if (!a) return;
      if (btn.classList.contains('cv-chip-x')) { current().dismissed.push(a.key); save(); render(); return; }
      a.run();
    });
    els.chips.addEventListener('pointerover', (e) => {
      const ch = e.target.closest('.cv-chip');
      const a = ch && chipActions[+ch.dataset.i];
      rendered.forEach((el, s) => el.classList.toggle('is-hint', !!(a && a.slugs.includes(s))));
    });
    els.chips.addEventListener('pointerleave', () => rendered.forEach(el => el.classList.remove('is-hint')));

    // Minimap: click to centre there.
    els.minimap.addEventListener('pointerdown', (e) => {
      const m = els.minimap._map;
      if (!m) return;
      const rr = els.minimap.getBoundingClientRect();
      const wx = (e.clientX - rr.left - m.ox) / m.s, wy = (e.clientY - rr.top - m.oy) / m.s;
      const r = els.stage.getBoundingClientRect();
      view.x = r.width / 2 - wx * view.k; view.y = r.height / 2 - wy * view.k;
      animateWorld(); schedule();
    });

    // Wheel: pinch / ⌘-scroll zooms at the pointer, plain scroll pans.
    els.stage.addEventListener('wheel', (e) => {
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
      if (!pinch) pinch = { d, k: view.k };
      else zoomAt(pinch.k * d / pinch.d, cx, cy);
    });
    window.addEventListener('pointerup', (e) => { touches.delete(e.pointerId); if (touches.size < 2) pinch = null; });

    els.stage.addEventListener('pointerdown', onStageDown);
    els.stage.addEventListener('dblclick', (e) => {
      const card = e.target.closest('.cv-card:not(.cv-ghost)');
      if (card && !e.target.closest('input, a, .cv-note')) App.openItem(card.dataset.slug);
      const fl = e.target.closest('.cv-frame-label');
      if (fl) {
        const g = current().groups.find(x => x.id === fl.dataset.group);
        const name = g && window.prompt('Group name', g.name);
        if (name && name.trim()) { g.name = name.trim(); save(); render(); }
      }
    });
    els.labels.addEventListener('click', (e) => {
      const b = e.target.closest('.cv-link-label');
      if (b) { editing = { kind: 'link', id: b.dataset.link }; render(); }
    });

    // Keys (only while the board is open; inputs keep their own keys).
    window.addEventListener('keydown', (e) => {
      if (els.root.hidden || !current()) return;
      if (e.target && e.target.matches && e.target.matches('input, textarea, [contenteditable]')) return;
      const p = current();
      if (e.code === 'Space') { spaceDown = true; els.stage.classList.add('is-hand'); if (e.target === els.stage || e.target === document.body) e.preventDefault(); return; }
      let handled = true;
      if ((e.key === '+' || e.key === '=') && !e.metaKey && !e.ctrlKey) { zoomAt(view.k * 1.25); animateWorld(); }
      else if ((e.key === '-' || e.key === '_') && !e.metaKey && !e.ctrlKey) { zoomAt(view.k / 1.25); animateWorld(); }
      else if (e.key === '0' && !e.metaKey && !e.ctrlKey) { zoomAt(1); animateWorld(); }
      else if (e.key === '!' || (e.key === '1' && e.shiftKey)) fit(true);
      else if ((e.key === 'Backspace' || e.key === 'Delete') && sel.size) removeCards([...sel]);
      else if (e.key === 'Escape') { sel.clear(); ghosts = []; render(); }
      else if (e.key === 'a' && (e.metaKey || e.ctrlKey) && document.activeElement === els.stage) { p.cards.forEach(c => sel.add(c.slug)); render(); }
      else if (e.key === 'Enter' && sel.size === 1) startNote([...sel][0]);
      else handled = false;
      if (handled) { e.preventDefault(); e.stopImmediatePropagation(); }
    }, true);
    window.addEventListener('keyup', (e) => { if (e.code === 'Space') { spaceDown = false; els.stage.classList.remove('is-hand'); } });
    window.addEventListener('resize', schedule);
    new ResizeObserver(schedule).observe(els.stage);
  }

  function removeCards(slugs) {
    const p = current();
    const set = new Set(slugs);
    p.cards = p.cards.filter(c => !set.has(c.slug));
    p.links = p.links.filter(l => !set.has(l.a) && !set.has(l.b));
    p.groups.forEach(g => { g.slugs = g.slugs.filter(s => !set.has(s)); });
    p.groups = p.groups.filter(g => g.slugs.length);
    sel.clear();
    save();
    paintGridMarks();
    render();
  }

  function onStageDown(e) {
    const p = current();
    if (!p || e.pointerType === 'touch' && e.isPrimary === false) return;
    if (e.target.closest('input, a, .cv-chip, .cv-link-label')) return;
    els.stage.focus({ preventScroll: true });
    const sx = e.clientX, sy = e.clientY;

    // Ghost: keep it.
    const gh = e.target.closest('.cv-ghost');
    if (gh) { e.preventDefault(); keepGhost(gh.dataset.ghost); return; }

    // Pan: middle button, Space held, or a touch on empty board.
    const card = e.target.closest('.cv-card');
    const frameLabel = e.target.closest('.cv-frame-label');
    if (e.button === 1 || spaceDown || (e.pointerType === 'touch' && !card)) {
      e.preventDefault();
      const vx = view.x, vy = view.y;
      els.stage.classList.add('is-panning');
      return track((ev) => { view.x = vx + ev.clientX - sx; view.y = vy + ev.clientY - sy; schedule(); },
        () => els.stage.classList.remove('is-panning'));
    }
    if (e.button !== 0) return;

    // Link: drag from the handle onto another card.
    if (card && e.target.closest('.cv-handle')) {
      e.preventDefault();
      const from = cardOf(p, card.dataset.slug);
      const A = boxOf(from);
      const draft = els.links.querySelector('.cv-draft');
      draft.style.display = '';
      draft.setAttribute('x1', A.cx); draft.setAttribute('y1', A.cy);
      const targetAt = (ev) => { const o = document.elementFromPoint(ev.clientX, ev.clientY); const t = o && o.closest('.cv-card:not(.cv-ghost)'); return t && t !== card ? t : null; };
      return track((ev) => {
        const w = screenToWorld(ev.clientX, ev.clientY);
        draft.setAttribute('x2', w.x); draft.setAttribute('y2', w.y);
        const t = targetAt(ev);
        rendered.forEach(el => el.classList.toggle('is-target', el === t));
      }, (ev) => {
        draft.style.display = 'none';
        rendered.forEach(el => el.classList.remove('is-target'));
        const t = targetAt(ev);
        if (!t) return;
        const a = card.dataset.slug, b = t.dataset.slug;
        if (p.links.some(l => (l.a === a && l.b === b) || (l.a === b && l.b === a))) return;
        const link = { id: uid(), a, b, label: '' };
        p.links.push(link);
        save();
        editing = { kind: 'link', id: link.id };
        render();
      });
    }

    // Card or group label: select, then move everything selected.
    if (card || frameLabel) {
      e.preventDefault();
      let slugs;
      if (frameLabel) {
        const g = p.groups.find(x => x.id === frameLabel.dataset.group);
        slugs = g ? g.slugs.slice() : [];
        if (!e.shiftKey) sel.clear();
        slugs.forEach(s => sel.add(s));
      } else {
        const s = card.dataset.slug;
        if (e.shiftKey || e.metaKey) { if (sel.has(s)) sel.delete(s); else sel.add(s); }
        else if (!sel.has(s)) { sel.clear(); sel.add(s); }
      }
      if (ghosts.length && !(card && ghosts.some(g => g.from === card.dataset.slug))) ghosts = [];
      render();
      const moving = [...sel].map(s => cardOf(p, s)).filter(Boolean);
      const start = moving.map(c => ({ c, x: c.x, y: c.y }));
      let moved = false;
      return track((ev) => {
        const dx = (ev.clientX - sx) / view.k, dy = (ev.clientY - sy) / view.k;
        if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 4) return;
        if (!moved) { moved = true; ghosts = []; els.root.classList.add('is-moving'); }
        const doSnap = !ev.altKey;
        start.forEach(o => { o.c.x = doSnap ? snap(o.x + dx) : o.x + dx; o.c.y = doSnap ? snap(o.y + dy) : o.y + dy; });
        schedule();
      }, () => {
        els.root.classList.remove('is-moving');
        if (moved) save();
        else if (card && !(e.shiftKey || e.metaKey)) { sel.clear(); sel.add(card.dataset.slug); render(); }
      });
    }

    // Empty board: marquee select (Shift adds).
    e.preventDefault();
    if (!e.shiftKey) sel.clear();
    if (editing) { editing = null; }
    ghosts = [];
    const base = new Set(sel);
    const r = els.stage.getBoundingClientRect();
    const mq = els.marquee;
    let moved = false;
    render();
    track((ev) => {
      if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 4) return;
      moved = true;
      const x0 = Math.min(sx, ev.clientX), y0 = Math.min(sy, ev.clientY), x1 = Math.max(sx, ev.clientX), y1 = Math.max(sy, ev.clientY);
      mq.hidden = false;
      mq.style.transform = `translate3d(${x0 - r.left}px, ${y0 - r.top}px, 0)`;
      mq.style.width = (x1 - x0) + 'px'; mq.style.height = (y1 - y0) + 'px';
      const w0 = screenToWorld(x0, y0), w1 = screenToWorld(x1, y1);
      const box = { x: w0.x, y: w0.y, w: w1.x - w0.x, h: w1.y - w0.y };
      sel.clear(); base.forEach(s => sel.add(s));
      p.cards.forEach(c => { if (overlaps(boxOf(c), box, 0)) sel.add(c.slug); });
      schedule();
    }, () => { mq.hidden = true; schedule(); });
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
    load();
    build();
    bind();
    bindGrid();
    const btn = document.getElementById('projects-btn');
    if (btn) {
      btn.innerHTML = App.icon('graph');
      btn.addEventListener('click', () => (els.root.hidden ? open() : close()));
    }
    if (localStorage.getItem(OPEN_KEY) || new URLSearchParams(location.search).has('projects')) open();
  }
  if (window.StelloApp) init();
  else document.addEventListener('stello:ready', init, { once: true });
})();
