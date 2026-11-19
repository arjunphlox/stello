/**
 * Stello MCP server — POST /api/mcp (Streamable HTTP, JSON responses, stateless).
 *
 * For the Figma agent (custom connector with an Authorization header), Claude
 * Code, Cursor and any MCP client. Auth: `Authorization: Bearer <device token>`
 * — get one by pairing (the Figma plugin, or /pair.html?new=1 on the web).
 *
 * Read tools: search_library, get_item, related_items, list_projects, get_project.
 * Write tools: add_to_project, link_items, add_note (clients usually keep
 * write tools off until the user turns them on).
 */
import auth from '../lib/auth.js';
import { loadLibrary, search, related, layer1 } from '../lib/library.js';
import { listProjects, getProject, createProject, saveProject, LIBRARY_ID, LINK_KINDS, newId } from '../lib/projects.js';

const PROTOCOL = '2025-06-18';
const SERVER = { name: 'stello', title: 'Stello', version: '1.0.0' };

const KINDS = ['website', 'tool', 'post', 'product', 'resource', 'article', 'course', 'book', 'image', 'video', 'music', 'snippet'];

const TOOLS = [
  {
    name: 'search_library',
    title: 'Search my Stello library',
    description: 'Search the saves in Stello by words, kind, tag/collection or colour. Returns slim items with title, kind, source, tags, colours and image URL.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Words to match in title, source, tags and summary' },
        kind: { type: 'string', description: `One of: ${KINDS.join(', ')}` },
        tag: { type: 'string', description: 'A tag or collection name' },
        colour: { type: 'string', description: 'A colour name (e.g. "cobalt blue") or #hex' },
        limit: { type: 'integer', minimum: 1, maximum: 50, default: 20 },
      },
    },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'get_item',
    title: 'Get one save',
    description: 'Full detail for one save by its slug: summary, tags, colours, source, image.',
    inputSchema: { type: 'object', properties: { slug: { type: 'string' } }, required: ['slug'] },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'related_items',
    title: 'Related saves',
    description: 'Saves related to one save, with the reasons (same colour, same style, same idea, same place, same kind, same source).',
    inputSchema: {
      type: 'object',
      properties: { slug: { type: 'string' }, limit: { type: 'integer', minimum: 1, maximum: 30, default: 10 } },
      required: ['slug'],
    },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'list_projects',
    title: 'List canvases and projects',
    description: 'The library canvas (id "library") and named projects, with card counts.',
    inputSchema: { type: 'object', properties: {} },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'get_project',
    title: 'Get a canvas or project',
    description: 'Cards (with item titles), groups, Layer 2 links and notes of a project. id "library" is the library canvas.',
    inputSchema: { type: 'object', properties: { id: { type: 'string', default: LIBRARY_ID } } },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'add_to_project',
    title: 'Add saves to a project',
    description: 'Place saves on a project (or the library canvas), optionally in a named group. Pass project_id "new" with name to create one.',
    inputSchema: {
      type: 'object',
      properties: {
        project_id: { type: 'string', default: LIBRARY_ID },
        name: { type: 'string', description: 'Name for a new project (project_id "new")' },
        slugs: { type: 'array', items: { type: 'string' }, minItems: 1, maxItems: 100 },
        group: { type: 'string', description: 'Group (section) name to put them in' },
      },
      required: ['slugs'],
    },
    annotations: { readOnlyHint: false, destructiveHint: false },
  },
  {
    name: 'link_items',
    title: 'Link two saves',
    description: `Draw a Layer 2 link between two cards in a project. kind: ${LINK_KINDS.join(', ')}.`,
    inputSchema: {
      type: 'object',
      properties: {
        project_id: { type: 'string', default: LIBRARY_ID },
        a: { type: 'string' }, b: { type: 'string' },
        kind: { type: 'string', enum: LINK_KINDS, default: 'manual' },
        label: { type: 'string' },
      },
      required: ['a', 'b'],
    },
    annotations: { readOnlyHint: false, destructiveHint: false },
  },
  {
    name: 'add_note',
    title: 'Add a note or question',
    description: 'Add a note or question to a project, optionally next to one card.',
    inputSchema: {
      type: 'object',
      properties: {
        project_id: { type: 'string', default: LIBRARY_ID },
        text: { type: 'string' },
        kind: { type: 'string', enum: ['note', 'question'], default: 'note' },
        near: { type: 'string', description: 'Slug of the card it belongs next to' },
      },
      required: ['text'],
    },
    annotations: { readOnlyHint: false, destructiveHint: false },
  },
];

const rpcResult = (id, result) => ({ jsonrpc: '2.0', id, result });
const rpcError = (id, code, message) => ({ jsonrpc: '2.0', id, error: { code, message } });
const text = (obj) => ({ content: [{ type: 'text', text: typeof obj === 'string' ? obj : JSON.stringify(obj, null, 1) }] });
const toolError = (msg) => ({ content: [{ type: 'text', text: msg }], isError: true });

function brief(it) {
  return {
    slug: it.slug, title: it.title, kind: it.kind, source: it.source_url || it.domain,
    tags: it.tags.map((t) => t.tag).slice(0, 8), colours: it.colours.map((c) => c.name),
    place: it.place, summary: it.summary, image: it.image, open_in_stello: it.stello_url,
  };
}

/** Save with one retry on a rev conflict (another client saved in between). */
async function editProject(db, userId, id, change) {
  for (let i = 0; i < 2; i++) {
    const p = await getProject(db, userId, id);
    if (!p) return { error: `No project "${id}". Use list_projects.` };
    const doc = change(structuredClone(p.doc));
    if (doc && doc.error) return doc;
    const out = await saveProject(db, userId, id, doc, p.rev);
    if (out.project) return out;
    if (!out.conflict) return { error: out.error || 'Save failed' };
  }
  return { error: 'The project changed while saving. Try again.' };
}

function placeNew(doc, slugs) {
  const maxY = doc.cards.reduce((m, c) => Math.max(m, c.y), -Infinity);
  const y0 = Number.isFinite(maxY) ? maxY + 400 : 0;
  const have = new Set(doc.cards.map((c) => c.slug));
  let n = 0;
  for (const slug of slugs) {
    if (have.has(slug)) continue;
    doc.cards.push({ slug, x: (n % 6) * 240, y: y0 + Math.floor(n / 6) * 320 });
    have.add(slug); n++;
  }
  return n;
}

async function callTool(env, userId, origin, name, args = {}) {
  const db = env.DB;
  const lib = () => loadLibrary(db, userId, origin);
  switch (name) {
    case 'search_library': {
      const items = search(await lib(), { query: args.query, kind: args.kind, tag: args.tag, colour: args.colour, limit: Math.min(args.limit || 20, 50) });
      return text({ count: items.length, items: items.map(brief) });
    }
    case 'get_item': {
      const it = (await lib()).find((i) => i.slug === args.slug);
      return it ? text({ ...brief(it), author: it.author, added_at: it.added_at, collections: it.collections, all_tags: it.tags }) : toolError(`No save with slug "${args.slug}".`);
    }
    case 'related_items': {
      const all = await lib();
      const seed = all.find((i) => i.slug === args.slug);
      if (!seed) return toolError(`No save with slug "${args.slug}".`);
      const rel = related(all, seed, { limit: Math.min(args.limit || 10, 30) });
      return text({ for: brief(seed).title, related: rel.map((r) => ({ ...brief(r.item), why: r.reasons })) });
    }
    case 'list_projects': {
      const list = await listProjects(db, userId);
      if (!list.some((p) => p.id === LIBRARY_ID)) list.unshift({ id: LIBRARY_ID, name: 'Library canvas', cards: 0 });
      return text(list);
    }
    case 'get_project': {
      const p = await getProject(db, userId, args.id || LIBRARY_ID);
      if (!p) return toolError(`No project "${args.id}".`);
      const bySlug = new Map((await lib()).map((i) => [i.slug, i]));
      const title = (s) => (bySlug.get(s) || {}).title || s;
      return text({
        id: p.id, name: p.name, group_by: p.doc.groupBy,
        groups: p.doc.groups.map((g) => ({ name: g.name, items: g.slugs.map(title) })),
        cards: p.doc.cards.map((c) => ({ slug: c.slug, title: title(c.slug), note: c.note, state: c.state })),
        links: p.doc.links.map((l) => ({ a: title(l.a), b: title(l.b), kind: l.kind, label: l.label })),
        notes: p.doc.notes.map((n) => ({ kind: n.kind, text: n.text, near: n.near ? title(n.near) : undefined })),
      });
    }
    case 'add_to_project': {
      const slugs = (Array.isArray(args.slugs) ? args.slugs : []).slice(0, 100);
      const known = new Set((await lib()).map((i) => i.slug));
      const ok = slugs.filter((s) => known.has(s));
      if (!ok.length) return toolError('None of those slugs are in the library. Use search_library first.');
      let id = args.project_id || LIBRARY_ID;
      if (id === 'new') {
        const made = await createProject(db, userId, { name: args.name || 'From the agent' });
        if (!made.project) return toolError('Could not create the project.');
        id = made.project.id;
      }
      let added = 0;
      const out = await editProject(db, userId, id, (doc) => {
        added = placeNew(doc, ok);
        if (args.group) {
          const name = String(args.group).slice(0, 200);
          doc.groups.forEach((g) => { g.slugs = g.slugs.filter((s) => !ok.includes(s)); });
          let g = doc.groups.find((x) => x.name.toLowerCase() === name.toLowerCase());
          if (!g) { g = { id: newId(), name, slugs: [] }; doc.groups.push(g); }
          g.slugs.push(...ok);
          doc.groups = doc.groups.filter((x) => x.slugs.length);
        }
        return doc;
      });
      if (out.error) return toolError(out.error);
      return text({ project_id: id, added, skipped_unknown: slugs.length - ok.length, group: args.group || null });
    }
    case 'link_items': {
      const all = await lib();
      const a = all.find((i) => i.slug === args.a), b = all.find((i) => i.slug === args.b);
      if (!a || !b) return toolError('Both a and b must be slugs from the library.');
      const kind = LINK_KINDS.includes(args.kind) ? args.kind : 'manual';
      const out = await editProject(db, userId, args.project_id || LIBRARY_ID, (doc) => {
        placeNew(doc, [a.slug, b.slug]);
        doc.links = doc.links.filter((l) => !([l.a, l.b].sort().join('|') === [a.slug, b.slug].sort().join('|')));
        doc.links.push({ id: newId(), a: a.slug, b: b.slug, kind, label: args.label || '', source: 'mcp' });
        return doc;
      });
      if (out.error) return toolError(out.error);
      return text({ linked: [a.title, b.title], kind, also_similar: layer1(a, b).map(({ type, value }) => ({ type, value })) });
    }
    case 'add_note': {
      if (!args.text) return toolError('text is required.');
      const out = await editProject(db, userId, args.project_id || LIBRARY_ID, (doc) => {
        const near = doc.cards.find((c) => c.slug === args.near);
        doc.notes.push({
          id: newId(), kind: args.kind === 'question' ? 'question' : 'note', text: String(args.text).slice(0, 2000),
          near: near ? near.slug : undefined, x: near ? near.x + 220 : 0, y: near ? near.y : -200,
        });
        return doc;
      });
      return out.error ? toolError(out.error) : text({ ok: true });
    }
    default:
      return null;
  }
}

export async function handleRpc(env, userId, origin, msg) {
  const { id, method, params } = msg || {};
  const isNote = id === undefined || id === null;
  switch (method) {
    case 'initialize':
      return rpcResult(id, {
        protocolVersion: (params && params.protocolVersion) || PROTOCOL,
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER,
        instructions: 'Stello is the user\'s personal library of saved links, images and references. Search it before suggesting outside references; cite saves by title and link.',
      });
    case 'ping':
      return rpcResult(id, {});
    case 'tools/list':
      return rpcResult(id, { tools: TOOLS });
    case 'tools/call': {
      const out = await callTool(env, userId, origin, params && params.name, (params && params.arguments) || {});
      return out ? rpcResult(id, out) : rpcError(id, -32602, `Unknown tool: ${params && params.name}`);
    }
    default:
      if (isNote) return null; // notifications/initialized etc.
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

export default function mountMcp(app) {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, Mcp-Session-Id, Mcp-Protocol-Version',
  };
  app.options('/api/mcp', () => new Response(null, { status: 204, headers: cors }));
  app.get('/api/mcp', () => new Response('Use POST', { status: 405, headers: { ...cors, Allow: 'POST' } }));
  app.post('/api/mcp', async (c) => {
    const user = await auth.userFromHeaders(c.env, (n) => c.req.header(n));
    if (!user) {
      return new Response(JSON.stringify({ error: 'Pair first: open Stello → /pair.html?new=1 to get a token.' }), {
        status: 401,
        headers: { ...cors, 'content-type': 'application/json', 'WWW-Authenticate': 'Bearer realm="stello"' },
      });
    }
    const body = await c.req.json().catch(() => null);
    if (!body) return new Response(JSON.stringify(rpcError(null, -32700, 'Parse error')), { status: 400, headers: { ...cors, 'content-type': 'application/json' } });
    const origin = new URL(c.req.url).origin;
    const msgs = Array.isArray(body) ? body : [body];
    const out = (await Promise.all(msgs.map((m) => handleRpc(c.env, user.id, origin, m)))).filter(Boolean);
    if (!out.length) return new Response(null, { status: 202, headers: cors });
    return new Response(JSON.stringify(Array.isArray(body) ? out : out[0]), { headers: { ...cors, 'content-type': 'application/json' } });
  });
}
