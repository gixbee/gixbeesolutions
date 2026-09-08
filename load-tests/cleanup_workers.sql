-- Take load-test workers offline and remove from Redis geo (run after load test)
UPDATE worker_profiles w
SET "isActive" = false
FROM users u
WHERE w."userId" = u.id
  AND u."phoneNumber" LIKE '+9198880%';
