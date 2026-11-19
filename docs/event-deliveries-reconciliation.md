# Photography deliveries and direct-payment reconciliation

This feature extends the existing **quote-first event bookings** and **immutable milestone schedules**. It does **not** transfer money, verify third-party bank transactions, automatically issue refunds, or let one party unilaterally adjudicate a payment dispute.

## Storage, privacy and authorization
- Delivery files are stored in private PostgreSQL `bytea` rows in `event_delivery_revisions`, not the publicly served `/uploads` folder.
- All read/write routes require a valid JWT and event quote participant identity. Only the owning photography vendor uploads; only the customer approves/requests revisions. Both can download their own quote's files.
- Supported: real JPEG, PNG, WebP, PDF or ZIP by file-signature + extension, one file per delivery milestone revision, maximum **12 MiB** per file, **30 revisions** per milestone and **256 MiB** total delivery storage per quote. A ZIP can contain multiple photographs or an album; no server-side unzip or media processing occurs.
- Each upload records SHA-256, filename, original byte content, uploader, version and timestamp; revisions are immutable. The latest version can be replaced only after a customer revision request.
- The customer approves the **latest submitted** version, which completes that delivery milestone. A revision request requires a written reason and leaves the milestone incomplete.
- No content antivirus, transcoding, watermarking or external object storage is provided; configure operational content scanning before accepting untrusted archives at scale.

## Direct-payment reconciliation
- The customer reports a specific payment milestone's exact agreed amount, method, receipt/reference identifier and optional note.
- The customer may attach up to five private receipt PDF/image files (maximum 5 MiB each, **64 MiB** total receipt storage per quote) to an active payment report. Both participants can download them through an authenticated endpoint. File signatures are checked and each receipt is hashed; submitted receipts are **unverified evidence**, not a bank statement confirmation.
- The server derives the amount from the milestone (the customer cannot override the quote). The vendor either **confirms receipt** or **contests the claim**.
- Confirmation completes the corresponding payment milestone and writes both sides' milestone acknowledgement audit entries.
- A contested claim opens a dispute. Either participant may open a dispute on an incomplete installment, add auditable notes and cast their own resolution vote.
- A dispute closes only if **both** choose `SETTLED` or both choose `UNPAID`. `SETTLED` completes the milestone; `UNPAID` rejects the reported payment and allows the customer to submit a new report.
- Disputed milestones block the legacy full-payment and completion actions until the dispute is resolved.
- Reporting a payment does **not** prove the transfer occurred. Vendor confirmation is not independent verification. For unresolved disputes, contact support outside the app; there is no admin adjudication endpoint in this version.

## REST endpoints (authenticated)
- `GET/POST /events/quotes/{quoteId}/deliveries/{milestoneId}`
- `POST /events/quotes/{quoteId}/deliveries/{milestoneId}/review`
- `GET /events/quotes/{quoteId}/deliveries/file/{fileId}`
- `GET/POST /events/quotes/{quoteId}/payments/{milestoneId}`
- `POST /events/quotes/{quoteId}/payments/{milestoneId}/review`
- `GET/POST /events/quotes/{quoteId}/payments/{milestoneId}/evidence`
- `GET /events/quotes/{quoteId}/payments/evidence/{fileId}`
- `GET/POST /events/quotes/{quoteId}/disputes`
- `POST /events/quotes/{quoteId}/disputes/{disputeId}/message`
- `POST /events/quotes/{quoteId}/disputes/{disputeId}/resolve`

## Migration and rollout
Run **after** `scripts/azure_event_quote_milestones.sql`:

```bash
docker exec -i gixbee_postgres psql -U postgres -d gixbee_db -v ON_ERROR_STOP=1 -f - < scripts/azure_event_delivery_payments.sql
```

`scripts/azure_sync_and_deploy.sh` includes this migration before starting the Rust image. Before deployment, take a database backup and validate the change on a disposable clone; rollback the application binary if necessary. The additive tables can remain on rollback. Do **not** drop the new tables after users upload files (that would delete delivery history and evidence). For a clean, unused test database, the reverse order is: `event_quote_dispute_events`, `event_quote_disputes`, `event_payment_evidence`, `event_payment_reports`, `event_delivery_revisions`.

## Acceptance tests
1. Two independent JWT accounts: customer and verified business owner. Stranger must receive 404 on listing/download/report/review and dispute routes.
2. Vendor upload v1, customer request revision with reason, vendor upload v2, customer approve; download v1/v2 as either participant, outsider forbidden.
3. MIME spoofing and payload over 12 MiB rejected, no public URL to private assets.
4. Customer submits a UPI claim for the exact agreed milestone amount; owner confirms only after independent receipt check; milestone completes. A duplicate submission or vendor double-confirm cannot create extra acknowledgements.
5. Vendor contests a claim; both can append notes. Mismatched votes keep dispute open; matching votes close it. `UNPAID` permits a fresh report; `SETTLED` completes the milestone. Neither party can vote as the other.
6. Simultaneous submissions/reviews use quote-level locks. Test on a disposable PostgreSQL instance with the migration applied.
7. Verify both Flutter themes and physical-device save/download behavior, large PDF/ZIP upload, recovery after network failure, and APK build. These runtime checks are required before release.

## Limits
Version history is immutable but stored directly in PostgreSQL to preserve per-quote access checks across replicas. For large video/RAW/photo packages or high-scale traffic, migrate private media to object storage with short-lived authorized downloads, checksums, malware scanning, quota enforcement and retention policy. Payment reconciliation remains **participant-attested**, not gateway/bank-verified. A future admin dispute workflow requires independent authorization and a separate operational policy.
