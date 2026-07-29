INSERT INTO job_credits (id, "userId", balance, "createdAt", "updatedAt") SELECT gen_random_uuid(), id, 50, now(), now() FROM users WHERE id NOT IN (SELECT "userId" FROM job_credits WHERE "userId" IS NOT NULL);
UPDATE job_credits SET balance = 50;
