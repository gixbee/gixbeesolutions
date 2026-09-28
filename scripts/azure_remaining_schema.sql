CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Enums ──────────────────────────────────────────────────────────────────
DO $$ BEGIN CREATE TYPE "businesses_type_enum" AS ENUM ('SERVICE','HIRING','RENTAL'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "businesses_servicetype_enum" AS ENUM ('HALL','CATERING','DECORATION','PHOTOGRAPHY'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "businesses_status_enum" AS ENUM ('PENDING','VERIFIED','REJECTED'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "rental_reservations_status_enum" AS ENUM ('PENDING','TEMP_HOLD','PAYMENT_PENDING','PENDING_OWNER_CONFIRMATION','CONFIRMED','ACTIVE','RETURN_PENDING','COMPLETED','CANCELLED','REJECTED'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "job_applications_status_enum" AS ENUM ('APPLIED','INTERVIEW','SELECTED','REJECTED','NO_SHOW','WITHDRAWN'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "hiring_requests_status_enum" AS ENUM ('COLLECTING','DELIVERED','GUARANTEE_FAILED','RESOLVED_CREDIT','RESOLVED_REFUND','CLOSED'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "job_preferences_employmenttype_enum" AS ENUM ('FT','PT','INTERN','CONTRACT'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "hiring_requests_employmenttype_enum" AS ENUM ('FT','PT','INTERN','CONTRACT'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "job_preferences_noticeperiod_enum" AS ENUM ('IMMEDIATE','DAYS_15','DAYS_30','DAYS_60','DAYS_90'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "hiring_interests_response_enum" AS ENUM ('PENDING','INTERESTED','NOT_INTERESTED'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "hiring_interests_decision_enum" AS ENUM ('PENDING','SHORTLISTED','REJECTED','HIRED'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "payment_orders_purpose_enum" AS ENUM ('WALLET_RECHARGE','JOB_CREDITS','PERIOD_FEE','LATE_CANCEL_COMPENSATION','HIRING_MATCH_FEE','EXTRA_JOB_TYPE_FEE','RENTAL_ADVANCE','RENTAL_SETTLEMENT'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "payment_orders_status_enum" AS ENUM ('CREATED','CREDITED','FAILED'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "worker_strikes_type_enum" AS ENUM ('GPS_FORFEIT','NO_SHOW','ADMIN'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "worker_strikes_status_enum" AS ENUM ('ACTIVE','APPEALED','OVERTURNED','UPHELD'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE "credit_transactions_reason_enum" AS ENUM ('PURCHASE','JOB_ACCEPTED','REFUND_CUSTOMER_CANCEL','REFUND_NOSHOW'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── addresses ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label varchar,
  line varchar NOT NULL,
  lat numeric(9,6),
  lng numeric(9,6),
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_addresses_userId" ON addresses ("userId");

-- ── businesses ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS businesses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ownerId" uuid NOT NULL REFERENCES users(id),
  type "businesses_type_enum" NOT NULL,
  "serviceType" "businesses_servicetype_enum",
  name varchar NOT NULL,
  location varchar NOT NULL,
  phone varchar(30),
  "eventServices" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "cityId" uuid REFERENCES cities(id),
  description text,
  "documentUrl" text,
  status "businesses_status_enum" NOT NULL DEFAULT 'PENDING',
  "operatorIds" text,
  "offlineDays" jsonb,
  "hiringProfile" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

-- ── rental_items ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rental_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ownerId" uuid NOT NULL REFERENCES users(id),
  "businessId" uuid REFERENCES businesses(id),
  quantity integer NOT NULL DEFAULT 1,
  "pickupAddress" text NOT NULL DEFAULT '',
  "deliveryAvailable" boolean NOT NULL DEFAULT false,
  "deliveryFee" numeric(10,2) NOT NULL DEFAULT 0,
  "depositPerUnit" numeric(10,2) NOT NULL DEFAULT 0,
  "pickupLat" double precision,
  "pickupLng" double precision,
  name varchar NOT NULL,
  description text,
  "imageUrl" varchar,
  "imageUrls" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "hourlyRate" numeric(10,2) NOT NULL,
  "dailyRate" numeric(10,2),
  "minHoursToRent" integer NOT NULL DEFAULT 1,
  "isAvailable" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_rental_items_ownerId" ON rental_items ("ownerId");
CREATE INDEX IF NOT EXISTS "IDX_rental_items_isAvailable_createdAt" ON rental_items ("isAvailable", "createdAt");

-- ── rental_reservations ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rental_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "itemId" uuid NOT NULL REFERENCES rental_items(id),
  "renterId" uuid NOT NULL REFERENCES users(id),
  "startTime" timestamp NOT NULL,
  "endTime" timestamp NOT NULL,
  "totalPrice" numeric(10,2) NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  fulfillment varchar(20) NOT NULL DEFAULT 'PICKUP',
  "fulfillmentAddress" text NOT NULL DEFAULT '',
  "priceBreakdown" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "ownerHandedOverAt" timestamptz,
  "renterCollectedAt" timestamptz,
  "ownerReturnedAt" timestamptz,
  "renterReturnedAt" timestamptz,
  "ownerPaidAt" timestamptz,
  "renterPaidAt" timestamptz,
  "ownerRefundedAt" timestamptz,
  "renterRefundedAt" timestamptz,
  status "rental_reservations_status_enum" NOT NULL DEFAULT 'PENDING',
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_rental_reservations_itemId" ON rental_reservations ("itemId");
CREATE INDEX IF NOT EXISTS "IDX_rental_reservations_renterId" ON rental_reservations ("renterId");
CREATE INDEX IF NOT EXISTS "IDX_rental_reservations_item_status" ON rental_reservations ("itemId", status);

-- ── job_posts ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "employerId" uuid NOT NULL REFERENCES users(id),
  "businessId" uuid REFERENCES businesses(id),
  title varchar NOT NULL,
  description text NOT NULL,
  "requiredSkills" text,
  "jobType" varchar,
  experience varchar,
  location varchar,
  "salaryMin" numeric(10,2),
  "salaryMax" numeric(10,2),
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_job_posts_employerId" ON job_posts ("employerId");
CREATE INDEX IF NOT EXISTS "IDX_job_posts_isActive_createdAt" ON job_posts ("isActive", "createdAt");

-- ── job_applications ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "jobPostId" uuid NOT NULL REFERENCES job_posts(id),
  "applicantId" uuid NOT NULL REFERENCES users(id),
  status "job_applications_status_enum" NOT NULL DEFAULT 'APPLIED',
  "coverLetter" text,
  "resumeUrl" text,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_job_applications_jobPostId" ON job_applications ("jobPostId");
CREATE INDEX IF NOT EXISTS "IDX_job_applications_applicantId" ON job_applications ("applicantId");

-- ── job_preferences ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL REFERENCES users(id),
  "jobType" varchar NOT NULL,
  skills text,
  "preferredLocation" varchar,
  "expectedSalary" numeric(10,2) NOT NULL DEFAULT 0,
  "salaryNegotiable" boolean NOT NULL DEFAULT false,
  "employmentType" "job_preferences_employmenttype_enum",
  "experienceYears" integer NOT NULL DEFAULT 0,
  "noticePeriod" "job_preferences_noticeperiod_enum" NOT NULL DEFAULT 'IMMEDIATE',
  "isActive" boolean NOT NULL DEFAULT true,
  "isPaid" boolean NOT NULL DEFAULT false,
  "paidUntil" timestamptz,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_job_preferences_userId" ON job_preferences ("userId");
CREATE INDEX IF NOT EXISTS "IDX_job_preferences_jobType_isActive" ON job_preferences ("jobType", "isActive");

-- ── hiring_requests ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS hiring_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "employerId" uuid NOT NULL REFERENCES users(id),
  "businessId" uuid REFERENCES businesses(id),
  "jobType" varchar NOT NULL,
  skills text,
  location varchar,
  "salaryOffered" numeric(10,2) NOT NULL DEFAULT 0,
  "salaryMin" numeric(10,2) NOT NULL DEFAULT 0,
  "salaryMax" numeric(10,2) NOT NULL DEFAULT 0,
  "salaryNegotiable" boolean NOT NULL DEFAULT false,
  "employmentType" "hiring_requests_employmenttype_enum",
  "experienceMinYears" integer NOT NULL DEFAULT 0,
  vacancies integer NOT NULL DEFAULT 1,
  "targetInterested" integer NOT NULL DEFAULT 3,
  "feeAmount" numeric(10,2) NOT NULL DEFAULT 0,
  "creditApplied" numeric(10,2) NOT NULL DEFAULT 0,
  "paymentOrderId" uuid,
  "razorpayPaymentId" varchar,
  status "hiring_requests_status_enum" NOT NULL DEFAULT 'COLLECTING',
  "deadlineAt" timestamptz NOT NULL,
  "batchesSent" integer NOT NULL DEFAULT 0,
  "deliveredAt" timestamptz,
  "resolvedAt" timestamptz,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_hiring_requests_employerId" ON hiring_requests ("employerId");
CREATE INDEX IF NOT EXISTS "IDX_hiring_requests_status_deadlineAt" ON hiring_requests (status, "deadlineAt");

-- ── hiring_interests ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS hiring_interests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "requestId" uuid NOT NULL REFERENCES hiring_requests(id),
  "candidateId" uuid NOT NULL REFERENCES users(id),
  "preferenceId" uuid REFERENCES job_preferences(id),
  response "hiring_interests_response_enum" NOT NULL DEFAULT 'PENDING',
  decision "hiring_interests_decision_enum" NOT NULL DEFAULT 'PENDING',
  progress jsonb NOT NULL DEFAULT '{}'::jsonb,
  revision integer NOT NULL DEFAULT 0,
  "notifiedAt" timestamptz,
  "respondedAt" timestamptz,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("requestId", "candidateId")
);
CREATE INDEX IF NOT EXISTS "IDX_hiring_interests_requestId" ON hiring_interests ("requestId");
CREATE INDEX IF NOT EXISTS "IDX_hiring_interests_candidateId" ON hiring_interests ("candidateId");

-- ── payment_orders ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL,
  amount numeric(10,2) NOT NULL,
  "razorpayOrderId" varchar NOT NULL UNIQUE,
  purpose "payment_orders_purpose_enum" NOT NULL DEFAULT 'WALLET_RECHARGE',
  "razorpayPaymentId" varchar,
  status "payment_orders_status_enum" NOT NULL DEFAULT 'CREATED',
  meta jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_payment_orders_userId" ON payment_orders ("userId");

-- ── career_profile_receipts ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS career_profile_receipts (
  "paymentOrderId" uuid PRIMARY KEY REFERENCES payment_orders(id),
  "preferenceId" uuid NOT NULL REFERENCES job_preferences(id),
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

-- ── event_plans / event_quotes ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS event_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "customerId" uuid NOT NULL REFERENCES users(id),
  "eventType" varchar(100) NOT NULL,
  "startTime" timestamptz NOT NULL,
  "endTime" timestamptz NOT NULL,
  "guestCount" integer NOT NULL CHECK ("guestCount" BETWEEN 1 AND 100000),
  location text NOT NULL,
  "cityId" uuid NULL REFERENCES cities(id),
  services jsonb NOT NULL CHECK (jsonb_typeof(services) = 'array'),
  notes text NOT NULL DEFAULT '',
  "cancelledAt" timestamptz NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  CHECK ("endTime" > "startTime")
);
CREATE TABLE IF NOT EXISTS event_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "planId" uuid NOT NULL REFERENCES event_plans(id),
  "businessId" uuid NOT NULL REFERENCES businesses(id),
  "serviceType" varchar(40) NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  inclusions text NOT NULL,
  "cancellationTerms" text NOT NULL,
  status varchar(30) NOT NULL DEFAULT 'OFFERED'
    CHECK (status IN ('OFFERED','DECLINED','EXPIRED','CONFIRMED','COMPLETED','CANCEL_REQUESTED','CANCELLED')),
  "expiresAt" timestamptz NOT NULL,
  "acceptedAt" timestamptz NULL,
  "customerPaidAt" timestamptz NULL,
  "vendorReceivedAt" timestamptz NULL,
  "customerCompletedAt" timestamptz NULL,
  "vendorCompletedAt" timestamptz NULL,
  "cancellationRequestedBy" uuid NULL REFERENCES users(id),
  "cancellationReason" text NULL,
  "cancellationRefund" numeric(12,2) NOT NULL DEFAULT 0 CHECK ("cancellationRefund" >= 0),
  "customerRefundReceivedAt" timestamptz NULL,
  "vendorRefundSentAt" timestamptz NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("planId","businessId","serviceType"),
  CHECK ("cancellationRefund" <= amount)
);
CREATE UNIQUE INDEX IF NOT EXISTS event_quotes_selected_service
  ON event_quotes ("planId","serviceType")
  WHERE status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED');
CREATE INDEX IF NOT EXISTS event_plans_customer ON event_plans ("customerId","createdAt");
CREATE INDEX IF NOT EXISTS event_quotes_business ON event_quotes ("businessId", status);

-- ── messages ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "senderId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  "recipientId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body text NOT NULL,
  "bookingId" uuid,
  "isRead" boolean NOT NULL DEFAULT false,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_messages_senderId" ON messages ("senderId");
CREATE INDEX IF NOT EXISTS "IDX_messages_recipientId" ON messages ("recipientId");

-- ── favourites ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS favourites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  "workerId" varchar NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("userId", "workerId")
);
CREATE INDEX IF NOT EXISTS "IDX_favourites_workerId" ON favourites ("workerId");

-- ── support_tickets ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subject varchar NOT NULL,
  message text NOT NULL,
  status varchar NOT NULL DEFAULT 'OPEN',
  reply text,
  "resolvedAt" timestamp,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_support_tickets_userId" ON support_tickets ("userId");

-- ── worker_strikes ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS worker_strikes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "workerUserId" varchar NOT NULL,
  "userId" uuid,
  "bookingId" uuid,
  type "worker_strikes_type_enum" NOT NULL,
  reason text NOT NULL,
  status "worker_strikes_status_enum" NOT NULL DEFAULT 'ACTIVE',
  "appealMessage" text,
  "appealedAt" timestamptz,
  "resolutionNote" text,
  "resolvedAt" timestamptz,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_worker_strikes_workerUserId" ON worker_strikes ("workerUserId");
CREATE INDEX IF NOT EXISTS "IDX_worker_strikes_userId" ON worker_strikes ("userId");
CREATE INDEX IF NOT EXISTS "IDX_worker_strikes_status" ON worker_strikes (status);

-- ── credit_transactions ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS credit_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL REFERENCES users(id),
  delta integer NOT NULL,
  reason "credit_transactions_reason_enum" NOT NULL,
  "bookingId" varchar,
  "razorpayPaymentId" varchar,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "IDX_credit_transactions_userId" ON credit_transactions ("userId");

-- ── booking_deadlines extra columns (earlier bootstrap was incomplete) ─────
ALTER TABLE booking_deadlines ADD COLUMN IF NOT EXISTS sequence integer NOT NULL DEFAULT 0;
ALTER TABLE booking_deadlines ADD COLUMN IF NOT EXISTS "processedAt" timestamptz;
ALTER TABLE booking_deadlines ADD COLUMN IF NOT EXISTS attempts integer NOT NULL DEFAULT 0;
ALTER TABLE booking_deadlines ADD COLUMN IF NOT EXISTS "lastError" text;
ALTER TABLE booking_deadlines ALTER COLUMN "dueAt" TYPE timestamptz USING "dueAt"::timestamptz;
CREATE UNIQUE INDEX IF NOT EXISTS "UQ_booking_deadlines_booking_kind_seq"
  ON booking_deadlines ("bookingId", kind, sequence);
CREATE INDEX IF NOT EXISTS booking_deadlines_due
  ON booking_deadlines ("dueAt") WHERE "processedAt" IS NULL;

-- rust get_my_strikes filters "userId"; entity stores workerUserId
ALTER TABLE worker_strikes ADD COLUMN IF NOT EXISTS "userId" uuid;

-- ── Gap-fill columns on tables that already existed from earlier bootstraps ─
ALTER TABLE users ADD COLUMN IF NOT EXISTS "hiringCreditBalance" numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "lateCancelStrikeCount" integer NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "instantHelpBlocked" boolean NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "unblockCompensationBookingId" uuid;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "unblockCompensationAmountInr" integer;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "unblockCompensationDistanceKm" numeric(8,2);
ALTER TABLE users ADD COLUMN IF NOT EXISTS "approvalStatus" "users_approvalstatus_enum" NOT NULL DEFAULT 'PENDING';
ALTER TABLE users ADD COLUMN IF NOT EXISTS "hasWorkerProfile" boolean NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "isAvailableForWork" boolean NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "profileImageUrl" varchar;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "fcmToken" varchar;
ALTER TABLE users ADD COLUMN IF NOT EXISTS "walletBalance" numeric(10,2) NOT NULL DEFAULT 0;

ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "activeSkills" text;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS languages text;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "serviceRadiusKm" integer NOT NULL DEFAULT 10;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "jobsSincePayment" integer NOT NULL DEFAULT 0;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "strikeCount" integer NOT NULL DEFAULT 0;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "maskedAadhaar" varchar(32);
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "lastLat" numeric(10,7);
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "lastLng" numeric(10,7);
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "availabilitySchedule" jsonb;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "goLiveToggleCountToday" integer NOT NULL DEFAULT 0;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "goLiveToggleDate" date;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "isFirstJobDone" boolean NOT NULL DEFAULT false;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "noShowCount" integer NOT NULL DEFAULT 0;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "rateUpdateCountToday" integer NOT NULL DEFAULT 0;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "rateUpdateDate" date;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS bio varchar;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS title varchar;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS rating numeric(3,2) NOT NULL DEFAULT 0;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "completedJobs" integer NOT NULL DEFAULT 0;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "reviewCount" integer NOT NULL DEFAULT 0;
ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS "availabilityTags" text;

ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "photoUrl" varchar;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS certificates text;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS experience varchar;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "hourlyRate" double precision;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "currentStatus" "talent_profiles_currentstatus_enum";
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "expectedSalary" integer;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "preferredRoles" text;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "preferredLocations" text;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "jobAlertsEnabled" boolean NOT NULL DEFAULT true;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "savedJobIds" text;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "noShowCount" integer NOT NULL DEFAULT 0;
ALTER TABLE talent_profiles ADD COLUMN IF NOT EXISTS "searchRank" double precision NOT NULL DEFAULT 100;

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "addressId" varchar;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "preferredLanguages" text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "onSiteContact" jsonb;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "acceptedAt" timestamp;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "gpsStrikes" integer NOT NULL DEFAULT 0;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "acceptLat" numeric(9,6);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "acceptLng" numeric(9,6);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "acceptDistanceKm" numeric(8,2);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "petrolDistanceKm" numeric(8,2);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "petrolRatePerKm" numeric(8,2);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "petrolAmount" integer;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "workerNoProgressAt" timestamp;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "arrivalOtp" varchar;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "completionOtp" varchar;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "workerPaidConfirmed" boolean NOT NULL DEFAULT false;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "customerPaidConfirmed" boolean NOT NULL DEFAULT false;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "paymentCollectionMethod" varchar;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "workerHonestyCheck" varchar;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "customerSafetyCheck" varchar;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "billingHours" integer;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "workedMinutes" integer;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "customerRating" integer;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "cancelRequestedAt" timestamp;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "lateCancelCompensationAmountInr" integer;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "lateCancelCompensationDistanceKm" numeric(8,2);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "lateCancelCompensationPaidAt" timestamp;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "disputeReason" text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "disputeReporterRole" varchar;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "disputedAt" timestamp;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "disputeResolution" text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "disputeResolvedAt" timestamp;

ALTER TABLE professional_skills ADD COLUMN IF NOT EXISTS bio varchar;
ALTER TABLE professional_skills ADD COLUMN IF NOT EXISTS "rateChart" jsonb;

ALTER TABLE master_entries ADD COLUMN IF NOT EXISTS icon varchar;
ALTER TABLE master_entries ADD COLUMN IF NOT EXISTS category varchar;
ALTER TABLE master_entries ADD COLUMN IF NOT EXISTS "cityId" uuid;
ALTER TABLE master_entries ADD COLUMN IF NOT EXISTS "isActive" boolean NOT NULL DEFAULT true;

ALTER TABLE cities ADD COLUMN IF NOT EXISTS "isActive" boolean NOT NULL DEFAULT true;

ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS attempts integer NOT NULL DEFAULT 0;
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS "processedAt" timestamptz;
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS "lastError" text;

ALTER TABLE job_credits ADD COLUMN IF NOT EXISTS "createdAt" timestamptz NOT NULL DEFAULT now();
ALTER TABLE job_credits ADD COLUMN IF NOT EXISTS "updatedAt" timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION worker_strikes_sync_userid() RETURNS trigger AS $$
BEGIN
  IF NEW."userId" IS NULL AND NEW."workerUserId" IS NOT NULL THEN
    BEGIN
      NEW."userId" := NEW."workerUserId"::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_worker_strikes_userid ON worker_strikes;
CREATE TRIGGER trg_worker_strikes_userid
BEFORE INSERT OR UPDATE ON worker_strikes
FOR EACH ROW EXECUTE PROCEDURE worker_strikes_sync_userid();
