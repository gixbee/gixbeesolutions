# ADR-009: Rust Backend Drop-In Replacement

**Status:** Accepted  
**Date:** 2026-09-07  
**Deciders:** Backend + architecture

## Context

Gixbee runs NestJS 11 as a modular monolith. A Rust rewrite (`backend_rust/`) must be a binary-compatible replacement: same REST paths, JWT secrets, Redis keys, Postgres schema, and Socket.IO contract. Clients (Flutter, admin) keep hitting `:3000` via Nginx.

## Decision

1. **Single crate** `backend_rust/` (Axum + sqlx + redis + socketioxide).
2. **Shared schema** — no Rust-owned migrations while Nest can still run; sqlx uses quoted camelCase columns matching TypeORM.
3. **Infra flip** — `BACKEND_IMPL=nest|rust` sets Docker Compose profile; both services register network alias `api`; Nginx and admin proxy `http://api:3000`.
4. **Nest remains fallback** until Rust passes contract tests; one env var rolls back.

## Switch

```bash
# Development
BACKEND_IMPL=rust make dev

# Production
BACKEND_IMPL=rust make prod

# Rollback
BACKEND_IMPL=nest make prod
```

Root `.env` or `.env.example`:

```
BACKEND_IMPL=nest
COMPOSE_PROFILES=${BACKEND_IMPL}
```

## Consequences

**Positive**
- Performance and memory footprint improve with Rust.
- Same Postgres, Redis, uploads volume, and `.env` secrets.
- Zero Flutter / admin URL changes.

**Negative**
- Two implementations must stay in sync until Nest is retired.
- Socket.IO Redis adapter parity requires ongoing validation across replicas.

## Review trigger

Retire Nest when Rust passes full contract test suite in CI and runs in production for 30 days without rollback.
