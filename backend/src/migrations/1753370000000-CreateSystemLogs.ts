/**
 * TypeORM migration: persistent API/system logs for the admin portal.
 * Runs automatically in production (migrationsRun: true).
 * In development, synchronize also creates this table.
 */
import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateSystemLogs1753370000000 implements MigrationInterface {
  name = 'CreateSystemLogs1753370000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS pgcrypto`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS system_logs (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        level varchar(10) NOT NULL DEFAULT 'INFO',
        type varchar(10) NOT NULL DEFAULT 'API',
        method varchar(10) NULL,
        path varchar(500) NULL,
        "statusCode" integer NULL,
        "durationMs" integer NULL,
        "userId" varchar(64) NULL,
        ip varchar(64) NULL,
        message varchar(500) NULL,
        detail text NULL,
        "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `);
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS "IDX_system_logs_level" ON system_logs (level)`,
    );
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS "IDX_system_logs_type" ON system_logs (type)`,
    );
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS "IDX_system_logs_path" ON system_logs (path)`,
    );
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS "IDX_system_logs_statusCode" ON system_logs ("statusCode")`,
    );
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS "IDX_system_logs_createdAt" ON system_logs ("createdAt")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_system_logs_createdAt"`);
    await queryRunner.query(
      `DROP INDEX IF EXISTS "IDX_system_logs_statusCode"`,
    );
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_system_logs_path"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_system_logs_type"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_system_logs_level"`);
    await queryRunner.query(`DROP TABLE IF EXISTS system_logs`);
  }
}
