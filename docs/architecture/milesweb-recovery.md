# MilesWeb recovery

The Compose stack shares a host. Two API containers provide process redundancy. A host failure still takes down PostgreSQL, Redis, the load balancer, and local uploads.

## Back up and restore

1. Provision a separate backup host or storage account. Keep the age private identity off the VPS and make the public recipient available to the backup job.
2. Schedule `bash scripts/backup-milesweb.sh` with `GIXBEE_BACKUP_SSH_TARGET`, `GIXBEE_BACKUP_REMOTE_DIR`, and `GIXBEE_BACKUP_AGE_RECIPIENT`. Use a restricted backup account and retention at the destination. Alert on failures and on a missing recent backup.
3. Download a backup to an isolated recovery host. Decrypt it with `age -d -i /path/to/identity -o backup.tar gixbee-TIMESTAMP.tar.age`. Extract it into an empty directory. Restore `database.dump` with `pg_restore --exit-on-error --no-owner --no-privileges --dbname <scratch-database> database.dump` on a fresh PostgreSQL instance with the same extensions available. Recreate application roles separately. Restore `uploads.tar.gz` into a scratch uploads volume.
4. Confirm row counts for users, bookings, payment orders, and credit records. Verify representative uploaded files and start the Rust API against the restored database with external providers disabled or configured for testing. Record the elapsed restore time and when the snapshot was taken.

The database dump is consistent by itself. The uploads archive is taken separately, so use a quiet period or pause upload writes if both must represent the same instant. A database and uploads backup does not include production secrets, DNS configuration, or deployment credentials. Keep those in a separate recovery store.

## Availability

- Monitor `GET /readyz`. A PostgreSQL failure returns HTTP 503. A Redis failure is reported in the response while database-backed routes remain ready.
- Move PostgreSQL and uploads to independent storage before claiming host-level failover. Put API replicas on separate hosts behind an independent load balancer when the uptime target requires it. Standby PostgreSQL, Redis availability, and off-host uploads require provisioned targets.
- Recent pending rental and fee orders are checked against Razorpay for 24 hours. After release, review terminal outbox failures by event ID. For a captured payment that failed before this release, compare Razorpay's payment reference and amount to the booking or account effect before correcting it. Older orders marked credited need this review because their status alone cannot prove delivery. The API's owned-order verification endpoint can recover supported orders that are still pending.
