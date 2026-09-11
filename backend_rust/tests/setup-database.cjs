// Creates only an explicitly named local contract-test database. Never load .env.
const { createRequire } = require('node:module');
const path = require('node:path');
const fs = require('node:fs');
const requireBackend = createRequire(path.resolve(__dirname, '../../backend/package.json'));
requireBackend('reflect-metadata');
const { Client } = requireBackend('pg');
const { DataSource } = requireBackend('typeorm');

async function main() {
  const url = new URL(process.env.GIXBEE_TEST_DATABASE_URL || '');
  const name = url.pathname.slice(1);
  if (!['127.0.0.1', 'localhost'].includes(url.hostname) || !/^gixbee_contract_[a-z0-9_]+$/.test(name)) {
    throw new Error('Use a local gixbee_contract_* database; this script refuses other targets');
  }
  const adminUrl = new URL(url);
  adminUrl.pathname = '/postgres';
  const admin = new Client({ connectionString: adminUrl.toString() });
  await admin.connect();
  try {
    const exists = await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [name]);
    if (!exists.rowCount) await admin.query(`CREATE DATABASE "${name}"`);
  } finally { await admin.end(); }
  const root = path.resolve(__dirname, '../../backend/dist/src');
  if (!fs.existsSync(root)) throw new Error('Run the Nest build to obtain its entity schema first');
  const db = new DataSource({ type: 'postgres', url: url.toString(),
    entities: [root.replaceAll('\\', '/') + '/**/*.entity.js'],
    synchronize: true, logging: false });
  await db.initialize();
  try {
    const rows = await db.query("SELECT count(*)::int AS count FROM information_schema.tables WHERE table_schema = 'public'");
    console.log(`Isolated contract schema ready: ${name}, ${rows[0].count} tables`);
  } finally { await db.destroy(); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
