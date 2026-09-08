import { randomUUID } from 'crypto';
import { writeFileSync } from 'fs';
import jwt from 'jsonwebtoken';

const args = process.argv.slice(2);
function getArg(name, defaultValue) {
  const eq = args.find((a) => a.startsWith(`--${name}=`));
  if (eq) return eq.split('=').slice(1).join('=');
  const index = args.indexOf(`--${name}`);
  if (index === -1) return defaultValue;
  return args[index + 1] ?? defaultValue;
}

const COUNT = Number(getArg('count', 50));
const JWT_SECRET = getArg('jwt-secret', process.env.JWT_SECRET);
const OUT_SQL = getArg('sql-out', 'seed_workers.sql');
const OUT_JSON = getArg('tokens-out', 'tokens.json');
const PHONE_PREFIX = getArg('phone-prefix', '+9198880');

if (!JWT_SECRET) {
  console.error('JWT_SECRET required: --jwt-secret <secret> or env JWT_SECRET');
  process.exit(1);
}

const tokens = [];
const sql = [];
sql.push('BEGIN;');
sql.push(`-- Load test workers ${new Date().toISOString()}`);
sql.push(`DELETE FROM job_credits WHERE "userId" IN (SELECT id FROM users WHERE "phoneNumber" LIKE '${PHONE_PREFIX}%');`);
sql.push(`DELETE FROM worker_profiles WHERE "userId" IN (SELECT id FROM users WHERE "phoneNumber" LIKE '${PHONE_PREFIX}%');`);
sql.push(`DELETE FROM users WHERE "phoneNumber" LIKE '${PHONE_PREFIX}%';`);

for (let i = 0; i < COUNT; i++) {
  const id = randomUUID();
  const phone = `${PHONE_PREFIX}${String(i).padStart(4, '0')}`;
  const label = `LoadTest Worker ${i}`;
  const profileId = randomUUID();
  const creditsId = randomUUID();

  sql.push(`
INSERT INTO users (id, "phoneNumber", name, role, "walletBalance", "isVerified", "hasWorkerProfile", "isAvailableForWork")
VALUES ('${id}', '${phone}', '${label}', 'CUSTOMER', 0, true, true, true);`);

  sql.push(`
INSERT INTO worker_profiles (id, "userId", skills, "activeSkills", "hourlyRate", "verificationStatus", "isActive", "lastLat", "lastLng")
VALUES ('${profileId}', '${id}', '["PLUMBING"]', '["PLUMBING"]', 250, 'VERIFIED', false, 21.1458, 79.0882);`);

  sql.push(`
INSERT INTO job_credits (id, "userId", balance)
VALUES ('${creditsId}', '${id}', 100);`);

  const token = jwt.sign(
    { sub: id, phoneNumber: phone, role: 'CUSTOMER' },
    JWT_SECRET,
    { expiresIn: '3h' }
  );

  tokens.push({ userId: id, phone, token });
}

sql.push('COMMIT;');

writeFileSync(OUT_SQL, sql.join('\n'));
writeFileSync(OUT_JSON, JSON.stringify(tokens, null, 2));

console.log(`Created ${COUNT} workers`);
console.log(`  SQL : ${OUT_SQL}`);
console.log(`  JWT : ${OUT_JSON}`);
