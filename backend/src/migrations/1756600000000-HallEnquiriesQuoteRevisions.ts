import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Hall Phase 3: enquiries, booking terms snapshots, event_quotes revisions
 * so re-offers can INSERT without colliding on (planId, businessId, serviceType).
 */
export class HallEnquiriesQuoteRevisions1756600000000
  implements MigrationInterface
{
  name = 'HallEnquiriesQuoteRevisions1756600000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
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
      )`);
    await q.query(
      `CREATE INDEX IF NOT EXISTS hall_enquiries_business_status
        ON hall_enquiries ("businessId", status)`,
    );
    await q.query(
      `CREATE INDEX IF NOT EXISTS hall_enquiries_hall
        ON hall_enquiries ("assignedHallId") WHERE "assignedHallId" IS NOT NULL`,
    );

    await q.query(`
      ALTER TABLE hall_reservations
        DROP CONSTRAINT IF EXISTS hall_reservations_enquiryId_fkey`);
    await q.query(`
      DO $$ BEGIN
        ALTER TABLE hall_reservations
          ADD CONSTRAINT hall_reservations_enquiryId_fkey
          FOREIGN KEY ("enquiryId") REFERENCES hall_enquiries(id) ON DELETE SET NULL;
      EXCEPTION WHEN duplicate_object THEN NULL;
      END $$`);

    await q.query(`
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
      )`);

    // --- event_quotes revisions ---
    await q.query(
      `ALTER TABLE event_quotes DROP CONSTRAINT IF EXISTS "UQ_event_quotes_planId_businessId_serviceType"`,
    );
    // TypeORM may name the unique constraint differently.
    await q.query(`
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
      END $$`);

    await q.query(
      `ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1`,
    );
    await q.query(
      `ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "supersedesQuoteId" uuid NULL REFERENCES event_quotes(id)`,
    );
    await q.query(
      `ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "hallEnquiryId" uuid NULL REFERENCES hall_enquiries(id)`,
    );
    await q.query(
      `ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "hallId" uuid NULL REFERENCES business_halls(id)`,
    );
    await q.query(
      `ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "intervalStart" timestamptz NULL`,
    );
    await q.query(
      `ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "intervalEnd" timestamptz NULL`,
    );
    await q.query(
      `ALTER TABLE event_quotes ADD COLUMN IF NOT EXISTS "supersedeReason" varchar(40) NULL`,
    );

    // Expand status check to include SUPERSEDED.
    await q.query(`
      ALTER TABLE event_quotes DROP CONSTRAINT IF EXISTS event_quotes_status_check`);
    await q.query(`
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
      END $$`);
    await q.query(`
      ALTER TABLE event_quotes ADD CONSTRAINT event_quotes_status_check
        CHECK (status IN (
          'OFFERED','DECLINED','EXPIRED','CONFIRMED','COMPLETED',
          'CANCEL_REQUESTED','CANCELLED','SUPERSEDED'
        ))`);

    await q.query(`
      DO $$ BEGIN
        ALTER TABLE event_quotes
          ADD CONSTRAINT event_quotes_revision_unique
          UNIQUE ("planId", "businessId", "serviceType", revision);
      EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;
      END $$`);

    await q.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS event_quotes_one_offered
        ON event_quotes ("planId", "businessId", "serviceType")
        WHERE status = 'OFFERED'`);

    await q.query(`
      DO $$ BEGIN
        ALTER TABLE hall_booking_terms_snapshot
          ADD CONSTRAINT hall_booking_terms_snapshot_quoteId_fkey
          FOREIGN KEY ("quoteId") REFERENCES event_quotes(id) ON DELETE CASCADE;
      EXCEPTION WHEN duplicate_object THEN NULL;
      END $$`);

    await q.query(`
      DO $$ BEGIN
        ALTER TABLE hall_reservations
          ADD CONSTRAINT hall_reservations_quoteId_fkey
          FOREIGN KEY ("quoteId") REFERENCES event_quotes(id) ON DELETE SET NULL;
      EXCEPTION WHEN duplicate_object THEN NULL;
      END $$`);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(
      `ALTER TABLE hall_reservations DROP CONSTRAINT IF EXISTS hall_reservations_quoteId_fkey`,
    );
    await q.query(
      `ALTER TABLE hall_booking_terms_snapshot DROP CONSTRAINT IF EXISTS hall_booking_terms_snapshot_quoteId_fkey`,
    );
    await q.query(`DROP INDEX IF EXISTS event_quotes_one_offered`);
    await q.query(
      `ALTER TABLE event_quotes DROP CONSTRAINT IF EXISTS event_quotes_revision_unique`,
    );
    await q.query(
      `ALTER TABLE event_quotes DROP CONSTRAINT IF EXISTS event_quotes_status_check`,
    );
    await q.query(
      `ALTER TABLE event_quotes ADD CONSTRAINT event_quotes_status_check
        CHECK (status IN (
          'OFFERED','DECLINED','EXPIRED','CONFIRMED','COMPLETED',
          'CANCEL_REQUESTED','CANCELLED'
        ))`,
    );
    await q.query(
      `ALTER TABLE event_quotes DROP COLUMN IF EXISTS "supersedeReason"`,
    );
    await q.query(
      `ALTER TABLE event_quotes DROP COLUMN IF EXISTS "intervalEnd"`,
    );
    await q.query(
      `ALTER TABLE event_quotes DROP COLUMN IF EXISTS "intervalStart"`,
    );
    await q.query(`ALTER TABLE event_quotes DROP COLUMN IF EXISTS "hallId"`);
    await q.query(
      `ALTER TABLE event_quotes DROP COLUMN IF EXISTS "hallEnquiryId"`,
    );
    await q.query(
      `ALTER TABLE event_quotes DROP COLUMN IF EXISTS "supersedesQuoteId"`,
    );
    await q.query(`ALTER TABLE event_quotes DROP COLUMN IF EXISTS revision`);
    await q.query(`
      DO $$ BEGIN
        ALTER TABLE event_quotes
          ADD CONSTRAINT "UQ_event_quotes_planId_businessId_serviceType"
          UNIQUE ("planId", "businessId", "serviceType");
      EXCEPTION WHEN duplicate_object THEN NULL;
      END $$`);
    await q.query(
      `ALTER TABLE hall_reservations DROP CONSTRAINT IF EXISTS hall_reservations_enquiryId_fkey`,
    );
    await q.query(`DROP TABLE IF EXISTS hall_booking_terms_snapshot`);
    await q.query(`DROP TABLE IF EXISTS hall_enquiries`);
  }
}
