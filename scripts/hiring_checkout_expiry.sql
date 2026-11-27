ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS "creditReleasedAt" timestamptz;

CREATE INDEX IF NOT EXISTS hiring_checkout_expiry
    ON payment_orders ("createdAt")
    WHERE status='CREATED' AND purpose='HIRING_MATCH_FEE' AND "creditReleasedAt" IS NULL;
