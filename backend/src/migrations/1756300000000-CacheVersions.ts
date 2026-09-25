import { MigrationInterface, QueryRunner } from 'typeorm';

export class CacheVersions1756300000000 implements MigrationInterface {
  name = 'CacheVersions1756300000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS cache_versions (
        domain TEXT PRIMARY KEY,
        version BIGINT NOT NULL DEFAULT 1,
        "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await queryRunner.query(`
      INSERT INTO cache_versions (domain, version) VALUES
        ('hiring_master', 1),
        ('location_master', 1),
        ('service_master', 1),
        ('public_listings', 1)
      ON CONFLICT (domain) DO NOTHING;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS cache_versions;`);
  }
}
