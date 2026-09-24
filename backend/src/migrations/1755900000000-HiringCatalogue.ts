import { MigrationInterface, QueryRunner } from 'typeorm';

/// Shared hiring catalogue and a location master separate from serviceable cities.
export class HiringCatalogue1755900000000 implements MigrationInterface {
  name = 'HiringCatalogue1755900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS pg_trgm`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_sectors (
        id varchar PRIMARY KEY,
        label varchar NOT NULL,
        subtitle text NOT NULL DEFAULT '',
        icon varchar NOT NULL DEFAULT '',
        color varchar NOT NULL DEFAULT '',
        "sortOrder" int NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true,
        "updatedAt" timestamptz NOT NULL DEFAULT NOW()
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_positions (
        id varchar PRIMARY KEY,
        label varchar NOT NULL,
        subtitle text NOT NULL DEFAULT '',
        "fieldPattern" varchar NOT NULL DEFAULT 'typeChips',
        "typeLabel" varchar NOT NULL DEFAULT 'Type',
        shared boolean NOT NULL DEFAULT false,
        "isActive" boolean NOT NULL DEFAULT true,
        "updatedAt" timestamptz NOT NULL DEFAULT NOW()
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_sector_positions (
        "sectorId" varchar NOT NULL,
        "positionId" varchar NOT NULL,
        PRIMARY KEY ("sectorId", "positionId")
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_specializations (
        id varchar PRIMARY KEY,
        "positionId" varchar NOT NULL,
        label varchar NOT NULL,
        "sortOrder" int NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_skills (
        id varchar PRIMARY KEY,
        label varchar NOT NULL,
        "isActive" boolean NOT NULL DEFAULT true
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_position_skills (
        "positionId" varchar NOT NULL,
        "skillId" varchar NOT NULL,
        tier varchar NOT NULL DEFAULT 'suggested',
        "sortOrder" int NOT NULL DEFAULT 0,
        PRIMARY KEY ("positionId", "skillId")
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_qualifications (
        id varchar PRIMARY KEY,
        label varchar NOT NULL,
        rank int,
        professional boolean NOT NULL DEFAULT false,
        "sortOrder" int NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_employment_types (
        code varchar PRIMARY KEY,
        label varchar NOT NULL,
        "sortOrder" int NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_salary_periods (
        code varchar PRIMARY KEY,
        label varchar NOT NULL,
        "sortOrder" int NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_aliases (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        "entityType" varchar NOT NULL,
        "entityId" varchar NOT NULL,
        alias varchar NOT NULL,
        "isActive" boolean NOT NULL DEFAULT true,
        UNIQUE ("entityType", "entityId", alias)
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_locations (
        id varchar PRIMARY KEY,
        kind varchar NOT NULL,
        name varchar NOT NULL,
        "parentId" varchar,
        "stateId" varchar,
        "districtId" varchar,
        "stateName" varchar NOT NULL DEFAULT '',
        "districtName" varchar NOT NULL DEFAULT '',
        lat double precision,
        lng double precision,
        source varchar NOT NULL DEFAULT '',
        "sourceKey" varchar NOT NULL DEFAULT '',
        "isActive" boolean NOT NULL DEFAULT true,
        "updatedAt" timestamptz NOT NULL DEFAULT NOW()
      )`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS hiring_location_aliases (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        "locationId" varchar NOT NULL,
        alias varchar NOT NULL,
        UNIQUE ("locationId", alias)
      )`);
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS hiring_locations_name_trgm ON hiring_locations USING gin (name gin_trgm_ops)`,
    );
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS hiring_location_aliases_trgm ON hiring_location_aliases USING gin (alias gin_trgm_ops)`,
    );
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS hiring_locations_kind_state ON hiring_locations (kind, "stateId")`,
    );

    const extras: Array<[string, string]> = [
      ['hiring_requests', `"sectorId" varchar`],
      ['hiring_requests', `"positionId" varchar`],
      ['hiring_requests', `"specializationIds" text NOT NULL DEFAULT ''`],
      ['hiring_requests', `"skillIds" text NOT NULL DEFAULT ''`],
      ['hiring_requests', `"qualificationId" varchar`],
      ['hiring_requests', `"qualificationRequired" boolean NOT NULL DEFAULT false`],
      ['hiring_requests', `"salaryPeriod" varchar NOT NULL DEFAULT 'MONTHLY'`],
      ['hiring_requests', `"locationId" varchar`],
      ['hiring_requests', `"addressText" text`],
      ['hiring_requests', `"locationMatchStatus" varchar NOT NULL DEFAULT 'UNRESOLVED'`],
      ['hiring_requests', `"workMode" varchar NOT NULL DEFAULT 'ONSITE'`],
      ['job_preferences', `"sectorId" varchar`],
      ['job_preferences', `"positionId" varchar`],
      ['job_preferences', `"specializationIds" text NOT NULL DEFAULT ''`],
      ['job_preferences', `"skillIds" text NOT NULL DEFAULT ''`],
      ['job_preferences', `"qualificationId" varchar`],
      ['job_preferences', `"locationId" varchar`],
      ['job_preferences', `"addressText" text`],
      ['job_preferences', `"locationMatchStatus" varchar NOT NULL DEFAULT 'UNRESOLVED'`],
      ['talent_profiles', `"positionIds" text NOT NULL DEFAULT ''`],
      ['talent_profiles', `"specializationIds" text NOT NULL DEFAULT ''`],
      ['talent_profiles', `"skillIds" text NOT NULL DEFAULT ''`],
      ['talent_profiles', `"qualificationId" varchar`],
      ['talent_profiles', `"locationId" varchar`],
      ['talent_profiles', `"addressText" text`],
      ['talent_profiles', `"locationMatchStatus" varchar NOT NULL DEFAULT 'UNRESOLVED'`],
      ['job_posts', `"sectorId" varchar`],
      ['job_posts', `"positionId" varchar`],
      ['job_posts', `"specializationIds" text NOT NULL DEFAULT ''`],
      ['job_posts', `"skillIds" text NOT NULL DEFAULT ''`],
      ['job_posts', `"qualificationId" varchar`],
      ['job_posts', `"qualificationRequired" boolean NOT NULL DEFAULT false`],
      ['job_posts', `"locationId" varchar`],
      ['job_posts', `"addressText" text`],
      ['job_posts', `"locationMatchStatus" varchar NOT NULL DEFAULT 'UNRESOLVED'`],
    ];
    for (const [table, column] of extras) {
      const name = column.split(' ')[0].replace(/"/g, '');
      await queryRunner.query(
        `ALTER TABLE ${table} ADD COLUMN IF NOT EXISTS ${column.startsWith('"') ? column : `"${name}" ${column}`}`,
      );
    }
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    const drops = [
      'hiring_requests."sectorId"',
      'hiring_requests."positionId"',
      'hiring_requests."specializationIds"',
      'hiring_requests."skillIds"',
      'hiring_requests."qualificationId"',
      'hiring_requests."qualificationRequired"',
      'hiring_requests."salaryPeriod"',
      'hiring_requests."locationId"',
      'hiring_requests."addressText"',
      'hiring_requests."locationMatchStatus"',
      'job_preferences."sectorId"',
      'job_preferences."positionId"',
      'job_preferences."specializationIds"',
      'job_preferences."skillIds"',
      'job_preferences."qualificationId"',
      'job_preferences."locationId"',
      'job_preferences."addressText"',
      'job_preferences."locationMatchStatus"',
      'talent_profiles."positionIds"',
      'talent_profiles."specializationIds"',
      'talent_profiles."skillIds"',
      'talent_profiles."qualificationId"',
      'talent_profiles."locationId"',
      'talent_profiles."addressText"',
      'talent_profiles."locationMatchStatus"',
      'job_posts."sectorId"',
      'job_posts."positionId"',
      'job_posts."specializationIds"',
      'job_posts."skillIds"',
      'job_posts."qualificationId"',
      'job_posts."qualificationRequired"',
      'job_posts."locationId"',
      'job_posts."addressText"',
      'job_posts."locationMatchStatus"',
    ];
    for (const column of drops) {
      const [table, name] = column.split('.');
      await queryRunner.query(`ALTER TABLE ${table} DROP COLUMN IF EXISTS ${name}`);
    }
    for (const table of [
      'hiring_location_aliases',
      'hiring_locations',
      'hiring_aliases',
      'hiring_salary_periods',
      'hiring_employment_types',
      'hiring_qualifications',
      'hiring_position_skills',
      'hiring_skills',
      'hiring_specializations',
      'hiring_sector_positions',
      'hiring_positions',
      'hiring_sectors',
    ]) {
      await queryRunner.query(`DROP TABLE IF EXISTS ${table}`);
    }
  }
}
