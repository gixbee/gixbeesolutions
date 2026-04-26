# Gixbee — Flow Issues Audit v2 (Complete)

> All Dart files under `lib/` have been read and analysed.
> This supersedes v1 — 11 new issues found in the second pass.

---

## Summary

| Severity | Count |
|---|---|
| 🔴 Crash / Won't compile | 2 |
| 🟠 Wrong behaviour (runs but incorrect) | 12 |
| 🟡 Missing logic (feature incomplete) | 10 |
| 🔵 UX gap | 6 |
| **Total** | **30** |

---

## 🔴 CRASH — Will not work at all

---

### 1. Firebase initialises without `firebase_options.dart` — `lib/main.dart`

```dart
// import 'firebase_options.dart';   ← commented out
await Firebase.initializeApp();      // ← crashes without options
```

App crashes on every launch before the first screen renders.

**Fix:**
```dart
import 'firebase_options.dart';
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

---

### 2. `_isVerifying` field never declared — `lib/features/booking/arrival_otp_screen.dart`

```dart
setState(() { _isVerifying = true; });  // ← field doesn't exist
onPressed: _isVerifying ? null : _confirmArrival,  // ← compile error
```

Entire arrival + completion OTP flow cannot compile.

**Fix:** Add `bool _isVerifying = false;` to `_ArrivalOtpScreenState`.

---

## 🟠 WRONG BEHAVIOUR — Runs but does the wrong thing

---

### 3. Both "Instant Help" and "Plan Ahead" go to identical screen — `lib/features/booking/book_services_split_screen.dart`

```dart
// Instant Help:
onTap: () => Navigator.push(context, MaterialPageRoute(
  builder: (_) => const WorkerListScreen(category: null),  // ← same
)),

// Plan Ahead:
onTap: () => Navigator.push(context, MaterialPageRoute(
  builder: (_) => const WorkerListScreen(category: null),  // ← same
)),
```

The split screen asks "How urgently do you need help?" and presents two
distinct-looking options that both navigate to the exact same screen with
the exact same parameters. The distinction exists only in the UI — the
actual flow is identical.

**Fix:** "Instant Help" should skip `BookingTypeSelector` and go straight to
`WorkerListScreen` → `WorkerDetailScreen` → location picker → `PresenceCheckScreen`.
"Plan Ahead" should go to `WorkerListScreen` → `WorkerDetailScreen` → `BookingTypeSelector`
→ `BookingScreen` (scheduled flow).

---

### 4. Selected package is never stored or passed forward — `lib/features/booking/booking_type_selector.dart`

```dart
// _PackageCard is always constructed with isSelected: false
..._packages.map((pkg) => _PackageCard(
  package: pkg,
  isSelected: false,   // ← always false — nothing ever selected
  onTap: () {
    _proceed();        // ← calls proceed without recording which package
  },
)),

// _proceed() passes nothing to BookingScreen:
Navigator.push(context, MaterialPageRoute(
  builder: (_) => BookingScreen(worker: widget.worker),  // ← no package info
));
```

No matter which package the user taps (Quick Fix ₹X, Half Day ₹3.5X,
Full Day ₹6X), `BookingScreen` always receives the raw `worker.hourlyRate`.
The selected duration and price are silently discarded.

**Fix:**
```dart
_ServicePackage? _selectedPackage;

// In _PackageCard:
isSelected: _selectedPackage == pkg,
onTap: () => setState(() => _selectedPackage = pkg),

// In _proceed():
Navigator.push(context, MaterialPageRoute(
  builder: (_) => BookingScreen(
    worker: widget.worker,
    selectedPackage: _selectedPackage,  // pass price + duration
  ),
));
```

---

### 5. Worker decline sends no notification to backend — `lib/features/booking/incoming_job_screen.dart`

```dart
void _declineJob() {
  Navigator.pop(context);  // ← just closes the screen
  // No API call. Backend never knows the worker declined.
}
```

When a worker declines a job, the booking stays in `REQUESTED` state on
the backend forever. The system never re-assigns it to another available
worker. The customer waits out the full 90-second timeout unnecessarily.

**Fix:**
```dart
Future<void> _declineJob() async {
  try {
    await ref.read(bookingRepositoryProvider).updateBookingStatus(
      widget.bookingData['id'], 'REJECTED',
    );
  } finally {
    if (mounted) Navigator.pop(context);
  }
}
```

---

### 6. `IncomingJobScreen` is dead code — never navigated to

The entire `IncomingJobScreen` widget exists but is never pushed from
anywhere in the codebase. `main_wrapper.dart` uses an `AlertDialog`
for incoming job requests instead. `IncomingJobScreen` has its own
timer, accept/decline logic, and circular countdown — all unreachable.

**Fix:** Either wire it up in `main_wrapper.dart` to replace the dialog:
```dart
// Instead of showDialog, push IncomingJobScreen:
Navigator.push(context, MaterialPageRoute(
  builder: (_) => IncomingJobScreen(bookingData: booking),
));
```
Or delete the file to avoid confusion.

---

### 7. `ActiveBookingCard` re-fetches on every rebuild — `lib/features/home/active_booking_card.dart`

```dart
// Inside ConsumerWidget.build():
return FutureBuilder<List<dynamic>>(
  future: ref.read(bookingRepositoryProvider).getMyBookings(),  // ← new call every rebuild
  builder: (context, snapshot) { ... },
);
```

`ref.read()` inside `build()` is incorrect — it bypasses Riverpod's
caching. Every rebuild of `ActiveBookingCard` (triggered by user scrolling,
theme changes, or parent rebuilds) makes a fresh HTTP call to `GET /bookings/my`.
This can cause dozens of unnecessary API calls per session.

**Fix:**
```dart
final activeBookingProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final bookings = await ref.watch(bookingRepositoryProvider).getMyBookings();
  const activeStatuses = ['ACCEPTED', 'ARRIVED', 'ACTIVE', 'IN_PROGRESS', 'CONFIRMED'];
  return bookings.firstWhere(
    (b) => activeStatuses.contains((b['status'] ?? '').toString().toUpperCase()),
    orElse: () => null,
  );
});

// In build():
final activeAsync = ref.watch(activeBookingProvider);
```

---

### 8. `ActiveBookingCard` launches `ArrivalOtpScreen` with empty OTP — `lib/features/home/active_booking_card.dart`

```dart
ArrivalOtpScreen(
  arrivalOtp: activeBooking['arrivalOtp'] ?? '',  // ← empty string fallback
  ...
),
```

Same issue as `my_bookings_screen.dart`. Customer taps the active booking
card, opens arrival OTP screen, reveals an empty OTP and shares nothing
with the worker. Job cannot start.

**Fix:** Guard before navigating:
```dart
final otp = activeBooking['arrivalOtp'] as String?;
if (otp == null || otp.isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('OTP not ready yet. Please refresh.')),
  );
  return;
}
```

---

### 9. Socket receives no booking events — `lib/services/socket_service.dart`

```dart
class SocketService {
  void connect(String token) {
    _socket = io.io(AppConfig.socketUrl, ...);
    _socket!.onConnect((_) { ... });
    _socket!.onDisconnect((_) { ... });
    _socket!.onConnectError((data) { ... });
    // ← No listeners for 'new_booking_request', 'booking_accepted', etc.
  }

  void updateLocation(...) { ... }  // only outgoing
  void joinJobRoom(...) { ... }      // only outgoing
  void onLocationUpdated(...) { ... } // only for map tracking
}
```

The socket is connected on login but only used for **sending** location
updates. No incoming booking events are ever listened to. The real-time
job dispatch system (socket → worker) is completely non-functional.
All job notifications rely solely on the 5-second HTTP polling fallback.

**Fix:** Add event listeners in `connect()`:
```dart
_socket!.on('new_booking_request', (data) {
  // Emit via StreamController for UI to listen
  _notificationController.add(data as Map<String, dynamic>);
});
_socket!.on('booking_accepted', (data) { ... });
_socket!.on('booking_cancelled', (data) { ... });
```

---

### 10. Socket has no reconnection config — `lib/services/socket_service.dart`

```dart
_socket = io.io(AppConfig.socketUrl, io.OptionBuilder()
  .setTransports(['websocket'])
  .setAuth({'token': token})
  .enableAutoConnect()
  // ← no reconnection attempts, no delay, no max retries
  .build());
```

`enableAutoConnect()` alone does not configure reconnection behaviour.
If the connection drops (network switch, server restart), the socket
silently stays disconnected. Workers stop receiving all real-time events.

**Fix:**
```dart
io.OptionBuilder()
  .setTransports(['websocket'])
  .setAuth({'token': token})
  .enableAutoConnect()
  .enableReconnection()
  .setReconnectionAttempts(10)
  .setReconnectionDelay(2000)
  .build()
```

---

### 11. Wallet `verifyPayment()` exists in repository but is never called — `lib/features/profile/wallet_screen.dart`

`WalletRepository.verifyPayment()` is properly implemented:
```dart
Future<void> verifyPayment({
  required String paymentId, String? orderId, String? signature,
}) async {
  await _dio.post('/wallets/verify-payment', data: { ... });
}
```

But `wallet_screen.dart` ignores it entirely:
```dart
void _handlePaymentSuccess(PaymentSuccessResponse response) {
  ScaffoldMessenger.of(context).showSnackBar(...);
  _fetchWalletData();  // ← just refreshes UI, never calls verifyPayment()
}
```

Payment is collected by Razorpay but never credited to the wallet.

**Fix:**
```dart
void _handlePaymentSuccess(PaymentSuccessResponse response) async {
  try {
    await ref.read(walletRepositoryProvider).verifyPayment(
      paymentId: response.paymentId!,
      orderId: response.orderId,
      signature: response.signature,
    );
    await _fetchWalletData();
  } catch (e) {
    // Show error with payment ID so user can contact support
  }
}
```

---

### 12. Auth state stream has no initial value on cold start — `lib/repositories/auth_repository.dart`

```dart
final authStateProvider = StreamProvider<bool>((ref) {
  return ref.watch(authTokenServiceProvider).onTokenChange();
});
```

`onTokenChange()` only emits when the token *changes*. On a cold app start
where the user is already logged in (token in secure storage), the stream
never emits — `authState.when(loading: ...)` shows forever until something
triggers a token change.

**Fix:**
```dart
final authStateProvider = FutureProvider<bool>((ref) {
  return ref.watch(authTokenServiceProvider).hasToken();
});
```

---

### 13. `isWorker` getter exists but is never used to gate the polling — `lib/main_wrapper.dart`

`User` model correctly defines:
```dart
bool get isWorker => role == 'OPERATOR' || hasWorkerProfile;
```

But `main_wrapper.dart` ignores it:
```dart
void _startPendingBookingPoll() {
  // Fires for ALL users — customers included
  _pendingPollTimer = Timer.periodic(...);
}
```

Every customer hits `GET /bookings/pending` every 5 seconds unnecessarily.

**Fix:**
```dart
Future<void> _maybeStartWorkerPoll() async {
  final user = await ref.read(currentUserProvider.future);
  if (user?.isWorker == true) _startPendingBookingPoll();
}

// In initState:
_maybeStartWorkerPoll(); // instead of _startPendingBookingPoll()
```

---

### 14. `User.toJson()` maps `avatar` instead of `profileImageUrl` — `lib/shared/models/user.dart`

```dart
// fromJson correctly reads backend field:
avatar: json['profileImageUrl'] as String?,

// toJson sends wrong key back:
Map<String, dynamic> toJson() => {
  'avatar': avatar,  // ← backend expects 'profileImageUrl'
};
```

If `toJson()` is ever used to update the profile, the avatar URL will
be sent under the wrong key and silently ignored by the backend.

**Fix:**
```dart
Map<String, dynamic> toJson() => {
  'profileImageUrl': avatar,  // match backend field name
};
```

---

## 🟡 MISSING LOGIC — Feature exists but incomplete

---

### 15. Booking created without address — `lib/features/booking/booking_screen.dart`

`_canProceed()` always returns `true` for step 1 (address). Address is
collected in the UI but never passed to `createBooking()`. Worker receives
a job with no location.

---

### 16. Booking flow skips `WaitingForWorkerScreen` — `lib/features/booking/booking_screen.dart`

After `createBooking()` succeeds, a success dialog is shown and the user
goes home. `WaitingForWorkerScreen` — which polls for worker acceptance —
is never navigated to. Customer cannot see if anyone accepted.

---

### 17. Payment step has no actual payment — `lib/features/booking/booking_screen.dart`

"Pay & Confirm" creates the booking without checking wallet balance or
deducting any funds. Wallet balance is never checked before booking.

---

### 18. `PresenceCheckScreen` has no loading guard on submit — `lib/features/booking/presence_check_screen.dart`

```dart
SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: _proceed,  // ← no isLoading guard
    child: const Text('Find Workers'),
  ),
),
```

User can tap "Find Workers" multiple times rapidly. Each tap calls
`sendInstantRequest()` and pushes a new `WaitingForWorkerScreen`.
Multiple booking requests are created for the same job.

**Fix:** Add `bool _isLoading = false;` and guard the button.

---

### 19. No loading guard on Login "Send Code" button — `lib/features/auth/login_screen.dart`

No `isLoading` state. Double-tap sends two OTP requests and pushes two
`OtpScreen` instances onto the navigation stack.

---

### 20. `IncomingJobScreen` timer uses magic number `90` — `lib/features/booking/incoming_job_screen.dart`

```dart
int _secondsRemaining = 90;                  // should be AppConfig.jobAcceptTimeoutSeconds
value: _secondsRemaining / 90,               // magic number repeated
color: _secondsRemaining > 10 ? Colors.green : Colors.red,  // magic number
```

Three separate instances of the hardcoded `90` that should all reference
`AppConfig.jobAcceptTimeoutSeconds`.

---

### 21. Chat button is dead — `lib/features/search/worker_detail_screen.dart`

```dart
OutlinedButton(
  onPressed: () {},  // ← does nothing
  child: const Text('Chat Now'),
),
```

No chat screen exists. The button is completely non-functional with no
placeholder, no snackbar, no "coming soon" indicator.

---

### 22. `workersProvider` error state has no retry — `lib/features/search/worker_list_screen.dart`

```dart
error: (err, stack) => Center(child: Text('Error: $err')),
```

When the worker list fails to load (network issue), the user sees a raw
error string with no retry button and no way to recover without restarting
the app.

**Fix:**
```dart
error: (err, stack) => Center(
  child: Column(children: [
    Text('Could not load workers'),
    ElevatedButton(
      onPressed: () => ref.invalidate(workersProvider),
      child: const Text('Retry'),
    ),
  ]),
),
```

---

### 23. Custom booking description never sent to backend — `lib/features/booking/booking_type_selector.dart`

When the user selects "Custom" type, fills in the event type, description,
guest count, and picks a location — none of this data is passed to
`BookingScreen`. `_proceed()` navigates to `BookingScreen(worker: widget.worker)`
with no custom request data. The description is silently discarded.

---

### 24. No loading state on `WelcomeScreen` → `LoginScreen` initial OTP request

Same as issue #19 — both entry points to the OTP flow lack loading guards.

---

## 🔵 UX GAPS

---

### 25. Timeout screen freezes at "0 s" — `lib/features/booking/waiting_for_worker_screen.dart`

When the 90-second countdown expires, timers cancel but nothing else
happens. Screen shows "0 s" permanently with a frozen radar animation.
No auto-cancel, no navigation, no message. User is stuck.

---

### 26. Duplicate job request popup from FCM + polling — `lib/main_wrapper.dart`

`_shownBookingIds` deduplication only guards the polling path. FCM
foreground listener has no deduplication. A booking can trigger both
simultaneously, showing two "Accept Job" dialogs at once.

---

### 27. Logout navigates to `LoginScreen` instead of `WelcomeScreen` — `lib/features/profile/profile_screen.dart`

After logout the user is manually pushed to `LoginScreen`, bypassing the
`WelcomeScreen` the rest of the auth flow flows through.

---

### 28. `devOtp` auto-fills OTP in production — `lib/features/auth/otp_screen.dart`

`initialOtp` from backend auto-fills the OTP fields with no `kDebugMode`
guard. If the backend accidentally returns `devOtp` in production, the
OTP screen bypasses the security gate for every user.

---

### 29. Notifications profile option is a dead tap — `lib/features/profile/profile_screen.dart`

```dart
const _ProfileOption(icon: Icons.notifications_none, label: 'Notifications'),
// no onTap — tapping does nothing silently
```

---

### 30. Worker list search resets unexpectedly on pull-to-refresh

```dart
onRefresh: () async {
  return await ref.refresh(workersProvider.future);
  // ← _searchQuery is not cleared but list re-renders from fresh data
},
```

After refreshing, the search filter remains applied to the new data, which
could cause the list to appear empty if the query matches fewer results in
the fresh data. No visual indication that results are filtered.

---

## Complete flow map — broken paths

```
COLD START
  main() → Firebase.initializeApp() [no options → CRASH] 🔴

AUTH
  LoginScreen → Send Code [no loading guard → double push] 🟡
             → OtpScreen [devOtp auto-fills in prod] 🔵
             → MainWrapper
                 authStateProvider [stream has no initial value → loading flicker] 🟠
                 _startPendingBookingPoll() [runs for customers too] 🟠
                 Socket.connect() [no booking event listeners] 🟠
                                  [no reconnection config] 🟠

BOOK A SERVICE (Customer path)
  HomeScreen → Search bar [not functional] 🟡
  BookServicesSplitScreen
    → "Instant Help" → WorkerListScreen(null) ─┐
    → "Plan Ahead"  → WorkerListScreen(null) ──┘ same screen 🟠

  WorkerListScreen → WorkerDetailScreen
    → "Chat Now" [dead button] 🟡
    → "Book Now" → EventLocationPickerScreen
                → PresenceCheckScreen
                    → _proceed() [no loading guard → double tap = double booking] 🟡
                    → WaitingForWorkerScreen ✅ (correct path)

  OR via BookingTypeSelector:
    → Package selected [isSelected always false, price discarded] 🟠
    → Custom request [description discarded] 🟡
    → BookingScreen
        Step 1: Address [can proceed empty, never sent to API] 🟡
        Step 2: Payment [no actual payment, wallet never deducted] 🟡
        Confirm → createBooking() → SuccessDialog ← WaitingForWorkerScreen SKIPPED 🟡

WORKER RECEIVES JOB
  FCM → popup [no dedup] 🟠
  Polling → popup [deduped, but runs for customers] 🟠
  Socket → nothing [no event listeners] 🟠
  IncomingJobScreen [never navigated to — dead code] 🟠
  Worker declines [no server notification] 🟠
  Worker accepts → acceptBooking() ✅

BOOKING LIVE FLOW
  WaitingForWorkerScreen → timeout → screen freezes at 0s 🔵
                        → accepted → ArrivalOtpScreen
                            [_isVerifying not declared → CRASH] 🔴

  MyBookingsScreen → ArrivalOtpScreen [arrivalOtp can be empty string] 🟠
  ActiveBookingCard → ArrivalOtpScreen [arrivalOtp can be empty string] 🟠
                   → re-fetches API on every rebuild 🟠

  ArrivalOtpScreen → confirmArrival() → CompletionOtpScreen
  CompletionOtpScreen → fetchOtp [no loading state → shows dots] 🔵
                     → confirmCompletion() → SuccessDialog ✅

WALLET
  Top-up → Razorpay → paymentSuccess
      → verifyPayment() EXISTS in repo but NEVER CALLED 🟠
      → only _fetchWalletData() called → balance unchanged

LOGOUT
  signOut() → navigates to LoginScreen [should be WelcomeScreen] 🔵
```

---

## Fix priority order (updated)

| Priority | Issue | File | Effort |
|---|---|---|---|
| P0 | Firebase crash — missing options | `main.dart` | 2 min |
| P0 | `_isVerifying` compile error | `arrival_otp_screen.dart` | 1 min |
| P1 | Wallet payment never credited | `wallet_screen.dart` | Low |
| P1 | Socket receives no booking events | `socket_service.dart` | Low |
| P1 | Package selection discarded | `booking_type_selector.dart` | Medium |
| P1 | Worker decline no server call | `incoming_job_screen.dart` | Low |
| P1 | Booking created without address | `booking_screen.dart` | Low |
| P1 | WaitingForWorkerScreen never shown | `booking_screen.dart` | Low |
| P1 | Both split screen options identical | `book_services_split_screen.dart` | Medium |
| P2 | ActiveBookingCard re-fetches every rebuild | `active_booking_card.dart` | Low |
| P2 | Empty arrivalOtp launched (2 places) | `my_bookings_screen.dart`, `active_booking_card.dart` | Low |
| P2 | Auth state stream no initial value | `auth_repository.dart` | Low |
| P2 | Poll fires for customers | `main_wrapper.dart` | Low |
| P2 | Duplicate popup FCM + polling | `main_wrapper.dart` | Low |
| P2 | Timeout screen freezes | `waiting_for_worker_screen.dart` | Low |
| P2 | Double-tap creates multiple bookings | `presence_check_screen.dart` | Low |
| P2 | Socket no reconnection config | `socket_service.dart` | Low |
| P2 | User.toJson() wrong field key | `user.dart` | 1 min |
| P3 | IncomingJobScreen dead code | `incoming_job_screen.dart` | Medium |
| P3 | No loading on Send Code | `login_screen.dart` | Low |
| P3 | devOtp auto-fills in production | `otp_screen.dart` | 1 min |
| P3 | Chat button dead | `worker_detail_screen.dart` | Low |
| P3 | Worker list no retry on error | `worker_list_screen.dart` | Low |
| P3 | Custom request description discarded | `booking_type_selector.dart` | Medium |
| P3 | No payment in booking flow | `booking_screen.dart` | High |
| P3 | No registration / role selection | Onboarding | High |
| P3 | Logout wrong destination | `profile_screen.dart` | Low |
| P3 | Notifications option dead tap | `profile_screen.dart` | Low |
| P3 | IncomingJobScreen magic number 90 | `incoming_job_screen.dart` | 1 min |
| P3 | No search from HomeScreen | `home_screen.dart` | Low |
