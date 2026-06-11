/**
 * Hono ⇄ Vercel handler adapter.
 *
 * The 12 endpoints were written for Vercel's `(req, res)` model with
 * `res.status().json()`, `req.body`, `req.query`, `req.headers`. Rather than
 * rewrite each to Hono-native, we present that same shape over a Hono
 * context — handler bodies stay near-verbatim, only their imports +
 * storage/image calls change.
 *
 * `req.env` carries the Worker env (secrets + R2/Images bindings);
 * `req.ctx` carries executionCtx for `waitUntil` (background enrich).
 */

function makeRes() {
  const state = { status: 200, headers: {}, body: undefined, ended: false };
  const res = {
    statusCode: 200,
    setHeader(k, v) { state.headers[k.toLowerCase()] = v; return res; },
    getHeader(k) { return state.headers[k.toLowerCase()]; },
    removeHeader(k) { delete state.headers[k.toLowerCase()]; return res; },
    status(code) { state.status = code; res.statusCode = code; return res; },
    json(data) {
      if (!state.headers['content-type']) state.headers['content-type'] = 'application/json';
      state.body = JSON.stringify(data);
      state.ended = true;
      return res;
    },
    end(body) {
      if (body !== undefined) state.body = body;
      state.ended = true;
      return res;
    },
    writeHead(code, headers) {
      state.status = code;
      if (headers) for (const [k, v] of Object.entries(headers)) state.headers[k.toLowerCase()] = v;
      res.statusCode = code;
      return res;
    },
    get writableEnded() { return state.ended; },
    get headersSent() { return state.ended; },
  };
  return { res, state };
}

/**
 * Build `{ req, res, finalize }` from a Hono context. The route does:
 *   const { req, res, finalize } = await adapt(c);
 *   await handler(req, res);
 *   return finalize();
 */
async function adapt(c) {
  const raw = c.req.raw;
  const headers = Object.fromEntries(raw.headers);

  const req = {
    method: c.req.method,
    headers,                       // lowercase keys (authorization, content-type, host…)
    query: c.req.query() || {},    // { id, slug, code, … }
    env: c.env,
    ctx: c.executionCtx,
    raw,
    body: undefined,
    // Raw bytes for binary endpoints (upload-image).
    async arrayBuffer() { return Buffer.from(await raw.arrayBuffer()); },
  };

  // Eagerly parse a JSON body so handlers can read req.body synchronously,
  // matching Vercel. Binary handlers ignore req.body and call arrayBuffer().
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    const ct = (headers['content-type'] || '').toLowerCase();
    if (ct.includes('application/json')) {
      try { req.body = await c.req.json(); } catch { req.body = {}; }
    }
  }

  const { res, state } = makeRes();

  const finalize = () => {
    const h = new Headers();
    for (const [k, v] of Object.entries(state.headers)) h.set(k, String(v));
    // 204/304 and redirects carry no body.
    const body = (state.status === 204 || state.status === 304) ? null : state.body;
    return new Response(body ?? null, { status: state.status, headers: h });
  };

  return { req, res, finalize };
}

/** Wrap a Vercel-style handler as a Hono route handler. */
function route(handler) {
  return async (c) => {
    const { req, res, finalize } = await adapt(c);
    await handler(req, res);
    return finalize();
  };
}

module.exports = { adapt, route, makeRes };
