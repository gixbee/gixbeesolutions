import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * V147-02: employment type on Smart Hiring profiles + requests.
 */
export class HiringEmploymentType1754710000000 implements MigrationInterface {
  name = 'HiringEmploymentType1754710000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'employment_type_enum') THEN
          CREATE TYPE "employment_type_enum" AS ENUM ('FT', 'PT', 'INTERN', 'CONTRACT');
        END IF;
      END $$
    `);
    await queryRunner.query(`
      ALTER TABLE "hiring_requests"
      ADD COLUMN IF NOT EXISTS "employmentType" "employment_type_enum"
    `);
    await queryRunner.query(`
      ALTER TABLE "job_preferences"
      ADD COLUMN IF NOT EXISTS "employmentType" "employment_type_enum"
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "job_preferences"
      DROP COLUMN IF EXISTS "employmentType"
    `);
    await queryRunner.query(`
      ALTER TABLE "hiring_requests"
      DROP COLUMN IF EXISTS "employmentType"
    `);
    await queryRunner.query(`DROP TYPE IF EXISTS "employment_type_enum"`);
  }
}
