ALTER TYPE payment_orders_purpose_enum ADD VALUE IF NOT EXISTS 'PLATFORM_PLAN';

CREATE TABLE IF NOT EXISTS platform_plan_grants (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    payment_order_id uuid UNIQUE REFERENCES payment_orders(id),
    family text NOT NULL CHECK (family IN ('CAREER', 'SERVICE', 'RENTAL', 'SHOP', 'HIRING')),
    tier text NOT NULL CHECK (tier IN ('STANDARD', 'PRO')),
    plan_code text NOT NULL,
    capacity integer NOT NULL CHECK (capacity >= 0),
    valid_until timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS platform_plan_trial_once
    ON platform_plan_grants (user_id) WHERE plan_code = 'career_trial';
CREATE INDEX IF NOT EXISTS platform_plan_grant_access
    ON platform_plan_grants (user_id, family, valid_until);
ALTER TABLE job_preferences ADD COLUMN IF NOT EXISTS "requiresCareerPlan" boolean NOT NULL DEFAULT false;
