CREATE TABLE IF NOT EXISTS admin_staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username varchar NOT NULL UNIQUE,
  "passwordHash" varchar NOT NULL,
  "displayName" varchar,
  "staffRole" varchar NOT NULL DEFAULT 'OPERATOR',
  "allowedPages" varchar,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
