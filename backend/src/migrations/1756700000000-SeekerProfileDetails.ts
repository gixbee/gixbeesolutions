import { MigrationInterface, QueryRunner } from 'typeorm';

export class SeekerProfileDetails1756700000000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.query('ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "seekerDetails" jsonb');
    await q.query(`CREATE TABLE IF NOT EXISTS seeker_resume_uploads (
      id uuid PRIMARY KEY,
      "userId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      filename varchar(255) NOT NULL,
      content bytea NOT NULL,
      "createdAt" timestamptz NOT NULL DEFAULT NOW()
    )`);
  }

  async down(q: QueryRunner): Promise<void> {
    await q.query('DROP TABLE IF EXISTS seeker_resume_uploads');
    await q.query('ALTER TABLE job_preferences DROP COLUMN IF EXISTS "seekerDetails"');
  }
}
