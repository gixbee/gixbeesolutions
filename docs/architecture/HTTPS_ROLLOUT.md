# HTTPS rollout on MilesWeb

Before releasing an APK, point the public API hostname and a distinct admin hostname at the VPS. Open inbound ports 80 and 443. Use a certificate covering both hostnames and store its files outside the release directory so they survive the release script's directory swap.

Set these values in the project root `.env`.

```dotenv
GIXBEE_API_HOST=api.example.com
GIXBEE_ADMIN_HOST=admin.example.com
GIXBEE_TLS_CERT_DIR=/persistent/path/to/tls
GIXBEE_DB_ADMIN_PASSWORD=<rotated-postgres-secret>
GIXBEE_APP_DB_PASSWORD=<separate-runtime-secret>
GIXBEE_APP_DATABASE_URL=postgres://gixbee_app:<url-encoded-runtime-secret>@pgbouncer:6432/gixbee_db
```

The directory must contain `fullchain.pem` and `privkey.pem`, readable by the edge container. If you use the ACME webroot for renewal, set `GIXBEE_CERTBOT_WEBROOT` to a persistent directory and reload the edge after certificates renew.

Prepare strong production secrets in `deploy/.env` before running the release. The MilesWeb script automatically loads `docker-compose.production.yml`. It sets the Rust API to production mode, serves both hosts at the edge, and exposes ports 80 and 443. The API probe uses the private listener inside the edge container. Local development can use the base Compose file with HTTP.

On the existing PostgreSQL instance, create `gixbee_app` as a LOGIN role without superuser, role creation, database creation, replication, row-security bypass, or inherited group memberships. Set its password with psql `\password gixbee_app`. Use the same secret in PgBouncer and the runtime URL. Rotate the existing PostgreSQL admin password separately with `\password postgres`; the container environment only initializes the password when the data volume is empty. The release applies migrations as `postgres` and applies the runtime grants before starting the API.

The release checks the certificate chain, both hostnames, the TLS private key, and the staged Rust production configuration before moving the release directory. A failed check stops the release before the directory swap.

Configure Razorpay to use `https://api.example.com/payments/webhook` and verify a test capture. Verify that the admin sign-in, API readiness, and Socket.IO connection work over HTTPS. Then build Flutter with `API_BASE_URL=https://api.example.com` and `SOCKET_URL=https://api.example.com`. Existing clients configured with public port 3000 require an updated build before this cutover.

For an application rollback, restore the previous API and admin images behind the same HTTPS edge. Keep the new nullable columns in place only if the old code can read checkout intents and refund states. Review incompatible pending rows before rolling back to a version that assumes an attached provider order for every payment.
