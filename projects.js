/* === Stello — Projects canvas (mockup) ===
 *
 * A project is a board where saves get used for real work. Stello suggests
 * related saves in a tray (rules only: shared tags, kind, colour, source and
 * the project's name; no AI). You drag items on, link them, and one short
 * optional question, "What's this here for?", records the intent on the item
 * for that project. Intent comes from use, not from a preset at save time.
 *
 * Rendering scales with the screen, not the board: the board moves as one
 * GPU-composited layer (a CSS transform), and only cards inside the visible
 * area (plus a margin) exist in the DOM.
 *
 * Mockup storage: projects live in this browser's localStorage. Saving them
 * to D1 (and syncing to the Apple apps) comes after the design is agreed.
 */
(function () {
  'use strict';

  const STORE_KEY = 'stello.projects.v0';
  const OPEN_KEY = 'stello.projects.open';
  const CARD_W = 184;
  const CULL_MARGIN = 400;       // px around the screen kept rendered
  const MAX_SUGGESTIONS = 24;
  const STOP = new Set(['the', 'and', 'for', 'with', 'from', 'into', 'project', 'new', 'my', 'our', 'of', 'a', 'an', 'to', 'in', 'on']);

  let App = null;
  let data = { projects: [], currentId: null };
  let view = { x: 0, y: 0 };
  const els = {};
  const rendered = new Map();     // slug -> card element (only visible cards)
  let suggestTimer = 0;
  let renderRaf = 0;
  let ask = null;                  // { kind: 'card'|'link', slug?, linkId? }

  // ---------- Store ----------
  function load() {
    try { data = JSON.parse(localStorage.getItem(STORE_KEY)) || data; } catch { /* keep default */ }
    if (!Array.isArray(data.projects)) data = { projects: [], currentId: null };
  }
  function save() { localStorage.setItem(STORE_KEY, JSON.stringify(data)); }
  function current() { return data.projects.find(p => p.id === data.currentId) || null; }
  function uid() { return Math.random().toString(36).slice(2, 10); }

  // ---------- Helpers ----------
  const esc = (s) => App.esc(String(s == null ? '' : s));
  function tokens(str) {
    return String(str || '').toLowerCase().split(/[^a-z0-9À-ɏ]+/)
      .filter(w => w.length >= 3 && !STOP.has(w));
  }
  function cardHeight(item) {
    // Same aspect the grid uses, clamped so tall posters don't dominate.
    let ratio = 0.75;
    if (item && item.has_image && item.image_width && item.image_height) ratio = item.image_height / item.image_width;
    else if (item && !item.has_image) ratio = 0.62;
    return Math.round(CARD_W * Math.max(0.5, Math.min(1.3, ratio)));
  }
  const META_H = 48;               // title + note line under the cover
  function cardBox(c) {
    const item = App.item(c.slug);
    const h = cardHeight(item) + META_H;
    return { x: c.x, y: c.y, w: CARD_W, h, cx: c.x + CARD_W / 2, cy: c.y + h / 2 };
  }
  function presetIntent(item) {
    // Old "why saved" presets become a starting chip, never the answer.
    return (item.tags || []).filter(t => t.category === 'intent')
      .map(t => String(t.tag).replace(/[-_]+/g, ' ').replace(/^\w/, c => c.toUpperCase()));
  }
  function screenToWorld(px, py) {
    const r = els.stage.getBoundingClientRect();
    return { x: px - r.left - view.x, y: py - r.top - view.y };
  }

  // ---------- DOM ----------
  function build() {
    const layout = document.querySelector('.main-layout');
    const root = document.createElement('section');
    root.className = 'canvas-view';
    root.hidden = true;
    root.setAttribute('aria-label', 'Projects');
    root.innerHTML = `
      <div class="canvas-stage">
        <div class="canvas-world">
          <svg class="canvas-links" width="1" height="1" overflow="visible" aria-hidden="true"></svg>
          <div class="canvas-labels"></div>
          <div class="canvas-cards"></div>
        </div>
        <div class="canvas-hint" hidden>Drag a suggestion here to start.</div>
      </div>

      <header class="canvas-header">
        <button type="button" class="canvas-title" aria-haspopup="true" aria-expanded="false">
          <span class="canvas-title-text"></span><sup class="canvas-title-count"></sup>
          <span class="canvas-caret" aria-hidden="true"></span>
        </button>
        <div class="canvas-menu" role="menu" hidden></div>
      </header>

      <aside class="canvas-tray" aria-label="Suggested saves">
        <div class="tray-head">
          <div class="tray-title">Suggested</div>
          <div class="tray-sub">From your library, by tags, kind, colour and source.</div>
          <input type="search" class="tray-search" placeholder="Find in library…" aria-label="Find in library" autocomplete="off">
        </div>
        <div class="tray-list" role="list"></div>
      </aside>

      <div class="canvas-bar" role="toolbar" aria-label="Project controls">
        <button type="button" class="bar-btn" data-act="library" title="Back to library" aria-label="Back to library">${App.icon('squares-four')}</button>
        <div class="canvas-bar-hint">Drag the dot on a card to link it to another.</div>
      </div>

      <div class="canvas-start" hidden>
        <div class="canvas-start-card">
          <div class="canvas-start-title">Start a project</div>
          <p class="canvas-start-text">Pull saves together for real work. Stello suggests related ones as you go, and asks what each is for when you place it.</p>
          <form class="canvas-start-form">
            <input type="text" class="canvas-start-input" placeholder="Project name, e.g. Café rebrand" maxlength="60" aria-label="Project name" required>
            <button type="submit" class="canvas-start-btn">Create</button>
          </form>
          <button type="button" class="canvas-start-cancel" hidden>Cancel</button>
        </div>
      </div>

      <div class="canvas-ask" hidden role="dialog" aria-label="What's this here for?">
        <div class="ask-q"></div>
        <input type="text" class="ask-input" maxlength="80" autocomplete="off">
        <div class="ask-chips"></div>
        <div class="ask-actions">
          <button type="button" class="ask-skip">Skip</button>
          <button type="button" class="ask-save">Save</button>
        </div>
      </div>
    `;
    layout.insertBefore(root, document.getElementById('panels-container'));
    Object.assign(els, {
      root,
      stage: root.querySelector('.canvas-stage'),
      world: root.querySelector('.canvas-world'),
      links: root.querySelector('.canvas-links'),
      labels: root.querySelector('.canvas-labels'),
      cards: root.querySelector('.canvas-cards'),
      hint: root.querySelector('.canvas-hint'),
      title: root.querySelector('.canvas-title'),
      titleText: root.querySelector('.canvas-title-text'),
      titleCount: root.querySelector('.canvas-title-count'),
      menu: root.querySelector('.canvas-menu'),
      tray: root.querySelector('.canvas-tray'),
      traySearch: root.querySelector('.tray-search'),
      trayList: root.querySelector('.tray-list'),
      traySub: root.querySelector('.tray-sub'),
      start: root.querySelector('.canvas-start'),
      startForm: root.querySelector('.canvas-start-form'),
      startInput: root.querySelector('.canvas-start-input'),
      startCancel: root.querySelector('.canvas-start-cancel'),
      ask: root.querySelector('.canvas-ask'),
      askQ: root.querySelector('.ask-q'),
      askInput: root.querySelector('.ask-input'),
      askChips: root.querySelector('.ask-chips'),
    });
    els.root.querySelector('.canvas-caret').innerHTML = '<svg viewBox="0 0 256 256" fill="currentColor"><path d="M213.66,101.66l-80,80a8,8,0,0,1-11.32,0l-80-80A8,8,0,0,1,53.66,90.34L128,164.69l74.34-74.35a8,8,0,0,1,11.32,11.32Z"/></svg>';

    // The canvas covers the grid column only, so the item panel still opens beside it.
    const mc = document.querySelector('.main-content');
    const fit = () => {
      root.style.left = mc.offsetLeft + 'px';
      root.style.width = mc.offsetWidth + 'px';
    };
    new ResizeObserver(fit).observe(mc);
    fit();
  }

  // ---------- Open / close ----------
  function open() {
    els.root.hidden = false;
    document.documentElement.classList.add('canvas-open');
    localStorage.setItem(OPEN_KEY, '1');
    if (!current()) showStart(false);
    else showProject();
  }
  function close() {
    els.root.hidden = true;
    document.documentElement.classList.remove('canvas-open');
    localStorage.removeItem(OPEN_KEY);
    hideAsk();
  }

  function showStart(cancellable) {
    els.start.hidden = false;
    els.startCancel.hidden = !cancellable;
    els.startInput.value = '';
    setTimeout(() => els.startInput.focus(), 30);
  }
  function createProject(name) {
    const p = { id: uid(), name: name.trim(), createdAt: new Date().toISOString(), cards: [], links: [] };
    data.projects.unshift(p);
    data.currentId = p.id;
    save();
    els.start.hidden = true;
    view = { x: 0, y: 0 };
    showProject();
  }
  function switchTo(id) {
    data.currentId = id;
    save();
    view = { x: 0, y: 0 };
    showProject();
  }

  function showProject() {
    const p = current();
    if (!p) return showStart(false);
    els.start.hidden = true;
    els.titleText.textContent = p.name;
    if (!p.cards.length) centerView(); else fitView(p);
    els.cards.innerHTML = '';
    rendered.clear();
    renderBoard();
    scheduleSuggestions();
  }
  function centerView() {
    const r = els.stage.getBoundingClientRect();
    view = { x: Math.round(r.width * 0.12), y: Math.round(r.height * 0.22) };
  }
  function fitView(p) {
    // Put the board's top-left near the top-left of the free area.
    let minX = Infinity, minY = Infinity;
    p.cards.forEach(c => { minX = Math.min(minX, c.x); minY = Math.min(minY, c.y); });
    view = { x: 48 - minX, y: 150 - minY };
  }

  // ---------- Board rendering (visible cards only) ----------
  function scheduleRender() {
    if (renderRaf) return;
    renderRaf = requestAnimationFrame(() => { renderRaf = 0; renderBoard(); });
  }
  function renderBoard() {
    const p = current();
    if (!p) return;
    els.world.style.transform = `translate3d(${view.x}px, ${view.y}px, 0)`;
    els.titleCount.textContent = p.cards.length ? String(p.cards.length) : '';
    els.hint.hidden = p.cards.length > 0;

    const r = els.stage.getBoundingClientRect();
    const vx0 = -view.x - CULL_MARGIN, vy0 = -view.y - CULL_MARGIN;
    const vx1 = -view.x + r.width + CULL_MARGIN, vy1 = -view.y + r.height + CULL_MARGIN;
    const keep = new Set();
    p.cards.forEach(c => {
      const b = cardBox(c);
      if (b.x + b.w < vx0 || b.x > vx1 || b.y + b.h < vy0 || b.y > vy1) return;
      keep.add(c.slug);
      let el = rendered.get(c.slug);
      if (!el) {
        el = cardEl(c);
        if (!el) return;
        rendered.set(c.slug, el);
        els.cards.appendChild(el);
      }
      el.style.transform = `translate3d(${c.x}px, ${c.y}px, 0)`;
    });
    rendered.forEach((el, slug) => {
      if (!keep.has(slug)) { el.remove(); rendered.delete(slug); }
    });
    renderLinks(p);
  }

  function cardEl(c) {
    const item = App.item(c.slug);
    if (!item) return null;
    const el = document.createElement('div');
    el.className = 'cv-card';
    el.dataset.slug = c.slug;
    el.innerHTML = `
      <div class="cv-cover" style="height:${cardHeight(item)}px">${App.thumbHTML(item)}</div>
      <div class="cv-meta">
        <div class="cv-title">${esc(item.title || item.slug)}</div>
        <button type="button" class="cv-note"></button>
      </div>
      <button type="button" class="cv-remove" title="Remove from project" aria-label="Remove from project">${App.icon('x')}</button>
      <span class="cv-handle" title="Drag to link" aria-hidden="true"></span>`;
    paintNote(el, c);
    return el;
  }
  function paintNote(el, c) {
    const n = el.querySelector('.cv-note');
    n.classList.toggle('is-empty', !c.note);
    n.textContent = c.note ? c.note : 'What’s this here for?';
  }

  function edgePoint(box, tx, ty) {
    const dx = tx - box.cx, dy = ty - box.cy;
    const sx = dx ? (box.w / 2 + 6) / Math.abs(dx) : Infinity;
    const sy = dy ? (box.h / 2 + 6) / Math.abs(dy) : Infinity;
    const k = Math.min(sx, sy, 1);
    return { x: Math.round(box.cx + dx * k), y: Math.round(box.cy + dy * k) };
  }
  function linkMid(p, l) {
    const A = cardBox(p.cards.find(c => c.slug === l.a)), B = cardBox(p.cards.find(c => c.slug === l.b));
    const p1 = edgePoint(A, B.cx, B.cy), p2 = edgePoint(B, A.cx, A.cy);
    return { x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 };
  }

  function renderLinks(p) {
    const byslug = {};
    p.cards.forEach(c => { byslug[c.slug] = c; });
    let lines = '', labels = '';
    p.links.forEach(l => {
      const a = byslug[l.a], b = byslug[l.b];
      if (!a || !b) return;
      const A = cardBox(a), B = cardBox(b);
      // Edge to edge, so the line (and its label) sit in the gap between cards.
      const p1 = edgePoint(A, B.cx, B.cy), p2 = edgePoint(B, A.cx, A.cy);
      lines += `<line x1="${p1.x}" y1="${p1.y}" x2="${p2.x}" y2="${p2.y}" data-link="${l.id}"/>`;
      const mx = (p1.x + p2.x) / 2, my = (p1.y + p2.y) / 2;
      labels += `<button type="button" class="cv-link-label${l.label ? '' : ' is-empty'}" data-link="${l.id}" style="transform:translate3d(${mx}px, ${my}px, 0) translate(-50%, -50%)">${l.label ? esc(l.label) : '+'}</button>`;
    });
    els.links.innerHTML = lines + '<line class="cv-draft" hidden x1="0" y1="0" x2="0" y2="0"/>';
    els.labels.innerHTML = labels;
  }

  // ---------- Placing items ----------
  function placeItem(slug, wx, wy) {
    const p = current();
    if (!p) return;
    if (p.cards.some(c => c.slug === slug)) return;
    const c = { slug, x: Math.round(wx - CARD_W / 2), y: Math.round(wy - 40), note: '' };
    p.cards.push(c);
    save();
    renderBoard();
    scheduleSuggestions();
    showAsk({ kind: 'card', slug });
  }
  function freeSpot() {
    // Next to the right-most card on the top row, or the screen centre for the first.
    const p = current();
    const r = els.stage.getBoundingClientRect();
    if (!p.cards.length) return { x: r.width * 0.35 - view.x, y: r.height * 0.3 - view.y };
    let best = p.cards[p.cards.length - 1];
    const b = cardBox(best);
    return { x: b.x + b.w + 32 + CARD_W / 2, y: b.y + 40 };
  }

  // ---------- Intent prompt ----------
  function showAsk(target) {
    const p = current();
    ask = target;
    let anchor, question, value = '', chips = [];
    if (target.kind === 'card') {
      const c = p.cards.find(x => x.slug === target.slug);
      const item = App.item(target.slug);
      if (!c || !item) return;
      const b = cardBox(c);
      anchor = { x: b.x, y: b.y + b.h + 8, above: b.y - 8 };
      question = 'What’s this here for?';
      value = c.note || '';
      // Recent answers in this project first, then the old preset as a hint.
      const recent = [...new Set(p.cards.filter(x => x.note && x.slug !== c.slug).map(x => x.note).reverse())].slice(0, 2);
      chips = recent.concat(presetIntent(item).filter(t => !recent.includes(t)).slice(0, 1));
    } else {
      const l = p.links.find(x => x.id === target.linkId);
      if (!l) return;
      const m = linkMid(p, l);
      anchor = { x: m.x - 140, y: m.y + 18, above: m.y - 18 };
      question = 'How do these connect?';
      value = l.label || '';
      chips = ['Same type family', 'Colour reference', 'Before / after'];
    }
    els.askQ.textContent = question;
    els.askInput.value = value;
    els.askInput.placeholder = target.kind === 'card' ? 'e.g. headline type, menu colours' : 'e.g. pairs with';
    els.askChips.innerHTML = chips.map(t => `<button type="button" class="ask-chip">${esc(t)}</button>`).join('');
    els.askChips.hidden = !chips.length;
    els.ask.hidden = false;
    // Below the card when it fits, else above it; kept clear of the tray.
    const sr = els.stage.getBoundingClientRect();
    const h = els.ask.offsetHeight;
    let top = anchor.y + view.y;
    if (top + h > sr.height - 84) top = anchor.above + view.y - h;
    const left = Math.max(12, Math.min(anchor.x + view.x, sr.width - 352 - 280 - 12));
    els.ask.style.transform = `translate3d(${left}px, ${Math.max(12, top)}px, 0)`;
    setTimeout(() => els.askInput.focus(), 20);
  }
  function hideAsk() { els.ask.hidden = true; ask = null; }
  function commitAsk(value) {
    const p = current();
    if (!ask || !p) return hideAsk();
    value = String(value || '').trim();
    if (ask.kind === 'card') {
      const c = p.cards.find(x => x.slug === ask.slug);
      if (c) {
        c.note = value;
        const el = rendered.get(c.slug);
        if (el) paintNote(el, c);
      }
    } else {
      const l = p.links.find(x => x.id === ask.linkId);
      if (l) l.label = value;
      renderLinks(p);
    }
    save();
    hideAsk();
  }

  // ---------- Suggestions (rules only) ----------
  function scheduleSuggestions() {
    clearTimeout(suggestTimer);
    suggestTimer = setTimeout(renderTray, 60);
  }
  function suggestions(p) {
    const items = App.items();
    const on = new Set(p.cards.map(c => c.slug));
    const seeds = p.cards.map(c => App.item(c.slug)).filter(Boolean);
    const tagW = new Map(), kinds = new Map(), domains = new Set(), colors = new Set();
    seeds.forEach(s => {
      (s.tags || []).forEach(t => {
        if (t.weight < 0.5 || t.category === 'color' || t.category === 'intent') return;
        const k = t.category + ':' + t.tag;
        tagW.set(k, (tagW.get(k) || 0) + 1);
      });
      if (s.kind && s.kind !== 'link') kinds.set(s.kind, (kinds.get(s.kind) || 0) + 1);
      if (s.domain) domains.add(s.domain);
      const col = topColor(s);
      if (col) colors.add(col);
    });
    const words = tokens(p.name);
    const out = [];
    for (const it of items) {
      if (on.has(it.slug)) continue;
      let score = 0;
      const reasons = [];
      if (words.length) {
        const hay = ((it.title || '') + ' ' + (it.tags || []).map(t => t.tag).join(' ')).toLowerCase();
        const hit = words.filter(w => hay.includes(w));
        if (hit.length) { score += 2 * hit.length; reasons.push(`Matches “${hit[0]}”`); }
      }
      if (seeds.length) {
        const shared = [];
        (it.tags || []).forEach(t => {
          if (t.weight < 0.5) return;
          const n = tagW.get(t.category + ':' + t.tag);
          if (n) { score += 0.6 * n; shared.push(t.tag); }
        });
        if (shared.length >= 2) reasons.unshift(`Shares ${shared.slice(0, 2).join(', ')}`);
        else if (shared.length === 1) score -= 0.4;     // one tag in common is noise
        if (it.domain && domains.has(it.domain)) { score += 1.2; reasons.push(`Same source: ${it.domain}`); }
        const col = topColor(it);
        if (col && colors.has(col)) { score += 0.8; reasons.push(`Same colour: ${col}`); }
        if (it.kind && kinds.has(it.kind)) { score += 0.5; reasons.push(`Also a ${App.kindLine(it) || it.kind}`); }
      }
      if (score >= 1.6 && reasons.length) out.push({ it, score, reason: reasons[0] });
    }
    out.sort((a, b) => b.score - a.score);
    let top = out.slice(0, MAX_SUGGESTIONS);
    if (!top.length) top = items.filter(i => !on.has(i.slug)).slice(0, MAX_SUGGESTIONS).map(it => ({ it, reason: 'Recently saved' }));
    return top;
  }
  function topColor(item) {
    const cs = (item.tags || []).filter(t => t.category === 'color');
    if (!cs.length) return null;
    return cs.reduce((a, b) => (b.weight > a.weight ? b : a)).tag;
  }
  function searchLibrary(q, p) {
    const on = new Set(p.cards.map(c => c.slug));
    const ws = q.toLowerCase().split(/\s+/).filter(Boolean);
    const out = [];
    for (const it of App.items()) {
      if (on.has(it.slug)) continue;
      const hay = ((it.title || '') + ' ' + (it.domain || '') + ' ' + (it.tags || []).map(t => t.tag).join(' ')).toLowerCase();
      if (ws.every(w => hay.includes(w))) out.push({ it, reason: it.domain || App.kindLine(it) || '' });
      if (out.length >= 40) break;
    }
    return out;
  }
  function renderTray() {
    const p = current();
    if (!p) { els.trayList.innerHTML = ''; return; }
    const q = els.traySearch.value.trim();
    const list = q ? searchLibrary(q, p) : suggestions(p);
    els.traySub.textContent = q
      ? `${list.length ? list.length : 'No'} match${list.length === 1 ? '' : 'es'} in your library.`
      : (p.cards.length ? 'Related to what’s on this board.' : `Matching “${p.name}”. Gets sharper as you add items.`);
    els.trayList.innerHTML = list.map(({ it, reason }) => `
      <div class="tray-row" role="listitem" data-slug="${esc(it.slug)}" title="Drag onto the board">
        <div class="tray-thumb">${App.thumbHTML(it)}</div>
        <div class="tray-text">
          <div class="tray-row-title">${esc(it.title || it.slug)}</div>
          <div class="tray-row-reason">${esc(reason)}</div>
        </div>
        <button type="button" class="tray-add" aria-label="Add to project" title="Add to project">${App.icon('plus')}</button>
      </div>`).join('');
  }

  // ---------- Menu ----------
  function renderMenu() {
    const p = current();
    els.menu.innerHTML = data.projects.map(x => `
      <button type="button" class="canvas-menu-item${p && x.id === p.id ? ' is-current' : ''}" data-id="${x.id}" role="menuitem">
        <span>${esc(x.name)}</span><span class="canvas-menu-count">${x.cards.length}</span>
      </button>`).join('') +
      `<div class="canvas-menu-sep"></div>
       <button type="button" class="canvas-menu-item" data-act="new" role="menuitem">${App.icon('plus')}<span>New project</span></button>
       ${p ? `<button type="button" class="canvas-menu-item is-danger" data-act="delete" role="menuitem"><span>Delete “${esc(p.name)}”</span></button>` : ''}`;
  }
  function toggleMenu(force) {
    const show = typeof force === 'boolean' ? force : els.menu.hidden;
    if (show) renderMenu();
    els.menu.hidden = !show;
    els.title.setAttribute('aria-expanded', String(show));
  }

  // ---------- Pointer interactions ----------
  function bind() {
    els.root.querySelector('[data-act="library"]').addEventListener('click', close);
    els.title.addEventListener('click', (e) => { e.stopPropagation(); toggleMenu(); });
    els.menu.addEventListener('click', (e) => {
      const b = e.target.closest('.canvas-menu-item');
      if (!b) return;
      toggleMenu(false);
      if (b.dataset.id) return switchTo(b.dataset.id);
      if (b.dataset.act === 'new') return showStart(true);
      if (b.dataset.act === 'delete') {
        const p = current();
        data.projects = data.projects.filter(x => x.id !== p.id);
        data.currentId = data.projects[0] ? data.projects[0].id : null;
        save();
        return data.currentId ? showProject() : showStart(false);
      }
    });
    document.addEventListener('click', (e) => {
      if (!els.menu.hidden && !e.target.closest('.canvas-header')) toggleMenu(false);
    });

    els.startForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const name = els.startInput.value.trim();
      if (name) createProject(name);
    });
    els.startCancel.addEventListener('click', () => { els.start.hidden = true; });

    // Intent prompt
    els.ask.addEventListener('click', (e) => {
      if (e.target.closest('.ask-skip')) return hideAsk();
      if (e.target.closest('.ask-save')) return commitAsk(els.askInput.value);
      const chip = e.target.closest('.ask-chip');
      if (chip) return commitAsk(chip.textContent);
    });
    els.askInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); commitAsk(els.askInput.value); }
      if (e.key === 'Escape') { e.preventDefault(); hideAsk(); }
    });

    // Tray: search, add button, drag onto the board
    let searchT = 0;
    els.traySearch.addEventListener('input', () => { clearTimeout(searchT); searchT = setTimeout(renderTray, 120); });
    els.trayList.addEventListener('click', (e) => {
      const add = e.target.closest('.tray-add');
      if (!add) return;
      const row = add.closest('.tray-row');
      const s = freeSpot();
      placeItem(row.dataset.slug, s.x, s.y);
    });
    els.trayList.addEventListener('pointerdown', (e) => {
      const row = e.target.closest('.tray-row');
      if (!row || e.target.closest('.tray-add') || e.button !== 0) return;
      e.preventDefault();
      dragFromTray(row, e);
    });

    // Board: pan, move cards, link, open, notes
    els.stage.addEventListener('pointerdown', onStageDown);
    els.stage.addEventListener('wheel', (e) => {
      if (e.ctrlKey) return;
      e.preventDefault();
      view.x -= e.deltaX; view.y -= e.deltaY;
      if (!els.ask.hidden) hideAsk();
      scheduleRender();
    }, { passive: false });
    els.labels.addEventListener('click', (e) => {
      const b = e.target.closest('.cv-link-label');
      if (b) showAsk({ kind: 'link', linkId: b.dataset.link });
    });
    window.addEventListener('resize', scheduleRender);
  }

  function dragFromTray(row, e) {
    const slug = row.dataset.slug;
    const ghost = row.cloneNode(true);
    ghost.classList.add('tray-ghost');
    document.body.appendChild(ghost);
    const move = (ev) => { ghost.style.transform = `translate3d(${ev.clientX - 30}px, ${ev.clientY - 24}px, 0)`; };
    move(e);
    const up = (ev) => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      ghost.remove();
      const r = els.stage.getBoundingClientRect();
      const t = els.tray.getBoundingClientRect();
      const overTray = ev.clientX >= t.left && ev.clientX <= t.right && ev.clientY >= t.top && ev.clientY <= t.bottom;
      if (!overTray && ev.clientX >= r.left && ev.clientX <= r.right && ev.clientY >= r.top && ev.clientY <= r.bottom) {
        const w = screenToWorld(ev.clientX, ev.clientY);
        placeItem(slug, w.x, w.y);
      }
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  }

  function onStageDown(e) {
    if (e.button !== 0) return;
    const p = current();
    if (!p) return;
    const card = e.target.closest('.cv-card');
    if (e.target.closest('.cv-link-label')) return;

    if (card && e.target.closest('.cv-remove')) {
      const slug = card.dataset.slug;
      p.cards = p.cards.filter(c => c.slug !== slug);
      p.links = p.links.filter(l => l.a !== slug && l.b !== slug);
      save(); hideAsk(); renderBoard(); scheduleSuggestions();
      return;
    }
    if (card && e.target.closest('.cv-note')) {
      e.preventDefault();
      return showAsk({ kind: 'card', slug: card.dataset.slug });
    }
    if (!els.ask.hidden) hideAsk();

    const sx = e.clientX, sy = e.clientY;
    let moved = false;

    if (card && e.target.closest('.cv-handle')) {
      // Draw a link to another card.
      const from = p.cards.find(c => c.slug === card.dataset.slug);
      const A = cardBox(from);
      const draft = els.links.querySelector('.cv-draft');
      draft.removeAttribute('hidden');
      draft.setAttribute('x1', A.cx); draft.setAttribute('y1', A.cy);
      card.classList.add('is-linking');
      const move = (ev) => {
        const w = screenToWorld(ev.clientX, ev.clientY);
        draft.setAttribute('x2', w.x); draft.setAttribute('y2', w.y);
        els.cards.querySelectorAll('.cv-card.is-target').forEach(n => n.classList.remove('is-target'));
        const over = document.elementFromPoint(ev.clientX, ev.clientY);
        const t = over && over.closest('.cv-card');
        if (t && t !== card) t.classList.add('is-target');
      };
      const up = (ev) => {
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        draft.setAttribute('hidden', '');
        card.classList.remove('is-linking');
        els.cards.querySelectorAll('.cv-card.is-target').forEach(n => n.classList.remove('is-target'));
        const over = document.elementFromPoint(ev.clientX, ev.clientY);
        const t = over && over.closest('.cv-card');
        if (!t || t === card) return;
        const a = card.dataset.slug, b = t.dataset.slug;
        if (p.links.some(l => (l.a === a && l.b === b) || (l.a === b && l.b === a))) return;
        const link = { id: uid(), a, b, label: '' };
        p.links.push(link);
        save();
        renderLinks(p);
        showAsk({ kind: 'link', linkId: link.id });
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
      e.preventDefault();
      return;
    }

    if (card) {
      // Move the card; a click without movement opens the item panel.
      const c = p.cards.find(x => x.slug === card.dataset.slug);
      const ox = c.x, oy = c.y;
      card.classList.add('is-dragging');
      const move = (ev) => {
        const dx = ev.clientX - sx, dy = ev.clientY - sy;
        if (!moved && Math.hypot(dx, dy) < 4) return;
        moved = true;
        c.x = Math.round(ox + dx); c.y = Math.round(oy + dy);
        card.style.transform = `translate3d(${c.x}px, ${c.y}px, 0)`;
        renderLinks(p);
      };
      const up = () => {
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        card.classList.remove('is-dragging');
        if (moved) save();
        else App.openItem(c.slug);
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
      e.preventDefault();
      return;
    }

    // Empty board: pan.
    const vx = view.x, vy = view.y;
    els.stage.classList.add('is-panning');
    const move = (ev) => {
      view.x = vx + ev.clientX - sx; view.y = vy + ev.clientY - sy;
      scheduleRender();
    };
    const up = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      els.stage.classList.remove('is-panning');
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  }

  // ---------- Boot ----------
  function init() {
    App = window.StelloApp;
    if (!App) return;
    load();
    build();
    bind();
    const btn = document.getElementById('projects-btn');
    if (btn) {
      btn.innerHTML = App.icon('graph');
      btn.addEventListener('click', open);
    }
    if (localStorage.getItem(OPEN_KEY) || new URLSearchParams(location.search).has('projects')) open();
  }
  if (window.StelloApp) init();
  else document.addEventListener('stello:ready', init, { once: true });
})();
