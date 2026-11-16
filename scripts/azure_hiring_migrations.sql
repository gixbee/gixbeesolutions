-- Hiring catalogue schema (from TypeORM migrations 1755900000000 + 1756000000000)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS hiring_sectors (
  id varchar PRIMARY KEY,
  label varchar NOT NULL,
  subtitle text NOT NULL DEFAULT '',
  icon varchar NOT NULL DEFAULT '',
  color varchar NOT NULL DEFAULT '',
  "sortOrder" int NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true,
  "updatedAt" timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS hiring_positions (
  id varchar PRIMARY KEY,
  label varchar NOT NULL,
  subtitle text NOT NULL DEFAULT '',
  "fieldPattern" varchar NOT NULL DEFAULT 'typeChips',
  "typeLabel" varchar NOT NULL DEFAULT 'Type',
  shared boolean NOT NULL DEFAULT false,
  "isActive" boolean NOT NULL DEFAULT true,
  "updatedAt" timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS hiring_sector_positions (
  "sectorId" varchar NOT NULL,
  "positionId" varchar NOT NULL,
  PRIMARY KEY ("sectorId", "positionId")
);

CREATE TABLE IF NOT EXISTS hiring_specializations (
  id varchar PRIMARY KEY,
  "positionId" varchar NOT NULL,
  label varchar NOT NULL,
  "sortOrder" int NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS hiring_skills (
  id varchar PRIMARY KEY,
  label varchar NOT NULL,
  "isActive" boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS hiring_position_skills (
  "positionId" varchar NOT NULL,
  "skillId" varchar NOT NULL,
  tier varchar NOT NULL DEFAULT 'suggested',
  "sortOrder" int NOT NULL DEFAULT 0,
  PRIMARY KEY ("positionId", "skillId")
);

CREATE TABLE IF NOT EXISTS hiring_qualifications (
  id varchar PRIMARY KEY,
  label varchar NOT NULL,
  rank int,
  professional boolean NOT NULL DEFAULT false,
  "sortOrder" int NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS hiring_employment_types (
  code varchar PRIMARY KEY,
  label varchar NOT NULL,
  "sortOrder" int NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS hiring_salary_periods (
  code varchar PRIMARY KEY,
  label varchar NOT NULL,
  "sortOrder" int NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS hiring_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "entityType" varchar NOT NULL,
  "entityId" varchar NOT NULL,
  alias varchar NOT NULL,
  "isActive" boolean NOT NULL DEFAULT true,
  UNIQUE ("entityType", "entityId", alias)
);

CREATE TABLE IF NOT EXISTS hiring_locations (
  id varchar PRIMARY KEY,
  kind varchar NOT NULL,
  name varchar NOT NULL,
  "parentId" varchar,
  "stateId" varchar,
  "districtId" varchar,
  "stateName" varchar NOT NULL DEFAULT '',
  "districtName" varchar NOT NULL DEFAULT '',
  lat double precision,
  lng double precision,
  source varchar NOT NULL DEFAULT '',
  "sourceKey" varchar NOT NULL DEFAULT '',
  "isActive" boolean NOT NULL DEFAULT true,
  "updatedAt" timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS hiring_location_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "locationId" varchar NOT NULL,
  alias varchar NOT NULL,
  UNIQUE ("locationId", alias)
);

CREATE INDEX IF NOT EXISTS hiring_locations_name_trgm ON hiring_locations USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS hiring_location_aliases_trgm ON hiring_location_aliases USING gin (alias gin_trgm_ops);
CREATE INDEX IF NOT EXISTS hiring_locations_kind_state ON hiring_locations (kind, "stateId");

ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "sectorId" varchar;
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "positionId" varchar;
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "specializationIds" text NOT NULL DEFAULT '';
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "skillIds" text NOT NULL DEFAULT '';
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "qualificationId" varchar;
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "qualificationRequired" boolean NOT NULL DEFAULT false;
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "salaryPeriod" varchar NOT NULL DEFAULT 'MONTHLY';
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "locationId" varchar;
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "addressText" text;
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "locationMatchStatus" varchar NOT NULL DEFAULT 'UNRESOLVED';
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "workMode" varchar NOT NULL DEFAULT 'ONSITE';

ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "sectorId" varchar;
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "positionId" varchar;
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "specializationIds" text NOT NULL DEFAULT '';
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "skillIds" text NOT NULL DEFAULT '';
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "qualificationId" varchar;
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "locationId" varchar;
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "addressText" text;
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "locationMatchStatus" varchar NOT NULL DEFAULT 'UNRESOLVED';

ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "positionIds" text NOT NULL DEFAULT '';
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "specializationIds" text NOT NULL DEFAULT '';
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "skillIds" text NOT NULL DEFAULT '';
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "qualificationId" varchar;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "locationId" varchar;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "addressText" text;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "locationMatchStatus" varchar NOT NULL DEFAULT 'UNRESOLVED';

ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "sectorId" varchar;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "positionId" varchar;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "specializationIds" text NOT NULL DEFAULT '';
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "skillIds" text NOT NULL DEFAULT '';
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "qualificationId" varchar;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "qualificationRequired" boolean NOT NULL DEFAULT false;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "locationId" varchar;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "addressText" text;
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "locationMatchStatus" varchar NOT NULL DEFAULT 'UNRESOLVED';

ALTER TYPE hiring_requests_employmenttype_enum ADD VALUE IF NOT EXISTS 'GIG';
ALTER TYPE job_preferences_employmenttype_enum ADD VALUE IF NOT EXISTS 'GIG';

ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "matchingPaused" boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS hiring_languages (
  id varchar PRIMARY KEY,
  label varchar NOT NULL,
  "quickPick" boolean NOT NULL DEFAULT false,
  "sortOrder" int NOT NULL DEFAULT 0,
  "isActive" boolean NOT NULL DEFAULT true,
  "updatedAt" timestamptz NOT NULL DEFAULT NOW()
);
ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "languageIds" text NOT NULL DEFAULT '';
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "languageIds" text NOT NULL DEFAULT '';
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "languageIds" text NOT NULL DEFAULT '';
ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "languageIds" text NOT NULL DEFAULT '';

-- 1756700000000-SeekerProfileDetails (keep existing profiles intact).
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "seekerDetails" jsonb;
CREATE TABLE IF NOT EXISTS seeker_resume_uploads (
  id uuid PRIMARY KEY,
  "userId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  filename varchar(255) NOT NULL,
  content bytea NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT NOW()
);
