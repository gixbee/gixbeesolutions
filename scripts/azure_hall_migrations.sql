-- Hall owner schema (idempotent). Mirrors TypeORM migrations:
--   backend/src/migrations/1756500000000-BusinessHalls.ts
--   backend/src/migrations/1756600000000-HallEnquiriesQuoteRevisions.ts
-- Applied by scripts/azure_sync_and_deploy.sh on every deploy; safe to re-run.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------------------------------------------------------------- Phase 1–2
CREATE TABLE IF NOT EXISTS business_hall_venue (
  "businessId" uuid PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
  "plannedHallCount" integer NOT NULL DEFAULT 1
    CHECK ("plannedHallCount" BETWEEN 1 AND 50),
  "commonParking" jsonb NOT NULL DEFAULT '{"car":0,"bike":0}'::jsonb,
  "hallSetupComplete" boolean NOT NULL DEFAULT false,
  timezone varchar(64) NOT NULL DEFAULT 'Asia/Kolkata',
  "assignHoldHours" integer NULL CHECK ("assignHoldHours" IS NULL OR "assignHoldHours" BETWEEN 1 AND 720),
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  "updatedAt" timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS business_halls (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  "hallNumber" integer NOT NULL CHECK ("hallNumber" >= 1),
  "useHallName" boolean NOT NULL DEFAULT true,
  name varchar(200) NOT NULL,
  "spaceType" varchar(20) NOT NULL DEFAULT 'indoor'
    CHECK ("spaceType" IN ('indoor','outdoor')),
  "listingActive" boolean NOT NULL DEFAULT true,
  "packageSaved" boolean NOT NULL DEFAULT false,
  "packageRevisionId" uuid NULL,
  "coverImageUrl" text NULL,
  "archivedAt" timestamptz NULL,
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  "updatedAt" timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE ("businessId", "hallNumber")
);
CREATE INDEX IF NOT EXISTS business_halls_business
  ON business_halls ("businessId") WHERE "archivedAt" IS NULL;

CREATE TABLE IF NOT EXISTS business_hall_package_revisions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "hallId" uuid NOT NULL REFERENCES business_halls(id) ON DELETE CASCADE,
  revision integer NOT NULL CHECK (revision >= 1),
  package jsonb NOT NULL,
  "createdBy" uuid NOT NULL REFERENCES users(id),
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE ("hallId", revision)
);
DO $$ BEGIN
  ALTER TABLE business_halls
    ADD CONSTRAINT business_halls_packageRevisionId_fkey
    FOREIGN KEY ("packageRevisionId")
    REFERENCES business_hall_package_revisions(id)
    ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS business_hall_operators (
  "hallId" uuid NOT NULL REFERENCES business_halls(id) ON DELETE CASCADE,
  "userId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY ("hallId", "userId")
);

CREATE TABLE IF NOT EXISTS business_hall_media (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "hallId" uuid NOT NULL REFERENCES business_halls(id) ON DELETE CASCADE,
  url text NOT NULL,
  kind varchar(20) NOT NULL DEFAULT 'gallery' CHECK (kind IN ('gallery')),
  "sortOrder" integer NOT NULL DEFAULT 0,
  "createdAt" timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS business_hall_media_hall
  ON business_hall_media ("hallId", "sortOrder");

CREATE TABLE IF NOT EXISTS hall_audit_log (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  "hallId" uuid NULL REFERENCES business_halls(id) ON DELETE SET NULL,
  "entityType" varchar(64) NOT NULL,
  "entityId" varchar(64) NOT NULL,
  action varchar(64) NOT NULL,
  "actorUserId" uuid NOT NULL REFERENCES users(id),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS hall_audit_log_business
  ON hall_audit_log ("businessId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS hall_calendar_blocks (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  "hallId" uuid NULL REFERENCES business_halls(id) ON DELETE CASCADE,
  "startAt" timestamptz NOT NULL,
  "endAt" timestamptz NOT NULL,
  reason varchar(40) NOT NULL DEFAULT 'offline'
    CHECK (reason IN ('offline','temp','maintenance','other')),
  notes text NOT NULL DEFAULT '',
  "createdBy" uuid NOT NULL REFERENCES users(id),
  "releasedAt" timestamptz NULL,
  "releasedBy" uuid NULL REFERENCES users(id),
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  CHECK ("endAt" > "startAt")
);
CREATE INDEX IF NOT EXISTS hall_calendar_blocks_biz_range
  ON hall_calendar_blocks ("businessId", "startAt", "endAt")
  WHERE "releasedAt" IS NULL;
CREATE INDEX IF NOT EXISTS hall_calendar_blocks_hall_range
  ON hall_calendar_blocks ("hallId", "startAt", "endAt")
  WHERE "releasedAt" IS NULL AND "hallId" IS NOT NULL;

CREATE OR REPLACE FUNCTION hall_calendar_blocks_biz_check()
RETURNS trigger AS $$
BEGIN
  IF NEW."hallId" IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM business_halls h
      WHERE h.id = NEW."hallId" AND h."businessId" = NEW."businessId"
    ) THEN
      RAISE EXCEPTION 'hall_calendar_blocks hall/business mismatch';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS hall_calendar_blocks_biz_trg ON hall_calendar_blocks;
CREATE TRIGGER hall_calendar_blocks_biz_trg
  BEFORE INSERT OR UPDATE ON hall_calendar_blocks
  FOR EACH ROW EXECUTE PROCEDURE hall_calendar_blocks_biz_check();

CREATE TABLE IF NOT EXISTS hall_reservations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  "hallId" uuid NOT NULL REFERENCES business_halls(id) ON DELETE CASCADE,
  "enquiryId" uuid NULL,
  "quoteId" uuid NULL,
  "startAt" timestamptz NOT NULL,
  "endAt" timestamptz NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'HELD'
    CHECK (status IN ('HELD','CONFIRMED','RELEASED')),
  "expiresAt" timestamptz NULL,
  "releasedAt" timestamptz NULL,
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  "updatedAt" timestamptz NOT NULL DEFAULT NOW(),
  CHECK ("endAt" > "startAt"),
  CHECK (status <> 'HELD' OR "expiresAt" IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS hall_reservations_hall_range
  ON hall_reservations ("hallId", "startAt", "endAt")
  WHERE status IN ('HELD','CONFIRMED');
CREATE INDEX IF NOT EXISTS hall_reservations_biz
  ON hall_reservations ("businessId", status);

-- Day-list backfill lives in scripts/availability_intervals.sql.
-- This file only creates hall tables. It does not copy offlineDays.

INSERT INTO business_hall_venue ("businessId")
SELECT id FROM businesses
WHERE type = 'SERVICE' AND "serviceType"::text = 'HALL'
ON CONFLICT ("businessId") DO NOTHING;

-- ---------------------------------------------------------------- Phase 3
CREATE TABLE IF NOT EXISTS hall_enquiries (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "eventPlanId" uuid NOT NULL REFERENCES event_plans(id) ON DELETE CASCADE,
  "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  status varchar(40) NOT NULL DEFAULT 'PENDING_OWNER'
    CHECK (status IN (
      'PENDING_OWNER','OWNER_APPROVED','OWNER_DECLINED','ASSIGNED',
      'QUOTE_OFFERED','CUSTOMER_ACCEPTED','QUOTE_DECLINED','QUOTE_EXPIRED','CANCELLED'
    )),
  "assignedHallId" uuid NULL REFERENCES business_halls(id) ON DELETE SET NULL,
  "proposedStartAt" timestamptz NULL,
  "proposedEndAt" timestamptz NULL,
  "activeQuoteId" uuid NULL,
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  "updatedAt" timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE ("eventPlanId", "businessId"),
  CHECK (
    ("proposedStartAt" IS NULL AND "proposedEndAt" IS NULL)
    OR ("proposedEndAt" > "proposedStartAt")
  )
);
CREATE INDEX IF NOT EXISTS hall_enquiries_business_status
  ON hall_enquiries ("businessId", status);
CREATE INDEX IF NOT EXISTS hall_enquiries_hall
  ON hall_enquiries ("assignedHallId") WHERE "assignedHallId" IS NOT NULL;

DO $$ BEGIN
  ALTER TABLE hall_reservations
    ADD CONSTRAINT hall_reservations_enquiryId_fkey
    FOREIGN KEY ("enquiryId") REFERENCES hall_enquiries(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS hall_booking_terms_snapshot (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "quoteId" uuid NOT NULL,
  "quoteRevision" integer NOT NULL DEFAULT 1,
  "packageRevisionId" uuid NULL REFERENCES business_hall_package_revisions(id) ON DELETE SET NULL,
  "hallId" uuid NULL REFERENCES business_halls(id) ON DELETE SET NULL,
  "deductionBasis" varchar(20) NOT NULL DEFAULT 'ADVANCE'
    CHECK ("deductionBasis" IN ('ADVANCE','TOTAL_QUOTE')),
  terms jsonb NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT NOW()
);

-- event_quotes revisions -----------------------------------------------------
ALTER TABLE event_quotes DROP CONSTRAINT IF EXISTS "UQ_event_quotes_planId_businessId_serviceType";
DO $$
DECLARE cname text;
BEGIN
  SELECT conname INTO cname
  FROM pg_constraint
  WHERE conrelid = 'event_quotes'::regclass
    AND contype = 'u'
    AND pg_get_constraintdef(oid) LIKE '%planId%businessId%serviceType%'
    AND pg_get_constraintdef(oid) NOT LIKE '%revision%';
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE event_quotes DROP CONSTRAINT %I', cname);
  END IF;
END $$;
-- Also drop a unique INDEX of that shape if TypeORM created one instead.
DO $$
DECLARE iname text;
BEGIN
  SELECT i.relname INTO iname
  FROM pg_index x
  JOIN pg_class i ON i.oid = x.indexrelid
  WHERE x.indrelid = 'event_quotes'::regclass
    AND x.indisunique
    AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = x.indexrelid)
    AND pg_get_indexdef(x.indexrelid) LIKE '%planId%businessId%serviceType%'
    AND pg_get_indexdef(x.indexrelid) NOT LIKE '%revision%'
    AND pg_get_indexdef(x.indexrelid) NOT LIKE '%WHERE%';
  IF iname IS NOT NULL THEN
    EXECUTE format('DROP INDEX %I', iname);
  END IF;
END $$;

ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1;
ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "supersedesQuoteId" uuid NULL REFERENCES event_quotes(id);
ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "hallEnquiryId" uuid NULL REFERENCES hall_enquiries(id);
ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "hallId" uuid NULL REFERENCES business_halls(id);
ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "intervalStart" timestamptz NULL;
ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "intervalEnd" timestamptz NULL;
ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "supersedeReason" varchar(40) NULL;

ALTER TABLE event_quotes DROP CONSTRAINT IF EXISTS event_quotes_status_check;
DO $$
DECLARE cname text;
BEGIN
  SELECT conname INTO cname
  FROM pg_constraint
  WHERE conrelid = 'event_quotes'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%OFFERED%DECLINED%';
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE event_quotes DROP CONSTRAINT %I', cname);
  END IF;
END $$;
ALTER TABLE event_quotes ADD CONSTRAINT event_quotes_status_check
  CHECK (status IN (
    'OFFERED','DECLINED','EXPIRED','CONFIRMED','COMPLETED',
    'CANCEL_REQUESTED','CANCELLED','SUPERSEDED'
  ));

DO $$ BEGIN
  ALTER TABLE event_quotes
    ADD CONSTRAINT event_quotes_revision_unique
    UNIQUE ("planId", "businessId", "serviceType", revision);
EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS event_quotes_one_offered
  ON event_quotes ("planId", "businessId", "serviceType")
  WHERE status = 'OFFERED';

DO $$ BEGIN
  ALTER TABLE hall_booking_terms_snapshot
    ADD CONSTRAINT hall_booking_terms_snapshot_quoteId_fkey
    FOREIGN KEY ("quoteId") REFERENCES event_quotes(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE hall_reservations
    ADD CONSTRAINT hall_reservations_quoteId_fkey
    FOREIGN KEY ("quoteId") REFERENCES event_quotes(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- cache domains used by the hall module (per-business/hall domains are upserted at runtime).
INSERT INTO cache_versions (domain, version) VALUES ('halls', 1), ('hall_enquiries', 1)
ON CONFLICT (domain) DO NOTHING;
