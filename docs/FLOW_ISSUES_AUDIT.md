# Gixbee — Flow Issues Audit

> Full end-to-end analysis of every user flow.
> Issues are ranked: 🔴 Crash / Broken · 🟠 Wrong behaviour · 🟡 Missing logic · 🔵 UX gap

---

## Summary

| Severity | Count | Flows affected |
|---|---|---|
| 🔴 Crash / Won't compile | 2 | Auth init, Arrival OTP |
| 🟠 Wrong behaviour | 8 | Auth, Booking, Payment, Notifications |
| 🟡 Missing logic | 7 | Registration, Booking, Wallet, Roles |
| 🔵 UX gap | 5 | Home, Profile, Booking, Timeout |

---

## 🔴 CRASH — App will not work at all

---

### 1. Firebase initialises without `firebase_options.dart` — `lib/main.dart`

**Found:**
```dart
// import 'firebase_options.dart';   ← commented out
await Firebase.initializeApp();      ← called without options
```

**Problem:**  
`Firebase.initializeApp()` without `DefaultFirebaseOptions.currentPlatform`
will throw a `FirebaseException` at startup on every platform.
The import is commented out but the call remains. App will crash on launch.

**Fix:**
```dart
import 'firebase_options.dart';

await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

Or if `firebase_options.dart` is genuinely absent, remove Firebase entirely
and use the WebSocket/OneSignal path documented in `WEBSOCKET_VS_FCM_NOTIFICATIONS.md`.

---

### 2. `_isVerifying` used but never declared — `lib/features/booking/arrival_otp_screen.dart`

**Found:**
```dart
// In _ArrivalOtpScreenState — field is never declared:
setState(() {
  _isVerifying = true;   // ← _isVerifying does not exist as a field
  _errorMsg = null;
});

// Also used in build():
onPressed: _isVerifying ? null : _confirmArrival,
```

**Problem:**  
`bool _isVerifying` is referenced in `_confirmArrival()` and the `build()`
method but is never declared as a class field. This is a compile error —
the entire booking arrival flow cannot run.

**Fix:**  
Add the missing field declaration:
```dart
class _ArrivalOtpScreenState extends ConsumerState<ArrivalOtpScreen>
    with SingleTickerProviderStateMixin {
  bool _isVerifying = false;   // ← add this
  bool _isRevealed = false;
  ...
}
```

---

## 🟠 WRONG BEHAVIOUR — Runs but does the wrong thing

---

### 3. Auth state stream misses initial value on cold start — `lib/repositories/auth_repository.dart`

**Found:**
```dart
final authStateProvider = StreamProvider<bool>((ref) {
  return ref.watch(authTokenServiceProvider).onTokenChange();
});
```

```dart
// In AuthTokenService constructor:
AuthTokenService() {
  hasToken().then((exists) => _tokenController.add(exists));
}
```

**Problem:**  
`hasToken()` is async. On a cold start (app launched, token already stored),
`onTokenChange()` returns the stream before the constructor's async check
completes. The `StreamProvider` has no initial value to emit, so
`authState.when(loading: ...)` shows the loading spinner forever
until the token check resolves — typically 300–500ms.

More critically: if the stream emits `false` before the async check
resolves (because the stream has no buffered value), the app shows
`WelcomeScreen` briefly before switching to `MainWrapper` — a visible flash.

**Fix:**  
Seed the stream with an initial synchronous value or use a `FutureProvider`
for the initial check:

```dart
// Replace StreamProvider with FutureProvider for the auth gate:
final authStateProvider = FutureProvider<bool>((ref) async {
  return ref.watch(authTokenServiceProvider).hasToken();
});
```

Use the stream provider only for reactive updates after login/logout.

---

### 4. Booking popup can appear twice for the same booking — `lib/main_wrapper.dart`

**Found:**
```dart
// FCM foreground listener — NO deduplication:
notifService.addForegroundListener((RemoteMessage message) {
  _handleMessage(message);   // always shows popup
});

// Polling — HAS deduplication with _shownBookingIds:
void _startPendingBookingPoll() {
  _pendingPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
    ...
    if (id != null && !_shownBookingIds.contains(id)) {
      _shownBookingIds.add(id);
      _showJobRequestPopup(...);
    }
  });
}
```

**Problem:**  
When a new booking arrives, both FCM foreground message AND the 5-second
polling timer can fire for the same `bookingId`. The FCM listener has no
`_shownBookingIds` check, so the worker sees two simultaneous job
request popups for a single booking.

**Fix:**  
Apply the same deduplication to the FCM handler:
```dart
notifService.addForegroundListener((RemoteMessage message) {
  final bookingId = message.data['bookingId'] as String?;
  if (bookingId != null && _shownBookingIds.contains(bookingId)) return;
  if (bookingId != null) _shownBookingIds.add(bookingId);
  _handleMessage(message);
});
```

---

### 5. Pending booking poll fires for customers too — `lib/main_wrapper.dart`

**Found:**
```dart
@override
void initState() {
  super.initState();
  _initSocket();
  _initNotifications();
  _startPendingBookingPoll();   // ← runs for ALL users
}
```

**Problem:**  
`_startPendingBookingPoll()` calls `GET /bookings/pending` every 5 seconds.
This endpoint is meant for workers. Every customer using the app is also
hitting this endpoint continuously, adding pointless load to the backend.
If the backend returns an error for non-workers, this produces a silent
exception every 5 seconds for every customer session.

**Fix:**  
Check user role before starting the poll:
```dart
Future<void> _maybeStartWorkerPoll() async {
  final user = await ref.read(currentUserProvider.future);
  if (user?.isWorker == true) {
    _startPendingBookingPoll();
  }
}
```

---

### 6. Booking created without address — `lib/features/booking/booking_screen.dart`

**Found:**
```dart
// Step 2: Address step — _canProceed() always returns true:
bool _canProceed() {
  if (_currentStep == 0) {
    return _selectedDate != null && _selectedTime != null;
  }
  return true;   // step 1 (address) and step 2 (payment) always pass
}

// createBooking() never sends address:
await ref.read(bookingRepositoryProvider).createBooking(
  workerId: widget.worker.id,
  scheduledAt: scheduledAt,
  amount: widget.worker.hourlyRate,
  // address is never included
);
```

**Problem:**  
The user can type an address in Step 2, click Continue with it empty,
and the booking is created with no location data at all. The worker
has nowhere to go. `createBooking()` in the repository also doesn't
accept or send an address field.

**Fix:**
```dart
bool _canProceed() {
  if (_currentStep == 0) return _selectedDate != null && _selectedTime != null;
  if (_currentStep == 1) return _addressController.text.trim().isNotEmpty;
  return true;
}

// In createBooking() repository method — add address parameter:
await ref.read(bookingRepositoryProvider).createBooking(
  workerId: widget.worker.id,
  scheduledAt: scheduledAt,
  amount: widget.worker.hourlyRate,
  address: _addressController.text.trim(),
);
```

---

### 7. Wallet payment success never verified with backend — `lib/features/profile/wallet_screen.dart`

**Found:**
```dart
void _handlePaymentSuccess(PaymentSuccessResponse response) {
  // In a real app, you would send the payment ID to your backend to verify
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Payment successful! Syncing balance...')),
  );
  _fetchWalletData();   // just refreshes UI — no verification call
}
```

**Problem:**  
After Razorpay confirms payment on the client side, the wallet balance
is never credited on the backend. `_fetchWalletData()` refreshes the
balance, but since no backend call was made to record the payment,
the balance will be unchanged. Users pay real money and see no change
in their wallet.

This is also a security issue — any client could call `_fetchWalletData()`
and the balance would never increase without backend verification.

**Fix:**
```dart
void _handlePaymentSuccess(PaymentSuccessResponse response) async {
  try {
    // 1. Send payment ID to backend for verification and crediting
    await ref.read(walletRepositoryProvider).verifyAndCredit(
      paymentId: response.paymentId!,
      orderId: response.orderId,
      signature: response.signature,
    );
    // 2. Only then refresh
    await _fetchWalletData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallet credited successfully!'), backgroundColor: Colors.green),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment received but crediting failed. Contact support. ID: ${response.paymentId}')),
      );
    }
  }
}
```

---

### 8. ArrivalOTP screen launched with empty string OTP — `lib/features/jobs/my_bookings_screen.dart`

**Found:**
```dart
ArrivalOtpScreen(
  bookingId: booking['id'],
  workerName: booking['operator']?['name'] ?? 'Worker',
  arrivalOtp: booking['arrivalOtp'] ?? '',   // ← falls back to empty string
  isWorker: isOperator,
),
```

**Problem:**  
When the booking data doesn't yet have `arrivalOtp` (e.g. booking is still
ACCEPTED but worker hasn't been assigned an OTP yet), the screen opens
with `arrivalOtp: ''`. The customer sees `• • • •` which they tap to
reveal an empty OTP. They share nothing with the worker. The job cannot
start.

**Fix:**  
Guard against launching the screen with an empty OTP:
```dart
final otp = booking['arrivalOtp'] as String?;
if (otp == null || otp.isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('OTP not ready yet. Please wait and refresh.')),
  );
  return;
}
// Then navigate with the valid otp
```

---

### 9. Booking timeout — screen freezes with no action — `lib/features/booking/waiting_for_worker_screen.dart`

**Found:**
```dart
void _startCountdown() {
  _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (_secondsRemaining > 0) {
      setState(() => _secondsRemaining--);
    } else {
      _countdownTimer?.cancel();
      _pollingTimer?.cancel();
      // ← nothing else happens. Screen stays open showing "0 s"
    }
  });
}
```

**Problem:**  
When the 90-second timeout expires, both timers are cancelled and
the screen simply freezes. The user sees "0 s" and a frozen radar
animation. There is no popup, no auto-cancel, no navigation back.
The user is stuck.

**Fix:**
```dart
} else {
  _countdownTimer?.cancel();
  _pollingTimer?.cancel();
  if (mounted) {
    _cancelRequest();   // auto-cancel the booking
    _showError('No worker accepted in time. Your request has been cancelled.');
  }
}
```

---

### 10. FCM token registered twice on every login — `lib/features/auth/otp_screen.dart` + `lib/main_wrapper.dart`

**Found:**
```dart
// otp_screen.dart — registers token after OTP verify:
await _registerFcmToken();

// main_wrapper.dart — also registers token on every app startup:
notifService.getDeviceToken().then((token) async {
  if (token != null) {
    await ref.read(authRepositoryProvider).registerFcmToken(token);
  }
});
```

**Problem:**  
The FCM token is sent to the backend twice on login: once in `otp_screen.dart`
and again immediately when `MainWrapper` mounts. Depending on the backend
implementation this could create duplicate token records or trigger
duplicate DB writes on every app open.

**Fix:**  
Remove the token registration from `main_wrapper.dart`. Keep it only in
`otp_screen.dart` (after login) and the `onTokenRefresh` listener
(when FCM rotates the token). Those two are sufficient.

---

## 🟡 MISSING LOGIC — Feature exists but incomplete

---

### 11. No actual registration flow — `lib/features/auth/login_screen.dart`

**Found:**
```dart
TextButton(
  onPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Just enter your phone number to start!')),
    );
  },
  child: Text('New to Gixbee? Register here'),
),
```

**Problem:**  
Tapping "New to Gixbee? Register here" shows a SnackBar, not a registration
screen. New users have no way to set their name, role (customer or worker),
or any profile details. They are silently auto-registered on OTP verify with
no context collected.

**Fix:**  
Either remove the button if registration is identical to login (OTP-only),
or navigate to a dedicated `RegisterScreen` that collects name and role
before sending the OTP.

---

### 12. No user role selection anywhere — entire app

**Problem:**  
Gixbee has two user types: **customers** (book services) and **workers**
(receive and fulfil jobs). There is no screen in the onboarding or profile
flow where a user selects their role. The pending booking poll (issue #5),
the "Register as Pro" flow, and the incoming job popup all depend on knowing
if the user is a worker — but this is never explicitly set during sign-up.

**Fix:**  
Add a role selection step after OTP verification:
```dart
// After verifyOtp() succeeds in otp_screen.dart:
Navigator.pushAndRemoveUntil(
  context,
  MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
  (route) => false,
);
```

---

### 13. Payment step has no actual payment integration — `lib/features/booking/booking_screen.dart`

**Found:**
```dart
Widget _buildPaymentStep() {
  ...
  _buildSelectionTile(
    icon: Icons.account_balance_wallet,
    title: 'UPI / Wallet',
    isAction: true,   // shows arrow but does nothing on tap
  ),
}

// "Pay & Confirm" button calls _confirmBooking() which:
Future<void> _confirmBooking() async {
  await ref.read(bookingRepositoryProvider).createBooking(...);
  // No wallet deduction, no Razorpay, no payment at all
}
```

**Problem:**  
The payment step is purely decorative. Clicking "Pay & Confirm" creates
the booking and shows a success dialog without any payment being processed.
The wallet balance is never deducted. This means all bookings are free.

**Fix:**  
Before calling `createBooking()`, check wallet balance and deduct:
```dart
Future<void> _confirmBooking() async {
  // 1. Check wallet balance
  final balance = await ref.read(walletRepositoryProvider).getBalance();
  if (balance < widget.worker.hourlyRate) {
    _showLowBalanceDialog();
    return;
  }
  // 2. Create booking (backend should deduct wallet atomically)
  await ref.read(bookingRepositoryProvider).createBooking(...);
}
```

---

### 14. Search bar on Home is not functional — `lib/features/home/home_screen.dart`

**Found:**
```dart
Container(
  // Search bar widget — no GestureDetector, no onTap, no navigation
  child: Row(
    children: [
      Icon(Icons.search_rounded, ...),
      Text('Find professionals...'),
      Icon(Icons.mic_rounded, ...),
    ],
  ),
),
```

**Problem:**  
The home screen search bar is a static widget with no interaction.
Tapping it does nothing. Users cannot search for workers or services
from the home screen.

**Fix:**
```dart
GestureDetector(
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const WorkerListScreen()),
  ),
  child: Container( /* search bar */ ),
),
```

---

### 15. Completion OTP customer view shows `• • • •` on slow networks — `lib/features/booking/completion_otp_screen.dart`

**Found:**
```dart
@override
void initState() {
  super.initState();
  if (!widget.isWorker) {
    _fetchOtp();   // async — takes time
  }
}

// In build():
Text(
  _fetchedOtp ?? '• • • •',   // shows dots until fetch completes
),
```

**Problem:**  
`_fetchOtp()` is async. On a slow network it could take 2–5 seconds.
During this time the customer sees `• • • •` — identical to how the
unrevealed Arrival OTP looks — and might think the OTP hasn't arrived yet
or the screen is broken.

**Fix:**  
Show a `CircularProgressIndicator` while loading:
```dart
if (_fetchedOtp != null)
  Text(_fetchedOtp!, style: ...)
else if (_isFetchingOtp)
  const CircularProgressIndicator()
else
  const Text('Could not load OTP. Please refresh.', style: TextStyle(color: Colors.red)),
```

---

### 16. No loading state on "Send Code" button — `lib/features/auth/login_screen.dart`

**Found:**
```dart
ElevatedButton(
  onPressed: () async {
    // no isLoading guard — user can tap multiple times
    await ref.read(authRepositoryProvider).signInWithPhone(phone);
    Navigator.push(...OtpScreen...);
  },
  child: const Text('Send Code'),
),
```

**Problem:**  
There is no loading indicator and no guard against multiple taps.
If the user taps "Send Code" twice quickly, two OTP requests are sent
to the backend and two `OtpScreen` instances are pushed onto the
navigation stack. The user now has two OTP screens open.

**Fix:**
```dart
bool _isSending = false;

onPressed: _isSending ? null : () async {
  setState(() => _isSending = true);
  try {
    final devOtp = await ref.read(authRepositoryProvider).signInWithPhone(phone);
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: phone, initialOtp: devOtp)));
  } finally {
    if (mounted) setState(() => _isSending = false);
  }
},
child: _isSending
  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
  : const Text('Send Code'),
```

---

### 17. Notifications profile option has no action — `lib/features/profile/profile_screen.dart`

**Found:**
```dart
const _ProfileOption(
  icon: Icons.notifications_none,
  label: 'Notifications',
  // no onTap — tapping does nothing
),
```

**Problem:**  
The Notifications menu item is completely dead — no navigation,
no settings screen, no action. Users tapping it get no feedback.

---

## 🔵 UX GAPS — Confusing or incomplete experience

---

### 18. Logout navigates to `LoginScreen` not `WelcomeScreen` — `lib/features/profile/profile_screen.dart`

**Found:**
```dart
await ref.read(authRepositoryProvider).signOut();
Navigator.pushAndRemoveUntil(
  context,
  MaterialPageRoute(builder: (_) => const LoginScreen()),   // ← skips welcome
  (route) => false,
);
```

**Problem:**  
After logout, the user is taken to `LoginScreen` (phone input) instead
of `WelcomeScreen`. The app's auth gate in `main.dart` would correctly
show `WelcomeScreen`, but this manual navigation bypasses it.

**Fix:**  
After sign out, just invalidate the token and let the `authStateProvider`
navigate automatically:
```dart
await ref.read(authRepositoryProvider).signOut();
// authStateProvider emits false → MaterialApp rebuilds to WelcomeScreen
```
Remove the manual `Navigator.pushAndRemoveUntil`.

---

### 19. `initialOtp` auto-filled in OTP screen is a dev-only feature with no guard — `lib/features/auth/otp_screen.dart`

**Found:**
```dart
late final List<TextEditingController> _controllers =
    List.generate(AppConfig.otpLength, (index) {
  final controller = TextEditingController();
  if (widget.initialOtp != null && index < widget.initialOtp!.length) {
    controller.text = widget.initialOtp![index];   // auto-fills OTP
  }
  return controller;
});
```

**Problem:**  
`initialOtp` is passed from `login_screen.dart` as `devOtp` returned by
the backend (`response.data['devOtp']`). This is useful in development
but if the backend accidentally returns `devOtp` in production, the OTP
screen auto-fills for every user — bypassing the entire OTP verification
gate.

**Fix:**  
Guard with `kDebugMode`:
```dart
if (kDebugMode && widget.initialOtp != null && index < widget.initialOtp!.length) {
  controller.text = widget.initialOtp![index];
}
```

---

### 20. Booking flow skips `WaitingForWorkerScreen` — `lib/features/booking/booking_screen.dart`

**Found:**
```dart
void _showSuccessDialog() {
  showDialog(
    builder: (context) => AlertDialog(
      title: const Icon(Icons.check_circle, color: Colors.green),
      content: Text('Your service with ${widget.worker.name} has been scheduled.'),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('Back to Home'),
        ),
      ],
    ),
  );
}
```

**Problem:**  
After booking is confirmed, the user is shown a success dialog and sent
back to home. `WaitingForWorkerScreen` — which polls for worker acceptance
and shows the 90-second countdown — is never navigated to. The customer
has no way to know if the worker accepted.

**Fix:**  
Replace the success dialog navigation with a push to `WaitingForWorkerScreen`:
```dart
// After createBooking() returns the booking ID:
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => WaitingForWorkerScreen(
      bookingId: createdBookingId,
      worker: widget.worker,
      skill: widget.worker.skill,
    ),
  ),
);
```

---

## Full flow diagram — current broken paths

```
ONBOARDING
WelcomeScreen → LoginScreen → [no loading guard → double push possible]
                            → OtpScreen → [devOtp auto-fills in prod]
                                       → MainWrapper
                                         [Firebase crash if options missing]

BOOKING (Customer)
BookServicesSplitScreen → BookingScreen
  Step 0: Schedule ✅
  Step 1: Address → [always passes even if empty] ← 🟠
  Step 2: Payment → [no actual payment] ← 🟡
  Confirm → createBooking() [no address sent] ← 🟠
          → SuccessDialog [WaitingForWorkerScreen never shown] ← 🔵

BOOKING (Worker)
FCM arrives → [popup shown]
Polling fires → [popup shown again for same booking] ← 🟠 duplicate
Worker taps Accept → acceptBooking() ✅
Worker opens MyBookings → ArrivalOtpScreen [_isVerifying crash] ← 🔴

BOOKING LIVE FLOW
WaitingForWorkerScreen → timeout → [screen freezes] ← 🟠
                       → accepted → ArrivalOtpScreen ✅
ArrivalOtpScreen → confirmArrival() → CompletionOtpScreen
CompletionOtpScreen → fetchOtp() [shows dots, no loading state] ← 🔵
                    → confirmCompletion() → SuccessDialog ✅

WALLET
Top-up → Razorpay → paymentSuccess → [balance never credited on backend] ← 🟠

AUTH STATE
App restart → StreamProvider [no initial value → loading flicker] ← 🟠
Logout → LoginScreen [should go to WelcomeScreen] ← 🔵
```

---

## Fix priority order

| Priority | Issue | File | Effort |
|---|---|---|---|
| P0 | Firebase crash — missing options | `main.dart` | 2 min |
| P0 | `_isVerifying` compile error | `arrival_otp_screen.dart` | 1 min |
| P1 | Wallet payment never credited | `wallet_screen.dart` | Medium |
| P1 | Booking created without address | `booking_screen.dart` | Low |
| P1 | Duplicate job request popup | `main_wrapper.dart` | Low |
| P1 | Timeout screen freezes | `waiting_for_worker_screen.dart` | Low |
| P2 | WaitingForWorkerScreen never shown | `booking_screen.dart` | Low |
| P2 | Auth state flicker on cold start | `auth_repository.dart` | Low |
| P2 | Poll fires for customers | `main_wrapper.dart` | Low |
| P2 | Empty arrival OTP launched | `my_bookings_screen.dart` | Low |
| P2 | No loading on Send Code button | `login_screen.dart` | Low |
| P3 | devOtp auto-fill in production | `otp_screen.dart` | 1 min |
| P3 | No payment in booking flow | `booking_screen.dart` | High |
| P3 | No registration flow | `login_screen.dart` | Medium |
| P3 | No role selection | Onboarding | High |
| P3 | Search bar non-functional | `home_screen.dart` | Low |
| P3 | Logout goes to wrong screen | `profile_screen.dart` | Low |
| P3 | Notifications option dead | `profile_screen.dart` | Low |
