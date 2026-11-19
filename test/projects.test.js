import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeD1 } from './d1-shim.js';
import {
  normalizeDoc, getProject, saveProject, createProject, listProjects, deleteProject, mergeBoard, LIBRARY_ID,
} from '../src/lib/projects.js';
import { handleRpc } from '../src/routes/mcp.js';
import { search, related, pseudoItem, slimItem } from '../src/lib/library.js';

const SQL = readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8')
  + '\n' + readFileSync(new URL('../migrations/0002_projects.sql', import.meta.url), 'utf8');
const U = 'user-1';

function freshDb() {
  const db = makeD1(SQL);
  db.raw.prepare("INSERT INTO users (id, email, created_at) VALUES (?, ?, ?)").run(U, 'a@b.c', Date.now());
  return db;
}

function addItem(db, slug, tags, extra = {}) {
  db.raw.prepare(`INSERT INTO items (id, user_id, slug, title, added_at, updated_at, tags, kind, domain, og_image_path)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
    slug, U, slug, extra.title || slug, new Date().toISOString(), Date.now(), JSON.stringify(tags),
    extra.kind || null, extra.domain || null, extra.img || null);
}

test('normalizeDoc keeps the canvas shape and drops junk', () => {
  const d = normalizeDoc({
    name: 'X', groupBy: 'kind', junk: 1,
    cards: [{ slug: 'a', x: 1.234, y: 2, state: 'use', extra: 1 }, { slug: 'a', x: 9 }, { x: 1 }],
    links: [{ a: 'a', b: 'b', kind: 'influence' }, { a: 'a', b: 'a' }, { a: 'a', b: 'c', kind: 'weird' }],
    notes: [{ kind: 'region', slug: 'a', rx: 2, ry: -1, text: 'here' }, { kind: 'region', text: 'no slug' },
      { kind: 'set', text: 'Part of', slugs: ['a', 'b', 'a'] }],
  });
  assert.deepEqual(d.cards, [{ slug: 'a', x: 1.23, y: 2, state: 'use' }]);
  assert.equal(d.links.length, 2);
  assert.equal(d.links[1].kind, 'manual');
  assert.equal(d.notes.length, 2);
  assert.deepEqual([d.notes[0].rx, d.notes[0].ry], [1, 0]);
  assert.deepEqual(d.notes[1].slugs, ['a', 'b']);
  assert.equal(d.junk, undefined);
});

test('library canvas exists before its first save; rev guards concurrent saves', async () => {
  const db = freshDb();
  const lib = await getProject(db, U, LIBRARY_ID);
  assert.equal(lib.rev, 0);
  const a = await saveProject(db, U, LIBRARY_ID, { cards: [{ slug: 'x', x: 0, y: 0 }] }, 0);
  assert.equal(a.project.rev, 1);
  const stale = await saveProject(db, U, LIBRARY_ID, { cards: [] }, 0);
  assert.ok(stale.conflict);
  assert.equal(stale.conflict.doc.cards.length, 1);
  const b = await saveProject(db, U, LIBRARY_ID, { cards: [] }, 1);
  assert.equal(b.project.rev, 2);
});

test('projects: create, list, delete; scoped to the user', async () => {
  const db = freshDb();
  const { project } = await createProject(db, U, { name: 'Moodboard' });
  assert.equal((await listProjects(db, U)).length, 1);
  assert.equal(await getProject(db, 'someone-else', project.id), null);
  assert.ok(await deleteProject(db, U, project.id));
  assert.equal((await listProjects(db, U)).length, 0);
});

test('mergeBoard: board wins for what it carries, Stello-only content stays', () => {
  const doc = {
    cards: [{ slug: 'a', x: 0, y: 0, note: 'keep' }, { slug: 'z', x: 5, y: 5 }],
    links: [{ id: 'l1', a: 'a', b: 'z', kind: 'contrast', source: 'web' }, { id: 'l2', a: 'a', b: 'b', kind: 'manual', source: 'figjam' }],
    groups: [{ id: 'g', name: 'Calm', slugs: ['a', 'z'] }],
    notes: [{ id: 'fjold', kind: 'note', text: 'gone' }, { id: 'n1', kind: 'question', text: 'stays' }],
  };
  const board = {
    name: 'From FigJam',
    cards: [{ slug: 'a', x: 100, y: 100 }, { slug: 'b', x: 200, y: 100 }],
    links: [{ id: 'fj1', a: 'b', b: 'a', kind: 'influence', label: 'led to' }],
    groups: [{ id: 'fjg', name: 'calm', slugs: ['a', 'b'] }],
    notes: [{ id: 'fjn', kind: 'note', text: 'this spacing', near: 'a' }],
  };
  const m = mergeBoard(doc, board);
  const a = m.cards.find((c) => c.slug === 'a');
  assert.deepEqual([a.x, a.note], [100, 'keep']);
  assert.ok(m.cards.find((c) => c.slug === 'z'));
  assert.equal(m.links.length, 2); // web contrast link stays, old figjam link replaced by the board's
  assert.equal(m.links.find((l) => l.kind === 'influence').source, 'figjam');
  assert.deepEqual(m.groups.map((g) => g.name), ['calm']);
  assert.deepEqual(m.notes.map((n) => n.text).sort(), ['stays', 'this spacing']);
  assert.equal(mergeBoard({ name: 'Mine' }, { name: 'Page 1' }).name, 'Mine');
  // Laid out from Stello, then deleted on the board → gone; still there → keeps id, kind and source.
  const laid = mergeBoard(
    { links: [{ id: 'w1', a: 'a', b: 'b', kind: 'contrast', source: 'web' }, { id: 'w2', a: 'a', b: 'c', kind: 'influence', source: 'web' }],
      notes: [{ id: 'q1', kind: 'region', slug: 'a', rx: 0.2, ry: 0.3, text: 'corner' }, { id: 'q2', kind: 'note', text: 'bye' }] },
    { links: [{ id: 'w1', a: 'a', b: 'b', kind: 'contrast' }],
      notes: [{ id: 'q1', kind: 'region', slug: 'a', rx: 0.2, ry: 0.3, text: 'this corner' }],
      removed: { links: ['w2'], notes: ['q2'] } });
  assert.deepEqual(laid.links.map((l) => [l.id, l.source]), [['w1', 'web']]);
  assert.deepEqual(laid.notes.map((n) => [n.id, n.kind, n.text]), [['q1', 'region', 'this corner']]);
});

test('library: search, related and selection match by Layer 1 rules', () => {
  const rows = [
    { slug: 'pane', title: 'Pane', kind: 'tool', tags: JSON.stringify([{ tag: 'cobalt blue', category: 'color', weight: 1 }, { tag: 'minimalist', category: 'style', weight: 0.8 }]) },
    { slug: 'excal', title: 'Excalidraw', kind: 'tool', tags: JSON.stringify([{ tag: 'blue', category: 'color', weight: 1 }, { tag: 'minimalist', category: 'style', weight: 0.8 }]) },
    { slug: 'ibm', title: 'IBM', kind: 'website', tags: JSON.stringify([{ tag: 'black', category: 'color', weight: 1 }, { tag: 'typography', category: 'subject', weight: 1 }]) },
  ].map((r) => slimItem(r, 'https://s'));
  assert.deepEqual(search(rows, { query: 'pane' }).map((i) => i.slug), ['pane']);
  assert.deepEqual(search(rows, { colour: 'cobalt blue' }).map((i) => i.slug).sort(), ['excal', 'pane']);
  const rel = related(rows, rows[0]);
  assert.equal(rel[0].item.slug, 'excal');
  assert.ok(rel[0].reasons.some((r) => r.type === 'same_style'));
  const sel = related(rows, pseudoItem({ text: 'Typography hero', colours: ['#111111'] }));
  assert.equal(sel[0].item.slug, 'ibm');
});

test('MCP: initialize, tools/list, search and add_to_project', async () => {
  const db = freshDb();
  addItem(db, 'pane', [{ tag: 'minimalist', category: 'style', weight: 1 }], { title: 'Pane', kind: 'tool', img: '/img/u/pane/og.webp' });
  addItem(db, 'excal', [{ tag: 'minimalist', category: 'style', weight: 1 }], { title: 'Excalidraw', kind: 'tool' });
  const env = { DB: db };
  const init = await handleRpc(env, U, 'https://s', { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } });
  assert.equal(init.result.serverInfo.name, 'stello');
  assert.equal(await handleRpc(env, U, 'https://s', { jsonrpc: '2.0', method: 'notifications/initialized' }), null);
  const list = await handleRpc(env, U, 'https://s', { jsonrpc: '2.0', id: 2, method: 'tools/list' });
  assert.ok(list.result.tools.some((t) => t.name === 'search_library'));
  const s = await handleRpc(env, U, 'https://s', { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'search_library', arguments: { query: 'pane' } } });
  const found = JSON.parse(s.result.content[0].text);
  assert.equal(found.items[0].slug, 'pane');
  assert.equal(found.items[0].image, 'https://s/img/u/pane/og.webp');
  const add = await handleRpc(env, U, 'https://s', { jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'add_to_project', arguments: { slugs: ['pane', 'excal', 'nope'], group: 'Tools' } } });
  assert.equal(JSON.parse(add.result.content[0].text).added, 2);
  const lib = await getProject(db, U, LIBRARY_ID);
  assert.deepEqual(lib.doc.groups[0].slugs, ['pane', 'excal']);
  const link = await handleRpc(env, U, 'https://s', { jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'link_items', arguments: { a: 'pane', b: 'excal', kind: 'influence' } } });
  assert.ok(!link.result.isError);
  assert.equal((await getProject(db, U, LIBRARY_ID)).doc.links[0].source, 'mcp');
});
