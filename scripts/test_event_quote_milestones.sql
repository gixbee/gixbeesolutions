-- Isolated constraint checks for scripts/azure_event_quote_milestones.sql
-- Prerequisites (disposable DB only): marketplace_migrate_events_rentals.sql,
-- azure_hall_migrations.sql, then azure_event_quote_milestones.sql (twice to
-- prove idempotency). This file does not write durable rows.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.event_quote_milestones') IS NULL
     OR to_regclass('public.event_quote_milestone_events') IS NULL THEN
    RAISE EXCEPTION 'Apply azure_event_quote_milestones.sql first';
  END IF;
END $$;

-- Unknown quoteId must fail FK
DO $$
BEGIN
  BEGIN
    INSERT INTO event_quote_milestones (id, "quoteId", kind, "position", label, amount)
    VALUES (uuid_generate_v4(), uuid_generate_v4(), 'PAYMENT', 1, 'Advance', 100);
    RAISE EXCEPTION 'expected quote FK to reject unknown quoteId';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;
END $$;

ROLLBACK;
SELECT 'event_quote_milestones_selftest_ok' AS status;
