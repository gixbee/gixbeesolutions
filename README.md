# Gixbee — The Skill Intelligence Network

> Intent-based multi-service platform for event booking, gig work, job discovery, and vendor management.

---

## Table of Contents

- [What is Gixbee](#what-is-gixbee)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Backend Setup](#backend-setup)
  - [Flutter Setup](#flutter-setup)
- [Environment Variables](#environment-variables)
- [Architecture](#architecture)
- [Feature Modules](#feature-modules)
- [API Endpoints](#api-endpoints)
- [Database Entities](#database-entities)
- [Implementation Status](#implementation-status)
- [What to Implement Next](#what-to-implement-next)
- [Known Issues](#known-issues)

---

## What is Gixbee

Gixbee is an **intent-based** platform — not role-based. A single user can book a hall, work as a driver, and list their own business all in the same session.

After login → OTP → name, the user sees four entry points:

| Entry | Purpose |
|---|---|
| **Book Services** | Plan events (Hall, Catering, Decoration, Photography, Rental) or get Instant Help (Electrician, Driver, Cleaner, Nurse) |
| **Find a Job** | Talent discovery — create a profile, receive job alerts, apply and track application status |
| **Earn by Working** | Live Worker Engine — register skills, go live, accept gig jobs, earn hourly |
| **List My Business** | Register a Service, Hiring, or Rental business; manage units and operators |

**Core principle:** Gixbee facilitates. It never assigns. Every booking, acceptance, and hiring decision is a conscious choice by the user.

---

## Tech Stack

### Flutter (Mobile)
| Package | Purpose |
|---|---|
| `flutter_riverpod` | State management |
| `dio` | HTTP client with JWT interceptor |
| `socket_io_client` | Real-time WebSocket for live worker tracking |
| `firebase_core` / `firebase_messaging` | Push notifications (FCM) |x
| `google_maps_flutter` | Worker location map |
| `geolocator` / `geocoding` | GPS and address resolution |
| `razorpay_flutter` | Payments and wallet top-up |
| `flutter_secure_storage` | JWT token storage |
| `google_fonts` / `flutter_animate` | UI and animations |

### Backend (NestJS)
| Tech | Purpose |
|---|---|
| NestJS + TypeScript | API framework |
| PostgreSQL + TypeORM | Primary database |
| Redis | OTP storage (5-min TTL) + worker location cache |
| Bull + Redis | Background job queue (GPS check, reminders) |
| Socket.IO | Real-time WebSocket gateway |
| JWT | Authentication |
| Firebase Admin SDK | Push notifications (FCM) |

---

## Project Structure

```
gixbee/
├── lib/                          # Flutter app
│   ├── core/
│   │   └── config/
│   │       └── app_config.dart   # Base URL, socket URL, constants
│   ├── data/                     # Repositories (API calls via Dio)
│   │   ├── auth_repository.dart
│   │   ├── booking_repository.dart
│   │   ├── worker_repository.dart
│   │   ├── profile_repository.dart
│   │   └── mock_repository.dart
│   ├── features/
│   │   ├── auth/
│   │   │   ├── login_screen.dart
│   │   │   └── otp_screen.dart
│   │   ├── onboarding/
│   │   │   └── welcome_screen.dart
│   │   ├── home/
│   │   │   ├── home_screen.dart        ⚠️ needs intent-based redesign
│   │   │   ├── banner_carousel.dart
│   │   │   ├── quick_action_button.dart
│   │   │   └── sub_app_button.dart
│   │   ├── booking/
│   │   │   ├── book_services_split_screen.dart
│   │   │   ├── event_location_picker_screen.dart
│   │   │   ├── booking_type_selector.dart
│   │   │   ├── presence_check_screen.dart
│   │   │   ├── arrival_otp_screen.dart
│   │   │   ├── completion_otp_screen.dart
│   │   │   └── booking_screen.dart
│   │   ├── jobs/
│   │   │   ├── find_job_module.dart
│   │   │   ├── talent_profile_screen.dart
│   │   │   ├── job_alerts_screen.dart
│   │   │   ├── application_tracker_screen.dart
│   │   │   ├── register_pro_screen.dart
│   │   │   ├── my_bookings_screen.dart
│   │   │   ├── offers_screen.dart
│   │   │   └── post_job_screen.dart    ⚠️ still a stub
│   │   ├── business/
│   │   │   ├── list_business_type_screen.dart
│   │   │   └── list_business_details_screen.dart
│   │   │                               ⚠️ unit dashboard missing
│   │   ├── profile/
│   │   │   ├── profile_screen.dart
│   │   │   ├── edit_profile_screen.dart
│   │   │   ├── wallet_screen.dart
│   │   │   └── worker_profile_card.dart
│   │   ├── search/
│   │   │   ├── worker_list_screen.dart
│   │   │   └── worker_detail_screen.dart
│   │   ├── map/
│   │   │   └── worker_map_screen.dart  ⚠️ needs jobId-scoped socket
│   │   └── common/
│   │       └── theme_provider.dart
│   ├── models/
│   │   ├── user.dart
│   │   └── worker.dart
│   ├── services/
│   │   ├── auth_token_service.dart
│   │   ├── location_service.dart
│   │   └── socket_service.dart
│   ├── widgets/
│   │   └── glass_container.dart
│   ├── main.dart
│   ├── main_wrapper.dart
│   └── theme.dart
│
├── backend/                      # NestJS API
│   └── src/
│       ├── auth/                 # OTP request, verify, JWT
│       ├── users/                # User entity and CRUD
│       ├── workers/              # Worker profiles, go-live, rate limit
│       ├── worker-engine/        # WebSocket gateway (real-time location)
│       ├── bookings/             # Booking lifecycle + Bull queue jobs
│       ├── wallets/              # Rs.12 balance, deduct, top-up
│       ├── rentals/              # Rental items, calendar, reservations
│       ├── hiring/               # Job posts, applications, pipeline
│       ├── notifications/        # FCM push notification service
│       ├── redis/                # OTP storage + worker location cache
│       ├── app.module.ts         # Root module (all modules registered)
│       └── main.ts               # Bootstrap with CORS
│
├── pubspec.yaml
└── README.md
```

---

## Getting Started

### Prerequisites

- Flutter SDK `>=3.2.0`
- Node.js `>=18`
- PostgreSQL (running locally or via Docker)
- Redis (running locally or via Docker)
- A Firebase project (for FCM push notifications)
- A Google Maps API key

### Backend Setup

```bash
cd backend

# Install dependencies
npm install

# Create your environment file
cp .env.example .env
# Then fill in the values (see Environment Variables below)

# Run in development mode (auto-restarts on changes)
npm run start:dev
```

The backend starts at `http://localhost:3000`

### Flutter Setup

```bash
# From the project root
flutter pub get

# Run on Android emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000

# Run on physical device (replace with your machine's local IP)
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:3000

# Run on iOS simulator
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

> **Note:** Firebase config files are required before running:
> - Android: `android/app/google-services.json`
> - iOS: `ios/Runner/GoogleService-Info.plist`
> Get these from your Firebase project console.

---

## Environment Variables

Create `backend/.env` with the following:

```env
# Database (PostgreSQL)
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USER=postgres
DATABASE_PASSWORD=yourpassword
DATABASE_NAME=gixbee

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# JWT
JWT_SECRET=your_super_secret_jwt_key_here

# Firebase Admin SDK (for FCM push notifications)
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxx@your-project.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"

# SMS Gateway (MSG91 — for OTP delivery)
MSG91_AUTH_KEY=your_msg91_key
MSG91_SENDER_ID=GIXBEE
MSG91_TEMPLATE_ID=your_template_id

# Razorpay (payments)
RAZORPAY_KEY_ID=rzp_test_xxx
RAZORPAY_KEY_SECRET=your_secret

# Server
PORT=3000
```

---

## Architecture

Gixbee uses **Clean Architecture** in Flutter and a **modular NestJS** backend.

```
Flutter App
  └── Presentation (Screens + Riverpod state)
        └── Data Layer (Repositories → Dio → REST API)
              └── NestJS Backend
                    ├── REST API (controllers + services)
                    ├── WebSocket (Socket.IO gateway)
                    ├── Background Jobs (Bull + Redis)
                    └── Database (PostgreSQL via TypeORM)
```

### Key flows

**Live Worker (Instant Help):**
```
Customer selects skill → Service location → Presence check
→ System notifies nearby workers (FCM) → Worker accepts
→ Customer confirms → Movement monitoring starts (Bull job)
→ Worker arrives → Arrival OTP sent to on-site contact
→ Work begins → Worker taps Finish → Completion OTP
→ Customer verifies → Payment → Rs.12 wallet deducted
```

**Plan Services (Hall/Catering/etc):**
```
Customer selects event location → Browse vendors → Check calendar
→ Choose Package or Custom → Send request
→ Vendor approves/rejects → Customer confirms
→ Calendar date blocked → Direct coordination
```

---

## Feature Modules

### Book Services
- **Plan Services**: Hall, Catering, Decoration, Photography, Rental
  - Location-driven (event location, not user GPS)
  - Package or Custom booking type
  - Vendor approval → customer confirmation → calendar block
- **Instant Help**: Electrician, Driver, Cleaner, Nurse
  - Real-time worker dispatch
  - Presence Check + On-Site Contact
  - Full OTP gate flow (Arrival + Completion)
  - Rs.12 wallet per job

### Find a Job
- Talent profile: education, skills, experience, preferences
- Job alerts via push notification
- Application pipeline: APPLIED → INTERVIEW → SELECTED / REJECTED
- No-show penalty: repeated skips lower search ranking

### Earn by Working
- Skill registration with admin verification
- Hourly rate setting (max 2 updates/day)
- Weekly availability schedule
- Go-live toggle (requires Rs.12 wallet balance after first job)
- Strike system: 3 strikes = account suspension

### List My Business
- **Service Business**: Hall, Catering, Decoration, Photography
  - Unit-based model (multiple independent businesses per owner)
  - Calendar management, capacity, offline days
  - Add operators (managers), transfer ownership (OTP + 24hr hold)
- **Hiring Business**: Post jobs, manage HR operators, hiring pipeline
- **Rental Business**: Equipment listing, hourly pricing, day-block calendar

---

## API Endpoints

### Auth
| Method | Endpoint | Description |
|---|---|---|
| POST | `/auth/request-otp` | Send OTP to phone number |
| POST | `/auth/verify-otp` | Verify OTP, returns JWT |
| GET | `/auth/profile` | Get current user profile |

### Workers
| Method | Endpoint | Description |
|---|---|---|
| GET | `/workers` | List all available workers |
| GET | `/workers/:id` | Get worker by ID |

### Bookings
| Method | Endpoint | Description |
|---|---|---|
| POST | `/bookings` | Create a booking (package/custom/instant) |
| GET | `/bookings/my` | Get current user's bookings |
| PATCH | `/bookings/:id/status` | Update booking status |

### Wallets
| Method | Endpoint | Description |
|---|---|---|
| GET | `/wallets/balance` | Get wallet balance |
| POST | `/wallets/add` | Add funds to wallet |

### Rentals
| Method | Endpoint | Description |
|---|---|---|
| GET | `/rentals` | List rental items by location |
| GET | `/rentals/:id/calendar` | Get item availability calendar |
| POST | `/rental-bookings` | Send rental request |
| PATCH | `/rental-bookings/:id/status` | Vendor approve/reject |

### Hiring
| Method | Endpoint | Description |
|---|---|---|
| POST | `/hiring/jobs` | Post a job |
| GET | `/hiring/jobs` | List jobs matching talent profile |
| POST | `/hiring/jobs/:id/apply` | Apply for a job |
| PATCH | `/hiring/applications/:id` | Update application status |

---

## Database Entities

| Entity | Table | Key Fields |
|---|---|---|
| `User` | `users` | id, phoneNumber, name, role, walletBalance, isVerified, fcmToken |
| `WorkerProfile` | `worker_profiles` | userId, skills[], hourlyRate, isActive, isFirstJobDone, noShowCount, strikeCount, rateUpdateCountToday, verificationStatus |
| `Booking` | `bookings` | customerId, operatorId, type, status, skill, serviceLocation, onSiteContact (JSON), arrivalOtp, completionOtp, billingHours |
| `WalletTransaction` | `wallet_transactions` | userId, amount, type (CREDIT/DEBIT), description |
| `RentalItem` | `rental_items` | vendorId, name, category, hourlyRate, minHours |
| `RentalReservation` | `rental_reservations` | itemId, customerId, date, status, billingHours |
| `JobPost` | `job_posts` | businessId, title, skills[], salary, location, status |
| `JobApplication` | `job_applications` | jobId, talentId, status, interviewAccepted, attended |

---

## Implementation Status

### Flutter Screens

| Screen | File | Status |
|---|---|---|
| Welcome / Onboarding | `onboarding/welcome_screen.dart` | ✅ Done |
| Login (Phone) | `auth/login_screen.dart` | ✅ Done |
| OTP Verification | `auth/otp_screen.dart` | ✅ Done |
| Home Screen | `home/home_screen.dart` | ⚠️ Needs intent-based redesign |
| Book Services Split | `booking/book_services_split_screen.dart` | ✅ Done |
| Event Location Picker | `booking/event_location_picker_screen.dart` | ✅ Done |
| Presence Check | `booking/presence_check_screen.dart` | ✅ Done |
| Booking Type Selector | `booking/booking_type_selector.dart` | ✅ Done |
| Booking Screen | `booking/booking_screen.dart` | ✅ Done |
| Arrival OTP | `booking/arrival_otp_screen.dart` | ✅ Done |
| Completion OTP | `booking/completion_otp_screen.dart` | ✅ Done |
| Calendar View | — | ❌ Missing |
| Find a Job | `jobs/find_job_module.dart` | ✅ Done |
| Talent Profile | `jobs/talent_profile_screen.dart` | ✅ Done |
| Job Alerts | `jobs/job_alerts_screen.dart` | ✅ Done |
| Application Tracker | `jobs/application_tracker_screen.dart` | ✅ Done |
| Post a Job | `jobs/post_job_screen.dart` | ❌ Still a stub |
| Register as Pro | `jobs/register_pro_screen.dart` | ✅ Done |
| My Bookings | `jobs/my_bookings_screen.dart` | ✅ Done |
| Offers | `jobs/offers_screen.dart` | ✅ Done |
| List Business Type | `business/list_business_type_screen.dart` | ✅ Done |
| List Business Details | `business/list_business_details_screen.dart` | ✅ Done |
| Business Unit Dashboard | — | ❌ Missing |
| Hiring Pipeline Kanban | — | ❌ Missing |
| Wallet Screen | `profile/wallet_screen.dart` | ✅ Done |
| Profile Screen | `profile/profile_screen.dart` | ✅ Done |
| Edit Profile | `profile/edit_profile_screen.dart` | ✅ Done |
| Worker List | `search/worker_list_screen.dart` | ✅ Done |
| Worker Detail | `search/worker_detail_screen.dart` | ✅ Done |
| Worker Map | `map/worker_map_screen.dart` | ⚠️ Needs jobId-scoped socket |

### Backend Modules

| Module | Status | Pending |
|---|---|---|
| Auth (OTP + JWT) | ✅ Done | Wire Redis for real OTP storage |
| Users | ✅ Done | — |
| Workers | ✅ Done | Go-live toggle, rate-limit enforcement |
| Worker Engine (WebSocket) | ✅ Done | Redis location store in gateway |
| Bookings | ✅ Done | Arrival/Completion OTP endpoints |
| Wallets | ✅ Done | — |
| Rentals | ✅ Done | — |
| Hiring | ✅ Done | Talent matching algorithm |
| Notifications (FCM) | ✅ Structure done | Wire Firebase Admin SDK |
| Redis | ✅ Structure done | Connect to auth OTP flow |
| Businesses | ❌ Missing | Entire module needed |
| Talent Profiles | ❌ Missing | Entity + endpoints needed |

---

## What to Implement Next

### Priority 1 — Unblocks core flows

1. **`home_screen.dart` — intent-based redesign**
   Replace the generic service category grid with 4 large entry cards:
   Book Services → Find a Job → Earn by Working → List My Business

2. **`calendar_screen.dart` — booking calendar**
   3-state date picker: Available (green) / Pending (yellow) / Booked (red).
   Used by Plan Services (Hall, Catering etc.) and Rental.

3. **`post_job_screen.dart` — currently a stub**
   Build the full job posting form (title, skills, salary, location).

4. **Backend: Redis wired into `auth.service.ts`**
   OTP currently accepts any 6 digits. Must store in Redis with 5-min TTL and verify properly.

5. **Backend: Arrival + Completion OTP endpoints**
   Add `POST /bookings/:id/arrive` and `POST /bookings/:id/complete` to `bookings.controller.ts`.

### Priority 2 — Complete modules

6. **Backend: `businesses/` module**
   `list_business_type_screen.dart` and `list_business_details_screen.dart` exist but have no API to call.

7. **Backend: `talent/` entity and endpoints**
   `talent_profile_screen.dart` has no save target in the backend.

8. **`worker_map_screen.dart` — scoped to job room**
   Currently may show all location events. Must filter by active `jobId` using the fixed socket gateway.

9. **Business unit dashboard screen**
   After a business is listed and verified, owner needs a card grid to manage units.

10. **Hiring Pipeline Kanban screen**
    Visual APPLIED → INTERVIEW → SELECTED / REJECTED board for HR operators.

### Priority 3 — Production readiness

11. **Firebase initialization in `main.dart`**
    Add `await Firebase.initializeApp()` before `runApp()`.

12. **FCM token registration on login**
    After OTP verification, send device FCM token to `PATCH /users/fcm-token`.

13. **MSG91 SMS integration** in `auth.service.ts`
    Replace `console.log` OTP with actual SMS delivery.

14. **GPS movement check** in `bookings.processor.ts`
    Fetch worker location from Redis, compare to previous, auto-cancel + strike if no movement at 10 minutes.

15. **No-show penalty** in hiring search ranking
    Deduct `search_rank` score based on `noShowCount` in talent query.

16. **`synchronize: true` → migrations**
    `app.module.ts` uses `synchronize: true` which is fine for dev but must be replaced with TypeORM migrations before any production deployment.

---

## Known Issues

| Issue | Location | Fix |
|---|---|---|
| OTP accepts any 6 digits | `backend/src/auth/auth.service.ts` | Wire Redis OTP storage |
| Workers loaded from hardcoded array | `backend/src/workers/workers.service.ts` | Switch to DB query |
| Firebase not initialized | `lib/main.dart` | Add `Firebase.initializeApp()` |
| GPS movement check is a stub | `backend/src/bookings/bookings.processor.ts` | Implement Redis fetch + check |
| WebSocket broadcasts without auth | `backend/src/worker-engine/worker.gateway.ts` | Add JWT guard on gateway |
| `synchronize: true` in TypeORM | `backend/src/app.module.ts` | Use migrations for production |
| `post_job_screen.dart` is a placeholder | `lib/features/jobs/post_job_screen.dart` | Build full form |
| Home screen uses old category grid | `lib/features/home/home_screen.dart` | Redesign with 4 intent cards |

---

## Running with Docker (optional)

Start PostgreSQL and Redis quickly for local development:

```bash
# PostgreSQL
docker run -d \
  --name gixbee-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=yourpassword \
  -e POSTGRES_DB=gixbee \
  -p 5432:5432 \
  postgres:15

# Redis
docker run -d \
  --name gixbee-redis \
  -p 6379:6379 \
  redis:7
```

---

## Contributing

1. Branch naming: `feature/screen-name` or `fix/issue-description`
2. All Flutter state via Riverpod — no `setState` in business logic
3. All API calls through repository classes in `lib/data/` — never call Dio directly from a screen
4. Backend: each feature = its own NestJS module (controller + service + entity + module file)
5. Never commit `.env` files or Firebase config files (`google-services.json`, `GoogleService-Info.plist`)

---

*Gixbee v1.0.0 — April 2026*
# gixbeesolutions
