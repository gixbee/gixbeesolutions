SELECT 'users' AS src, COUNT(*)::int AS n FROM users
UNION ALL SELECT 'worker_profiles', COUNT(*)::int FROM worker_profiles
UNION ALL SELECT 'talent_profiles', COUNT(*)::int FROM talent_profiles
UNION ALL SELECT 'professional_skills', COUNT(*)::int FROM professional_skills
UNION ALL SELECT 'wp_pending', COUNT(*)::int FROM worker_profiles WHERE "verificationStatus"::text = 'PENDING';

SELECT u.id, u.name, u."phoneNumber", u."hasWorkerProfile", u."approvalStatus"::text AS approval, u."isVerified"
FROM users u ORDER BY u."createdAt" DESC LIMIT 20;

SELECT w.id, w."userId", w.skills, w."hourlyRate", w."verificationStatus"::text AS vs, w."isActive", w.bio
FROM worker_profiles w;

SELECT tp.id, tp."userId", tp."photoUrl", tp.certificates
FROM talent_profiles tp;

SELECT ps.name, ps.status::text AS status, ps."hourlyRate", tp."userId"
FROM professional_skills ps JOIN talent_profiles tp ON tp.id = ps."talentProfileId";
