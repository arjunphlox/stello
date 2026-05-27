---
name: Supabase Storage RLS — upsert:true needs BOTH INSERT and UPDATE policies
description: Stello's item-images bucket policies live in schema.sql + migrations/2026-04-16-storage-policies.sql; the UPDATE half is easy to miss and causes silent "new row violates RLS" failures
type: project
---

Every capture path (`api/capture.js`, `api/capture-bulk.js`, `api/upload-image.js`, `api/reprocess.js`, `api/cron/process-batches.js`) uploads to the `item-images` bucket with `upsert: true`. The Supabase SDK turns an `upsert:true` call on an existing path into UPDATE, not INSERT — so without an UPDATE policy the second upload for any given `{user_id}/{slug}/og-image.{ext}` path fails with `"new row violates row-level security policy"`.

## The canonical policy set (schema.sql + migrations/2026-04-16-storage-policies.sql)

```sql
DROP POLICY IF EXISTS "stello item-images public read"    ON storage.objects;
DROP POLICY IF EXISTS "stello item-images user insert"    ON storage.objects;
DROP POLICY IF EXISTS "stello item-images user update"    ON storage.objects;
DROP POLICY IF EXISTS "stello item-images user delete"    ON storage.objects;

CREATE POLICY "stello item-images public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'item-images');

CREATE POLICY "stello item-images user insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'item-images'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "stello item-images user update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'item-images'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "stello item-images user delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'item-images'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
```

Public SELECT is required for `getPublicUrl()` card thumbnails to render without auth. The owner check uses `(storage.foldername(name))[1]` — path segments as a text array — matching against `auth.uid()` as text.

## How to apply

- If images aren't appearing on newly-captured items AND capture logs show `image upload failed ... new row violates row-level security policy`, the policies are missing or broken. Re-run `scripts/migrations/2026-04-16-storage-policies.sql` in Supabase SQL editor — it's idempotent (`DROP POLICY IF EXISTS` + `CREATE POLICY`).
- `scripts/verify-supabase.js` only checks bucket existence, not policies. There's a BACKLOG quick-win to extend it to attempt a real user-scoped upload — until that lands, a green `npm run verify` does NOT mean uploads work.
- If you add a new bucket or a new storage path convention, the policies above must be extended. The `foldername(name)[1]` trick depends on `{user_id}/...` being the path shape — breaking that convention will require a different policy expression.
- Service-role uploads bypass RLS — that's why `cron/process-batches.js` (uses `getAdminClient()`) could succeed even when user-scoped uploads were failing. Don't use this as a diagnostic bypass; fix the policy.
