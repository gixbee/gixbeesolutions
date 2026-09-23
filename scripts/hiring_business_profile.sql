ALTER TABLE businesses ADD COLUMN IF NOT EXISTS "hiringProfile" jsonb NOT NULL DEFAULT '{}'::jsonb;
