-- Stello Database Schema (Supabase / PostgreSQL)
-- Version: 2026.001
-- Run this in Supabase SQL Editor to initialize the database.

-- =============================================================
-- 1. Profiles (extends Supabase auth.users)
-- =============================================================
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  theme_preferences JSONB DEFAULT '{"mode":"dark","accent":"amber"}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Auto-create profile on user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.email)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- =============================================================
-- 2. Items (core data — replaces _items/ + index.json)
-- =============================================================
CREATE TABLE items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  slug TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  source_url TEXT,
  domain TEXT,
  author TEXT,
  summary TEXT,
  body_markdown TEXT,
  og_image_path TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'broken', 'archived')),
  location TEXT,
  needs_review BOOLEAN DEFAULT true,
  link_last_checked DATE,
  added_at TIMESTAMPTZ DEFAULT now(),
  analyzed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now(),
  enrichment_status TEXT DEFAULT 'pending'
    CHECK (enrichment_status IN ('pending', 'text_done', 'vision_done', 'candidates_done', 'error')),
  tags JSONB DEFAULT '[]'::jsonb,
  -- Curation: user-selected images + snippets. og_image_path is kept for
  -- backward-compat reads; on write it mirrors whichever images[] entry
  -- has is_primary=true.
  images JSONB DEFAULT '[]'::jsonb,
  snippets JSONB DEFAULT '[]'::jsonb,
  -- Transient bag of enrichment-suggested candidates the user hasn't
  -- resolved yet: { images:[{url,label?}], snippets:[text], reasons:[text] }
  enrichment_candidates JSONB DEFAULT '{}'::jsonb,
  -- Last enrichment/image failure reason (null = none). Set when a swallowed
  -- failure would otherwise leave an item silently incomplete; cleared on success.
  enrichment_error TEXT,
  UNIQUE(user_id, slug)
);

CREATE INDEX idx_items_user_added ON items(user_id, added_at DESC);
CREATE INDEX idx_items_user_updated ON items(user_id, updated_at DESC);
CREATE INDEX idx_items_user_enrichment ON items(user_id, enrichment_status);
CREATE INDEX idx_items_tags ON items USING GIN(tags);

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER items_updated_at
  BEFORE UPDATE ON items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================
-- 3. User Settings (API keys — replaces config.json)
-- =============================================================
CREATE TABLE user_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  setting_key TEXT NOT NULL,
  setting_value JSONB NOT NULL,
  UNIQUE(user_id, setting_key)
);

-- =============================================================
-- 4. Batch Jobs (replaces SSE in-memory streams)
-- =============================================================
CREATE TABLE batch_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  total_items INT DEFAULT 0,
  completed_items INT DEFAULT 0,
  failed_items INT DEFAULT 0,
  urls JSONB DEFAULT '[]'::jsonb,
  results JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TRIGGER batch_jobs_updated_at
  BEFORE UPDATE ON batch_jobs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================
-- 5. Row Level Security
-- =============================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE batch_jobs ENABLE ROW LEVEL SECURITY;

-- Profiles: users can read/update their own profile
CREATE POLICY "Users can read own profile"
  ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile"
  ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Items: full CRUD on own items
CREATE POLICY "Users can read own items"
  ON items FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own items"
  ON items FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own items"
  ON items FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own items"
  ON items FOR DELETE USING (auth.uid() = user_id);

-- User settings: full CRUD on own settings
CREATE POLICY "Users can manage own settings"
  ON user_settings FOR ALL USING (auth.uid() = user_id);

-- Batch jobs: full CRUD on own batches
CREATE POLICY "Users can manage own batches"
  ON batch_jobs FOR ALL USING (auth.uid() = user_id);

-- =============================================================
-- 6. Storage bucket + policies
-- =============================================================
-- The bucket itself must be created in the dashboard first:
--   Storage > New Bucket > name: item-images > Public: ON
-- Then this SQL block wires up the four policies the app needs.
--
-- Path convention: {user_id}/{slug}/og-image.{ext}
-- INSERT matches the first path segment against auth.uid().
-- UPDATE is required because capture/upload-image/reprocess call
-- upload() with upsert:true — a re-capture with the same slug becomes
-- an UPDATE, not an INSERT.

DROP POLICY IF EXISTS "stello item-images public read" ON storage.objects;
DROP POLICY IF EXISTS "stello item-images user insert" ON storage.objects;
DROP POLICY IF EXISTS "stello item-images user update" ON storage.objects;
DROP POLICY IF EXISTS "stello item-images user delete" ON storage.objects;

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

-- =============================================================
-- 7. Idempotent migrations (re-runnable)
-- =============================================================
-- For existing databases that predate the curation columns. Safe to
-- re-run; each statement no-ops if already applied.
ALTER TABLE items
  ADD COLUMN IF NOT EXISTS images JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS snippets JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS enrichment_candidates JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS enrichment_error TEXT;

ALTER TABLE items DROP CONSTRAINT IF EXISTS items_enrichment_status_check;
ALTER TABLE items ADD CONSTRAINT items_enrichment_status_check
  CHECK (enrichment_status IN ('pending', 'text_done', 'vision_done', 'candidates_done', 'error'));
