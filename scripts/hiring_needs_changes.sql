-- Hiring verification: admin can request changes instead of only verify/reject.
ALTER TYPE "businesses_status_enum" ADD VALUE IF NOT EXISTS 'NEEDS_CHANGES';
