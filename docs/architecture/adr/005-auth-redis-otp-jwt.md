# ADR-005: Auth — Redis OTP + JWT (REST and WebSocket)

**Status:** Accepted  
**Date:** 2026-07 (hardened 2026-08-28 MSG91)  
**Deciders:** Backend + security audit

## Context

Gixbee uses phone OTP as the sole customer login path. Admin staff use username/password. Realtime features (chat, GPS, voice) need authenticated WebSocket connections across 2 backend replicas.

Prior vulnerabilities: OTP echoed in HTTP responses when `NODE_ENV=development`, non-atomic OTP verify (replay window), WS identity taken from message body fields.

## Decision

### Login OTP flow

```
POST /auth/request-otp { phone }
  → 6-digit OTP → Redis key otp:{phone} (5 min TTL)
  → MSG91 v5 Flow via SmsService (production required)
  → Response: { message } only — devOtp ONLY if ALLOW_OTP_ECHO=true AND not production

POST /auth/verify-otp { phone, otp }
  → Redis atomic GETDEL (consumeOtp)
  → Upsert User → JWT accessToken + refreshToken
  → Throttle: 5 request-otp/min, 10 verify-otp/min per IP
```

Production boot (`main.ts`) refuses: weak JWT, default admin creds, `ALLOW_OTP_ECHO=true`, missing MSG91 keys.

### Token model

| Token | Use |
|---|---|
| Access JWT | `Authorization: Bearer` on REST; `auth.token` on Socket.IO |
| Refresh JWT | `POST /auth/refresh` — Dio interceptor in `auth_repository.dart` |

JWT payload carries `userId`; admin tokens add `role: ADMIN` and `pages[]` for page ACL.

### WebSocket auth

- `WsJwtGuard` on all gateways — identity from verified JWT only
- Personal rooms: server derives `userId` from token (ignore body `userId`)
- Job rooms: membership verified against `Booking` entity

### Admin auth

- `POST /auth/admin-login` → staff JWT with `pages[]` from `AdminStaff`
- `AdminGuard` + `@RequireAdminPage()` on admin API routes
- Angular `pageGuard` mirrors backend ACL keys

## API contract (Flutter ↔ NestJS)

| Endpoint | Client | Notes |
|---|---|---|
| `POST /auth/request-otp` | `auth_repository.requestOtp` | Never expect `devOtp` in prod |
| `POST /auth/verify-otp` | `auth_repository.verifyOtp` | Stores tokens via `auth_token_service` |
| `POST /auth/refresh` | Dio interceptor | Auto on 401 |
| `GET /auth/profile` | `currentUserProvider` | No wallet/FCM in response |
| `PATCH /auth/fcm-token` | post-login in `main_wrapper` | Legacy alias kept |

**Do not change** response shapes without updating `auth_repository.dart` and admin `auth.service.ts`.

## Consequences

**Positive**
- OTP replay closed; SMS gated in production
- Consistent identity on REST + WS
- Brute-force throttled on auth routes

**Negative**
- Dev without MSG91 relies on console OTP log (non-production only)
- Stale specs (`jwt.strategy.spec`) don't cover admin `pages`/`staffRole` — rewrite needed (see GAPS.md)

## Contract recommendations

1. Oscar: any new auth endpoint must use `@Throttle` — don't rely on global 120/min alone
2. Pam: FCM registration must stay on login path; token refresh on app resume
3. Never add OTP to HTTP response without explicit `ALLOW_OTP_ECHO` audit
