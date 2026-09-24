import { MigrationInterface, QueryRunner } from 'typeorm';

/// Gig is a real employment code, and Hire Employee stores on-site vs remote.
export class HiringGigAndWorkMode1756000000000 implements MigrationInterface {
  name = 'HiringGigAndWorkMode1756000000000';
  transaction = false;

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "workMode" varchar NOT NULL DEFAULT 'ONSITE'`,
    );
    await queryRunner.query(
      `ALTER TYPE hiring_requests_employmenttype_enum ADD VALUE IF NOT EXISTS 'GIG'`,
    );
    await queryRunner.query(
      `ALTER TYPE job_preferences_employmenttype_enum ADD VALUE IF NOT EXISTS 'GIG'`,
    );
  }

  public async down(): Promise<void> {
    // Enum values cannot be removed without rewriting the type.
  }
}
