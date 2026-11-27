-- Existing overlapping Instant Help assignments must be resolved before this index can be created.
CREATE UNIQUE INDEX IF NOT EXISTS bookings_one_live_instant_per_worker
    ON bookings ("operatorId")
    WHERE "operatorId" IS NOT NULL AND type = 'INSTANT'
      AND status IN ('ACCEPTED','ARRIVED','ACTIVE');

ALTER TABLE booking_offer_recipients ADD COLUMN IF NOT EXISTS push_status text;
ALTER TABLE booking_offer_recipients ADD COLUMN IF NOT EXISTS push_attempted_at timestamptz;
ALTER TABLE booking_offer_recipients ADD COLUMN IF NOT EXISTS push_retry_at timestamptz;
