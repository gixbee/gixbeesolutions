import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Hall owner Phase 1–2 schema: venue setup, halls, package revisions,
 * operators, media, audit, calendar blocks, reservations.
 * Enquiries / quote revisions ship in 1756600000000.
 */
export class BusinessHalls1756500000000 implements MigrationInterface {
  name = 'BusinessHalls1756500000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
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
      )`);

    await q.query(`
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
      )`);
    await q.query(
      `CREATE INDEX IF NOT EXISTS business_halls_business ON business_halls ("businessId") WHERE "archivedAt" IS NULL`,
    );

    await q.query(`
      CREATE TABLE IF NOT EXISTS business_hall_package_revisions (
        id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
        "hallId" uuid NOT NULL REFERENCES business_halls(id) ON DELETE CASCADE,
        revision integer NOT NULL CHECK (revision >= 1),
        package jsonb NOT NULL,
        "createdBy" uuid NOT NULL REFERENCES users(id),
        "createdAt" timestamptz NOT NULL DEFAULT NOW(),
        UNIQUE ("hallId", revision)
      )`);
    await q.query(`
      ALTER TABLE business_halls
        DROP CONSTRAINT IF EXISTS business_halls_packageRevisionId_fkey`);
    await q.query(`
      DO $$ BEGIN
        ALTER TABLE business_halls
          ADD CONSTRAINT business_halls_packageRevisionId_fkey
          FOREIGN KEY ("packageRevisionId")
          REFERENCES business_hall_package_revisions(id)
          ON DELETE SET NULL;
      EXCEPTION WHEN duplicate_object THEN NULL;
      END $$`);

    await q.query(`
      CREATE TABLE IF NOT EXISTS business_hall_operators (
        "hallId" uuid NOT NULL REFERENCES business_halls(id) ON DELETE CASCADE,
        "userId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        "createdAt" timestamptz NOT NULL DEFAULT NOW(),
        PRIMARY KEY ("hallId", "userId")
      )`);

    await q.query(`
      CREATE TABLE IF NOT EXISTS business_hall_media (
        id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
        "hallId" uuid NOT NULL REFERENCES business_halls(id) ON DELETE CASCADE,
        url text NOT NULL,
        kind varchar(20) NOT NULL DEFAULT 'gallery'
          CHECK (kind IN ('gallery')),
        "sortOrder" integer NOT NULL DEFAULT 0,
        "createdAt" timestamptz NOT NULL DEFAULT NOW()
      )`);
    await q.query(
      `CREATE INDEX IF NOT EXISTS business_hall_media_hall ON business_hall_media ("hallId", "sortOrder")`,
    );

    await q.query(`
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
      )`);
    await q.query(
      `CREATE INDEX IF NOT EXISTS hall_audit_log_business ON hall_audit_log ("businessId", "createdAt" DESC)`,
    );

    await q.query(`
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
      )`);
    await q.query(
      `CREATE INDEX IF NOT EXISTS hall_calendar_blocks_biz_range
        ON hall_calendar_blocks ("businessId", "startAt", "endAt")
        WHERE "releasedAt" IS NULL`,
    );
    await q.query(
      `CREATE INDEX IF NOT EXISTS hall_calendar_blocks_hall_range
        ON hall_calendar_blocks ("hallId", "startAt", "endAt")
        WHERE "releasedAt" IS NULL AND "hallId" IS NOT NULL`,
    );

    // Enforce hall.businessId = block.businessId when hallId is set.
    await q.query(`
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
      $$ LANGUAGE plpgsql`);
    await q.query(`DROP TRIGGER IF EXISTS hall_calendar_blocks_biz_trg ON hall_calendar_blocks`);
    await q.query(`
      CREATE TRIGGER hall_calendar_blocks_biz_trg
      BEFORE INSERT OR UPDATE ON hall_calendar_blocks
      FOR EACH ROW EXECUTE PROCEDURE hall_calendar_blocks_biz_check()`);

    await q.query(`
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
      )`);
    await q.query(
      `CREATE INDEX IF NOT EXISTS hall_reservations_hall_range
        ON hall_reservations ("hallId", "startAt", "endAt")
        WHERE status IN ('HELD','CONFIRMED')`,
    );
    await q.query(
      `CREATE INDEX IF NOT EXISTS hall_reservations_biz
        ON hall_reservations ("businessId", status)`,
    );

    // Migrate HALL business offlineDays → venue-wide blocks when the column
    // is JSON-array shaped. Failures are ignored so setup still completes.
    await q.query(`
      DO $$
      BEGIN
        INSERT INTO hall_calendar_blocks (
          id, "businessId", "hallId", "startAt", "endAt", reason, notes, "createdBy"
        )
        SELECT
          uuid_generate_v4(),
          b.id,
          NULL,
          (left(elem, 10)::date AT TIME ZONE 'Asia/Kolkata'),
          ((left(elem, 10)::date + 1) AT TIME ZONE 'Asia/Kolkata'),
          'offline',
          'Migrated from business offlineDays',
          b."ownerId"
        FROM businesses b
        CROSS JOIN LATERAL jsonb_array_elements_text(
          COALESCE(b."offlineDays"::jsonb, '[]'::jsonb)
        ) AS elem
        WHERE b.type = 'SERVICE'
          AND b."serviceType"::text = 'HALL'
          AND length(elem) >= 10;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'offlineDays backfill skipped: %', SQLERRM;
      END $$`);

    // Ensure venue rows exist for existing HALL businesses.
    await q.query(`
      INSERT INTO business_hall_venue ("businessId")
      SELECT id FROM businesses
      WHERE type = 'SERVICE' AND "serviceType"::text = 'HALL'
      ON CONFLICT ("businessId") DO NOTHING`);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP TRIGGER IF EXISTS hall_calendar_blocks_biz_trg ON hall_calendar_blocks`);
    await q.query(`DROP FUNCTION IF EXISTS hall_calendar_blocks_biz_check()`);
    await q.query(`DROP TABLE IF EXISTS hall_reservations`);
    await q.query(`DROP TABLE IF EXISTS hall_calendar_blocks`);
    await q.query(`DROP TABLE IF EXISTS hall_audit_log`);
    await q.query(`DROP TABLE IF EXISTS business_hall_media`);
    await q.query(`DROP TABLE IF EXISTS business_hall_operators`);
    await q.query(`ALTER TABLE business_halls DROP CONSTRAINT IF EXISTS business_halls_packageRevisionId_fkey`);
    await q.query(`DROP TABLE IF EXISTS business_hall_package_revisions`);
    await q.query(`DROP TABLE IF EXISTS business_halls`);
    await q.query(`DROP TABLE IF EXISTS business_hall_venue`);
  }
}
