import { MigrationInterface, QueryRunner } from 'typeorm';

export class HiringBusinessProfile1755500000000 implements MigrationInterface {
  name = 'HiringBusinessProfile1755500000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE businesses ADD COLUMN IF NOT EXISTS "hiringProfile" jsonb NOT NULL DEFAULT '{}'::jsonb`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE businesses DROP COLUMN IF EXISTS "hiringProfile"`,
    );
  }
}
