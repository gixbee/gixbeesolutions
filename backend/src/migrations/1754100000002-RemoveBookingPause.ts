import { MigrationInterface, QueryRunner } from 'typeorm';

/** Remove columns left behind by the retired pause/resume workflow. */
export class RemoveBookingPause1754100000002 implements MigrationInterface {
  name = 'RemoveBookingPause1754100000002';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "bookings" DROP COLUMN IF EXISTS "pauseRequestedAt"`,
    );
    await queryRunner.query(
      `ALTER TABLE "bookings" DROP COLUMN IF EXISTS "pausedAt"`,
    );
    await queryRunner.query(
      `ALTER TABLE "bookings" DROP COLUMN IF EXISTS "pausedMinutes"`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "pauseRequestedAt" timestamp`,
    );
    await queryRunner.query(
      `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "pausedAt" timestamp`,
    );
    await queryRunner.query(
      `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "pausedMinutes" integer NOT NULL DEFAULT 0`,
    );
  }
}
