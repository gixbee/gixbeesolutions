# Architecture Gap List vs CURRENT_STATUS.md

> Baseline audit **2026-08-30** (Jim). Cross-check against [../CURRENT_STATUS.md](../CURRENT_STATUS.md).

Legend: **Doc** = documentation gap · **Contract** = API/client alignment · **Ops** = deployment/secrets · **Risk** = security/scalability

---

## P0 — Production blockers (ops, not code)

| Gap | CURRENT_STATUS | Architecture note | Owner |
|---|---|---|---|
| MSG91 keys on EC2 | SMS OTP code done | Auth ADR-005; prod boot exits without keys | god/ops |
| Razorpay live keys + webhook | Payments code done | ADR-006; APK needs `--dart-define=RAZORPAY_KEY` | god/ops |
| Surepass Aadhaar keys | eKYC code done | ADR-007; migration `1754600000000` not deployed | Oscar + ops |
| Secret rotation (JWT/admin/DB) | Listed P0 | `main.ts` assertProductionSecrets enforces at boot | god/ops |
| `NODE_ENV=production` on EC2 | Listed P0 | Compose reads `${NODE_ENV:-development}` — mis-set leaves dev behaviour | ops |

**Architecture assessment:** Code paths are complete and fail-closed. No NestJS/Flutter structural changes required — only secrets + migration + APK rebuild.

---

## P1 — Consistency & contract gaps

| Gap | Status | Recommendation |
|---|---|---|
| **Stale backend specs** | Open (CURRENT_STATUS P1) | Rewrite `jwt.strategy`, `payments.service` specs to match admin `pages` and renamed methods — does not affect prod behaviour |
| **PhonePe/UPI stub** | Open (payments P0 notes) | UI must gate on `gateway-status.upi.available === false`; remove misleading copy if any remains |
| **Wallet UI vs wallet OFF** | Implicit gap | Flutter `wallet_screen` + `wallet_repository` still ship; ADR-001 documents dormant path — Pam should keep wallet screens behind `gateway-status.wallet.available` |
| **Flutter APK rollout** | Open P1 | Petrol + late-cancel UI require new APK; backend already live — coordinate release build |
| **`.gitignore` firebase pattern** | Open P1 | Add `*firebase-adminsdk*.json` at repo root |

---

## P2 — Documentation & polish

| Gap | Status | Recommendation |
|---|---|---|
| **Architecture docs** | **Closed** (this audit) | `ARCHITECTURE.md` + ADRs 001–007 + this file |
| **April backlog docs** | Removed 2026-07-18 | Use git history only — no restore needed |
| **Theme debt** | P2 open | ~booking shell chrome; intentional semantic colors documented in CURRENT_STATUS |
| **`cached_network_image` package** | Optional P2 | Performance polish, not architectural |

---

## Security risks (flagged to god)

| Risk | Severity | Mitigation in code | Residual |
|---|---|---|---|
| Weak JWT on deploy | Critical | Boot exit in production | Ops must rotate before `NODE_ENV=production` |
| OTP echo bypass | Critical | `ALLOW_OTP_ECHO` blocked at prod boot | Ensure EC2 `.env` never sets it |
| **Self-service ADMIN role PATCH (ARCH-001)** | **Critical** | **Fixed** (2026-08-30) — PATCH rejects privileged fields for non-admin; `AdminGuard` requires portal `staffRole` (blocks mobile JWT on all portal routes incl. `admin-staff/pages` + `/me`) | Smoke on prod deploy |
| User search / GET by id phone leak (ARCH-002) | High | **Fixed** (2026-08-30) — self-or-admin `:id`; search min 3 chars; phone omitted for non-admin JWT | Smoke on prod deploy |
| Razorpay client-only credit | High | Webhook-only fulfilment (ADR-006) | Webhook URL + secret must be live |
| WS room hijack | High | JWT-derived rooms (ADR-002) | Contract: never trust body userId |
| Aadhaar data retention | High | Masked storage only (ADR-007) | Audit logs must not print full Aadhaar |
| CORS `origin: *` | Medium | Acceptable — JWT in header not cookies | Revisit if cookie auth added |
| Global 120/min throttle | Medium | Auth routes have tighter limits | Aadhaar generate-otp may need dedicated `@Throttle` |
| PgBouncer session features | Medium | Documented ban (ADR-003) | Code review on new Postgres usage |

---

## Scalability notes

| Area | Current state | Growth trigger |
|---|---|---|
| Backend replicas | 2 + Redis Socket.IO adapter | Add replicas when CPU > 70% sustained; Redis adapter mandatory |
| PgBouncer pool | 40 server conns | Monitor pool wait; raise `DEFAULT_POOL_SIZE` before adding many replicas |
| Instant broadcast fan-out | FCM parallel + Redis pending | Watch wave-2 rebroadcast volume in high-density cities |
| Master entries cache | Hard cap 2000 on miss | OK today; paginate admin if catalog grows |
| Outbox poller | 5s safety net, stable Bull jobId | Do not change jobId without prune logic (already in `OutboxDispatcher`) |
| EBS disk | Tight on EC2 P1 | Image builds may fail — grow volume |

---

## Cross-team contract watchlist

Before Oscar or Ryan ship cross-cutting changes, verify against [ARCHITECTURE.md §11](./ARCHITECTURE.md#11-api-contract-review-checklist):

1. `money-model.ts` — no new wallet charges while OFF
2. FCM `data.type` ↔ `main_wrapper.dart` `_bookingStateTypes`
3. Outbox event types ↔ `BookingLifecycleHandler`
4. `PaymentPurpose` enum ↔ webhook fulfilment branch
5. Talent `/verification/*` ↔ `talent_repository.dart`
6. Auth token refresh ↔ Dio interceptor paths

**Pam** owns Flutter-side alignment; **Oscar** owns NestJS modules (`auth`, `sms`, `payments`, `talent`, `outbox`).

---

## Audit deliverables checklist

| Deliverable | Status |
|---|---|
| `docs/architecture/ARCHITECTURE.md` | Done |
| ADRs: auth | Done → [adr/005-auth-redis-otp-jwt.md](./adr/005-auth-redis-otp-jwt.md) |
| ADRs: payments | Done → [adr/006-payments-razorpay-webhook-only.md](./adr/006-payments-razorpay-webhook-only.md) |
| ADRs: eKYC | Done → [adr/007-aadhaar-surepass-ekyc.md](./adr/007-aadhaar-surepass-ekyc.md) |
| Gap list vs CURRENT_STATUS | Done (this file) |
| Feature implementation | None (doc-only per boundary) |

---

## Architecture issue hunt (2026-08-30)

Issues found cross-checking code vs `ARCHITECTURE.md` / ADRs. Severity: **Critical** → fix before prod; **High** → next security sprint; **Medium** → contract/coupling debt; **Low** → cleanup/docs.

| ID | Sev | Module | Issue | File refs | Recommendation |
|---|---|---|---|---|---|
| **ARCH-001** | **Critical** | `users` / auth | ~~Self-service role escalation~~ **Fixed 2026-08-30.** Non-admin PATCH with `role`/`hasWorkerProfile` → 403 (`users.controller.ts` L96–107). Service only persists privileged fields when `allowPrivilegedFields` (`users.service.ts` L74–78). `AdminGuard` rejects JWTs without portal `staffRole` (`admin.guard.ts` L36–38) — mobile tokens cannot reach `admin-staff/pages`, `/me`, or any portal route. | `users.controller.ts` L86–107, `users.service.ts` L61–78, `admin.guard.ts` L33–38 | **Closed** — smoke tests in PROD_DEPLOY § Security |
| **ARCH-002** | **High** | `users` | ~~User lookup privacy~~ **Fixed 2026-08-30.** `GET :id` self-or-admin (`users.controller.ts` L73–78). Search requires ≥3 chars; `phoneNumber` omitted unless admin JWT (`users.controller.ts` L69–70, `users.service.ts` L121, L129–130). Operator picker uses id/name/role only. | `users.controller.ts` L61–78, `users.service.ts` L113–131, `business_repository.dart` L62 | **Closed** — smoke tests in PROD_DEPLOY § Security |
| **ARCH-003** | **Medium** | Flutter payments | **Split payment repositories:** `payment_repository.dart` (gateway-status, UPI stub) vs `payments_repository.dart` (late-cancel order). `GatewayStatus.fromJson` parses **UPI only** — ignores `razorpay.available`, `wallet.available`, `cash` from backend. | `payment_repository.dart`, `payments_repository.dart`, `payments.service.ts` `getGatewayStatus()` | **Pam:** Merge into one repository; model full gateway-status response per ADR-006. |
| **ARCH-004** | **Medium** | `workers` / billing | ~~Period-fee dual path~~ Backend **fixed 2026-08-30** — `POST /workers/me/pay-period-fee` returns 400 when wallet OFF (`worker-golive.service.ts` L419–422). Live path: `POST /payments/period-fee/order` + webhook. Flutter wallet dev fallback in `go_live_screen.dart` L494–496 still open (**Pam**). | `worker-golive.service.ts` L411–422, `workers.controller.ts` L182, `go_live_screen.dart` L494–496 | **Oscar: closed.** **Pam:** remove wallet fallback |
| **ARCH-005** | **Medium** | `payments` ↔ `hiring` | **Circular module coupling:** `PaymentsService` ↔ `MatchingService` via `forwardRef`; webhook fulfilment for hiring fees lives inside payments. | `payments.module.ts`, `hiring.module.ts`, `payments.service.ts` L60, `matching.service.ts` L63 | Accept for now; document boundary. Long-term: extract `PaymentFulfillmentHandler` or event bus to break cycle. |
| **ARCH-006** | **Medium** | Flutter client | **Wallet UI vs wallet OFF:** `wallet_screen.dart` still exposes balance + Razorpay top-up (`wallet_repository.dart`). Backend wallet charges throw when OFF. Misleading UX. | `wallet_screen.dart`, `wallets.service.ts`, ADR-001 | **Pam:** Hide wallet menu when `gateway-status.wallet.available === false`. |
| **ARCH-007** | **Low** | Flutter conventions | **Dio outside repositories:** Direct `Dio()` in `crash_reporter.dart`, `ola_maps_style_service.dart`, `location_search_delegate.dart`, `live_tracking_route_service.dart` — bypasses JWT interceptor / base URL conventions. | Files above | Accept for third-party URLs; document exceptions in ARCHITECTURE.md §4.1. |
| **ARCH-008** | **Low** | Flutter booking | **Orphan dead code:** `payment_method_screen.dart` defaults `_method = 'WALLET'`; marked orphaned, no call sites. | `payment_method_screen.dart` L4–11, L67 | Delete or archive once committed; prevents accidental re-wiring. |
| **ARCH-009** | **Low** | `talent` / auth | **Aadhaar OTP throttle:** `POST /talent/verification/generate-otp` inherits global 120/min only (ADR-007 note). | `talent.controller.ts` L46 | **Oscar:** Add `@Throttle` (e.g. 3/min) on generate-otp. |

### Contract sync notes (no new gap — already on watchlist)

- FCM `booking_status_update` is primarily **Socket.IO** (`booking-status.service.ts`); listed in `main_wrapper.dart` `_bookingStateTypes` for FCM parity — verify outbox emits FCM if background refresh needed.
- Uploads use shared Docker volume `uploads_data` — OK for 2 replicas (`docker-compose.yml` L217, L242).

---

## Prototype v147 hiring gaps (2026-08-30)

Full study: [PROTOTYPE_v147_HIRING_FLOWS.md](./PROTOTYPE_v147_HIRING_FLOWS.md) · Direction: [ADR-008](./adr/008-v147-profiles-alerts-ux.md).

| ID | Sev | Gap | Owner |
|---|---|---|---|
| **V147-01** | P1 | Seeker IA: prototype Profiles/Alerts/Status vs shipped Jobs/Offers/Job Types/Apps | Kelly + Pam |
| **V147-02** | P1 | No shared job category taxonomy (prototype `cat` catalog vs free-text Job Type) | Kelly + Oscar |
| **V147-03** | P1 | Salary **range** + negotiable on employer/seeker — API has single `salaryOffered` / `expectedSalary` only | Oscar |
| **V147-04** | P1 | Employer `hj1–hj4` wizard vs single `hire_employee_screen` | Jan + Pam |
| **V147-05** | P1 | Monetization: prototype ₹299 unlimited profiles vs shipped ₹50/extra slot | Product/god |
| **V147-06** | N/A | Shop business + flash offers (`s1–s8`) — no SHOP business type | Product (defer) |
| **V147-07** | P2 | Ranked match cards (`mc-*` %) vs flat interest list | Pam |

**Aligned (no gap):** matching engine, Interested privacy gate, estimate/candidate count API, 2 free Job Types, match fee tiers, FCM offers.
