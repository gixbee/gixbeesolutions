# Activity feed (Flutter + Rust)

## API

`GET /activity/feed` (JWT, user-scoped)

Query: `category`, `phase` (`active`|`history`), `statusGroup`, `page`, `limit` (max 50).

Response: `{ items, page, limit, hasMore, categoriesAvailable }`.

## Category mapping

| UI category | Source table / endpoint | Status (exact) | Detail screen |
|-------------|-------------------------|----------------|---------------|
| Services | `bookings` (`/bookings/my` equivalent) | Booking `status` enum | `BookingDetailScreen` |
| Rentals | `rental_reservations` (+ `rental_items`) | Reservation `status` | `MyRentalsScreen` / `OwnerRentalsScreen` |
| Events (plan) | `event_plans` (`GET /events`) | `PLANNED` / `CANCELLED` | `EventPlanDetailScreen` |
| Events (vendor quote) | `event_quotes` + plan | Quote `status` | `EventPlanDetailScreen` (vendor `businessId`) |
| Job Applications | `job_applications` (`GET /hiring/my-applications`) | `APPLIED`, `INTERVIEW`, `SELECTED`, `REJECTED`, `WITHDRAWN` | `ApplicationTrackerScreen` |
| Hiring | `hiring_requests` (`GET /hiring/match/requests`) | `COLLECTING`, `DELIVERED`, `CLOSED`, etc. | `HiringRequestDetailScreen` |

Legacy service tabs: `MyBookingsScreen` (Upcoming / Active / Past) via Activity app-bar list icon.

## Not in feed (by design)

- Instant Help **job offers** (`GET /hiring/match/offers`, pending bookings) — not labelled as applications.
- Smart Hiring **candidate** pipeline (`hiring_interests` as candidate) — use Find a Job flows.
- Job board **employer** application inbox per post — use job post / pipeline screens.

## Migrations

None required (read-only union over existing tables).
