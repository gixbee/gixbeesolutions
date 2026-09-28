-- Board-first matching engine. Idempotent. PostGIS / pgvector are optional.
-- Paid Smart Hiring tables (job_preferences, hiring_requests, hiring_interests) are unchanged.

ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "workMode" varchar NOT NULL DEFAULT 'ONSITE';
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "salaryPeriod" varchar NOT NULL DEFAULT 'MONTHLY';
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "experienceMin" double precision;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "experienceMax" double precision;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS lat double precision;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS lng double precision;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS openings integer NOT NULL DEFAULT 1;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "joiningType" varchar;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "joiningDate" timestamptz;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS status varchar NOT NULL DEFAULT 'PUBLISHED';

UPDATE job_posts SET status = CASE WHEN "isActive" THEN 'PUBLISHED' ELSE 'CLOSED' END
WHERE status IS NULL OR status = '';

CREATE INDEX IF NOT EXISTS "IDX_job_posts_status_createdAt" ON job_posts (status, "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "IDX_job_posts_lat_lng" ON job_posts (lat, lng) WHERE lat IS NOT NULL AND lng IS NOT NULL;

ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS lat double precision;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS lng double precision;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "travelRadiusKm" double precision NOT NULL DEFAULT 25;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS availability varchar NOT NULL DEFAULT 'IMMEDIATE';
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "lastActiveAt" timestamptz;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "profileStatus" varchar NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "preferredWorkMode" varchar;

CREATE INDEX IF NOT EXISTS "IDX_talent_profiles_status" ON talent_profiles ("profileStatus");
CREATE INDEX IF NOT EXISTS "IDX_talent_profiles_lat_lng" ON talent_profiles (lat, lng) WHERE lat IS NOT NULL AND lng IS NOT NULL;

CREATE TABLE IF NOT EXISTS skills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar NOT NULL,
  "normalizedName" varchar NOT NULL UNIQUE,
  "categoryId" uuid,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS skill_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "skillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
  alias varchar NOT NULL,
  "normalizedAlias" varchar NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS "IDX_skill_aliases_skillId" ON skill_aliases ("skillId");

CREATE TABLE IF NOT EXISTS skill_related (
  "skillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
  "relatedSkillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
  weight real NOT NULL DEFAULT 0.5,
  PRIMARY KEY ("skillId", "relatedSkillId")
);

CREATE TABLE IF NOT EXISTS job_post_skills (
  "jobPostId" uuid NOT NULL REFERENCES job_posts(id) ON DELETE CASCADE,
  "skillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
  "isRequired" boolean NOT NULL DEFAULT true,
  importance real NOT NULL DEFAULT 1,
  PRIMARY KEY ("jobPostId", "skillId")
);

CREATE TABLE IF NOT EXISTS candidate_skills (
  "talentProfileId" uuid NOT NULL REFERENCES talent_profiles(id) ON DELETE CASCADE,
  "skillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
  "experienceLevel" varchar,
  PRIMARY KEY ("talentProfileId", "skillId")
);

CREATE TABLE IF NOT EXISTS matching_config (
  id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  skill_weight real NOT NULL DEFAULT 30,
  category_weight real NOT NULL DEFAULT 25,
  distance_weight real NOT NULL DEFAULT 15,
  employment_type_weight real NOT NULL DEFAULT 10,
  salary_weight real NOT NULL DEFAULT 10,
  experience_weight real NOT NULL DEFAULT 5,
  availability_weight real NOT NULL DEFAULT 5,
  semantic_weight real NOT NULL DEFAULT 0,
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
INSERT INTO matching_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS matching_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid,
  "jobPostId" uuid,
  "candidateId" uuid,
  "businessId" uuid,
  "eventType" varchar NOT NULL,
  "matchScoreAtTime" real,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_matching_events_job" ON matching_events ("jobPostId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "IDX_matching_events_type" ON matching_events ("eventType", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS matching_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL,
  "jobPostId" uuid NOT NULL,
  "candidateId" uuid,
  side varchar NOT NULL,
  reason varchar NOT NULL,
  note text,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_matching_feedback_job" ON matching_feedback ("jobPostId", side);

INSERT INTO skills (name, "normalizedName")
SELECT v.name, v.norm
FROM (VALUES
  ('Flutter', 'flutter'),
  ('Electrical Installation', 'electrical installation'),
  ('Wiring', 'wiring'),
  ('MCB Installation', 'mcb installation'),
  ('Fault Finding', 'fault finding'),
  ('Inverter', 'inverter')
) AS v(name, norm)
WHERE NOT EXISTS (SELECT 1 FROM skills s WHERE s."normalizedName" = v.norm);

INSERT INTO skill_aliases ("skillId", alias, "normalizedAlias")
SELECT s.id, v.alias, v.norm
FROM (VALUES
  ('flutter', 'Flutter Dev', 'flutter dev'),
  ('flutter', 'Flutter SDK', 'flutter sdk'),
  ('flutter', 'Dart Flutter', 'dart flutter'),
  ('electrical installation', 'House Wiring', 'house wiring'),
  ('wiring', '3 Phase Wiring', '3 phase wiring')
) AS v(canon, alias, norm)
JOIN skills s ON s."normalizedName" = v.canon
WHERE NOT EXISTS (SELECT 1 FROM skill_aliases a WHERE a."normalizedAlias" = v.norm);

INSERT INTO skill_related ("skillId", "relatedSkillId", weight)
SELECT a.id, b.id, 0.6
FROM skills a
JOIN skills b ON b."normalizedName" = 'electrical installation'
WHERE a."normalizedName" IN ('wiring', 'mcb installation', 'fault finding')
ON CONFLICT DO NOTHING;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS postgis;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'postgis skipped: %', SQLERRM;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis')
     AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_name = 'job_posts' AND column_name = 'geo'
     ) THEN
    EXECUTE 'ALTER TABLE job_posts ADD COLUMN geo geography(Point,4326)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS "IDX_job_posts_geo" ON job_posts USING GIST (geo)';
  END IF;
END $$;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS vector;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pgvector skipped: %', SQLERRM;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vector') THEN
    EXECUTE $sql$
      CREATE TABLE IF NOT EXISTS job_embeddings (
        "jobPostId" uuid PRIMARY KEY REFERENCES job_posts(id) ON DELETE CASCADE,
        embedding vector(64),
        model varchar NOT NULL DEFAULT 'pending',
        "updatedAt" timestamptz NOT NULL DEFAULT now()
      )
    $sql$;
    EXECUTE $sql$
      CREATE TABLE IF NOT EXISTS candidate_embeddings (
        "talentProfileId" uuid PRIMARY KEY REFERENCES talent_profiles(id) ON DELETE CASCADE,
        embedding vector(64),
        model varchar NOT NULL DEFAULT 'pending',
        "updatedAt" timestamptz NOT NULL DEFAULT now()
      )
    $sql$;
    BEGIN
      EXECUTE 'CREATE INDEX IF NOT EXISTS job_embeddings_hnsw ON job_embeddings USING hnsw (embedding vector_cosine_ops)';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'hnsw skipped: %', SQLERRM;
    END;
  END IF;
END $$;
