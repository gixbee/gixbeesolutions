# Architecture fixes rollout

Applies the Instant Help OTP lock, Razorpay checkout intents, rental late-capture refunds, worker availability sync, batched matching Redis reads, and HTTPS preparation.

## Apply (MilesWeb)

`scripts/milesweb_sync_and_deploy.sh` runs `scripts/arch_fixes_v1.sql` **before** rebuilding the API. Order matters:

1. Schema (`arch_fixes_v1.sql`) — nullable `razorpayOrderId`, refund statuses, rental late-capture column.
2. Rebuild/restart `backend_rust` (and admin if needed).
3. HTTPS is **optional** at this step; follow [HTTPS_ROLLOUT.md](./HTTPS_ROLLOUT.md) when ready.

Manual schema-only apply:

```bash
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 \
  < scripts/arch_fixes_v1.sql
```

## Compatibility

- Existing `payment_orders` with a non-null `razorpayOrderId` keep working.
- New checkouts insert an intent (`razorpayOrderId` NULL) then attach the provider id outside the DB lock.
- Webhooks that arrive before attach resolve via `notes.gixbeePaymentOrderId`.
- Booking OTP clients are unchanged; the assigned worker must submit OTPs (matches the Flutter UI).

## Refund recovery

Late rental captures move the payment order to `REFUND_REQUIRED` and enqueue `payment.refund_required`.

- Renter notification: “refund pending” (independent of owner payout).
- Admin: `GET /payments/admin/refund-failures` (admin JWT).
- SQL triage:
  ```sql
  SELECT id, status, "razorpayPaymentId", "refundFailure", meta
  FROM payment_orders
  WHERE status::text IN ('REFUND_REQUIRED','REFUND_PENDING');
  ```
- After a Razorpay-accepted refund and a crash, the outbox retries; “already refunded” is treated as success.

## Rollout failure rollback

1. **API binary** — Redeploy the previous image/tag; leave the additive schema in place (nullable column + enum values are backward compatible).
2. **Stuck CREATED intents** without a provider id — safe to leave; resume on next checkout or mark `FAILED` manually after review.
3. **REFUND_REQUIRED rows** — do not delete; complete refunds in Razorpay dashboard if the outbox cannot, then set `status='REFUNDED'` and `refundedAt=NOW()`.

## Single-VPS residual risk

Compose still colocates PostgreSQL, Redis, uploads, and API replicas on one host. Host failure takes the stack down together.

External work still required for true durability:

- Off-host encrypted backups (`scripts/backup-milesweb.sh` + separate storage) and a restore drill ([milesweb-recovery.md](./milesweb-recovery.md)).
- Off-host object storage for uploads.
- Separate DB standby / second API host behind an independent load balancer for host failover.

## Focused regression checklist

- [ ] Worker OTP arrival/completion succeeds; customer JWT + OTP is rejected.
- [ ] Concurrent completion OTP does not double-bill; repeat submit after COMPLETED is idempotent.
- [ ] `mark-paid` does not insert duplicate outbox when flags are unchanged.
- [ ] Checkout: payment intent row exists before Razorpay HTTP; lock is released during the call.
- [ ] Webhook before attach (intent id in notes) still credits once.
- [ ] Expire rental hold, then capture → `REFUND_REQUIRED`, inventory free, refund outbox runs.
- [ ] Accept then cancel (or complete) with delayed outbox → Redis status matches active bookings; offline workers stay offline.
- [ ] Matching: Redis status/location fetched via MGET batches; busy DB operators excluded.
- [ ] Release Flutter build with `http://` URL refuses to start; `https://` accepted. Debug HTTP still works.
