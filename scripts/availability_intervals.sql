-- Single owner for businesses."offlineDays" and the copy into interval tables.
-- Hall unavailability lives in hall_calendar_blocks.
-- Photography, catering, and other non-hall services live in event_vendor_calendar.
-- Fail the script on a real error. Do not swallow a second copy.

BEGIN;

ALTER TABLE businesses
  ALTER COLUMN "offlineDays" TYPE jsonb
  USING CASE
    WHEN "offlineDays" IS NULL THEN '[]'::jsonb
    WHEN btrim("offlineDays"::text) IN ('', 'null') THEN '[]'::jsonb
    ELSE "offlineDays"::text::jsonb
  END;

ALTER TABLE businesses
  ALTER COLUMN "offlineDays" SET DEFAULT '[]'::jsonb;

UPDATE businesses
SET "offlineDays" = '[]'::jsonb
WHERE "offlineDays" IS NULL;

CREATE TABLE IF NOT EXISTS event_vendor_calendar (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "businessId" uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  title varchar(160) NOT NULL,
  "startAt" timestamptz NOT NULL,
  "endAt" timestamptz NOT NULL,
  "cancelledAt" timestamptz NULL,
  "createdAt" timestamptz NOT NULL DEFAULT NOW(),
  CHECK ("endAt" > "startAt")
);

CREATE INDEX IF NOT EXISTS event_vendor_calendar_active_range
  ON event_vendor_calendar ("businessId", "startAt", "endAt")
  WHERE "cancelledAt" IS NULL;

-- Hall day list → one venue-wide block per valid IST day. Skip a day already stored.
INSERT INTO hall_calendar_blocks (
  id, "businessId", "hallId", "startAt", "endAt", reason, notes, "createdBy"
)
SELECT
  gen_random_uuid(),
  b.id,
  NULL,
  (left(elem, 10)::date AT TIME ZONE 'Asia/Kolkata'),
  ((left(elem, 10)::date + 1) AT TIME ZONE 'Asia/Kolkata'),
  'offline',
  'Migrated from business offlineDays',
  b."ownerId"
FROM businesses b
CROSS JOIN LATERAL jsonb_array_elements_text(b."offlineDays") AS elem
WHERE b.type = 'SERVICE'
  AND b."serviceType"::text = 'HALL'
  AND jsonb_typeof(b."offlineDays") = 'array'
  AND left(elem, 10) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  AND NOT EXISTS (
    SELECT 1 FROM hall_calendar_blocks blk
    WHERE blk."businessId" = b.id
      AND blk."hallId" IS NULL
      AND blk."releasedAt" IS NULL
      AND blk."startAt" = (left(elem, 10)::date AT TIME ZONE 'Asia/Kolkata')
      AND blk."endAt" = ((left(elem, 10)::date + 1) AT TIME ZONE 'Asia/Kolkata')
  );

-- Non-hall service day list → one Unavailable interval per valid IST day.
INSERT INTO event_vendor_calendar (id, "businessId", title, "startAt", "endAt")
SELECT
  gen_random_uuid(),
  b.id,
  'Unavailable',
  (left(elem, 10)::date AT TIME ZONE 'Asia/Kolkata'),
  ((left(elem, 10)::date + 1) AT TIME ZONE 'Asia/Kolkata')
FROM businesses b
CROSS JOIN LATERAL jsonb_array_elements_text(b."offlineDays") AS elem
WHERE b.type = 'SERVICE'
  AND b."serviceType"::text IS DISTINCT FROM 'HALL'
  AND jsonb_typeof(b."offlineDays") = 'array'
  AND left(elem, 10) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  AND NOT EXISTS (
    SELECT 1 FROM event_vendor_calendar e
    WHERE e."businessId" = b.id
      AND e."cancelledAt" IS NULL
      AND e.title = 'Unavailable'
      AND e."startAt" = (left(elem, 10)::date AT TIME ZONE 'Asia/Kolkata')
      AND e."endAt" = ((left(elem, 10)::date + 1) AT TIME ZONE 'Asia/Kolkata')
  );

-- The column remains so old rows have a type, but it is no longer a calendar.
UPDATE businesses
SET "offlineDays" = '[]'::jsonb
WHERE "offlineDays" IS DISTINCT FROM '[]'::jsonb;

COMMIT;
