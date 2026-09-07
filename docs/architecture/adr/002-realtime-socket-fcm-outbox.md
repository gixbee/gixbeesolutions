# ADR-002: Realtime — Socket.IO Primary, FCM Background, Outbox for Side Effects

**Status:** Accepted  
**Date:** 2026-08-01 (consolidation)  
**Deciders:** Backend + mobile

## Context

Booking lifecycle generates many side effects: push notifications, socket events, Redis pending-set updates, sibling booking cancellations. Doing these inline in HTTP handlers risks partial failure, duplicate sends under retries, and slow API responses.

Multiple polling loops (4s/5s/30s) on the Flutter client caused duplicate UI and battery drain.

## Decision

### Server

1. **Transactional outbox** — domain writes + `outbox_events` in one DB transaction; `OutboxDispatcher` (Bull) processes FCM + socket emits.
2. **Socket.IO** with **Redis adapter** for multi-replica fan-out (`RedisIoAdapter` in `main.ts`).
3. **Three gateways:**
   - `WorkerGateway` — GPS, job rooms, presence
   - `MessagesGateway` — chat
   - `VoiceCallsGateway` — WebRTC signaling
4. **FCM** via Firebase Admin for background delivery.
5. **HTTP status fallback** — `BookingStatusService` + Redis snapshot; client polls at 5s only when socket not live.

### Client

1. **Socket.IO primary** for foreground realtime (`socket_service.dart`).
2. **FCM** routes typed events in `main_wrapper.dart` (`_bookingStateTypes`).
3. **Single HTTP reconciliation** at startup/resume for pending worker queue (replaces periodic polling).
4. **`bookingStatusProvider`** — shared 5s fallback, backs off when `socketService.isLiveForPolling`.

## Security (2026-08-01)

- WS auth via `WsJwtGuard`; never trust body `userId`
- Personal rooms derived from JWT identity
- Job rooms require booking participation
- Only assigned pro may publish GPS to job room

## Consequences

**Positive**
- Reliable side effects after commit
- Replica-safe socket fan-out
- Reduced client polling and duplicate popups

**Negative**
- Eventual consistency (typically <5s; poll covers gaps)
- Outbox + Bull operational complexity
- Must keep FCM `data.type` and socket event names in sync with Flutter handlers

## Contract surfaces to keep aligned

| Server emit | Client handler |
|---|---|
| FCM `data.type` | `main_wrapper.dart` `_bookingStateTypes`, incoming job |
| Socket booking events | `socket_service.dart` notification stream |
| WS `locationUpdated` | `live_tracking_map_screen` callback |

Any new lifecycle event requires updates in outbox handler, FCM payload, and Flutter routing.
