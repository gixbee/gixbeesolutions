import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreatePaymentOrders1753400000000 implements MigrationInterface {
  name = 'CreatePaymentOrders1753400000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS payment_orders (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        "userId" uuid NOT NULL,
        amount numeric(10,2) NOT NULL,
        "razorpayOrderId" varchar NOT NULL,
        "razorpayPaymentId" varchar,
        status varchar NOT NULL DEFAULT 'CREATED',
        "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `);
    
    await queryRunner.query(`
      ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "jobsSincePayment" integer DEFAULT 0
    `);
    
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_payment_orders_userId" ON payment_orders ("userId")
    `);
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS "IDX_payment_orders_razorpayOrderId" ON payment_orders ("razorpayOrderId")
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_payment_orders_razorpayOrderId"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_payment_orders_userId"`);
    await queryRunner.query(`ALTER TABLE worker_profiles DROP COLUMN IF EXISTS "jobsSincePayment"`);
    await queryRunner.query(`DROP TABLE IF EXISTS payment_orders`);
  }
}
