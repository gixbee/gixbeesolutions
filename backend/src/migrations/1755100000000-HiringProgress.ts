import { MigrationInterface, QueryRunner } from 'typeorm';

export class HiringProgress1755100000000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "businessId" uuid NULL REFERENCES businesses(id)`);
    await q.query(`ALTER TABLE hiring_interests
      ADD COLUMN IF NOT EXISTS progress jsonb NOT NULL DEFAULT '{}'::jsonb,
      ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 0`);
    await q.query(`CREATE INDEX IF NOT EXISTS hiring_requests_business ON hiring_requests ("businessId")`);
    // Only infer an old request's business when the owner has exactly one hiring unit.
    await q.query(`UPDATE hiring_requests h SET "businessId"=b.id FROM businesses b
      WHERE h."businessId" IS NULL AND b."ownerId"=h."employerId" AND b.type='HIRING'
      AND (SELECT count(*) FROM businesses own WHERE own."ownerId"=h."employerId" AND own.type='HIRING')=1`);
  }
  async down(): Promise<void> { /* Preserve candidate consent and joining history. */ }
}
