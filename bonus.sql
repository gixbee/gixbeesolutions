WITH updated_users AS (
    UPDATE users 
    SET "walletBalance" = "walletBalance" + 1000 
    WHERE "hasWorkerProfile" = true 
    RETURNING id
) 
INSERT INTO wallet_transactions (id, "userId", amount, type, description, timestamp) 
SELECT gen_random_uuid(), id, 1000, 'CREDIT', 'Admin Bonus', now() 
FROM updated_users 
RETURNING id;
