/**
 * TypeORM migration: transactional outbox for booking lifecycle side effects.
 * Runs automatically in production (migrationsRun: true).
 */
import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateOutboxEvents1753360000000 implements MigrationInterface {
  name = 'CreateOutboxEvents1753360000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS pgcrypto`);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS outbox_events (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        type varchar(80) NOT NULL,
        "aggregateId" uuid NOT NULL,
        payload jsonb NOT NULL,
        status varchar(20) NOT NULL DEFAULT 'pending',
        attempts integer NOT NULL DEFAULT 0,
        "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
        "processedAt" TIMESTAMPTZ NULL,
        "lastError" text NULL
      )
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_outbox_events_status_createdAt"
        ON outbox_events (status, "createdAt")
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_outbox_events_aggregateId_type"
        ON outbox_events ("aggregateId", type)
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX IF EXISTS "IDX_outbox_events_aggregateId_type"`,
    );
    await queryRunner.query(
      `DROP INDEX IF EXISTS "IDX_outbox_events_status_createdAt"`,
    );
    await queryRunner.query(`DROP TABLE IF EXISTS outbox_events`);
  }
}
