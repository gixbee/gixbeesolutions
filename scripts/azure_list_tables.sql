SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1;
SELECT COUNT(*) AS table_count FROM pg_tables WHERE schemaname = 'public';
