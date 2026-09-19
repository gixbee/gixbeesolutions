-- Recalc Instant Help billing from wall-clock startedAt → completedAt.
-- Azure "startedAt" is timestamp without time zone; rust previously failed to
-- decode it as timestamptz and billed 1 minute / 1 hour.
UPDATE bookings
SET
  "workedMinutes" = GREATEST(
    1,
    ROUND(EXTRACT(EPOCH FROM ("completedAt" - "startedAt")) / 60.0)::int
  ),
  "billingHours" = GREATEST(
    1,
    CEIL(EXTRACT(EPOCH FROM ("completedAt" - "startedAt")) / 3600.0)::int
  ),
  "totalAmount" = ROUND(
    amount
      * GREATEST(
          60,
          ROUND(EXTRACT(EPOCH FROM ("completedAt" - "startedAt")) / 60.0)
        )
      / 60.0
  ) + COALESCE("petrolAmount", 0)
WHERE id = 'e3765b2a-04c7-4629-bae4-eca85423ebb3'
  AND COALESCE("isPaid", false) = false
  AND "startedAt" IS NOT NULL
  AND "completedAt" IS NOT NULL;

SELECT id, status, "isPaid", amount, "workedMinutes", "billingHours",
       "petrolAmount", "totalAmount", "startedAt", "completedAt"
FROM bookings
WHERE id = 'e3765b2a-04c7-4629-bae4-eca85423ebb3';
