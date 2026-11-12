# Apple apps ↔ web sync (step 2 of the Supabase exit)

Status: design + Worker API + Swift bridge written 2026-11-06. Swift not built yet
(Mac off). Depends on step 1 ("Replace Supabase with Cloudflare storage") for the D1
`items`/`users` tables, Sign in with Apple, and `requireUser`.

## The idea in one paragraph

Stello keeps **two copies** of the library. The Apple apps keep theirs in SwiftData +
CloudKit (end-to-end encrypted under Advanced Data Protection; no server can read it).
The web app keeps its own copy in Cloudflare D1 (rows) + R2 (image bytes). A **bridge
inside the Apple app** is the only thing that sees both: it pushes the app's changes to
the Worker and pulls the web's changes back. Both copies use the **same item UUIDs**, so
a change is always "this field of this item", never a fuzzy match.

## Moving parts

| Part | Where | Job |
|---|---|---|
| `items.seq` + `users.sync_seq` | D1 | Per-user change counter. Every write gets the next number, so "what changed since N" is one indexed query. |
| `items.field_clock` | D1 | JSON `{field: epoch ms}`: when each field last changed. Per-field last-write-wins. |
| `items.deleted_at` | D1 | Soft delete (tombstone). Web hides it, Trash can restore it for 30 days, then a cron purges it. |
| `POST /api/sync/push` | Worker | App sends changed fields + their clocks. Server keeps whichever side changed each field last. |
| `GET /api/sync/pull?since=N` | Worker | Returns full rows with `seq > N`, oldest first, pages of 500. |
| `PUT /api/sync/image` | Worker | App uploads image bytes it captured itself (content-addressed R2 key, so re-uploads are free). |
| Daily snapshot | Worker cron | Gzipped JSON of every user's items to R2 `snapshots/<user>/<date>.json.gz`, kept 30 days. Plus D1 Time Travel (built-in, 30-day point-in-time restore). |
| `SyncBridge` | Apple app | Background actor. Reads SwiftData's change history, pushes, pulls, applies. |
| `SyncAccount` | Apple app | Sign in with Apple once, exchange for a Stello device token, keep it in the Keychain. |

## How a change flows

1. **Edit on Mac/iPhone.** SwiftData records it in its persistent history (which attributes
   of which item changed, and when). The bridge reads history since its last token, keeps
   the transactions *this device* made, turns each changed item into `{id, fields, clock}`
   and pushes. Clock = the transaction's timestamp. Image/snippet changes reach history
   through `Item.imagesChangedAt` / `snippetsChangedAt`, bumped on save.
2. **Edit on web.** Step 1's `src/lib/db.js` bumps `seq` and `field_clock` on every write,
   the same bookkeeping the push does.
3. **Pull.** The bridge asks for everything after its saved cursor and applies each field,
   except fields this device changed more recently than the server's clock for them.
   "Changed on this device" includes edits from another Apple device that arrived through
   CloudKit and haven't reached the web yet, so they aren't overwritten. Bridge writes use
   the context author `stello.sync`, so the next history read skips them.
4. **Each Apple device pushes only its own edits**, never what it received through CloudKit.
   Otherwise an old value arriving late through CloudKit could be pushed with a fresh clock
   and beat a newer web edit. Cost: an edit made on the iPhone reaches the web when the
   iPhone syncs (open, or background refresh), not when the Mac sees it.

Order inside one cycle: push first, then pull. An item with local history not yet pushed
is skipped by that pull; it pushes next cycle and the server decides. Known gap: an edit
saved in the few milliseconds between the bridge's history check and its save can be
overwritten by an older server value. Rare for one person; worth a test on the Mac.

## Conflicts

- **Per field, last write wins** by clock. Tie → server keeps its value.
- **Delete vs edit:** `deleted_at` is a field with its own clock. A later edit on the other
  side does *not* undelete (an edit isn't a restore); a later explicit restore does.
- **Tags, images, snippets** are each one field (a JSON list), so two sides editing tags on
  the same item at once → the later list wins. Good enough for one person; revisit if
  Stello goes multi-user.
- **Clock skew:** device clocks are trusted. The server clamps any clock more than 5 minutes
  in its future to "now", so one wrong clock can't win every conflict forever.

## What syncs

| Field (D1) | Apple model | Note |
|---|---|---|
| title, slug, source_url, domain, author, summary, body_markdown, status, needs_review, kind, added_at, analyzed_at, enrichment_status | `Item` same names | plain values |
| metadata | `Item.metadataJSON` | per-kind JSON |
| tags | `Item.tagsJSON` | `[{name, category, weight, source}]` |
| snippets | `Snippet` rows | `[{text, source, added_at}]` |
| images | `ItemImage` rows | `[{path:"/img/<key>", source, is_primary, width, height, role, label}]`; bytes in R2 |
| cover_aspect | `Item.coverAspect` | lets the web grid lay out without loading images |
| deleted_at | delete / recreate | tombstone |

Not synced: `extractedText` (big, re-readable from the page), open counts, local video
attachments, enrichment errors.

**Profile** (name, designation, photo) rides along at the end of each cycle
(`ProfileSync.swift`), through `/api/me/profile` rather than `/api/sync`. Same rule:
per field (`name`, `designation`, `avatar`), the newer epoch-ms clock wins, ties keep
the server value, the server clamps future clocks (`src/lib/profile.js`). Web edits
count as "now"; the app sends when the edit was made. A Mac profile from before this
existed is seeded at clock 1, so on the first sync it beats web values saved without
clocks (clock 0). The photo is WebP in R2 on the web, `avatar.jpg` in Application
Support on the device; the device remembers the web path so it neither re-uploads nor
re-downloads.

## First link-up

The Mac imported the same Supabase export that step 1 migrates into D1, with the same
UUIDs. First run: the bridge pulls everything (cursor 0), then pushes every app item with
clock = `item.updatedAt`. The ~90 items made natively since the import get created on the
server; for the rest each field goes to whichever side is newer (the Mac, almost always,
since its summaries and kinds are newer than the export). Images that already point at
`/img/<key>` upload nothing.

Budget (perf + import rules): 10k items = 20 pull pages + 100 push pages of 100, all in a
background `ModelActor`, saves batched by 100, nothing on the main thread. Target well
under the 15-minute import rule; to be timed on the 10k perf store on the Mac.

## When it runs

- **Mac app open:** after each local save (debounced 2 s) and every 30 s while active.
- **iPhone:** on foreground, after saves, and in a `BGAppRefreshTask` (iOS decides how
  often; typically every few hours). If only the iPhone is used, web sees its edits next
  time the app runs or gets background time.
- **Web → app immediacy:** not instant when the Mac app is closed. A later add-on could send
  a silent push from the Worker (APNs) to wake the app; out of scope for v1.

## Auth

The app does native Sign in with Apple (`ASAuthorizationAppleIDProvider`), posts the
identity token to `POST /api/auth/apple/native` (step 1's Apple verification; audience =
app bundle id `com.arjunphlox.Stello`, in addition to the web Services ID), and gets a
long-lived device token. Same Apple user id → same Stello account as the web. The token
lives in the Keychain; sign-out deletes it and revokes the device row.

## Open items

- Wiring, once step 1 lands: `app.route('/api/sync', syncRoutes({ requireUser }))`,
  `app.post('/api/auth/apple/native', appleNative)`, and the daily cron calling
  `purgeExpired`, `writeSnapshot`, `pruneSnapshots` (step 1 left a TODO in `scheduled()`).
- `WebInboxProcessor` (the CloudKit-JS inbox from PR #56/#57) is superseded by this and can
  go once the bridge is proven.
- Images pulled from the web are stored as served; shrink to ~600 px thumbnails if memory
  or iCloud storage needs it.
- `Item.id` needs `@Attribute(.preserveValueOnDeletion)` so delete history carries the id.
  Additive; needs a CloudKit Development schema update when built.
- Build + test on the Mac (paused until Arjun is on it): unit tests for the mapper, then a
  10k-item perf run of the first link-up, then a live round trip on the real library.
