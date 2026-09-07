# ADR-003: PgBouncer Transaction Pooling

**Status:** Accepted  
**Date:** 2026-07  
**Deciders:** Backend + ops

## Context

Under load, direct Postgres connections from TypeORM (default pool ~10) caused pool-timeout failures. Backend runs 2 replicas in production.

## Decision

Insert **PgBouncer** in transaction pooling mode between NestJS and Postgres:

- App connects to PgBouncer (`DATABASE_HOST=pgbouncer`, port 6432)
- `POOL_MODE=transaction` — one server backend per transaction
- TypeORM `extra.max: 50` per replica (cheap client conns to pooler)
- `DEFAULT_POOL_SIZE: 40` real Postgres connections
- `statement_timeout=60s` on Postgres server (not client startup param — PgBouncer rejects it)
- `SERVER_RESET_QUERY=DISCARD ALL` between checkouts

## Constraints (enforced)

**Do NOT use** in application code:
- `LISTEN` / `NOTIFY`
- Session-level advisory locks
- Named `PREPARE` that outlives a transaction

All work stays inside TypeORM transactions or single queries. Documented in `app.module.ts` and `docker-compose.yml`.

## Consequences

**Positive**
- Multiplexes thousands of client connections onto ~40 server connections
- Eliminates TypeORM pool exhaustion under burst traffic

**Negative**
- Cannot use Postgres pub/sub for realtime (Socket.IO + Redis used instead)
- Migration authors must avoid session-scoped patterns
- Debugging requires awareness of pooler layer

## Review trigger

Switching to **session pooling** requires revisiting pool sizing, connection counts, and this ADR.
