import { MigrationInterface, QueryRunner } from 'typeorm';
export class CareerProfileReceipts1755300000000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE payment_orders ALTER COLUMN "userId" TYPE uuid USING "userId"::uuid`);
    await q.query(`CREATE TABLE IF NOT EXISTS career_profile_receipts (
      "paymentOrderId" uuid PRIMARY KEY REFERENCES payment_orders(id),
      "preferenceId" uuid NOT NULL REFERENCES job_preferences(id), "createdAt" timestamptz NOT NULL DEFAULT NOW())`);
  }
  async down(): Promise<void> { /* Preserve payment fulfillment receipts. */ }
}
