SELECT column_name FROM information_schema.columns WHERE table_name='hiring_requests' ORDER BY 1;
SELECT column_name FROM information_schema.columns WHERE table_name='hiring_interests' ORDER BY 1;
SELECT to_regclass('event_plans') AS event_plans;
SELECT to_regclass('booking_deadlines') AS booking_deadlines;
SELECT to_regclass('career_profile_receipts') AS career_profile_receipts;
