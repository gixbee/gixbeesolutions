-- Event quote milestones for Photography deliverables / direct payments
-- and Hall advance acknowledgement. Apply after:
--   scripts/marketplace_migrate_events_rentals.sql
--   scripts/azure_hall_migrations.sql
-- This is an additive, idempotent migration. It does not collect money.
BEGIN;

CREATE TABLE IF NOT EXISTS event_quote_milestones (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    "quoteId" uuid NOT NULL REFERENCES event_quotes(id) ON DELETE CASCADE,
    kind varchar(12) NOT NULL CHECK (kind IN ('PAYMENT','DELIVERY')),
    position smallint NOT NULL CHECK (position BETWEEN 1 AND 20),
    label varchar(150) NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 150),
    details text NOT NULL DEFAULT '' CHECK (length(details) <= 3000),
    "percent" smallint NULL CHECK ("percent" BETWEEN 1 AND 100),
    amount numeric(12,2) NULL CHECK (amount > 0),
    "dueAt" timestamptz NULL,
    "customerAcknowledgedAt" timestamptz NULL,
    "vendorAcknowledgedAt" timestamptz NULL,
    "completedAt" timestamptz NULL,
    "createdAt" timestamptz NOT NULL DEFAULT NOW(),
    "updatedAt" timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT event_quote_milestones_kind_fields CHECK (
        (kind = 'PAYMENT' AND amount IS NOT NULL)
        OR (kind = 'DELIVERY' AND amount IS NULL AND "percent" IS NULL)
    ),
    CONSTRAINT event_quote_milestones_completion CHECK (
        "completedAt" IS NULL OR (
            "customerAcknowledgedAt" IS NOT NULL AND
            "vendorAcknowledgedAt" IS NOT NULL
        )
    ),
    CONSTRAINT event_quote_milestones_unique_position UNIQUE ("quoteId", kind, position)
);
CREATE INDEX IF NOT EXISTS event_quote_milestones_due
    ON event_quote_milestones (kind, "dueAt")
    WHERE "completedAt" IS NULL AND "dueAt" IS NOT NULL;

-- Append-only audit events: separate from read-side acknowledgement timestamps.
CREATE TABLE IF NOT EXISTS event_quote_milestone_events (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    "milestoneId" uuid NOT NULL REFERENCES event_quote_milestones(id) ON DELETE CASCADE,
    "actorId" uuid NOT NULL REFERENCES users(id),
    action varchar(32) NOT NULL CHECK (action IN (
        'CUSTOMER_ACKNOWLEDGED', 'VENDOR_ACKNOWLEDGED'
    )),
    "createdAt" timestamptz NOT NULL DEFAULT NOW(),
    UNIQUE ("milestoneId", "actorId", action)
);
CREATE INDEX IF NOT EXISTS event_quote_milestone_events_milestone
    ON event_quote_milestone_events ("milestoneId", "createdAt" DESC);

COMMIT;
