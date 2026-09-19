CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  CREATE TYPE "talent_profiles_currentstatus_enum" AS ENUM ('FINAL_YEAR', 'GRADUATE', 'EXPERIENCED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "professional_skills_status_enum" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "worker_profiles_verificationstatus_enum" AS ENUM ('PENDING', 'VERIFIED', 'REJECTED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "bookings_type_enum" AS ENUM ('PACKAGE', 'CUSTOM', 'INSTANT', 'RENTAL');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "bookings_status_enum" AS ENUM (
    'REQUESTED', 'CUSTOM_REQUESTED', 'PENDING', 'ACCEPTED', 'ARRIVED',
    'CONFIRMED', 'ACTIVE', 'COMPLETED', 'CANCELLED', 'REJECTED'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS talent_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL UNIQUE REFERENCES users(id),
  education text,
  skills text,
  "photoUrl" varchar,
  certificates text,
  experience varchar,
  "hourlyRate" double precision,
  "currentStatus" "talent_profiles_currentstatus_enum",
  "expectedSalary" integer,
  "preferredRoles" text,
  "preferredLocations" text,
  "jobAlertsEnabled" boolean NOT NULL DEFAULT true,
  "savedJobIds" text,
  "noShowCount" integer NOT NULL DEFAULT 0,
  "searchRank" double precision NOT NULL DEFAULT 100,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS professional_skills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "talentProfileId" uuid NOT NULL REFERENCES talent_profiles(id) ON DELETE CASCADE,
  name varchar NOT NULL,
  "hourlyRate" double precision NOT NULL,
  status "professional_skills_status_enum" NOT NULL DEFAULT 'PENDING',
  bio varchar,
  "rateChart" jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS worker_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL UNIQUE REFERENCES users(id),
  skills text,
  "activeSkills" text,
  languages text,
  "serviceRadiusKm" integer NOT NULL DEFAULT 10,
  "hourlyRate" numeric(10,2) NOT NULL DEFAULT 0,
  "availabilitySchedule" jsonb,
  "isActive" boolean NOT NULL DEFAULT false,
  "goLiveToggleCountToday" integer NOT NULL DEFAULT 0,
  "goLiveToggleDate" date,
  "jobsSincePayment" integer NOT NULL DEFAULT 0,
  "isFirstJobDone" boolean NOT NULL DEFAULT false,
  "noShowCount" integer NOT NULL DEFAULT 0,
  "strikeCount" integer NOT NULL DEFAULT 0,
  "rateUpdateCountToday" integer NOT NULL DEFAULT 0,
  "rateUpdateDate" date,
  "verificationStatus" "worker_profiles_verificationstatus_enum" NOT NULL DEFAULT 'PENDING',
  "maskedAadhaar" varchar(32),
  bio varchar,
  title varchar,
  rating numeric(3,2) NOT NULL DEFAULT 0,
  "completedJobs" integer NOT NULL DEFAULT 0,
  "reviewCount" integer NOT NULL DEFAULT 0,
  "availabilityTags" text,
  "lastLat" numeric(10,7),
  "lastLng" numeric(10,7),
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "IDX_worker_profiles_verificationStatus"
  ON worker_profiles ("verificationStatus");

CREATE TABLE IF NOT EXISTS bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "customerId" uuid NOT NULL REFERENCES users(id),
  "operatorId" uuid REFERENCES users(id),
  skill varchar,
  "serviceLocation" varchar,
  "addressId" varchar,
  description text,
  "preferredLanguages" text,
  "totalAmount" numeric(10,2),
  "cancellationReason" varchar,
  "serviceLat" numeric(9,6),
  "serviceLng" numeric(9,6),
  "onSiteContact" jsonb,
  type "bookings_type_enum" NOT NULL DEFAULT 'INSTANT',
  "customDetails" jsonb,
  quote numeric(10,2),
  "vendorNote" varchar,
  status "bookings_status_enum" NOT NULL DEFAULT 'PENDING',
  amount numeric(10,2) NOT NULL DEFAULT 0,
  "scheduledAt" timestamp,
  "startedAt" timestamp,
  "acceptedAt" timestamp,
  "completedAt" timestamp,
  "gpsStrikes" integer NOT NULL DEFAULT 0,
  "acceptLat" numeric(9,6),
  "acceptLng" numeric(9,6),
  "acceptDistanceKm" numeric(8,2),
  "petrolDistanceKm" numeric(8,2),
  "petrolRatePerKm" numeric(8,2),
  "petrolAmount" integer,
  "workerNoProgressAt" timestamp,
  "arrivalOtp" varchar,
  "completionOtp" varchar,
  "paymentMethod" varchar NOT NULL DEFAULT 'WALLET',
  "isPaid" boolean NOT NULL DEFAULT false,
  "workerPaidConfirmed" boolean NOT NULL DEFAULT false,
  "customerPaidConfirmed" boolean NOT NULL DEFAULT false,
  "paymentCollectionMethod" varchar,
  "workerHonestyCheck" varchar,
  "customerSafetyCheck" varchar,
  "billingHours" integer,
  "workedMinutes" integer,
  rating integer,
  "customerRating" integer,
  "cancelRequestedAt" timestamp,
  "lateCancelCompensationAmountInr" integer,
  "lateCancelCompensationDistanceKm" numeric(8,2),
  "lateCancelCompensationPaidAt" timestamp,
  "disputeReason" text,
  "disputeReporterRole" varchar,
  "disputedAt" timestamp,
  "disputeResolution" text,
  "disputeResolvedAt" timestamp,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "IDX_bookings_operator_status" ON bookings ("operatorId", status);
CREATE INDEX IF NOT EXISTS "IDX_bookings_customer_status" ON bookings ("customerId", status);
CREATE INDEX IF NOT EXISTS "IDX_bookings_status_createdAt" ON bookings (status, "createdAt");
