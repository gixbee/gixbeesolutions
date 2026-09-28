import { MigrationInterface, QueryRunner } from 'typeorm';

/// Salary period on career preferences, and the Hire Employee description.
export class JobFlowCompleteness1755800000000 implements MigrationInterface {
  name = 'JobFlowCompleteness1755800000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "expectedSalaryPeriod" varchar NOT NULL DEFAULT 'MONTHLY'`,
    );
    await queryRunner.query(
      `ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS description text`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE hiring_requests DROP COLUMN IF EXISTS description`);
    await queryRunner.query(
      `ALTER TABLE job_preferences DROP COLUMN IF EXISTS "expectedSalaryPeriod"`,
    );
  }
}
