-- v147 shop businesses, owner offers, and enquiries.
ALTER TYPE businesses_type_enum ADD VALUE IF NOT EXISTS 'SHOP';

CREATE TABLE IF NOT EXISTS shop_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  kind varchar NOT NULL CHECK (kind IN ('FLASH', 'NORMAL', 'PACKAGE')),
  title varchar NOT NULL,
  code varchar NOT NULL,
  discount varchar,
  category varchar NOT NULL,
  "endsAt" timestamptz,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS shop_enquiries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "businessId" uuid REFERENCES businesses(id) ON DELETE SET NULL,
  "customerId" uuid,
  "placeName" varchar NOT NULL,
  category varchar NOT NULL,
  package varchar,
  message varchar NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
