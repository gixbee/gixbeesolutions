# HTTPS rollout (MilesWeb)

Prepare TLS **before** shipping a release APK that enforces HTTPS. Local `flutter run` / debug builds may still use `http://`.

## What you must configure

1. **DNS** — Point `api.<your-domain>` (and optionally the admin hostname) at the MilesWeb VPS public IP (`103.102.234.152` today).
2. **Certificates** — Place Let’s Encrypt (or equivalent) files on the host:
   - `fullchain.pem`
   - `privkey.pem`
   - Default mount: `GIXBEE_TLS_CERT_DIR` → `/etc/nginx/ssl` inside `api_balancer` (compose defaults to `./nginx/ssl`).
3. **Nginx config** — After certs exist:
   ```bash
   cp nginx/lb.https.conf nginx/lb.conf
   # In docker-compose.yml under api_balancer.ports, uncomment:
   # - "80:80"
   # - "443:443"
   docker compose up -d api_balancer
   ```
4. **Firewall** — Allow inbound TCP `80` and `443`. Keep `3000` only for cutover healthchecks, then restrict it.
5. **Razorpay webhook** — Update the dashboard URL to  
   `https://api.<your-domain>/payments/webhook`  
   (same path; HMAC secret unchanged). Replay a test capture after cutover.
6. **Flutter release** — Rebuild APK/IPA with HTTPS dart-defines:
   ```text
   --dart-define=API_BASE_URL=https://api.<your-domain>
   --dart-define=SOCKET_URL=https://api.<your-domain>
   ```
   Release builds **reject** loopback and cleartext `http://` URLs.
7. **Angular admin** — Serve admin over HTTPS (terminate TLS on `:443` for the admin container or put it behind the same edge). The SPA already uses same-origin `/api/` proxy; ensure `X-Forwarded-Proto` is `https`.

## Cutover order

1. Issue certs and switch `lb.conf` → `lb.https.conf` while old HTTP `:3000` clients still work.
2. Update Razorpay webhook to HTTPS; confirm captures land.
3. Ship the HTTPS APK.
4. Optionally close public `:3000` after clients migrate.

## Rollback

Restore `nginx/lb.conf` from the HTTP template in git, comment out `80`/`443` ports, and `docker compose up -d api_balancer`. Existing HTTP clients keep working; HTTPS-only APKs will fail until certs/config return.
