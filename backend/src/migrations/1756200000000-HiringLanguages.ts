import { MigrationInterface, QueryRunner } from 'typeorm';

/// Shared hiring language master and language preferences on requests/profiles.
export class HiringLanguages1756200000000 implements MigrationInterface {
  name = 'HiringLanguages1756200000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_languages (
        id varchar PRIMARY KEY,
        label varchar NOT NULL,
        "quickPick" boolean NOT NULL DEFAULT false,
        "sortOrder" int NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true,
        "updatedAt" timestamptz NOT NULL DEFAULT NOW()
      )`);

    await queryRunner.query(`
      ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "languageIds" text NOT NULL DEFAULT ''`);
    await queryRunner.query(`
      ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "languageIds" text NOT NULL DEFAULT ''`);
    await queryRunner.query(`
      ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "languageIds" text NOT NULL DEFAULT ''`);
    await queryRunner.query(`
      ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "languageIds" text NOT NULL DEFAULT ''`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE job_posts DROP COLUMN IF EXISTS "languageIds"`);
    await queryRunner.query(`ALTER TABLE talent_profiles DROP COLUMN IF EXISTS "languageIds"`);
    await queryRunner.query(`ALTER TABLE job_preferences DROP COLUMN IF EXISTS "languageIds"`);
    await queryRunner.query(`ALTER TABLE hiring_requests DROP COLUMN IF EXISTS "languageIds"`);
    await queryRunner.query(`DROP TABLE IF EXISTS hiring_languages`);
  }
}
