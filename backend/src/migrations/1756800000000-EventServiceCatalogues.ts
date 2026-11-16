import { MigrationInterface, QueryRunner } from 'typeorm';

export class EventServiceCatalogues1756800000000 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS event_service_catalogues (
        "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        "serviceType" text NOT NULL CHECK ("serviceType" IN ('PHOTOGRAPHY', 'CATERING')),
        catalogue jsonb NOT NULL CHECK (jsonb_typeof(catalogue) = 'object'),
        revision integer NOT NULL DEFAULT 1,
        PRIMARY KEY ("businessId", "serviceType")
      );
      ALTER TABLE event_plans ADD COLUMN IF NOT EXISTS "targetBusinessId" uuid REFERENCES businesses(id);
      ALTER TABLE event_plans ADD COLUMN IF NOT EXISTS "serviceRequest" jsonb;
      ALTER TABLE event_plans ADD COLUMN IF NOT EXISTS "clientRequestId" uuid;
      CREATE UNIQUE INDEX IF NOT EXISTS event_plans_client_request ON event_plans ("customerId", "clientRequestId");
      CREATE INDEX IF NOT EXISTS event_plans_target_business ON event_plans ("targetBusinessId", "startTime");
      CREATE TABLE IF NOT EXISTS event_vendor_calendar (
        id uuid PRIMARY KEY,
        "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        title text NOT NULL,
        "startAt" timestamptz NOT NULL,
        "endAt" timestamptz NOT NULL CHECK ("endAt" > "startAt"),
        "cancelledAt" timestamptz
      );
      CREATE INDEX IF NOT EXISTS event_vendor_calendar_active ON event_vendor_calendar
        ("businessId", "startAt", "endAt") WHERE "cancelledAt" IS NULL;
    `);
  }

  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE event_plans DROP COLUMN IF EXISTS "serviceRequest", DROP COLUMN IF EXISTS "targetBusinessId",
        DROP COLUMN IF EXISTS "clientRequestId";
      DROP TABLE IF EXISTS event_vendor_calendar;
      DROP TABLE IF EXISTS event_service_catalogues;
    `);
  }
}
