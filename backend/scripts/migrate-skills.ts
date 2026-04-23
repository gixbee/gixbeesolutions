import { Client } from 'pg';
import * as dotenv from 'dotenv';
import * as path from 'path';
import { randomUUID } from 'crypto';

// Load environment variables from .env
dotenv.config({ path: path.join(__dirname, '..', '.env') });

async function migrateSkills() {
  const client = new Client({
    host: process.env.DATABASE_HOST,
    port: parseInt(process.env.DATABASE_PORT || '5432'),
    user: process.env.DATABASE_USER,
    password: process.env.DATABASE_PASSWORD,
    database: process.env.DATABASE_NAME,
  });

  try {
    await client.connect();
    console.log('Connected to database.');

    // Fetch all profiles with legacy skills
    const res = await client.query('SELECT id, skills, "hourlyRate" FROM talent_profiles WHERE skills IS NOT NULL');
    console.log(`Found ${res.rows.length} profiles to check for migration.`);

    let migrationCount = 0;

    for (const row of res.rows) {
      const profileId = row.id;
      const skillsStr = row.skills; // simple-array is comma-separated text in DB
      const globalRate = row.hourlyRate || 100;

      if (!skillsStr) continue;

      const skills = skillsStr.split(',').filter((s: string) => s.trim().length > 0);
      
      // Check if this profile already has records in professional_skills
      const existingCheck = await client.query('SELECT id FROM professional_skills WHERE "talentProfileId" = $1', [profileId]);
      
      if (existingCheck.rows.length > 0) {
        console.log(`Profile ${profileId} already has ${existingCheck.rows.length} skills in new table. Skipping.`);
        continue;
      }

      console.log(`Migrating ${skills.length} skills for profile ${profileId}...`);

      for (const skillName of skills) {
        await client.query(`
          INSERT INTO professional_skills (id, name, "hourlyRate", status, "talentProfileId", "createdAt", "updatedAt")
          VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
        `, [
          randomUUID(),
          skillName.trim(),
          globalRate,
          'APPROVED', // Set to approved since they were previously verified
          profileId
        ]);
        migrationCount++;
      }
    }

    console.log(`Migration complete! Created ${migrationCount} professional skill records.`);

  } catch (err) {
    console.error('Migration failed:', err);
  } finally {
    await client.end();
  }
}

migrateSkills();
