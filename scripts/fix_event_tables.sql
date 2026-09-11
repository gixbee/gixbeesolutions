-- event_plans / event_quotes were created by an unquoted heredoc, so every
-- identifier folded to lowercase and the Rust queries ("customerId", "startTime", ...)
-- 500. Both tables are empty, so drop and recreate with correct quoted identifiers
-- to match migration 1754900000000-EventPlanning.

DROP TABLE IF EXISTS event_quotes;
DROP TABLE IF EXISTS event_plans;

CREATE TABLE event_plans (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "customerId" uuid NOT NULL REFERENCES users(id),
  "eventType" varchar(100) NOT NULL,
  "startTime" timestamptz NOT NULL,
  "endTime" timestamptz NOT NULL,
  "guestCount" integer NOT NULL CHECK ("guestCount" BETWEEN 1 AND 100000),
  location text NOT NULL,
  "cityId" uuid NULL REFERENCES cities(id),
  services jsonb NOT NULL CHECK (jsonb_typeof(services) = 'array'),
  notes text NOT NULL DEFAULT '',
  "cancelledAt" timestamptz NULL,
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  "updatedAt" timestamptz NOT NULL DEFAULT NOW(),
  CHECK ("endTime" > "startTime")
);

CREATE TABLE event_quotes (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  "planId" uuid NOT NULL REFERENCES event_plans(id),
  "businessId" uuid NOT NULL REFERENCES businesses(id),
  "serviceType" varchar(40) NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  inclusions text NOT NULL,
  "cancellationTerms" text NOT NULL,
  status varchar(30) NOT NULL DEFAULT 'OFFERED'
    CHECK (status IN ('OFFERED','DECLINED','EXPIRED','CONFIRMED','COMPLETED','CANCEL_REQUESTED','CANCELLED')),
  "expiresAt" timestamptz NOT NULL,
  "acceptedAt" timestamptz NULL,
  "customerPaidAt" timestamptz NULL,
  "vendorReceivedAt" timestamptz NULL,
  "customerCompletedAt" timestamptz NULL,
  "vendorCompletedAt" timestamptz NULL,
  "cancellationRequestedBy" uuid NULL REFERENCES users(id),
  "cancellationReason" text NULL,
  "cancellationRefund" numeric(12,2) NOT NULL DEFAULT 0 CHECK ("cancellationRefund" >= 0),
  "customerRefundReceivedAt" timestamptz NULL,
  "vendorRefundSentAt" timestamptz NULL,
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  "updatedAt" timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE ("planId","businessId","serviceType"),
  CHECK ("cancellationRefund" <= amount)
);

CREATE UNIQUE INDEX IF NOT EXISTS event_quotes_selected_service
  ON event_quotes ("planId","serviceType")
  WHERE status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED');
CREATE INDEX IF NOT EXISTS event_plans_customer ON event_plans ("customerId","createdAt");
CREATE INDEX IF NOT EXISTS event_quotes_business ON event_quotes ("businessId",status);
