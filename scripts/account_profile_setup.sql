ALTER TABLE users
    ADD COLUMN IF NOT EXISTS "profileSetupPending" boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS "legalName" text,
    ADD COLUMN IF NOT EXISTS "dateOfBirth" date,
    ADD COLUMN IF NOT EXISTS "gender" text,
    ADD COLUMN IF NOT EXISTS "identityDetailsConfirmedAt" timestamptz;
