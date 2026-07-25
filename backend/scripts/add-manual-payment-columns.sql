-- Manual payment dual-confirm columns (post-completion OTP flow).
-- Safe to re-run: IF NOT EXISTS guards.

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "workerPaidConfirmed" boolean NOT NULL DEFAULT false;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "customerPaidConfirmed" boolean NOT NULL DEFAULT false;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "paymentCollectionMethod" varchar NULL;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "workerHonestyCheck" varchar NULL;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "customerSafetyCheck" varchar NULL;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "workedMinutes" integer NULL;
