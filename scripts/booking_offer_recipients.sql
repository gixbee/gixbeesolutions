CREATE TABLE IF NOT EXISTS booking_offer_recipients (
    booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    worker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    dismissed_at timestamptz,
    PRIMARY KEY (booking_id, worker_id)
);

CREATE INDEX IF NOT EXISTS booking_offer_recipients_pending
    ON booking_offer_recipients (worker_id, expires_at, booking_id)
    WHERE dismissed_at IS NULL;
