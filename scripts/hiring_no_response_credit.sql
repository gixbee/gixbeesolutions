ALTER TABLE hiring_requests
    ADD COLUMN IF NOT EXISTS "noResponseCredit" numeric(10,2) NOT NULL DEFAULT 0
    CHECK ("noResponseCredit" >= 0 AND "noResponseCredit" <= "feeAmount");
