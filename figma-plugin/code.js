/* Stello for Figma and FigJam — main thread (the canvas side).
 *
 * The panel (ui.html) talks to Stello over the network and sends this side
 * plain messages. This side owns the canvas:
 *   - insert Stello cards (image + title + kind · source + tags + colours),
 *     each carrying its Stello slug and source link (plugin data + relaunch
 *     buttons "Open source" / "Open in Stello");
 *   - report the selection so the panel can show related saves;
 *   - FigJam Board sync: lay a Stello project out as sections, cards,
 *     connectors (Layer 2 links) and stickies (notes), and read a board back;
 *   - draw / clear Layer 1 "similar" lines (dashed, never synced back);
 *   - export the selection as PNG for "Save to Stello".
 */

const NS = 'stello';
const CARD_W = 240;
const IMG_MAX_H = 320;
const GAP = 40;
const IS_JAM = figma.editorType === 'figjam';

// Layer 2 link colours (Exploration canvas legend) and Layer 1 line colours.
const LINK_COLOURS = {
  influence: '#E5484D', contrast: '#6E56CF', part_of: '#0090FF', question: '#F5A524',
  maybe: '#8B8D98', manual: '#3A3A3A',
};
const L1_COLOURS = {
  same_colour: '#3E63DD', same_style: '#12A594', same_idea: '#30A46C', same_kind: '#8E4EC6',
  same_place: '#F76B15', same_source: '#8B8D98',
};
const L1_LABEL = {
  same_colour: 'Same colour', same_style: 'Same style', same_idea: 'Same idea', same_kind: 'Same kind',
  same_place: 'Same place', same_source: 'Same source',
};
const LINK_WORDS = [
  ['influence', /influenc|inspired|led to/i], ['contrast', /contrast|opposite|versus|vs\b/i],
  ['part_of', /part of|belongs/i], ['question', /\?|question/i], ['maybe', /maybe|related\?/i],
];

function hex(h) {
  const s = h.replace('#', '');
  return { r: parseInt(s.slice(0, 2), 16) / 255, g: parseInt(s.slice(2, 4), 16) / 255, b: parseInt(s.slice(4, 6), 16) / 255 };
}
function toHex({ r, g, b }) {
  return '#' + [r, g, b].map((v) => Math.round(v * 255).toString(16).padStart(2, '0')).join('');
}
const solid = (h, opacity = 1) => [{ type: 'SOLID', color: hex(h), opacity }];

let fontsReady = null;
function loadFonts() {
  if (!fontsReady) {
    fontsReady = Promise.all([
      figma.loadFontAsync({ family: 'Inter', style: 'Regular' }),
      figma.loadFontAsync({ family: 'Inter', style: 'Semi Bold' }),
    ]);
  }
  return fontsReady;
}

figma.showUI(__html__, { width: 340, height: 600, themeColors: true, title: 'Stello' });

// Relaunch buttons on a card.
if (figma.command === 'open-source' || figma.command === 'open-stello') {
  const node = figma.currentPage.selection[0];
  const card = node && cardOf(node);
  const url = card && card.getPluginData(figma.command === 'open-source' ? 'url' : 'stello_url');
  if (url) figma.openExternal(url);
  else figma.notify('This card has no link.');
}

// ------------------------------------------------------------------ cards

function cardOf(node) {
  let n = node;
  while (n && n.type !== 'PAGE' && n.type !== 'DOCUMENT') {
    if (n.getPluginData && n.getPluginData('slug')) return n;
    n = n.parent;
  }
  return null;
}

function text(chars, { size = 11, bold = false, colour = '#1A1A1A', width = CARD_W - 24 } = {}) {
  const t = figma.createText();
  t.fontName = { family: 'Inter', style: bold ? 'Semi Bold' : 'Regular' };
  t.fontSize = size;
  t.characters = chars;
  t.fills = solid(colour);
  t.textAutoResize = 'HEIGHT';
  t.resize(width, t.height);
  return t;
}

async function imageFill(url) {
  try {
    const img = await figma.createImageAsync(url);
    const size = await img.getSizeAsync();
    return { hash: img.hash, ...size };
  } catch (e) {
    return null;
  }
}

/** One Stello card. `item` is a slim library item from the panel. */
async function makeCard(item) {
  await loadFonts();
  const card = figma.createFrame();
  card.name = `Stello · ${item.title}`;
  card.layoutMode = 'VERTICAL';
  card.primaryAxisSizingMode = 'AUTO';
  card.counterAxisSizingMode = 'FIXED';
  card.resize(CARD_W, 100);
  card.itemSpacing = 0;
  card.cornerRadius = 12;
  card.clipsContent = true;
  card.fills = solid('#FFFFFF');
  card.strokes = solid('#000000', 0.08);
  card.strokeWeight = 1;
  card.effects = [{ type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: 0.06 }, offset: { x: 0, y: 2 }, radius: 8, spread: 0, visible: true, blendMode: 'NORMAL' }];

  const imgUrl = item.figma_image || item.image;
  const fill = imgUrl ? await imageFill(imgUrl) : null;
  const cover = figma.createRectangle();
  cover.name = 'Image';
  if (fill) {
    const h = Math.min(IMG_MAX_H, Math.max(90, Math.round(CARD_W * fill.height / fill.width)));
    cover.resize(CARD_W, h);
    cover.fills = [{ type: 'IMAGE', imageHash: fill.hash, scaleMode: 'FILL' }];
  } else {
    cover.resize(CARD_W, 120);
    cover.fills = solid((item.colours[0] && item.colours[0].hex) || '#EDEDED', item.colours[0] ? 0.35 : 1);
  }
  card.appendChild(cover);

  const body = figma.createFrame();
  body.name = 'Details';
  body.layoutMode = 'VERTICAL';
  body.primaryAxisSizingMode = 'AUTO';
  body.counterAxisSizingMode = 'FIXED';
  body.resize(CARD_W, 10);
  body.paddingLeft = body.paddingRight = 12;
  body.paddingTop = 10; body.paddingBottom = 12;
  body.itemSpacing = 4;
  body.fills = [];
  card.appendChild(body);
  body.layoutAlign = 'STRETCH';

  body.appendChild(text(item.title, { size: 13, bold: true }));
  const meta = [item.kind && item.kind[0].toUpperCase() + item.kind.slice(1), item.domain, item.place].filter(Boolean).join(' · ');
  if (meta) body.appendChild(text(meta, { colour: '#6F6F6F' }));
  const tags = item.tags.slice(0, 4).map((t) => t.tag).join(', ');
  if (tags) body.appendChild(text(tags, { colour: '#8A8A8A' }));
  if (item.colours.length) {
    const row = figma.createFrame();
    row.name = 'Colours';
    row.layoutMode = 'HORIZONTAL';
    row.primaryAxisSizingMode = 'AUTO';
    row.counterAxisSizingMode = 'AUTO';
    row.itemSpacing = 4;
    row.fills = [];
    for (const c of item.colours.slice(0, 5)) {
      if (!c.hex) continue;
      const dot = figma.createEllipse();
      dot.name = c.name;
      dot.resize(10, 10);
      dot.fills = solid(c.hex);
      dot.strokes = solid('#000000', 0.12);
      row.appendChild(dot);
    }
    if (row.children.length) body.appendChild(row); else row.remove();
  }

  card.setPluginData('slug', item.slug);
  card.setPluginData('url', item.source_url || '');
  card.setPluginData('stello_url', item.stello_url || '');
  card.setSharedPluginData(NS, 'slug', item.slug);
  card.setSharedPluginData(NS, 'url', item.source_url || '');
  const relaunch = { 'open-stello': 'From your Stello library', panel: '' };
  if (item.source_url) relaunch['open-source'] = item.source_url.replace(/^https?:\/\//, '').slice(0, 60);
  card.setRelaunchData(relaunch);
  return card;
}

function viewportCentre() {
  const { x, y } = figma.viewport.center;
  return { x, y };
}

/** Insert cards in a row (wrapping every 4) starting at `at`. */
async function insertCards(items, at, { select = true } = {}) {
  const start = at || viewportCentre();
  const made = [];
  let x = start.x, y = start.y, rowH = 0;
  for (let i = 0; i < items.length; i++) {
    const card = await makeCard(items[i]);
    figma.currentPage.appendChild(card);
    if (i && i % 4 === 0) { x = start.x; y += rowH + GAP; rowH = 0; }
    card.x = x; card.y = y;
    x += CARD_W + GAP; rowH = Math.max(rowH, card.height);
    made.push(card);
  }
  if (select && made.length) {
    figma.currentPage.selection = made;
    if (!at) figma.viewport.scrollAndZoomIntoView(made);
  }
  return made;
}

/** Put cards to the right of the current selection (for "related"). */
function besideSelection() {
  const sel = figma.currentPage.selection;
  if (!sel.length) return null;
  const right = Math.max(...sel.map((n) => n.absoluteBoundingBox ? n.absoluteBoundingBox.x + n.absoluteBoundingBox.width : n.x + n.width));
  const top = Math.min(...sel.map((n) => n.absoluteBoundingBox ? n.absoluteBoundingBox.y : n.y));
  return { x: right + GAP * 2, y: top };
}

// ------------------------------------------------------------------ selection

function collectSelection() {
  const sel = figma.currentPage.selection;
  const slugs = [];
  const words = [];
  const colours = new Map();
  let exportable = 0;
  const visit = (n, depth) => {
    if (depth > 4 || words.length > 200) return;
    if (n.type === 'TEXT' && n.characters) words.push(n.characters.slice(0, 200));
    if ('fills' in n && Array.isArray(n.fills)) {
      for (const f of n.fills) {
        if (f.type === 'SOLID' && f.visible !== false) {
          const h = toHex(f.color);
          colours.set(h, (colours.get(h) || 0) + (n.width * n.height || 1));
        }
      }
    }
    if ('children' in n) for (const c of n.children.slice(0, 60)) visit(c, depth + 1);
  };
  for (const n of sel) {
    const card = cardOf(n);
    if (card) { slugs.push(card.getPluginData('slug')); continue; }
    words.push(n.name);
    if ('exportAsync' in n) exportable++;
    visit(n, 0);
  }
  // Ignore near-white / near-black canvas noise, keep the 5 biggest areas.
  const picked = [...colours.entries()]
    .filter(([h]) => { const { r, g, b } = hex(h); const l = (r + g + b) / 3; return l > 0.06 && l < 0.95; })
    .sort((a, b) => b[1] - a[1]).slice(0, 5).map(([h]) => h);
  return { count: sel.length, slugs: [...new Set(slugs)], text: words.join(' ').slice(0, 3000), colours: picked, exportable };
}

let selTimer = null;
figma.on('selectionchange', () => {
  clearTimeout(selTimer);
  selTimer = setTimeout(() => figma.ui.postMessage({ type: 'selection', selection: collectSelection() }), 250);
});

// ------------------------------------------------------------------ drag and drop

figma.on('drop', (event) => {
  const data = event.dropMetadata;
  if (!data || !data.stello) return true;
  insertCards(data.items, { x: event.absoluteX, y: event.absoluteY }, { select: true })
    .catch((e) => figma.notify(`Couldn't place it: ${e.message}`));
  return false;
});

// ------------------------------------------------------------------ FigJam Board sync

function pageProjectId() { return figma.currentPage.getPluginData('project') || ''; }

async function sticky(chars, colour) {
  const s = figma.createSticky();
  await figma.loadFontAsync(s.text.fontName);
  s.text.characters = chars;
  if (colour) s.fills = solid(colour);
  return s;
}

async function connect(a, b, colour, label, dashed) {
  const c = figma.createConnector();
  c.connectorStart = { endpointNodeId: a.id, magnet: 'AUTO' };
  c.connectorEnd = { endpointNodeId: b.id, magnet: 'AUTO' };
  c.strokes = solid(colour);
  c.strokeWeight = dashed ? 1 : 2;
  if (dashed) c.dashPattern = [4, 4];
  c.connectorEndStrokeCap = dashed ? 'NONE' : 'ARROW_LINES';
  if (label) { await figma.loadFontAsync(c.text.fontName); c.text.characters = label; }
  return c;
}

/**
 * Lay a project out on the current FigJam page. `project` = { id, name, doc },
 * `items` = slug → slim item. Existing Stello cards on the page are reused.
 */
async function pushBoard(project, items) {
  if (!IS_JAM) throw new Error('Board sync works in FigJam.');
  await loadFonts();
  await figma.loadFontAsync({ family: 'Inter', style: 'Medium' }).catch(() => {});
  const doc = project.doc;
  const existing = new Map();
  figma.currentPage.findAll((n) => !!n.getPluginData('slug')).forEach((n) => existing.set(n.getPluginData('slug'), n));
  const cards = new Map();
  const ensure = async (slug) => {
    if (cards.has(slug)) return cards.get(slug);
    let node = existing.get(slug);
    if (!node && items[slug]) { node = await makeCard(items[slug]); figma.currentPage.appendChild(node); }
    if (node) cards.set(slug, node);
    return node;
  };

  const placed = new Set();
  const origin = viewportCentre();
  let sx = origin.x;
  const sy = origin.y;
  // Groups → sections, cards in a 3-wide grid inside.
  for (const g of doc.groups) {
    const nodes = [];
    for (const slug of g.slugs) { const n = await ensure(slug); if (n) { nodes.push(n); placed.add(slug); } }
    if (!nodes.length) continue;
    const section = figma.createSection();
    section.name = g.name || 'Group';
    section.setPluginData('group', g.id);
    const cols = Math.min(3, nodes.length);
    let x = 40, y = 80, rowH = 0;
    nodes.forEach((n, i) => {
      if (i && i % cols === 0) { x = 40; y += rowH + GAP; rowH = 0; }
      section.appendChild(n);
      n.x = x; n.y = y;
      x += CARD_W + GAP; rowH = Math.max(rowH, n.height);
    });
    section.resizeWithoutConstraints(cols * (CARD_W + GAP) + 40, y + rowH + 40);
    section.x = sx; section.y = sy;
    sx += section.width + 120;
  }
  // Loose cards keep their canvas positions, offset to sit below the sections.
  const loose = doc.cards.filter((c) => !placed.has(c.slug));
  const minX = Math.min(...loose.map((c) => c.x), 0), minY = Math.min(...loose.map((c) => c.y), 0);
  const looseTop = sy + (doc.groups.length ? 1200 : 0);
  for (const c of loose) {
    const n = await ensure(c.slug);
    if (!n) continue;
    if (n.parent !== figma.currentPage) figma.currentPage.appendChild(n);
    n.x = origin.x + (c.x - minX); n.y = looseTop + (c.y - minY);
  }
  // Card notes and notes → stickies; Layer 2 links → connectors.
  for (const n of figma.currentPage.findAll((x) => !!x.getPluginData('note') || !!x.getPluginData('link'))) n.remove();
  const pushedNotes = [];
  const pushedLinks = [];
  for (const c of doc.cards) {
    if (!c.note) continue;
    const card = cards.get(c.slug);
    if (!card) continue;
    const s = await sticky(c.note, '#FFF3B0');
    s.setPluginData('note', `card:${c.slug}`);
    const b = card.absoluteBoundingBox;
    s.x = b.x + b.width + 24; s.y = b.y;
  }
  for (const n of doc.notes) {
    if (n.kind === 'set') continue;
    const near = n.near ? cards.get(n.near) : n.slug ? cards.get(n.slug) : null;
    const prefix = n.kind === 'question' ? '' : n.kind === 'region' ? 'On the image: ' : '';
    const s = await sticky(prefix + (n.text || ''), n.kind === 'question' ? '#FFE1B3' : '#FFF3B0');
    s.setPluginData('note', n.id);
    s.setPluginData('note_json', JSON.stringify(n));
    pushedNotes.push(n.id);
    if (near) { const b = near.absoluteBoundingBox; s.x = b.x + b.width + 24; s.y = b.y + 140; }
    else { s.x = origin.x + (n.x || 0); s.y = origin.y - 400 + (n.y || 0); }
  }
  for (const l of doc.links) {
    const a = cards.get(l.a), b = cards.get(l.b);
    if (!a || !b) continue;
    const label = l.label || (l.kind !== 'manual' ? l.kind.replace('_', ' ') : '');
    const c = await connect(a, b, LINK_COLOURS[l.kind] || LINK_COLOURS.manual, label, false);
    c.setPluginData('link', l.id);
    c.setPluginData('kind', l.kind);
    pushedLinks.push(l.id);
  }
  figma.currentPage.setPluginData('pushed', JSON.stringify({ notes: pushedNotes, links: pushedLinks }));
  figma.currentPage.setPluginData('project', project.id);
  figma.currentPage.setPluginData('project_name', project.name || '');
  const all = [...cards.values()];
  if (all.length) figma.viewport.scrollAndZoomIntoView(all);
  return { cards: all.length };
}

/** Read the current FigJam page as a board doc for /api/projects/:id/board. */
async function readBoard() {
  const page = figma.currentPage;
  const cardNodes = page.findAll((n) => !!n.getPluginData('slug'));
  const byId = new Map(cardNodes.map((n) => [n.id, n]));
  const cards = [];
  const groups = new Map();
  for (const n of cardNodes) {
    const slug = n.getPluginData('slug');
    const b = n.absoluteBoundingBox || { x: n.x, y: n.y };
    const card = { slug, x: Math.round(b.x), y: Math.round(b.y) };
    let p = n.parent;
    while (p && p.type !== 'PAGE') {
      if (p.type === 'SECTION') {
        const name = (p.name || '').trim();
        if (/^use$/i.test(name)) card.state = 'use';
        else if (/^reject(ed)?$/i.test(name)) card.state = 'rejected';
        else {
          const key = p.id;
          if (!groups.has(key)) groups.set(key, { id: 'fj' + p.id.replace(/[^A-Za-z0-9]/g, '_'), name: name || 'Group', slugs: [] });
          groups.get(key).slugs.push(slug);
        }
        break;
      }
      p = p.parent;
    }
    cards.push(card);
  }
  const resolve = async (endpoint) => {
    if (!endpoint || !endpoint.endpointNodeId) return null;
    let node = byId.get(endpoint.endpointNodeId);
    if (!node) node = cardOf(await figma.getNodeByIdAsync(endpoint.endpointNodeId));
    return node ? node.getPluginData('slug') : null;
  };
  const links = [];
  for (const c of page.findAll((n) => n.type === 'CONNECTOR')) {
    if (c.getPluginData('auto')) continue; // Layer 1 lines are computed, never stored
    const a = await resolve(c.connectorStart), b = await resolve(c.connectorEnd);
    if (!a || !b || a === b) continue;
    const label = (c.text && c.text.characters || '').trim();
    let kind = c.getPluginData('kind');
    if (!kind) kind = (LINK_WORDS.find(([, re]) => re.test(label)) || ['manual'])[0];
    const id = c.getPluginData('link') || 'fj' + c.id.replace(/[^A-Za-z0-9]/g, '_');
    links.push({ id, a, b, kind, label: label.replace(/^(influence|contrast|part of|part_of|maybe)$/i, '') });
  }
  const notes = [];
  const cardBoxes = cardNodes.map((n) => ({ slug: n.getPluginData('slug'), b: n.absoluteBoundingBox }));
  const cardNotes = new Map();
  for (const s of page.findAll((n) => n.type === 'STICKY')) {
    const txt = (s.text.characters || '').trim();
    const tag = s.getPluginData('note');
    if (tag.startsWith('card:')) { cardNotes.set(tag.slice(5), txt); continue; } // a card's own note
    if (!txt) continue;
    const sb = s.absoluteBoundingBox;
    let orig = null;
    try { orig = tag ? JSON.parse(s.getPluginData('note_json') || 'null') : null; } catch (e) { orig = null; }
    if (orig) {
      // A note that came from Stello keeps its id, kind and anchor.
      const keep = { ...orig, text: txt.replace(/^On the image:\s*/, ''), x: Math.round(sb.x), y: Math.round(sb.y) };
      if (keep.near && !cardBoxes.some((c) => c.slug === keep.near)) delete keep.near;
      notes.push(keep);
      continue;
    }
    let near = null, best = 420;
    for (const { slug, b } of cardBoxes) {
      const dx = Math.max(b.x - (sb.x + sb.width), sb.x - (b.x + b.width), 0);
      const dy = Math.max(b.y - (sb.y + sb.height), sb.y - (b.y + b.height), 0);
      const d = Math.hypot(dx, dy);
      if (d < best) { best = d; near = slug; }
    }
    notes.push({
      id: 'fj' + s.id.replace(/[^A-Za-z0-9]/g, '_'),
      kind: /\?\s*$/.test(txt) ? 'question' : 'note',
      text: txt.replace(/^On the image:\s*/, ''),
      x: Math.round(sb.x), y: Math.round(sb.y),
      ...(near ? { near } : {}),
    });
  }
  for (const card of cards) if (cardNotes.has(card.slug)) card.note = cardNotes.get(card.slug);
  // What was laid out from Stello and has since been deleted on the board.
  let pushed = { notes: [], links: [] };
  try { pushed = JSON.parse(page.getPluginData('pushed') || '{}'); } catch (e) { /* none */ }
  const noteIds = new Set(notes.map((n) => n.id)), linkIds = new Set(links.map((l) => l.id));
  return {
    name: page.getPluginData('project_name') || page.name,
    cards, links, notes, groups: [...groups.values()],
    removed: {
      notes: (pushed.notes || []).filter((id) => !noteIds.has(id)),
      links: (pushed.links || []).filter((id) => !linkIds.has(id)),
    },
  };
}

function clearSimilar() {
  const old = figma.currentPage.findAll((n) => n.type === 'CONNECTOR' && !!n.getPluginData('auto'));
  old.forEach((n) => n.remove());
  return old.length;
}

async function drawSimilar(links) {
  clearSimilar();
  const bySlug = new Map();
  figma.currentPage.findAll((n) => !!n.getPluginData('slug')).forEach((n) => bySlug.set(n.getPluginData('slug'), n));
  let n = 0;
  for (const l of links) {
    const a = bySlug.get(l.a), b = bySlug.get(l.b);
    if (!a || !b) continue;
    const c = await connect(a, b, L1_COLOURS[l.type] || '#8B8D98', `${L1_LABEL[l.type] || 'Similar'} · ${l.value}`, true);
    c.setPluginData('auto', '1');
    c.opacity = 0.7;
    n++;
  }
  return n;
}

function boardSlugs() {
  return [...new Set(figma.currentPage.findAll((n) => !!n.getPluginData('slug')).map((n) => n.getPluginData('slug')))];
}

// ------------------------------------------------------------------ save to Stello

async function exportSelection() {
  const nodes = figma.currentPage.selection.filter((n) => 'exportAsync' in n && !cardOf(n)).slice(0, 10);
  const out = [];
  for (const n of nodes) {
    const longest = Math.max(n.width, n.height) || 1;
    const scale = Math.min(2, 2400 / longest);
    const bytes = await n.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: scale } });
    const key = figma.fileKey;
    const link = key ? `https://www.figma.com/${IS_JAM ? 'board' : 'design'}/${key}/?node-id=${encodeURIComponent(n.id.replace(':', '-'))}` : '';
    out.push({ name: n.name, bytes, link });
  }
  return out;
}

// ------------------------------------------------------------------ messages

figma.ui.onmessage = async (msg) => {
  const reply = (data) => figma.ui.postMessage({ type: 'reply', id: msg.id, ...data });
  try {
    switch (msg.type) {
      case 'init': {
        const [token, origin] = await Promise.all([figma.clientStorage.getAsync('token'), figma.clientStorage.getAsync('origin')]);
        reply({ token: token || null, origin: origin || null, editor: figma.editorType, project: pageProjectId(), selection: collectSelection() });
        break;
      }
      case 'store': {
        await figma.clientStorage.setAsync(msg.key, msg.value);
        reply({ ok: true });
        break;
      }
      case 'open': figma.openExternal(msg.url); reply({ ok: true }); break;
      case 'notify': figma.notify(msg.text, { timeout: msg.timeout || 3000 }); reply({ ok: true }); break;
      case 'insert': {
        const at = msg.beside ? besideSelection() : null;
        const made = await insertCards(msg.items, at);
        reply({ count: made.length });
        break;
      }
      case 'push-board': reply(await pushBoard(msg.project, msg.items)); break;
      case 'read-board': reply({ board: await readBoard(), project: pageProjectId() }); break;
      case 'set-project': figma.currentPage.setPluginData('project', msg.project || ''); figma.currentPage.setPluginData('project_name', msg.name || ''); reply({ ok: true }); break;
      case 'board-slugs': reply({ slugs: boardSlugs() }); break;
      case 'draw-similar': reply({ count: await drawSimilar(msg.links) }); break;
      case 'clear-similar': reply({ count: clearSimilar() }); break;
      case 'export-selection': reply({ files: await exportSelection() }); break;
      case 'resize': figma.ui.resize(340, Math.max(360, Math.min(900, msg.height))); reply({ ok: true }); break;
      default: reply({ error: `Unknown message ${msg.type}` });
    }
  } catch (e) {
    reply({ error: (e && e.message) || String(e) });
  }
};
