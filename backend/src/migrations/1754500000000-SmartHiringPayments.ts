import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Smart Hiring client wiring: hiring credit on users, Razorpay payment meta +
 * purposes, and hiring_requests payment/credit columns for 24h guarantee refunds.
 */
export class SmartHiringPayments1754500000000 implements MigrationInterface {
  name = 'SmartHiringPayments1754500000000';

  /** Enum ADD VALUE cannot run inside a PG transaction on older servers. */
  transaction = false;

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "users"
      ADD COLUMN IF NOT EXISTS "hiringCreditBalance" numeric(10,2) NOT NULL DEFAULT 0
    `);

    await queryRunner.query(`
      ALTER TABLE "payment_orders"
      ADD COLUMN IF NOT EXISTS "meta" jsonb
    `);

    // purpose may be enum or varchar depending on when the table was created
    await queryRunner.query(`
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1 FROM pg_type WHERE typname = 'payment_orders_purpose_enum'
        ) THEN
          ALTER TYPE "payment_orders_purpose_enum"
            ADD VALUE IF NOT EXISTS 'HIRING_MATCH_FEE';
          ALTER TYPE "payment_orders_purpose_enum"
            ADD VALUE IF NOT EXISTS 'EXTRA_JOB_TYPE_FEE';
        END IF;
      END $$
    `);

    await queryRunner.query(`
      ALTER TABLE "hiring_requests"
      ADD COLUMN IF NOT EXISTS "creditApplied" numeric(10,2) NOT NULL DEFAULT 0
    `);
    await queryRunner.query(`
      ALTER TABLE "hiring_requests"
      ADD COLUMN IF NOT EXISTS "paymentOrderId" uuid
    `);
    await queryRunner.query(`
      ALTER TABLE "hiring_requests"
      ADD COLUMN IF NOT EXISTS "razorpayPaymentId" varchar
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "hiring_requests" DROP COLUMN IF EXISTS "razorpayPaymentId"`,
    );
    await queryRunner.query(
      `ALTER TABLE "hiring_requests" DROP COLUMN IF EXISTS "paymentOrderId"`,
    );
    await queryRunner.query(
      `ALTER TABLE "hiring_requests" DROP COLUMN IF EXISTS "creditApplied"`,
    );
    await queryRunner.query(
      `ALTER TABLE "payment_orders" DROP COLUMN IF EXISTS "meta"`,
    );
    await queryRunner.query(
      `ALTER TABLE "users" DROP COLUMN IF EXISTS "hiringCreditBalance"`,
    );
    // Enum values cannot be removed safely in Postgres — leave them.
  }
}
