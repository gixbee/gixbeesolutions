-- Event delivery revision history and direct-payment reconciliation.
-- Prerequisite: azure_event_quote_milestones.sql. Additive; no funds transferred.
BEGIN;

CREATE TABLE IF NOT EXISTS event_delivery_revisions (
  id uuid PRIMARY KEY,
  "quoteId" uuid NOT NULL REFERENCES event_quotes(id) ON DELETE CASCADE,
  "milestoneId" uuid NOT NULL REFERENCES event_quote_milestones(id) ON DELETE CASCADE,
  version integer NOT NULL CHECK (version BETWEEN 1 AND 30),
  "fileName" varchar(180) NOT NULL,
  "mediaType" varchar(80) NOT NULL
    CHECK ("mediaType" IN ('application/pdf','application/zip','image/jpeg','image/png','image/webp')),
  "fileBytes" bytea NOT NULL CHECK (octet_length("fileBytes") BETWEEN 1 AND 12582912),
  "sha256" char(64) NOT NULL,
  "note" varchar(1200) NOT NULL DEFAULT '',
  status varchar(20) NOT NULL DEFAULT 'SUBMITTED'
    CHECK (status IN ('SUBMITTED','REVISION_REQUESTED','APPROVED')),
  "feedback" varchar(1500) NULL,
  "uploadedBy" uuid NOT NULL REFERENCES users(id),
  "reviewedBy" uuid NULL REFERENCES users(id),
  "uploadedAt" timestamptz NOT NULL DEFAULT NOW(),
  "reviewedAt" timestamptz NULL,
  UNIQUE ("milestoneId", version)
);
CREATE INDEX IF NOT EXISTS event_delivery_revisions_quote
  ON event_delivery_revisions ("quoteId", "milestoneId", version DESC);

CREATE TABLE IF NOT EXISTS event_payment_reports (
  id uuid PRIMARY KEY,
  "quoteId" uuid NOT NULL REFERENCES event_quotes(id) ON DELETE CASCADE,
  "milestoneId" uuid NOT NULL REFERENCES event_quote_milestones(id) ON DELETE CASCADE,
  version integer NOT NULL CHECK (version BETWEEN 1 AND 30),
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  method varchar(20) NOT NULL CHECK (method IN ('UPI','BANK','CASH','OTHER')),
  reference varchar(120) NOT NULL CHECK (length(btrim(reference)) BETWEEN 4 AND 120),
  note varchar(1500) NOT NULL DEFAULT '',
  status varchar(16) NOT NULL DEFAULT 'REPORTED'
    CHECK (status IN ('REPORTED','CONFIRMED','CONTESTED','REJECTED')),
  "reportedBy" uuid NOT NULL REFERENCES users(id),
  "reviewedBy" uuid NULL REFERENCES users(id),
  "reviewNote" varchar(1500) NOT NULL DEFAULT '',
  "reportedAt" timestamptz NOT NULL DEFAULT NOW(),
  "reviewedAt" timestamptz NULL,
  UNIQUE ("milestoneId", version)
);
CREATE INDEX IF NOT EXISTS event_payment_reports_quote
  ON event_payment_reports ("quoteId", "milestoneId", version DESC);

CREATE TABLE IF NOT EXISTS event_quote_disputes (
  id uuid PRIMARY KEY,
  "quoteId" uuid NOT NULL REFERENCES event_quotes(id) ON DELETE CASCADE,
  "milestoneId" uuid NOT NULL REFERENCES event_quote_milestones(id) ON DELETE CASCADE,
  "reportId" uuid NULL REFERENCES event_payment_reports(id),
  "openedBy" uuid NOT NULL REFERENCES users(id),
  reason varchar(2000) NOT NULL CHECK (length(btrim(reason)) BETWEEN 10 AND 2000),
  status varchar(12) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','RESOLVED')),
  "customerVote" varchar(12) NULL CHECK ("customerVote" IN ('SETTLED','UNPAID')),
  "vendorVote" varchar(12) NULL CHECK ("vendorVote" IN ('SETTLED','UNPAID')),
  resolution varchar(12) NULL CHECK (resolution IN ('SETTLED','UNPAID')),
  "openedAt" timestamptz NOT NULL DEFAULT NOW(),
  "resolvedAt" timestamptz NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS event_quote_disputes_one_active
  ON event_quote_disputes ("milestoneId") WHERE status='OPEN';
CREATE INDEX IF NOT EXISTS event_quote_disputes_quote
  ON event_quote_disputes ("quoteId", "openedAt" DESC);

CREATE TABLE IF NOT EXISTS event_quote_dispute_events (
  id uuid PRIMARY KEY,
  "disputeId" uuid NOT NULL REFERENCES event_quote_disputes(id) ON DELETE CASCADE,
  "actorId" uuid NOT NULL REFERENCES users(id),
  action varchar(20) NOT NULL CHECK (action IN ('OPENED','MESSAGE','VOTED','RESOLVED')),
  message varchar(2000) NOT NULL DEFAULT '',
  "createdAt" timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS event_quote_dispute_events_order
  ON event_quote_dispute_events ("disputeId", "createdAt", id);

COMMIT;
