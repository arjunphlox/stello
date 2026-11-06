-- Step 2: two-copy sync with the Apple apps (docs/plans/apple-web-sync.md).
-- 0001_init.sql already has every synced column (seq, field_clock, deleted_at,
-- purged_at, kind, metadata, cover_aspect) and users.sync_seq. This only adds the
-- index the daily purge reads.
CREATE INDEX IF NOT EXISTS idx_items_purge ON items(deleted_at) WHERE deleted_at IS NOT NULL AND purged_at IS NULL;
