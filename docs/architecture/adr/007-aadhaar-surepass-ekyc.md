# ADR-007: Aadhaar eKYC — Surepass OTP, Masked Storage Only

**Status:** Accepted (code done 2026-08-28; credentials pending)  
**Date:** 2026-08-28  
**Deciders:** Backend + compliance intent

## Context

Pro verification (Go Live gate) prefers Aadhaar OTP eKYC over DigiLocker. UIDAI rules prohibit storing full Aadhaar numbers. Integration was blocked until Surepass credentials exist on EC2.

## Decision

### Provider

**Surepass** Aadhaar v2 OTP API (`AadhaarKycService`):

| Env var | Role |
|---|---|
| `AADHAAR_CLIENT_ID` | Account id (checked via `isRealSecret`) |
| `AADHAAR_CLIENT_SECRET` | Bearer token for API |
| `AADHAAR_API_BASE` | Optional override; prod default `https://kyc-api.surepass.app` |

When not configured: `ServiceUnavailableException` — never fake a verified result.

### API contract (JWT required)

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/talent/verification/status` | — | `{ configured, verified, maskedAadhaar? }` |
| POST | `/talent/verification/initiate` | — | Legacy DigiLocker stub / redirect info |
| POST | `/talent/verification/generate-otp` | `{ aadhaarNumber: 12 digits }` | `{ clientId, message }` |
| POST | `/talent/verification/submit-otp` | `{ clientId, otp: 6 digits }` | `{ maskedAadhaar, fullName }` → updates worker |

Flow on success:
1. `TalentService.submitAadhaarOtp` → `AadhaarKycService.submitOtp`
2. `WorkersService.recordAadhaarVerification(userId, maskedAadhaar, fullName)`
3. Migration `1754600000000` adds `worker_profiles.maskedAadhaar`

**Full Aadhaar number is never persisted** — only masked reference after UIDAI OTP success.

### Flutter contract

- Register-as-Pro OTP sheet (`register_pro_screen.dart`) → `talent_repository` generate/submit OTP
- Read `verification/status` before showing "Verify with Aadhaar" tile (same pattern as Razorpay gateway-status)

## Consequences

**Positive**
- Compliance-aligned storage (masked only)
- Credential-gated — clear UX when keys missing
- Separated from login OTP (Redis/MSG91) — different trust domain

**Negative**
- P0 blocked on EC2 secrets + migration deploy
- Surepass vendor lock-in; API base URL must match prod/sandbox
- `initiateVerification` legacy path still exists — document or remove in future cleanup

## Contract recommendations

1. **Oscar:** deploy migration `1754600000000` before enabling prod keys; log Surepass failures without leaking Aadhaar in logs
2. **Pam:** do not cache full Aadhaar in Riverpod state longer than the OTP sheet session
3. **god/ops:** Surepass bearer rotation = update `AADHAAR_CLIENT_SECRET` only; no app rebuild required

## Security flags

- Aadhaar OTP endpoints are JWT-authenticated — no anonymous KYC
- Rate-limit consideration: generate-otp should not be hammerable (currently inherits global 120/min — consider tighter `@Throttle` if abuse seen)
