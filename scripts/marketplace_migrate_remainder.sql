ALTER TABLE hiring_requests ADD COLUMN IF NOT EXISTS "businessId" uuid NULL REFERENCES businesses(id);
ALTER TABLE hiring_interests
  ADD COLUMN IF NOT EXISTS progress jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS hiring_requests_business ON hiring_requests ("businessId");

UPDATE hiring_requests h SET "businessId"=b.id FROM businesses b
  WHERE h."businessId" IS NULL AND b."ownerId"=h."employerId" AND b.type='HIRING'
  AND (SELECT count(*) FROM businesses own WHERE own."ownerId"=h."employerId" AND own.type='HIRING')=1;

CREATE TABLE IF NOT EXISTS booking_deadlines (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), "bookingId" uuid NOT NULL REFERENCES bookings(id),
  kind varchar(20) NOT NULL, sequence integer NOT NULL, "dueAt" timestamptz NOT NULL,
  "processedAt" timestamptz NULL, attempts integer NOT NULL DEFAULT 0, "lastError" text NULL,
  UNIQUE ("bookingId",kind,sequence));
CREATE INDEX IF NOT EXISTS booking_deadlines_due ON booking_deadlines ("dueAt") WHERE "processedAt" IS NULL;

DO $$ BEGIN
  ALTER TABLE payment_orders ALTER COLUMN "userId" TYPE uuid USING "userId"::uuid;
EXCEPTION WHEN others THEN NULL;
END $$;
CREATE TABLE IF NOT EXISTS career_profile_receipts (
  "paymentOrderId" uuid PRIMARY KEY REFERENCES payment_orders(id),
  "preferenceId" uuid NOT NULL REFERENCES job_preferences(id),
  "createdAt" timestamptz NOT NULL DEFAULT NOW());

ALTER TABLE job_posts ADD COLUMN IF NOT EXISTS "businessId" uuid NULL REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS job_posts_business ON job_posts ("businessId");
UPDATE job_posts j SET "businessId"=b.id FROM businesses b WHERE j."businessId" IS NULL
  AND b."ownerId"=j."employerId" AND b.type='HIRING'
  AND (SELECT count(*) FROM businesses own WHERE own."ownerId"=j."employerId" AND own.type='HIRING')=1;
