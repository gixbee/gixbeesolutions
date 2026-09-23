CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS geo geography(Point, 4326);
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS geo geography(Point, 4326);

UPDATE job_posts
SET geo = ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
WHERE lat IS NOT NULL AND lng IS NOT NULL;

UPDATE talent_profiles
SET geo = ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
WHERE lat IS NOT NULL AND lng IS NOT NULL;

CREATE INDEX IF NOT EXISTS "IDX_job_posts_geo" ON job_posts USING GIST (geo);
CREATE INDEX IF NOT EXISTS "IDX_talent_profiles_geo" ON talent_profiles USING GIST (geo);

CREATE OR REPLACE FUNCTION gixbee_sync_geo() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.lat IS NOT NULL AND NEW.lng IS NOT NULL THEN
    NEW.geo := ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography;
  ELSE
    NEW.geo := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS job_posts_sync_geo ON job_posts;
CREATE TRIGGER job_posts_sync_geo
  BEFORE INSERT OR UPDATE OF lat, lng ON job_posts
  FOR EACH ROW EXECUTE FUNCTION gixbee_sync_geo();

DROP TRIGGER IF EXISTS talent_profiles_sync_geo ON talent_profiles;
CREATE TRIGGER talent_profiles_sync_geo
  BEFORE INSERT OR UPDATE OF lat, lng ON talent_profiles
  FOR EACH ROW EXECUTE FUNCTION gixbee_sync_geo();

CREATE TABLE IF NOT EXISTS job_embeddings (
  "jobPostId" uuid PRIMARY KEY REFERENCES job_posts(id) ON DELETE CASCADE,
  embedding vector(64),
  model varchar NOT NULL DEFAULT 'local-hash-64',
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS candidate_embeddings (
  "talentProfileId" uuid PRIMARY KEY REFERENCES talent_profiles(id) ON DELETE CASCADE,
  embedding vector(64),
  model varchar NOT NULL DEFAULT 'local-hash-64',
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS job_embeddings_hnsw
  ON job_embeddings USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS candidate_embeddings_hnsw
  ON candidate_embeddings USING hnsw (embedding vector_cosine_ops);

UPDATE matching_config SET semantic_weight = 10, "updatedAt" = now() WHERE id = 1;
