# ADR-004: Intent-Based User Model (Not Role-Based)

**Status:** Accepted  
**Date:** Product inception  
**Deciders:** Product

## Context

Users fluidly switch between booking services, working gigs, finding employment, and managing businesses — often in one session. A rigid role enum (CUSTOMER vs WORKER vs EMPLOYER) would force account switching or duplicate profiles.

## Decision

**Single `User` account** with optional capability profiles:

| Capability | Data | Entry point (Flutter home) |
|---|---|---|
| Book services | Bookings as `customerId` | Book Services |
| Work gigs | `WorkerProfile` + Go Live | Earn by Working |
| Find jobs | `TalentProfile` + Job Types | Find a Job |
| List business | `Business` entities (SERVICE / HIRING / RENTAL) | List My Business |

Authorization is **contextual** — e.g. only booking participants join a job room; only business owner/operators manage a unit; Smart Hiring requires VERIFIED HIRING business.

There is no global "mode switch" that locks the user into one role.

## Consequences

**Positive**
- Matches real user behaviour (same person books and works)
- Single OTP login, one notification stream, unified profile

**Negative**
- UI must gate features by profile completeness (verification, business type)
- Backend guards must check relationship to resource, not a single role flag
- Admin views must filter by entity type, not role column alone

## Implementation notes

- `User.role` exists for admin/staff distinction; not used to block customer flows
- Worker verification gates Go Live; business verification gates Smart Hiring match start
- JWT carries `userId`; resource ownership checked per endpoint
