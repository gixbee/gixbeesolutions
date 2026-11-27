#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${GIXBEE_BACKUP_SSH_TARGET:?Set the off-host backup SSH target}"
: "${GIXBEE_BACKUP_REMOTE_DIR:?Set the backup directory on the remote host}"
: "${GIXBEE_BACKUP_AGE_RECIPIENT:?Set the public age recipient for encryption}"
[[ "$GIXBEE_BACKUP_REMOTE_DIR" =~ ^/[A-Za-z0-9/_-]+$ ]] || {
    echo "Use a simple absolute remote backup directory." >&2
    exit 2
}
[[ "$GIXBEE_BACKUP_SSH_TARGET" != -* ]] || exit 2

stamp=$(date -u +%Y%m%dT%H%M%SZ)
work=$(mktemp -d)
trap 'rm -f -- "$work/database.dump" "$work/uploads.tar.gz" "$work/backup.tar.age"; rmdir -- "$work"' EXIT

docker exec gixbee_postgres sh -c 'pg_dump --format=custom -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$work/database.dump"
docker exec -i gixbee_postgres pg_restore --list < "$work/database.dump" > /dev/null
docker exec gixbee_api_balancer tar -czf - -C /app/uploads . > "$work/uploads.tar.gz"
tar -cf - -C "$work" database.dump uploads.tar.gz |
    age -r "$GIXBEE_BACKUP_AGE_RECIPIENT" -o "$work/backup.tar.age"

remote="$GIXBEE_BACKUP_REMOTE_DIR/gixbee-$stamp.tar.age"
ssh -o BatchMode=yes "$GIXBEE_BACKUP_SSH_TARGET" \
    "umask 077; cat > '$remote.part' && mv -- '$remote.part' '$remote'" < "$work/backup.tar.age"
echo "Uploaded encrypted backup gixbee-$stamp.tar.age"
