-- Persisted cache invalidation counters (run once per environment).
CREATE TABLE IF NOT EXISTS cache_versions (
  domain TEXT PRIMARY KEY,
  version BIGINT NOT NULL DEFAULT 1,
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO cache_versions (domain, version) VALUES
  ('hiring_master', 1),
  ('location_master', 1),
  ('service_master', 1),
  ('public_listings', 1)
ON CONFLICT (domain) DO NOTHING;
