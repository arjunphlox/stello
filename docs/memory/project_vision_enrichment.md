---
name: Vision enrichment is now at capture time
description: scripts/vision_enrich.py is archived — enrichment happens inline via api/enrich.js when items are captured (Apr 2026)
type: project
---

Vision enrichment used to be a batch job (`scripts/vision_enrich.py`) that ran periodically over the local `_items/` mirror. One-time historical run on 2026-03-31 enriched ~1594 items, producing 3844 color, 3661 style, 2449 mood tags.

That script moved to `scripts/archive/vision_enrich.py` in Apr 2026 (PR #5). Enrichment now happens at capture time inside the Vercel flow: `api/capture.js` + `api/enrich.js`. New items get color/style/mood tags on the way into Supabase, no separate pass needed.

**How to apply:** Don't suggest running the archived script — it operates on a stale local backup mirror and would diverge from Supabase. If the user asks about enriching "old items missing vision tags," the right move is a one-shot script that queries Supabase, calls `api/enrich.js`-equivalent logic, writes back — not restoring the Python path.
