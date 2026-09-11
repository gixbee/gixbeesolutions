-- Event planning (1754900000000) + rental fulfillment (1755000000000)

CREATE TABLE IF NOT EXISTS event_plans (
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

CREATE TABLE IF NOT EXISTS event_quotes (
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

ALTER TABLE businesses ADD COLUMN IF NOT EXISTS phone varchar(30) NULL;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS "eventServices" jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE rental_items
  ADD COLUMN IF NOT EXISTS "businessId" uuid NULL REFERENCES businesses(id),
  ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 100000),
  ADD COLUMN IF NOT EXISTS "pickupAddress" text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "deliveryAvailable" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "deliveryFee" numeric(10,2) NOT NULL DEFAULT 0 CHECK ("deliveryFee" >= 0),
  ADD COLUMN IF NOT EXISTS "depositPerUnit" numeric(10,2) NOT NULL DEFAULT 0 CHECK ("depositPerUnit" >= 0);

ALTER TABLE rental_reservations
  ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 100000),
  ADD COLUMN IF NOT EXISTS fulfillment varchar(20) NOT NULL DEFAULT 'PICKUP' CHECK (fulfillment IN ('PICKUP','DELIVERY')),
  ADD COLUMN IF NOT EXISTS "fulfillmentAddress" text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "priceBreakdown" jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS "ownerHandedOverAt" timestamptz NULL,
  ADD COLUMN IF NOT EXISTS "renterCollectedAt" timestamptz NULL,
  ADD COLUMN IF NOT EXISTS "ownerReturnedAt" timestamptz NULL,
  ADD COLUMN IF NOT EXISTS "renterReturnedAt" timestamptz NULL,
  ADD COLUMN IF NOT EXISTS "ownerPaidAt" timestamptz NULL,
  ADD COLUMN IF NOT EXISTS "renterPaidAt" timestamptz NULL,
  ADD COLUMN IF NOT EXISTS "ownerRefundedAt" timestamptz NULL,
  ADD COLUMN IF NOT EXISTS "renterRefundedAt" timestamptz NULL;

CREATE INDEX IF NOT EXISTS rental_items_business ON rental_items ("businessId");
