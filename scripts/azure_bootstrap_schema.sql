CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  CREATE TYPE "users_role_enum" AS ENUM ('CUSTOMER', 'OWNER', 'OPERATOR', 'ADMIN');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "users_approvalstatus_enum" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "wallet_transactions_type_enum" AS ENUM ('DEBIT', 'CREDIT', 'REFUND');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "phoneNumber" varchar NOT NULL UNIQUE,
  name varchar,
  role "users_role_enum" NOT NULL DEFAULT 'CUSTOMER',
  "walletBalance" numeric(10,2) NOT NULL DEFAULT 0,
  "hiringCreditBalance" numeric(10,2) NOT NULL DEFAULT 0,
  "isVerified" boolean NOT NULL DEFAULT false,
  "profileImageUrl" varchar,
  "fcmToken" varchar,
  "hasWorkerProfile" boolean NOT NULL DEFAULT false,
  "isAvailableForWork" boolean NOT NULL DEFAULT true,
  "lateCancelStrikeCount" integer NOT NULL DEFAULT 0,
  "instantHelpBlocked" boolean NOT NULL DEFAULT false,
  "unblockCompensationBookingId" uuid,
  "unblockCompensationAmountInr" integer,
  "unblockCompensationDistanceKm" numeric(8,2),
  "approvalStatus" "users_approvalstatus_enum" NOT NULL DEFAULT 'PENDING',
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS wallet_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid REFERENCES users(id),
  amount numeric(10,2) NOT NULL,
  type "wallet_transactions_type_enum" NOT NULL,
  description varchar,
  timestamp timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS job_credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid REFERENCES users(id),
  balance integer NOT NULL DEFAULT 0,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type varchar(80) NOT NULL,
  "aggregateId" uuid NOT NULL,
  payload jsonb NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "processedAt" timestamptz,
  "lastError" text
);

CREATE TABLE IF NOT EXISTS booking_deadlines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "bookingId" uuid NOT NULL,
  kind varchar(80) NOT NULL,
  "dueAt" timestamptz NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'pending',
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
