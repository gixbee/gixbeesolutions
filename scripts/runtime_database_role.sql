-- The role password is provisioned separately with psql \password.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname='gixbee_app' AND rolcanlogin
            AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
            AND NOT rolreplication AND NOT rolbypassrls
    ) OR EXISTS (
        SELECT 1 FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member
        WHERE r.rolname='gixbee_app'
    ) THEN
        RAISE EXCEPTION 'Provision gixbee_app as a restricted LOGIN role before release';
    END IF;
END $$;

GRANT CONNECT ON DATABASE gixbee_db TO gixbee_app;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO gixbee_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO gixbee_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO gixbee_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO gixbee_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO gixbee_app;
