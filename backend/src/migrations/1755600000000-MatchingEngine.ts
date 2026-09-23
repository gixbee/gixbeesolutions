import { MigrationInterface, QueryRunner } from 'typeorm';

/// Board matching columns, canonical skills, and recommendation events.
/// PostGIS / pgvector blocks are best-effort and never fail the migration.
export class MatchingEngine1755600000000 implements MigrationInterface {
  name = 'MatchingEngine1755600000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    const q = (sql: string) => queryRunner.query(sql);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "workMode" varchar NOT NULL DEFAULT 'ONSITE'`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "salaryPeriod" varchar NOT NULL DEFAULT 'MONTHLY'`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "experienceMin" double precision`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "experienceMax" double precision`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS lat double precision`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS lng double precision`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS openings integer NOT NULL DEFAULT 1`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "joiningType" varchar`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "joiningDate" timestamptz`);
    await q(`ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS status varchar NOT NULL DEFAULT 'PUBLISHED'`);
    await q(`UPDATE job_posts SET status = CASE WHEN "isActive" THEN 'PUBLISHED' ELSE 'CLOSED' END WHERE status IS NULL OR status = ''`);
    await q(`CREATE INDEX IF NOT EXISTS "IDX_job_posts_status_createdAt" ON job_posts (status, "createdAt" DESC)`);
    await q(`CREATE INDEX IF NOT EXISTS "IDX_job_posts_lat_lng" ON job_posts (lat, lng) WHERE lat IS NOT NULL AND lng IS NOT NULL`);

    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS lat double precision`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS lng double precision`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "travelRadiusKm" double precision NOT NULL DEFAULT 25`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS availability varchar NOT NULL DEFAULT 'IMMEDIATE'`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "lastActiveAt" timestamptz`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "profileStatus" varchar NOT NULL DEFAULT 'ACTIVE'`);
    await q(`ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "preferredWorkMode" varchar`);
    await q(`CREATE INDEX IF NOT EXISTS "IDX_talent_profiles_status" ON talent_profiles ("profileStatus")`);

    await q(`CREATE TABLE IF NOT EXISTS skills (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      name varchar NOT NULL,
      "normalizedName" varchar NOT NULL UNIQUE,
      "categoryId" uuid,
      "createdAt" timestamptz NOT NULL DEFAULT now()
    )`);
    await q(`CREATE TABLE IF NOT EXISTS skill_aliases (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      "skillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
      alias varchar NOT NULL,
      "normalizedAlias" varchar NOT NULL UNIQUE
    )`);
    await q(`CREATE TABLE IF NOT EXISTS skill_related (
      "skillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
      "relatedSkillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
      weight real NOT NULL DEFAULT 0.5,
      PRIMARY KEY ("skillId", "relatedSkillId")
    )`);
    await q(`CREATE TABLE IF NOT EXISTS job_post_skills (
      "jobPostId" uuid NOT NULL REFERENCES job_posts(id) ON DELETE CASCADE,
      "skillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
      "isRequired" boolean NOT NULL DEFAULT true,
      importance real NOT NULL DEFAULT 1,
      PRIMARY KEY ("jobPostId", "skillId")
    )`);
    await q(`CREATE TABLE IF NOT EXISTS candidate_skills (
      "talentProfileId" uuid NOT NULL REFERENCES talent_profiles(id) ON DELETE CASCADE,
      "skillId" uuid NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
      "experienceLevel" varchar,
      PRIMARY KEY ("talentProfileId", "skillId")
    )`);
    await q(`CREATE TABLE IF NOT EXISTS matching_config (
      id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
      skill_weight real NOT NULL DEFAULT 30,
      category_weight real NOT NULL DEFAULT 25,
      distance_weight real NOT NULL DEFAULT 15,
      employment_type_weight real NOT NULL DEFAULT 10,
      salary_weight real NOT NULL DEFAULT 10,
      experience_weight real NOT NULL DEFAULT 5,
      availability_weight real NOT NULL DEFAULT 5,
      semantic_weight real NOT NULL DEFAULT 0,
      "updatedAt" timestamptz NOT NULL DEFAULT now()
    )`);
    await q(`INSERT INTO matching_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING`);
    await q(`CREATE TABLE IF NOT EXISTS matching_events (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      "userId" uuid,
      "jobPostId" uuid,
      "candidateId" uuid,
      "businessId" uuid,
      "eventType" varchar NOT NULL,
      "matchScoreAtTime" real,
      payload jsonb NOT NULL DEFAULT '{}'::jsonb,
      "createdAt" timestamptz NOT NULL DEFAULT now()
    )`);
    await q(`CREATE INDEX IF NOT EXISTS "IDX_matching_events_job" ON matching_events ("jobPostId", "createdAt" DESC)`);
    await q(`CREATE TABLE IF NOT EXISTS matching_feedback (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      "userId" uuid NOT NULL,
      "jobPostId" uuid NOT NULL,
      "candidateId" uuid,
      side varchar NOT NULL,
      reason varchar NOT NULL,
      note text,
      "createdAt" timestamptz NOT NULL DEFAULT now()
    )`);
    await q(`
      INSERT INTO skills (name, "normalizedName")
      SELECT v.name, v.norm FROM (VALUES
        ('Flutter','flutter'),
        ('Electrical Installation','electrical installation'),
        ('Wiring','wiring'),
        ('MCB Installation','mcb installation'),
        ('Fault Finding','fault finding'),
        ('Inverter','inverter')
      ) AS v(name, norm)
      WHERE NOT EXISTS (SELECT 1 FROM skills s WHERE s."normalizedName" = v.norm)
    `);
  }

  public async down(): Promise<void> {}
}
