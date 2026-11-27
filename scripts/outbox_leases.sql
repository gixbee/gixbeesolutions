ALTER TABLE outbox_events
    ADD COLUMN IF NOT EXISTS "availableAt" TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS outbox_events_claimable
    ON outbox_events ("availableAt", "createdAt")
    WHERE status IN ('pending', 'processing');

ALTER TABLE booking_deadlines
    ADD COLUMN IF NOT EXISTS "leaseUntil" TIMESTAMPTZ;

ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS "reconcileAfter" TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS payment_orders_reconcile_recent
    ON payment_orders ("createdAt")
    WHERE status = 'CREATED';
