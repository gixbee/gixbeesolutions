import { MigrationInterface, QueryRunner } from 'typeorm';

/// Pause one job profile without pausing others or the whole talent account.
export class JobPreferenceMatchingPaused1756100000000 implements MigrationInterface {
  name = 'JobPreferenceMatchingPaused1756100000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "matchingPaused" boolean NOT NULL DEFAULT false`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE job_preferences DROP COLUMN IF EXISTS "matchingPaused"`,
    );
  }
}
