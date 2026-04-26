# FCM Failure + Worker OTP Flow — Deep Audit

---

## PART 1 — What happens when FCM fails

---

### How Gixbee currently delivers job notifications to workers

```
NestJS creates booking
       │
       ▼
Firebase Admin SDK → FCM → Worker device
       │
       │ (if FCM fails or app is open)
       ▼
Socket.io → worker's connected socket   ← BROKEN (no listeners)
       │
       │ (if socket also fails / not used)
       ▼
HTTP Poll every 5s → GET /bookings/pending  ← only working fallback
```

---

### Issue 1 — Socket is the real-time fallback but has NO booking event listeners

**Found in `lib/main_wrapper.dart`:**
```dart
socketService.notifications.listen((data) { ... });
```

**Found in `lib/services/socket_service.dart`:**
```dart
class SocketService {
  // Only outgoing events:
  void updateLocation(...) { ... }
  void joinJobRoom(...) { ... }
  void onLocationUpdated(...) { ... }

  // NO 'notifications' stream exists ← compile error
  // NO 'new_booking_request' listener
  // NO 'booking_accepted' listener
}
```

`main_wrapper.dart` calls `socketService.notifications.listen()` but
`SocketService` has no `notifications` getter or `StreamController` at all.
This line will throw a `NoSuchMethodError` at runtime — the socket
notification path crashes the moment it's called.

**Fix — add to `socket_service.dart`:**
```dart
final _notificationController =
    StreamController<Map<String, dynamic>>.broadcast();

Stream<Map<String, dynamic>> get notifications =>
    _notificationController.stream;

// In connect():
_socket!.on('new_booking_request', (data) {
  _notificationController.add(Map<String, dynamic>.from(data as Map));
});
_socket!.on('booking_cancelled', (data) {
  _notificationController.add(Map<String, dynamic>.from(data as Map));
});

// In disconnect():
_notificationController.close();
```

---

### Issue 2 — Worker poll race condition at startup — poll never starts

**Found in `lib/main_wrapper.dart`:**
```dart
Future<void> _maybeStartWorkerPoll() async {
  final user = ref.read(currentUserProvider).value;  // ← .value is null at initState
  if (user?.isWorker == true) {
    _startPendingBookingPoll();   // ← never reached on first login
  }
}
```

`currentUserProvider` is a `FutureProvider`. At `initState()` the future
has not resolved yet — `.value` is always `null`. So `user?.isWorker`
is always `false` at this point. The poll never starts for any worker.

**Fix:**
```dart
Future<void> _maybeStartWorkerPoll() async {
  // Wait for the future to resolve, not just read current snapshot
  final user = await ref.read(currentUserProvider.future);
  if (user?.isWorker == true) {
    _startPendingBookingPoll();
  }
}
```

---

### Issue 3 — FCM foreground notification silent on data-only messages

**Found in `lib/services/notification_service.dart`:**
```dart
void addForegroundListener(void Function(RemoteMessage message) handler) {
  FirebaseMessaging.onMessage.listen((message) {

    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifications.show(...);  // ← only shows if notification block exists
    }

    handler(message);  // ← handler always called regardless
  });
}
```

Firebase recommends sending **data-only messages** from the backend for
background handling (no `notification` key in the FCM payload). When NestJS
sends a data-only FCM message, `message.notification` is `null`. The
local notification is NOT shown — the worker gets no sound, no banner.
The in-app dialog does appear (via `handler(message)`) but is completely
silent and easy to miss.

**Current NestJS payload (notifications.service.ts):**
```typescript
notification: {
  title: payload.title,
  body: payload.body,
},
data: payload.data ?? {},
```

This includes both `notification` and `data` blocks. On Android foreground
this works. But on Android background/killed, having a `notification` block
means FCM shows a system notification automatically — but the
`_firebaseBackgroundHandler` may not run.

**Fix — two-pronged:**

1. For foreground, always show a local notification regardless of whether
   `notification` block exists:
```dart
void addForegroundListener(void Function(RemoteMessage message) handler) {
  FirebaseMessaging.onMessage.listen((message) {
    // Always show local notification in foreground
    final title = message.notification?.title ?? message.data['title'] ?? 'New Job';
    final body = message.notification?.body ?? message.data['body'] ?? '';

    _localNotifications.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gixbee_high_importance',
          'Gixbee Job Alerts',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(sound: 'default'),
      ),
    );

    handler(message);
  });
}
```

2. Ensure NestJS sends both `notification` and `data` blocks (already done)
   so FCM handles background/killed delivery automatically.

---

### Issue 4 — No retry or user feedback when FCM token registration fails

**Found in `lib/main_wrapper.dart`:**
```dart
notifService.getDeviceToken().then((token) async {
  if (token != null) {
    await ref.read(authRepositoryProvider).registerFcmToken(token);
  }
  // ← no catch, no retry, no feedback
});
```

If this fails (network error, backend down), the token is never registered.
The worker will never receive FCM pushes. There is no retry and no error
shown to the user or developer.

**Fix:**
```dart
Future<void> _registerFcmTokenWithRetry() async {
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      final token = await notifService.getDeviceToken();
      if (token == null) return;
      await ref.read(authRepositoryProvider).registerFcmToken(token);
      debugPrint('[FCM] Token registered on attempt $attempt');
      return;
    } catch (e) {
      debugPrint('[FCM] Token registration failed attempt $attempt: $e');
      if (attempt < 3) await Future.delayed(Duration(seconds: attempt * 2));
    }
  }
  debugPrint('[FCM] Token registration failed after 3 attempts — worker may not receive pushes');
}
```

---

### Issue 5 — `BookingStatus` enum is missing 7 statuses used in the app

**Found in `lib/shared/models/booking_status.dart`:**
```dart
enum BookingStatus {
  pending,
  accepted,
  cancelled,
  rejected;     // ← only 4 statuses defined
}
```

**Used across the app:**
```dart
// my_bookings_screen.dart:
['REQUESTED', 'CUSTOM_REQUESTED', 'PENDING', 'ACCEPTED',
 'CONFIRMED', 'ACTIVE', 'IN_PROGRESS']   // 7 statuses — none in enum

// active_booking_card.dart:
['ACCEPTED', 'ARRIVED', 'ACTIVE', 'IN_PROGRESS', 'CONFIRMED']

// completion_otp_screen.dart — status badge:
'IN_PROGRESS', 'COMPLETED'
```

`BookingStatus.fromString()` returns `pending` for any unknown string
via `orElse`. So when the backend returns `ARRIVED`, `ACTIVE`,
`IN_PROGRESS`, or `COMPLETED`, they all silently map to `pending`.

In `waiting_for_worker_screen.dart`:
```dart
if (status == BookingStatus.accepted) {   // only accepted triggers next step
  // navigate to ArrivalOtpScreen
} else if (status == BookingStatus.cancelled || status == BookingStatus.rejected) {
  // show error
}
// ARRIVED, ACTIVE, IN_PROGRESS, COMPLETED → all fall to pending → nothing happens
```

A booking that moves to `ARRIVED` or `ACTIVE` will be silently ignored
by the polling loop — the customer is stuck on the waiting screen forever.

**Fix:**
```dart
enum BookingStatus {
  requested,
  customRequested,
  pending,
  confirmed,
  accepted,
  arrived,
  active,
  inProgress,
  completed,
  cancelled,
  rejected;

  static BookingStatus fromString(String value) {
    const map = {
      'REQUESTED': BookingStatus.requested,
      'CUSTOM_REQUESTED': BookingStatus.customRequested,
      'PENDING': BookingStatus.pending,
      'CONFIRMED': BookingStatus.confirmed,
      'ACCEPTED': BookingStatus.accepted,
      'ARRIVED': BookingStatus.arrived,
      'ACTIVE': BookingStatus.active,
      'IN_PROGRESS': BookingStatus.inProgress,
      'COMPLETED': BookingStatus.completed,
      'CANCELLED': BookingStatus.cancelled,
      'REJECTED': BookingStatus.rejected,
    };
    return map[value.toUpperCase()] ?? BookingStatus.pending;
  }
}
```

---

### Summary — FCM failure coverage

| Scenario | Current state | Fixed state |
|---|---|---|
| App open, FCM arrives | ✅ Works (dialog shown) | ✅ |
| App open, FCM silent (data-only) | ⚠️ Dialog shows, no sound | ✅ Always play sound |
| App backgrounded | ✅ FCM system tray works | ✅ |
| App killed | ✅ FCM system tray works | ✅ |
| FCM fails, socket fallback | ❌ `notifications` getter crashes | ✅ After fix |
| FCM fails, poll fallback | ❌ Poll never starts (race condition) | ✅ After fix |
| Token not registered | ❌ Silent failure, no retry | ✅ With 3-attempt retry |

---

## PART 2 — Worker OTP Flow Issues

---

### The intended flow vs what actually happens

**Intended flow:**
```
Worker accepts job
       ↓
Worker travels to location
       ↓
Worker taps "Mark Arrived" → backend generates arrivalOtp → sends to customer
       ↓
Customer sees OTP → tells worker verbally
       ↓
Worker types OTP → POST /bookings/:id/arrival → status: ACTIVE
       ↓
Job in progress...
       ↓
Worker finishes → taps "Mark Complete" → backend generates completionOtp → sends to customer
       ↓
Customer sees OTP → tells worker
       ↓
Worker types OTP → POST /bookings/:id/completion → status: COMPLETED
```

**What actually happens:**
```
Worker accepts job
       ↓
Worker opens MyBookings → taps "Open Tracker"
       ↓
ArrivalOtpScreen opens immediately (no "Mark Arrived" step)
       ↓
arrivalOtp is EMPTY — backend never generated it because
markArrived() was never called
       ↓
Customer sees "• • • •" — nothing to share
       ↓
Worker types something → POST /bookings/:id/arrival → backend rejects (wrong OTP)
       ↓
STUCK — no way to proceed
```

---

### Issue 6 — `markArrived()` is never called — OTP is never generated

**`booking_repository.dart`:**
```dart
Future<void> markArrived(String bookingId) async {
  await _dio.patch('/bookings/$bookingId/arrive');
  // ← This triggers backend to generate arrivalOtp and send it to customer
}
```

This method is **never called from any screen** in the entire app.

The worker accepts the job, opens `ArrivalOtpScreen`, and the backend
has never been told the worker arrived. Since the backend generates the
`arrivalOtp` in response to `PATCH /bookings/:id/arrive`, the OTP
doesn't exist yet. The customer has nothing to show the worker.

**Fix — add a "I've Arrived" step before the OTP screen:**

In `ArrivalOtpScreen` (worker view), before showing the OTP input,
show an "I've Arrived" button:

```dart
bool _hasMarkedArrived = false;
bool _isMarkingArrived = false;

// In build() — worker view, before showing OTP input:
if (widget.isWorker && !_hasMarkedArrived)
  SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: _isMarkingArrived ? null : _markArrived,
      icon: const Icon(Icons.location_on),
      label: const Text('I\'ve Arrived at Location'),
    ),
  )
else if (widget.isWorker)
  // OTP input row — shown only after marking arrived
  Row(children: [ /* existing 4 digit inputs */ ]),
```

```dart
Future<void> _markArrived() async {
  setState(() => _isMarkingArrived = true);
  try {
    await ref.read(bookingRepositoryProvider).markArrived(widget.bookingId);
    setState(() => _hasMarkedArrived = true);
    // Now the backend has generated arrivalOtp and sent it to the customer
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark arrival: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _isMarkingArrived = false);
  }
}
```

---

### Issue 7 — `markComplete()` is never called — completion OTP never generated

Same problem as `markArrived()` for the completion gate.

**`booking_repository.dart`:**
```dart
Future<void> markComplete(String bookingId) async {
  await _dio.patch('/bookings/$bookingId/complete');
  // ← generates completionOtp and sends to customer
}
```

Never called from any screen.

**In `completion_otp_screen.dart` (customer view), `_fetchOtp()` is called immediately:**
```dart
Future<void> _fetchOtp() async {
  final b = await ref.read(bookingRepositoryProvider).getBookingById(widget.bookingId);
  if (b != null && mounted) {
    setState(() => _fetchedOtp = b['completionOtp']);  // ← always null
  }
}
```

`completionOtp` is `null` because the worker never called `markComplete()`.
The customer sees `• • • •` forever. The job cannot be closed.

**Fix — same pattern as arrival:**

In `CompletionOtpScreen` (worker view), before showing OTP input:
```dart
bool _hasMarkedComplete = false;

// Worker taps "Job Done" → calls markComplete() → backend generates OTP
// Customer sees OTP update (via refresh or polling)
Future<void> _markJobComplete() async {
  await ref.read(bookingRepositoryProvider).markComplete(widget.bookingId);
  setState(() => _hasMarkedComplete = true);
}
```

Customer-side: the completion OTP fetch `_fetchOtp()` should poll or
the customer should be able to tap "Refresh OTP" (this button already
exists via `_refreshOtp()` — but the underlying `refreshCompletionOtp`
endpoint probably also fails if `markComplete` was never called).

---

### Issue 8 — OTP length mismatch: config says 6, screens use 4

**`lib/core/config/app_config.dart`:**
```dart
static const int otpLength = 6;   // ← 6 digits
```

**`lib/features/booking/arrival_otp_screen.dart`:**
```dart
final List<TextEditingController> _controllers =
    List.generate(4, (_) => TextEditingController());  // ← 4 digits

if (i == 3 && value.isNotEmpty && ...) _confirmArrival();  // ← triggers at 4
```

**`lib/features/booking/completion_otp_screen.dart`:**
```dart
List.generate(4, (_) => TextEditingController());  // ← 4 digits
if (otp.length != 4) { ... }                       // ← validates as 4
```

**`lib/features/auth/otp_screen.dart`:**
```dart
List.generate(AppConfig.otpLength, ...)  // ← 6 digits (uses config correctly)
```

Auth OTP is 6 digits. Booking OTPs are hardcoded as 4 digits.
If the backend generates 4-digit booking OTPs this is fine — but
`AppConfig.otpLength` is misleading (it's for auth, not booking).

**Fix:** Add a separate constant and use it consistently:
```dart
// In AppConfig:
static const int otpLength = 6;           // auth OTP
static const int bookingOtpLength = 4;    // arrival + completion OTP
```

Then in `arrival_otp_screen.dart` and `completion_otp_screen.dart`:
```dart
List.generate(AppConfig.bookingOtpLength, ...)
if (otp.length != AppConfig.bookingOtpLength) { ... }
```

---

### Issue 9 — Worker OTP input auto-submits before all digits typed

**`lib/features/booking/arrival_otp_screen.dart`:**
```dart
onChanged: (value) {
  if (value.isNotEmpty && i < 3) _focusNodes[i + 1].requestFocus();
  if (i == 3 && value.isNotEmpty && _controllers.every((c) => c.text.isNotEmpty)) {
    _confirmArrival();  // ← auto-submits
  }
},
```

**`lib/features/booking/completion_otp_screen.dart`:**
```dart
onChanged: (value) {
  if (value.isNotEmpty && i < 3) _focusNodes[i + 1].requestFocus();
  if (i == 3 && value.isNotEmpty && _enteredOtp.length == 4) {
    _verifyCompletion();  // ← auto-submits
  }
},
```

Both screens auto-submit the moment the last digit is entered. If the
worker mis-types the 4th digit, the wrong OTP is immediately submitted
before they can correct it. This causes:
- An unnecessary API call with wrong OTP
- `_errorMsg = 'Invalid OTP. Please try again.'` shown
- All fields cleared (`_controllers[i].clear()`)
- Worker must re-enter all 4 digits

This is especially problematic given `markArrived()` is never called —
the worker is already in a broken state and now can't even retry
without the whole form clearing.

**Fix:** Remove auto-submit and let the "Start Job" / "Confirm Complete"
button handle submission explicitly:
```dart
onChanged: (value) {
  if (value.isNotEmpty && i < 3) _focusNodes[i + 1].requestFocus();
  // Remove auto-submit — let user tap the button
},
```

---

### Issue 10 — Customer `ArrivalOtpScreen` shows OTP immediately (`_isRevealed = true`)

**`lib/features/booking/arrival_otp_screen.dart`:**
```dart
bool _isRevealed = true;   // ← OTP shown by default, not hidden
```

The screen opens with the OTP fully visible. If the customer opens the
screen in a public place, the OTP is immediately visible to anyone
nearby before the worker even arrives.

**Fix:**
```dart
bool _isRevealed = false;  // hidden by default — customer taps to reveal
```

---

### Issue 11 — Worker `ArrivalOtpScreen` has no backspace handling

**Found in `arrival_otp_screen.dart` worker input:**
```dart
onChanged: (value) {
  if (value.isNotEmpty && i < 3) _focusNodes[i + 1].requestFocus();
  // ← no handling for backspace (value.isEmpty)
},
```

When the worker deletes a digit (backspace), focus stays on the current
field — it does not move back to the previous field. The worker has to
manually tap the previous field to correct a mistake. This makes
OTP entry very frustrating on a physical keyboard or hardware back.

**Fix:**
```dart
onChanged: (value) {
  if (value.isNotEmpty && i < 3) {
    _focusNodes[i + 1].requestFocus();
  } else if (value.isEmpty && i > 0) {
    _focusNodes[i - 1].requestFocus();  // ← go back on delete
  }
},
```

---

### Issue 12 — Completion OTP customer view has no loading indicator

**`lib/features/booking/completion_otp_screen.dart`:**
```dart
@override
void initState() {
  super.initState();
  if (!widget.isWorker) {
    _fetchOtp();   // ← async, no loading state
  }
}

// In build():
Text(
  _fetchedOtp ?? '• • • •',  // ← shows dots while loading AND when null
),
```

While `_fetchOtp()` is running, the customer sees `• • • •`.
If `_fetchOtp()` fails or `completionOtp` is null (because `markComplete()`
was never called), the customer also sees `• • • •`.
These two states are indistinguishable — the customer cannot tell if
the OTP is loading or simply not generated yet.

**Fix:**
```dart
bool _isFetchingOtp = false;

Future<void> _fetchOtp() async {
  setState(() => _isFetchingOtp = true);
  try { ... }
  finally { if (mounted) setState(() => _isFetchingOtp = false); }
}

// In build():
if (_isFetchingOtp)
  const CircularProgressIndicator()
else if (_fetchedOtp != null)
  Text(_fetchedOtp!, style: ...)
else
  Column(children: [
    const Text('OTP not ready yet.', style: TextStyle(color: Colors.grey)),
    const Text('Ask the worker to mark the job as complete first.',
      style: TextStyle(fontSize: 12, color: Colors.grey)),
    TextButton(onPressed: _fetchOtp, child: const Text('Retry')),
  ]),
```

---

### Issue 13 — Rating in completion dialog silently discards rating

**`lib/features/booking/completion_otp_screen.dart`:**
```dart
Row(
  children: List.generate(5, (i) {
    return IconButton(
      icon: Icon(Icons.star_rounded, color: i < 4 ? Colors.amber : Colors.grey),
      onPressed: () {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Thank you! You rated ${widget.workerName} ${i + 1} stars.')),
        );
        // ← rating is never sent to backend
      },
    );
  }),
),
```

The rating snackbar shows "You rated X stars" but no API call is made.
The worker's rating is never updated. Additionally, the pre-selected
state (`i < 4` = first 4 stars amber) is confusing — it implies a rating
is already chosen before the user interacts.

**Fix:**
```dart
int? _selectedRating;

// In dialog:
Row(
  children: List.generate(5, (i) {
    return IconButton(
      icon: Icon(Icons.star_rounded,
        color: (_selectedRating != null && i <= _selectedRating!)
          ? Colors.amber : Colors.grey.shade400),
      onPressed: () async {
        setState(() => _selectedRating = i);
        try {
          await ref.read(bookingRepositoryProvider)
            .submitRating(widget.bookingId, i + 1);
        } catch (e) {
          // handle gracefully
        }
      },
    );
  }),
),
```

---

## Full Worker OTP Flow — corrected sequence

```
CORRECT FLOW (after all fixes):

Worker accepts job (IncomingJobScreen or dialog)
  ↓
Worker travels → opens booking in MyBookings
  ↓
ArrivalOtpScreen (worker view)
  → "I've Arrived" button → markArrived() → backend generates arrivalOtp
  → OTP sent to customer via FCM push
  ↓
Customer opens ArrivalOtpScreen
  → taps to reveal OTP (starts hidden) → sees 4-digit code
  → tells worker verbally
  ↓
Worker types OTP → taps "Start Job" (no auto-submit)
  → POST /bookings/:id/arrival {otp: '1234'}
  → backend validates, status → ACTIVE
  → navigate to CompletionOtpScreen
  ↓
Job in progress...
  ↓
CompletionOtpScreen (worker view)
  → "Job Done" button → markComplete() → backend generates completionOtp
  → OTP sent to customer via FCM push
  ↓
Customer opens CompletionOtpScreen
  → shows loading indicator while fetching
  → sees completionOtp (or 'OTP not ready — ask worker to mark complete')
  → tells worker
  ↓
Worker types OTP → taps "Confirm Complete" (no auto-submit)
  → POST /bookings/:id/completion {otp: '5678'}
  → backend validates, status → COMPLETED, billing locked
  ↓
Rating dialog → sends rating to backend
  ↓
Job closed
```

---

## Fix priority — FCM + OTP

| Priority | Issue | File | Effort |
|---|---|---|---|
| P0 | `markArrived()` never called — OTP never generated | `arrival_otp_screen.dart` | Medium |
| P0 | `markComplete()` never called — completion OTP never generated | `completion_otp_screen.dart` | Medium |
| P0 | `BookingStatus` enum missing 7 statuses — polling loop breaks | `booking_status.dart` | Low |
| P0 | Socket `notifications` getter doesn't exist — crashes | `socket_service.dart` | Low |
| P1 | Worker poll race condition — poll never starts | `main_wrapper.dart` | Low |
| P1 | FCM token registration no retry | `main_wrapper.dart` | Low |
| P1 | OTP auto-submits on last digit — no correction possible | Both OTP screens | Low |
| P1 | Backspace doesn't move focus back | Both OTP screens | Low |
| P2 | FCM foreground silent on data-only messages | `notification_service.dart` | Low |
| P2 | Arrival OTP visible by default (security) | `arrival_otp_screen.dart` | 1 min |
| P2 | Completion OTP no loading indicator | `completion_otp_screen.dart` | Low |
| P2 | Rating never sent to backend | `completion_otp_screen.dart` | Medium |
| P3 | OTP length config mismatch (6 vs 4) | `app_config.dart` + screens | Low |
