-- Owner listing controls: deposit/delivery/advance already exist.
-- Adds availability window, pickup notes, late fee, condition, category, cancel policy.

ALTER TABLE rental_items
  ADD COLUMN IF NOT EXISTS "pickupInstructions" varchar(280) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "lateFeePerHour" numeric(10,2) NOT NULL DEFAULT 0 CHECK ("lateFeePerHour" >= 0),
  ADD COLUMN IF NOT EXISTS condition varchar(16) NOT NULL DEFAULT 'GOOD',
  ADD COLUMN IF NOT EXISTS category varchar(40) NOT NULL DEFAULT 'OTHER',
  ADD COLUMN IF NOT EXISTS "cancellationPolicy" varchar(24) NOT NULL DEFAULT 'FLEXIBLE',
  ADD COLUMN IF NOT EXISTS "advancePercent" numeric(5,2) NOT NULL DEFAULT 0 CHECK ("advancePercent" >= 0 AND "advancePercent" <= 100),
  ADD COLUMN IF NOT EXISTS "availableFrom" date NULL,
  ADD COLUMN IF NOT EXISTS "availableUntil" date NULL,
  ADD COLUMN IF NOT EXISTS "availableWeekdays" smallint[] NOT NULL DEFAULT '{1,2,3,4,5,6,7}',
  ADD COLUMN IF NOT EXISTS "slotStartMinute" integer NULL,
  ADD COLUMN IF NOT EXISTS "slotEndMinute" integer NULL;

ALTER TABLE rental_items DROP CONSTRAINT IF EXISTS rental_items_condition_check;
ALTER TABLE rental_items ADD CONSTRAINT rental_items_condition_check
  CHECK (condition IN ('NEW','GOOD','USED'));

ALTER TABLE rental_items DROP CONSTRAINT IF EXISTS rental_items_category_check;
ALTER TABLE rental_items ADD CONSTRAINT rental_items_category_check
  CHECK (category IN ('TOOLS','DRILL','CAMERA','FURNITURE','VEHICLE','ELECTRONICS','PARTY','SPORTS','OTHER'));

ALTER TABLE rental_items DROP CONSTRAINT IF EXISTS rental_items_cancel_policy_check;
ALTER TABLE rental_items ADD CONSTRAINT rental_items_cancel_policy_check
  CHECK ("cancellationPolicy" IN ('FLEXIBLE','MODERATE','STRICT','NON_REFUNDABLE'));

ALTER TABLE rental_items DROP CONSTRAINT IF EXISTS rental_items_slot_window_check;
ALTER TABLE rental_items ADD CONSTRAINT rental_items_slot_window_check
  CHECK (
    ("slotStartMinute" IS NULL AND "slotEndMinute" IS NULL)
    OR (
      "slotStartMinute" IS NOT NULL AND "slotEndMinute" IS NOT NULL
      AND "slotStartMinute" >= 0 AND "slotStartMinute" < 1440
      AND "slotEndMinute" > "slotStartMinute" AND "slotEndMinute" <= 1440
    )
  );

ALTER TABLE rental_items DROP CONSTRAINT IF EXISTS rental_items_available_range_check;
ALTER TABLE rental_items ADD CONSTRAINT rental_items_available_range_check
  CHECK ("availableFrom" IS NULL OR "availableUntil" IS NULL OR "availableFrom" <= "availableUntil");

CREATE INDEX IF NOT EXISTS rental_items_category ON rental_items (category) WHERE "isAvailable" = true;
