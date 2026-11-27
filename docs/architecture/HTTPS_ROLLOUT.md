# HTTPS rollout on MilesWeb

Before releasing an APK, point the public API hostname and a distinct admin hostname at the VPS. Open inbound ports 80 and 443. Use a certificate covering both hostnames and store its files outside the release directory so they survive the release script's directory swap.

Set these values in the project root `.env`.

```dotenv
GIXBEE_API_HOST=api.example.com
GIXBEE_ADMIN_HOST=admin.example.com
GIXBEE_TLS_CERT_DIR=/persistent/path/to/tls
```

The directory must contain `fullchain.pem` and `privkey.pem`, readable by the edge container. If you use the ACME webroot for renewal, set `GIXBEE_CERTBOT_WEBROOT` to a persistent directory and reload the edge after certificates renew.

Prepare strong production secrets in `deploy/.env` before running the release. The MilesWeb script automatically loads `docker-compose.production.yml`. It sets the Rust API to production mode, serves both hosts at the edge, and exposes ports 80 and 443. The API probe uses the private listener inside the edge container. Local development can use the base Compose file with HTTP.

Configure Razorpay to use `https://api.example.com/payments/webhook` and verify a test capture. Verify that the admin sign-in, API readiness, and Socket.IO connection work over HTTPS. Then build Flutter with `API_BASE_URL=https://api.example.com` and `SOCKET_URL=https://api.example.com`. Existing clients configured with public port 3000 require an updated build before this cutover.

For an application rollback, restore the previous API and admin images behind the same HTTPS edge. Keep the new nullable columns in place only if the old code can read checkout intents and refund states. Review incompatible pending rows before rolling back to a version that assumes an attached provider order for every payment.
