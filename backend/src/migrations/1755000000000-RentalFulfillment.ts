import { MigrationInterface, QueryRunner } from 'typeorm';

export class RentalFulfillment1755000000000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE rental_items
      ADD COLUMN IF NOT EXISTS "businessId" uuid NULL REFERENCES businesses(id),
      ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 100000),
      ADD COLUMN IF NOT EXISTS "pickupAddress" text NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS "deliveryAvailable" boolean NOT NULL DEFAULT false,
      ADD COLUMN IF NOT EXISTS "deliveryFee" numeric(10,2) NOT NULL DEFAULT 0 CHECK ("deliveryFee" >= 0),
      ADD COLUMN IF NOT EXISTS "depositPerUnit" numeric(10,2) NOT NULL DEFAULT 0 CHECK ("depositPerUnit" >= 0)`);
    await q.query(`ALTER TABLE rental_reservations
      ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 100000),
      ADD COLUMN IF NOT EXISTS fulfillment varchar(20) NOT NULL DEFAULT 'PICKUP' CHECK (fulfillment IN ('PICKUP','DELIVERY')),
      ADD COLUMN IF NOT EXISTS "fulfillmentAddress" text NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS "priceBreakdown" jsonb NOT NULL DEFAULT '{}'::jsonb,
      ADD COLUMN IF NOT EXISTS "ownerHandedOverAt" timestamptz NULL,
      ADD COLUMN IF NOT EXISTS "renterCollectedAt" timestamptz NULL,
      ADD COLUMN IF NOT EXISTS "ownerReturnedAt" timestamptz NULL,
      ADD COLUMN IF NOT EXISTS "renterReturnedAt" timestamptz NULL,
      ADD COLUMN IF NOT EXISTS "ownerPaidAt" timestamptz NULL,
      ADD COLUMN IF NOT EXISTS "renterPaidAt" timestamptz NULL,
      ADD COLUMN IF NOT EXISTS "ownerRefundedAt" timestamptz NULL,
      ADD COLUMN IF NOT EXISTS "renterRefundedAt" timestamptz NULL`);
    await q.query(`CREATE INDEX IF NOT EXISTS rental_items_business ON rental_items ("businessId")`);
  }
  async down(): Promise<void> {
    // Preserve fulfillment and payment acknowledgement history on application rollback.
  }
}
