CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS system_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  level varchar(10) NOT NULL DEFAULT 'INFO',
  type varchar(10) NOT NULL DEFAULT 'API',
  method varchar(10) NULL,
  path varchar(500) NULL,
  "statusCode" integer NULL,
  "durationMs" integer NULL,
  "userId" varchar(64) NULL,
  ip varchar(64) NULL,
  message varchar(500) NULL,
  detail text NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "IDX_system_logs_level" ON system_logs (level);
CREATE INDEX IF NOT EXISTS "IDX_system_logs_type" ON system_logs (type);
CREATE INDEX IF NOT EXISTS "IDX_system_logs_path" ON system_logs (path);
CREATE INDEX IF NOT EXISTS "IDX_system_logs_statusCode" ON system_logs ("statusCode");
CREATE INDEX IF NOT EXISTS "IDX_system_logs_createdAt" ON system_logs ("createdAt");
