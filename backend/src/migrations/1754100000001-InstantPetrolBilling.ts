import { MigrationInterface, QueryRunner } from 'typeorm';

/** Frozen one-way petrol charge for completed Instant Help bookings. */
export class InstantPetrolBilling1754100000001
  implements MigrationInterface
{
  name = 'InstantPetrolBilling1754100000001';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "petrolDistanceKm" numeric(8,2)`,
    );
    await queryRunner.query(
      `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "petrolRatePerKm" numeric(8,2)`,
    );
    await queryRunner.query(
      `ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "petrolAmount" integer`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "bookings" DROP COLUMN IF EXISTS "petrolAmount"`,
    );
    await queryRunner.query(
      `ALTER TABLE "bookings" DROP COLUMN IF EXISTS "petrolRatePerKm"`,
    );
    await queryRunner.query(
      `ALTER TABLE "bookings" DROP COLUMN IF EXISTS "petrolDistanceKm"`,
    );
  }
}
