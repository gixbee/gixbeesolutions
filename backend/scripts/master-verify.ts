import { Client } from 'pg';
import * as dotenv from 'dotenv';
import * as path from 'path';

// Load environment variables from .env
dotenv.config({ path: path.join(__dirname, '..', '.env') });

async function verifyAllUsers() {
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

    // Update the specific user and all existing users for testing
    const res = await client.query(`
      UPDATE users 
      SET "isVerified" = true, 
          role = 'ADMIN', 
          "hasWorkerProfile" = true
      RETURNING id, "phoneNumber", "isVerified", role
    `);

    console.log(`Successfully verified ${res.rowCount} users.`);
    console.log('Details:', res.rows);

  } catch (err) {
    console.error('Error executing query:', err);
  } finally {
    await client.end();
  }
}

verifyAllUsers();
