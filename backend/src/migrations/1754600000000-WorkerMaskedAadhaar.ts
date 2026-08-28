import { MigrationInterface, QueryRunner } from 'typeorm';

/** Store masked Aadhaar reference after Surepass eKYC (never the full number). */
export class WorkerMaskedAadhaar1754600000000 implements MigrationInterface {
  name = 'WorkerMaskedAadhaar1754600000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "worker_profiles"
      ADD COLUMN IF NOT EXISTS "maskedAadhaar" varchar
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "worker_profiles"
      DROP COLUMN IF EXISTS "maskedAadhaar"
    `);
  }
}
