-- Copy talent_profiles.photoUrl onto users.profileImageUrl when the user row is empty.
-- My Profile /auth/me reads users.profileImageUrl; Register as Pro only wrote talent photoUrl.
UPDATE users u
SET "profileImageUrl" = tp."photoUrl",
    "updatedAt" = NOW()
FROM talent_profiles tp
WHERE tp."userId" = u.id
  AND (u."profileImageUrl" IS NULL OR u."profileImageUrl" = '')
  AND tp."photoUrl" IS NOT NULL
  AND tp."photoUrl" <> '';

SELECT u.name, u."profileImageUrl", tp."photoUrl"
FROM users u
LEFT JOIN talent_profiles tp ON tp."userId" = u.id;
