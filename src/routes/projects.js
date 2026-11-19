/**
 * /api/projects — canvas docs (see src/lib/projects.js for the shape).
 *
 *   GET    /api/projects             → { projects: [{ id, name, rev, updated_at, cards }] }
 *   POST   /api/projects  { doc }    → 201 { project }
 *   GET    /api/projects/:id         → { project }   ('library' = the library canvas, always there)
 *   PUT    /api/projects/:id  { rev, doc }          → { project } | 409 { error, project }
 *   POST   /api/projects/:id/board  { rev, board }  → FigJam Board sync: merge, then save
 *   DELETE /api/projects/:id         → { ok }        (soft delete)
 *
 * Signed-in only: the web cookie, or a device token as a bearer (Apple apps,
 * Figma plugin, MCP).
 */
import { listProjects, getProject, createProject, saveProject, deleteProject, mergeBoard } from '../lib/projects.js';

export default function mountProjects(app, { requireUser }) {
  const who = async (c) => requireUser(c);
  const body = (c) => c.req.json().catch(() => ({}));
  const fail = (c, out) => {
    if (out.conflict) return c.json({ error: 'conflict', project: out.conflict }, 409);
    if (out.error === 'not_found') return c.json({ error: 'Project not found' }, 404);
    if (out.error === 'too_large') return c.json({ error: 'Project is too large' }, 413);
    return c.json({ error: out.error || 'Bad request' }, 400);
  };

  app.get('/api/projects', async (c) => {
    const userId = await who(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    return c.json({ projects: await listProjects(c.env.DB, userId) });
  });

  app.post('/api/projects', async (c) => {
    const userId = await who(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const { doc } = await body(c);
    const out = await createProject(c.env.DB, userId, doc);
    return out.project ? c.json({ project: out.project }, 201) : fail(c, out);
  });

  app.get('/api/projects/:id', async (c) => {
    const userId = await who(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const project = await getProject(c.env.DB, userId, c.req.param('id'));
    return project ? c.json({ project }) : c.json({ error: 'Project not found' }, 404);
  });

  app.put('/api/projects/:id', async (c) => {
    const userId = await who(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const { rev, doc } = await body(c);
    const out = await saveProject(c.env.DB, userId, c.req.param('id'), doc, rev);
    return out.project ? c.json({ project: out.project }) : fail(c, out);
  });

  app.post('/api/projects/:id/board', async (c) => {
    const userId = await who(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const id = c.req.param('id');
    const { rev, board } = await body(c);
    const current = await getProject(c.env.DB, userId, id);
    if (!current) return c.json({ error: 'Project not found' }, 404);
    if (rev != null && Number(rev) !== current.rev) return c.json({ error: 'conflict', project: current }, 409);
    const merged = mergeBoard(current.doc, board || {});
    const out = await saveProject(c.env.DB, userId, id, merged, current.rev);
    return out.project ? c.json({ project: out.project }) : fail(c, out);
  });

  app.delete('/api/projects/:id', async (c) => {
    const userId = await who(c);
    if (!userId) return c.json({ error: 'Not signed in' }, 401);
    const ok = await deleteProject(c.env.DB, userId, c.req.param('id'));
    return ok ? c.json({ ok: true }) : c.json({ error: 'Project not found' }, 404);
  });
}
