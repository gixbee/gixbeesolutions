SELECT "createdAt", message, detail FROM system_logs WHERE level = 'ERROR' OR type = 'APP_CRASH' ORDER BY "createdAt" DESC LIMIT 5;
