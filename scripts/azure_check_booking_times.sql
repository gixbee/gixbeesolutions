SELECT id, status, skill, amount, "totalAmount", "workedMinutes", "billingHours",
       "petrolAmount", "startedAt", "completedAt", "acceptedAt", "createdAt",
       NOW() AS db_now
FROM bookings
ORDER BY "createdAt" DESC
LIMIT 8;
