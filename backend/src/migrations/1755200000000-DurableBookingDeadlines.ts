import { MigrationInterface, QueryRunner } from 'typeorm';
export class DurableBookingDeadlines1755200000000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.query(`CREATE TABLE IF NOT EXISTS booking_deadlines (
      id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), "bookingId" uuid NOT NULL REFERENCES bookings(id),
      kind varchar(20) NOT NULL, sequence integer NOT NULL, "dueAt" timestamptz NOT NULL,
      "processedAt" timestamptz NULL, attempts integer NOT NULL DEFAULT 0, "lastError" text NULL,
      UNIQUE ("bookingId",kind,sequence))`);
    await q.query(`CREATE INDEX IF NOT EXISTS booking_deadlines_due ON booking_deadlines ("dueAt") WHERE "processedAt" IS NULL`);
  }
  async down(): Promise<void> { /* Keep durable pending work across application rollback. */ }
}
