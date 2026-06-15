---
name: Vision enrichment — inline at capture + server-side drain
description: Enrichment lives in src/routes/enrich.js (vision) + reprocess.js (OG/image/tags), runs inline at capture and via a daily cron drain; needs an Anthropic key (env.ANTHROPIC_API_KEY or per-user user_settings) or it silently no-ops
type: project
---

Vision enrichment used to be a batch Python job (`scripts/vision_enrich.py`, archived in PR #5). It now lives in the Cloudflare Worker:

- **`src/routes/enrich.js`** — `enrichItem(env, client, item, apiKey, userId)` is the pure vision+candidates core (Phase A: color/style/mood tags → `vision_done`; Phase B: image/snippet/reason candidates). `enrichCore(env, accessToken, …)` is the auth wrapper (builds a user client from the bearer, fetches the item, resolves the key, delegates). Exports: `enrichCore`, `enrichItem`, `getApiKey`.
- **`src/routes/reprocess.js`** — `reprocessItem(env, client, item, userId)` re-fetches OG/image/tags and sets `enrichment_status`. Returns the updated item so callers can chain straight into vision. The handler is the auth wrapper.
- **`src/routes/process-batches.js`** — `drainEnrichment(env, {limit})` heals items stuck at `text_done` server-side: admin client selects `text_done`, resolves each owner's key, runs `reprocessItem` → `enrichItem`. Runs from the daily `scheduled()` cron (`limit:20` backstop) and a guarded `POST /api/cron/drain-enrichment` (Bearer = `SUPABASE_SERVICE_ROLE_KEY`, `?limit=1-75`).

**Critical quirk — the key resolution (`getApiKey`):** `user_settings.anthropic_api_key` → fallback `env.ANTHROPIC_API_KEY`. If BOTH are absent, `anthropic` is `null` and the vision block is **skipped silently** (no error, item stays `text_done`). This is exactly what stranded ~1000 items after the CF migration: the `ANTHROPIC_API_KEY` Worker secret was never set and `user_settings` is empty. Set it with `wrangler secret put ANTHROPIC_API_KEY`. **Always check the key exists before debugging "vision isn't running."**

**Status machine:** `text_done` = has text/maybe image, vision pending (retryable — frontend backfill + cron both retry it). `vision_done` = vision tags written. `candidates_done` = terminal, no recoverable image (dead/rotted og:image). `error` = vision threw (e.g. Anthropic `400 invalid_request` on a bad/oversized image) — terminal, reason in `enrichment_error`, NOT retried by backfill.

**How to apply:** To re-enrich a deep backlog, use the server-side drain (cron or the guarded trigger), NOT the archived Python script or a per-load frontend loop. The manual trigger is **synchronous** — keep `limit` small (≤~25) or it blows past the Worker request window; the cron path uses `waitUntil` so it isn't time-bound. Draining oldest-first hits link-rotted items first (slow OG-fetch timeouts, ~5% land `vision_done`); the value of vision is mostly on newer items with live images. See [[project_capture_pipeline]].
