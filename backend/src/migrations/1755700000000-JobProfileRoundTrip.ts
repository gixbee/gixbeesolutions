import { MigrationInterface, QueryRunner } from 'typeorm';

/// Seeker choices that must round-trip: salary period, employment list,
/// resume metadata, custom join date, and 7-day / custom notice codes.
export class JobProfileRoundTrip1755700000000 implements MigrationInterface {
  name = 'JobProfileRoundTrip1755700000000';
  transaction = false;

  public async up(queryRunner: QueryRunner): Promise<void> {
    const q = (sql: string) => queryRunner.query(sql);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "expectedSalaryPeriod" varchar NOT NULL DEFAULT 'MONTHLY'`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "employmentTypes" text`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "availableOn" date`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "resumeUrl" varchar`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "resumeFileName" varchar`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "resumeMimeType" varchar`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "resumeUploadedAt" timestamptz`);
    await q(`ALTER TYPE "job_preferences_noticeperiod_enum" ADD VALUE IF NOT EXISTS 'DAYS_7'`);
    await q(`ALTER TYPE "job_preferences_noticeperiod_enum" ADD VALUE IF NOT EXISTS 'CUSTOM_DATE'`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    const q = (sql: string) => queryRunner.query(sql);
    await q(`ALTER TABLE talent_profiles DROP COLUMN IF EXISTS "resumeUploadedAt"`);
    await q(`ALTER TABLE talent_profiles DROP COLUMN IF EXISTS "resumeMimeType"`);
    await q(`ALTER TABLE talent_profiles DROP COLUMN IF EXISTS "resumeFileName"`);
    await q(`ALTER TABLE talent_profiles DROP COLUMN IF EXISTS "resumeUrl"`);
    await q(`ALTER TABLE talent_profiles DROP COLUMN IF EXISTS "availableOn"`);
    await q(`ALTER TABLE talent_profiles DROP COLUMN IF EXISTS "employmentTypes"`);
    await q(`ALTER TABLE talent_profiles DROP COLUMN IF EXISTS "expectedSalaryPeriod"`);
  }
}
