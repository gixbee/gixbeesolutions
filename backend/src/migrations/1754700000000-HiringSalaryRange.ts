import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * V147-03: employer salary range + negotiable flags for Smart Hiring matcher.
 */
export class HiringSalaryRange1754700000000 implements MigrationInterface {
  name = 'HiringSalaryRange1754700000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "hiring_requests"
      ADD COLUMN IF NOT EXISTS "salaryMin" numeric(10,2) NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS "salaryMax" numeric(10,2) NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS "salaryNegotiable" boolean NOT NULL DEFAULT false
    `);
    await queryRunner.query(`
      UPDATE "hiring_requests"
      SET "salaryMax" = "salaryOffered"
      WHERE "salaryMax" = 0 AND "salaryOffered" > 0
    `);
    await queryRunner.query(`
      UPDATE "hiring_requests"
      SET "salaryMin" = "salaryOffered"
      WHERE "salaryMin" = 0 AND "salaryMax" = "salaryOffered" AND "salaryOffered" > 0
    `);

    await queryRunner.query(`
      ALTER TABLE "job_preferences"
      ADD COLUMN IF NOT EXISTS "salaryNegotiable" boolean NOT NULL DEFAULT false
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "job_preferences"
      DROP COLUMN IF EXISTS "salaryNegotiable"
    `);
    await queryRunner.query(`
      ALTER TABLE "hiring_requests"
      DROP COLUMN IF EXISTS "salaryNegotiable",
      DROP COLUMN IF EXISTS "salaryMax",
      DROP COLUMN IF EXISTS "salaryMin"
    `);
  }
}
