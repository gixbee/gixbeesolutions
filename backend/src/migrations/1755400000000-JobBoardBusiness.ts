import { MigrationInterface, QueryRunner } from 'typeorm';
export class JobBoardBusiness1755400000000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "businessId" uuid NULL REFERENCES businesses(id)`);
    await q.query(`CREATE INDEX IF NOT EXISTS job_posts_business ON job_posts ("businessId")`);
    await q.query(`UPDATE job_posts j SET "businessId"=b.id FROM businesses b WHERE j."businessId" IS NULL
      AND b."ownerId"=j."employerId" AND b.type='HIRING'
      AND (SELECT count(*) FROM businesses own WHERE own."ownerId"=j."employerId" AND own.type='HIRING')=1`);
  }
  async down(): Promise<void> { /* Keep business attribution. */ }
}
