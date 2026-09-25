-- Mirror of backend/src/migrations/1756400000000-MasterDataAudit.ts (manual apply if needed)
CREATE TABLE IF NOT EXISTS master_data_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section varchar NOT NULL,
  "entityType" varchar NOT NULL,
  "entityId" varchar NOT NULL,
  action varchar NOT NULL,
  "actorUserId" uuid NOT NULL,
  "beforeJson" jsonb,
  "afterJson" jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS master_data_audit_section_created ON master_data_audit (section, "createdAt" DESC);
CREATE INDEX IF NOT EXISTS master_data_audit_entity ON master_data_audit ("entityType", "entityId");
