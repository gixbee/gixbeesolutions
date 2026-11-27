-- Architecture fixes: checkout intents, refund-required payment states,
-- and rental late-capture bookkeeping. Safe to re-run.

-- Allow creating a payment intent before the Razorpay order id is known.
-- Existing UNIQUE on razorpayOrderId still applies to non-null values;
-- PostgreSQL allows multiple NULLs under that constraint.
ALTER TABLE payment_orders
    ALTER COLUMN "razorpayOrderId" DROP NOT NULL;

ALTER TYPE payment_orders_status_enum ADD VALUE IF NOT EXISTS 'REFUND_REQUIRED';
ALTER TYPE payment_orders_status_enum ADD VALUE IF NOT EXISTS 'REFUND_PENDING';
ALTER TYPE payment_orders_status_enum ADD VALUE IF NOT EXISTS 'REFUNDED';

ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS "refundFailure" text,
    ADD COLUMN IF NOT EXISTS "refundedAt" timestamptz;

-- Compare enum values directly (casting status::text is not IMMUTABLE for indexes).
CREATE INDEX IF NOT EXISTS payment_orders_refund_required
    ON payment_orders ("createdAt")
    WHERE status IN ('REFUND_REQUIRED', 'REFUND_PENDING');

-- Durable marker for rentals that cannot receive a late advance capture.
ALTER TABLE rental_reservations
    ADD COLUMN IF NOT EXISTS "lateCapturePaymentId" text;
