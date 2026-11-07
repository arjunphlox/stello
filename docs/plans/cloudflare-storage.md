# Replace Supabase with Cloudflare storage (step 1)

Decided by Arjun, 2026-11-06: two synced copies of the library. The Apple apps keep SwiftData + CloudKit (protected by Advanced Data Protection). The web app gets its own copy on Cloudflare, with one Stello account that both email and Sign in with Apple open. Step 2 (sync bridge, PR #58) builds on this schema.

## What changes

| Piece | Before | After |
|---|---|---|
| Item data | Supabase Postgres, browser queries it directly | Cloudflare D1 (`env.DB`, database `stello`), browser goes through `/api/items` |
| Accounts | Supabase Auth | `users` + `identities` + `sessions` tables in D1, HttpOnly cookie |
| Apple sign-in | Supabase OAuth (never used) | Our own: redirect to Apple, verify Apple's signed token. No client secret |
| Images | R2 | R2, unchanged (`/img/<key>` paths stay valid) |
| Deletes | Hard delete + image cleanup | Soft delete, restorable 30 days (sync needs it) |

## Order

1. Build on a branch, test locally (done: full import of 3,608 items in about 7 s, grid renders all of them).
2. Push the branch. Cloudflare builds a preview at `claude-project-thread-i6fc0y-stello.arjunphlox.workers.dev` and creates the D1 database the first time.
3. Arjun creates the Apple Services ID (steps below). Test Sign in with Apple on the preview with his ADP account.
4. Run the import on the preview (it writes into the same D1 the live site will use). Check counts.
5. With Arjun's go-ahead: merge, which makes it live. Re-run the import right before, so last-minute Supabase edits come along.
6. After a few days of normal use, with Arjun's go-ahead: remove the Supabase key, the import route, the old scripts, and delete the Supabase project.

## Apple setup (Arjun, about 5 minutes)

developer.apple.com → Certificates, Identifiers & Profiles → Identifiers:

1. Open App ID `com.arjunphlox.Stello`, tick **Sign in with Apple**, save. (Lets the app and web share one Apple account id.)
2. **+** → **Services IDs** → identifier `com.arjunphlox.Stello.web`, description "Stello Web". Register.
3. Open it, tick **Sign in with Apple** → **Configure**: primary App ID `com.arjunphlox.Stello`; Domains `stello.arjunphlox.workers.dev, claude-project-thread-i6fc0y-stello.arjunphlox.workers.dev`; Return URLs `https://stello.arjunphlox.workers.dev/api/auth/apple/callback` and `https://claude-project-thread-i6fc0y-stello.arjunphlox.workers.dev/api/auth/apple/callback`. Save, Continue, Save.

Then `APPLE_SERVICES_ID` in `wrangler.jsonc` gets `com.arjunphlox.Stello.web` (Claude does this).

## Secrets

- `ADMIN_TOKEN` (new, optional): gates the admin routes. Until it's set, the existing `SUPABASE_SERVICE_ROLE_KEY` secret works as the gate.
- `SUPABASE_SERVICE_ROLE_KEY`: only needed by the import; deleted in step 6.

## First sign-in after the switch

His account keeps its id and email, but Supabase never hands out password hashes, so there is no password yet. Either Sign in with Apple (links automatically when Apple shares the same verified email), or a one-time link from `POST /api/admin/login-link`. Both land on "Set password".

## Known gaps

- No password-reset email (no mail service). Recovery is Sign in with Apple, then set a new password.
- No login rate limiting yet; add before opening sign-up to the public.
- Sign-up is closed (`ALLOW_SIGNUP=false`).
- PBKDF2 at 100k iterations costs roughly 30-50 ms CPU per login; fine on Workers Paid, could hit the 10 ms free-plan cap.
