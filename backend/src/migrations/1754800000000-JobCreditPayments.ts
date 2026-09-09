import { MigrationInterface, QueryRunner } from 'typeorm';

export class JobCreditPayments1754800000000 implements MigrationInterface {
  name = 'JobCreditPayments1754800000000';

  async up(queryRunner: QueryRunner): Promise<void> {
    // Rust casts to this enum explicitly. A missing enum must fail migration,
    // rather than record success and leave every order insert broken.
    // Commit this migration before starting the new Rust binary.
    await queryRunner.query(
      `ALTER TYPE "payment_orders_purpose_enum" ADD VALUE IF NOT EXISTS 'JOB_CREDITS'`,
    );
  }

  async down(): Promise<void> {
    // Retain the enum value and all financial receipts on application rollback.
  }
}
