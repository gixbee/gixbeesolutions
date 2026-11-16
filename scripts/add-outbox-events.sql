-- Transactional outbox table for booking lifecycle side effects.
-- Safe to re-run: IF NOT EXISTS guards.
-- Apply on EC2 when migrationsRun did not create the table yet:
--   psql "$DATABASE_URL" -f backend/scripts/add-outbox-events.sql

  CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type varchar(80) NOT NULL,
  "aggregateId" uuid NOT NULL,
  payload jsonb NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "processedAt" TIMESTAMPTZ NULL,
  "lastError" text NULL
);

CREATE INDEX IF NOT EXISTS "IDX_outbox_events_status_createdAt"
  ON outbox_events (status, "createdAt");

CREATE INDEX IF NOT EXISTS "IDX_outbox_events_aggregateId_type"
  ON outbox_events ("aggregateId", type);
