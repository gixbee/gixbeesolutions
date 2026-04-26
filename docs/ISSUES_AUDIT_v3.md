# Gixbee — Issues Audit (Fresh Pass — April 2026)
# Based on actual file content currently on disk.

---

## Summary

| Severity | Count |
|---|---|
| 🔴 Crash / Won't compile | 3 |
| 🟠 Wrong behaviour | 9 |
| 🟡 Missing logic | 8 |
| 🔵 UX gap | 5 |
| **Total** | **25** |

---

## 🔴 CRASH — Will not work at all

---

### 1. Firebase init has no options — app crashes on launch
**File:** `lib/main.dart` line 21

```dart
// firebase_options.dart is COMMENTED OUT
// import 'firebase_options.dart';

await Firebase.initializeApp();  // ← no options — crashes on Android/iOS
```

`Firebase.initializeApp()` without `DefaultFirebaseOptions.currentPlatform`
throws `FirebaseException` immediately. The try/catch swallows it and
continues — but FCM never initialises. No push notifications will
ever work.

**Fix:**
```dart
import 'firebase_options.dart';

await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

---

### 2. `NotificationService` instantiated twice in `main()` — second instance has no listeners
**File:** `lib/main.dart` lines 27–31

```dart
// Two separate instances — NOT the same object that ProviderScope uses
NotificationService().initialize().then((_) {
  NotificationService().getDeviceToken().then((token) {  // ← third new instance
    debugPrint('[FCM] INITIAL_TOKEN: $token');
  });
});
```

`NotificationService()` is called 3 times in `main()`. Each call creates a
brand new object. None of these is the instance managed by Riverpod's
`notificationServiceProvider`. The listeners registered in `main_wrapper.dart`
(via `ref.read(notificationServiceProvider)`) are on a different object
than the one initialised here. FCM events registered via the provider
never fire.

**Fix:** Remove all `NotificationService()` calls from `main()`.
Initialisation should happen through the provider:
```dart
// In main() — after Firebase.initializeApp():
// Do NOT call NotificationService() here.
// main_wrapper.dart handles init via ref.read(notificationServiceProvider)
```

---

### 3. `_PackageCard.onTap` calls `_proceed()` directly — selected package is STILL never stored
**File:** `lib/features/booking/booking_type_selector.dart` lines 192–197

```dart
..._packages.map((pkg) => _PackageCard(
  package: pkg,
  isSelected: false,      // ← ALWAYS false — nothing is ever selected visually
  onTap: () {
    _proceed();           // ← jumps straight to checkout without storing pkg
  },
)),
```

`_selectedPackage` is declared and initialised to `_packages.first`:
```dart
_ServicePackage? _selectedPackage;
// initState:
_selectedPackage = _packages.first;
```

But `_PackageCard.onTap` calls `_proceed()` immediately without first
doing `setState(() => _selectedPackage = pkg)`. So regardless of which
card the user taps, `_selectedPackage` is always the first package.
The "Half Day" and "Full Day" cards can never actually be selected.
Also `isSelected: false` means the selection highlight never shows.

**Fix:**
```dart
..._packages.map((pkg) => _PackageCard(
  package: pkg,
  isSelected: _selectedPackage == pkg,  // show selection highlight
  onTap: () {
    setState(() => _selectedPackage = pkg);  // store selection first
    // Don't auto-proceed — let user confirm with the Continue button
  },
)),
```

---

## 🟠 WRONG BEHAVIOUR

---

### 4. Supabase removed from `main.dart` but `auth_repository.dart` still uses it
**File:** `lib/main.dart` line 5

```dart
// import 'package:supabase_flutter/supabase_flutter.dart'; // Removed Supabase dependency
```

But `lib/repositories/auth_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

final _supabase = sb.Supabase.instance.client;  // ← will throw

await _supabase.auth.signInWithOtp(phone: phoneNumber);  // ← NPE
await _supabase.auth.verifyOTP(...);                     // ← NPE
```

Supabase is initialised in `auth_repository.dart` but `Supabase.initialize()`
is never called in `main()`. `Supabase.instance.client` will throw a
`StateError: Supabase is not initialized` on first auth attempt.

**Fix:** Either re-add Supabase init to `main()`:
```dart
await Supabase.initialize(
  url: AppConfig.supabaseUrl,
  anonKey: AppConfig.supabaseAnonKey,
);
```
Or replace Supabase auth with a direct OTP provider (Twilio etc.) as planned.

---

### 5. `devOtp` auto-fills OTP with no `kDebugMode` guard in production
**File:** `lib/features/auth/otp_screen.dart` lines 17–23

```dart
late final List<TextEditingController> _controllers =
    List.generate(AppConfig.otpLength, (index) {
  final controller = TextEditingController();
  if (widget.initialOtp != null && index < widget.initialOtp!.length) {
    controller.text = widget.initialOtp![index];  // ← no kDebugMode check
  }
  return controller;
});
```

And in `login_screen.dart` the devOtp snackbar is also unguarded:
```dart
if (devOtp != null) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('TEST MODE: Your OTP is $devOtp'), ...),
  );
}
```

If backend accidentally returns `devOtp` in production, the OTP is
auto-filled and displayed in a banner for every user — bypassing the
security gate entirely.

**Fix:**
```dart
// otp_screen.dart:
if (kDebugMode && widget.initialOtp != null && index < widget.initialOtp!.length) {
  controller.text = widget.initialOtp![index];
}

// login_screen.dart:
if (kDebugMode && devOtp != null) {
  ScaffoldMessenger.of(context).showSnackBar(...);
}
```

---

### 6. OTP resend in `otp_screen.dart` — timer restarts even if `signInWithPhone` fails
**File:** `lib/features/auth/otp_screen.dart` lines 98–113

```dart
onTap: _resendTimer == 0
    ? () async {
        setState(() => _resendTimer = AppConfig.otpResendSeconds);
        _startTimer();  // ← timer restarted BEFORE the API call
        final newOtp = await ref
            .read(authRepositoryProvider)
            .signInWithPhone(widget.phone);
        // If signInWithPhone throws, the timer is already counting down
        // and user cannot retry for 30s even though no OTP was sent
      }
    : null,
```

If `signInWithPhone` fails (network error, backend down), the resend
timer is already running and the user must wait 30 seconds to try again
even though no OTP was sent.

**Fix:**
```dart
onTap: _resendTimer == 0
    ? () async {
        try {
          final newOtp = await ref
              .read(authRepositoryProvider)
              .signInWithPhone(widget.phone);
          // Only restart timer if request succeeded
          setState(() => _resendTimer = AppConfig.otpResendSeconds);
          _startTimer();
          // update fields if devOtp returned
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Resend failed: $e')),
            );
          }
        }
      }
    : null,
```

---

### 7. `WalletScreen` reads `currentUserProvider` via `.value` — may be null
**File:** `lib/features/profile/wallet_screen.dart` line 117

```dart
final user = ref.read(currentUserProvider).value;  // ← .value can be null
var options = {
  'prefill': {
    'contact': user?.phone ?? '',   // ← sends empty string to Razorpay
    'email': user?.email ?? '',
  }
};
```

`currentUserProvider` is a `FutureProvider`. `.value` is `null` until
the future resolves. If `_startTopUp()` is called before the provider
resolves, Razorpay prefill is empty. No loading guard ensures the user
profile is ready before payment starts.

**Fix:** Use `ref.read(currentUserProvider).requireValue` with a guard,
or fetch user before opening Razorpay:
```dart
final userAsync = ref.read(currentUserProvider);
if (userAsync.isLoading) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Loading profile, please wait...')),
  );
  return;
}
final user = userAsync.value;
```

---

### 8. `booking_type_selector.dart` — location picked but never stored or passed forward
**File:** `lib/features/booking/booking_type_selector.dart` lines 352–365

```dart
final location = await Navigator.push<PickedLocation>(
  context,
  MaterialPageRoute(builder: (_) => const EventLocationPickerScreen()),
);
if (location != null && mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Location set: ${location.address}')),
  );
  // ← _selectedLocation is NEVER updated with the picked location
}
```

`_selectedLocation` is declared but the picked location result is only
shown in a SnackBar — never stored. `_proceed()` passes
`initialLocation: _selectedLocation` to `BookingScreen` which is always
`null`.

**Fix:**
```dart
if (location != null && mounted) {
  setState(() => _selectedLocation = location);  // ← store it
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Location set: ${location.address}')),
  );
}
```

---

### 9. `home_screen.dart` — `NotificationsScreen` import references non-existent file
**File:** `lib/features/home/home_screen.dart` line 14

```dart
import '../notifications/notifications_screen.dart';
```

There is no `lib/features/notifications/` directory in the project.
This import will cause a compile error.

**Fix:** Either create `notifications_screen.dart` or replace with:
```dart
import '../jobs/my_bookings_screen.dart';
// and navigate there, or show a simple placeholder
```

---

### 10. `active_booking_card.dart` — imported in `home_screen.dart` but not read in this pass
Likely has the `ref.read()` in `build()` re-fetching issue from the audit v2.
Flagged for verification.

---

### 11. `profile_screen.dart` — "Notifications" option has no `onTap` handler
**File:** `lib/features/profile/profile_screen.dart` line 183

```dart
const _ProfileOption(
    icon: Icons.notifications_none, label: 'Notifications'),
// ← no onTap. Tapping does nothing silently.
```

`_ProfileOption` defaults `onTap` to null. There is no `GestureDetector`
feedback at all (no ripple, no snackbar, no navigation). Users will
think the app is frozen.

**Fix:** Add a placeholder until a notifications settings screen exists:
```dart
_ProfileOption(
  icon: Icons.notifications_none,
  label: 'Notifications',
  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Notification settings coming soon')),
  ),
),
```

---

### 12. `profile_screen.dart` — "Help & Support" also has no `onTap`
**File:** `lib/features/profile/profile_screen.dart` line 185

```dart
const _ProfileOption(icon: Icons.help_outline, label: 'Help & Support'),
// ← no onTap — same dead tap issue
```

---

## 🟡 MISSING LOGIC

---

### 13. No role selection screen — worker vs customer never established
The entire app has no screen where a new user selects whether they are
a customer or a worker. `isWorker` in the `User` model depends on the
backend `role` field being set — but there is no onboarding step that
collects this. New users will always be treated as customers.

---

### 14. No registration flow — "Register here" shows SnackBar
**File:** `lib/features/auth/login_screen.dart` line 134

```dart
onPressed: () {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Just enter your phone number to start!')),
  );
},
child: Text('New to Gixbee? Register here'),
```

New users have no way to set their name, role, or profile details.

---

### 15. `WaitingForWorkerScreen` — `_arrivalOtp` can be null when proceeding
**File:** `lib/features/booking/waiting_for_worker_screen.dart` line 71

```dart
setState(() {
  _isAccepted = true;
  _arrivalOtp = statusData['arrivalOtp'];  // can be null if backend hasn't generated yet
});
```

`_confirmAndProceed()` has a null check but the "Confirm & See OTP"
button is shown immediately when `_isAccepted` is true — before the
worker has actually called `markArrived()`. The customer sees a
"success" state and taps "Confirm & See OTP" which triggers the error
dialog "OTP not received. Please contact support."

**Fix:** Show the "Confirm & See OTP" button only when `_arrivalOtp != null`,
otherwise show "Waiting for worker to confirm arrival...":
```dart
if (_isAccepted && _arrivalOtp != null)
  ElevatedButton(onPressed: _confirmAndProceed, child: const Text('Confirm & See OTP'))
else if (_isAccepted)
  const Text('Waiting for worker to confirm arrival at your location...',
      style: TextStyle(color: Colors.grey)),
```

---

### 16. Payment method in `booking_screen.dart` — "UPI / Wallet" tap does nothing
**File:** `lib/features/booking/booking_screen.dart` line 300

```dart
_buildSelectionTile(
  icon: Icons.account_balance_wallet,
  title: 'UPI / Wallet',
  isAction: true,  // shows arrow → implies tappable
),
```

The tile shows an arrow but has no `onTap`. Wallet balance is checked
before booking (good) but the user has no way to switch to a different
payment method or see their wallet balance from this screen.

---

### 17. `booking_type_selector.dart` — no `kDebugMode` note: packages fetched locally
Packages are generated locally with hardcoded multipliers
(`rate * 3.5`, `rate * 6`). In production these should come from the
backend per worker. Flagged as missing backend integration.

---

### 18. `completion_otp_screen.dart` — dispute report just shows a SnackBar
**File:** `lib/features/booking/completion_otp_screen.dart` line 296

```dart
onTap: () {
  Navigator.pop(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Report filed: $reason')),  // ← fake, no API call
  );
},
```

No API call is made. The dispute is never sent to the backend. The
SnackBar tells the user "Report filed" which is false.

---

### 19. `wallet_screen.dart` — top-up amount field allows non-numeric/empty submission
**File:** `lib/features/profile/wallet_screen.dart` line 106

```dart
final amount = double.tryParse(_topUpAmountCtrl.text);
if (amount == null || amount < AppConfig.walletMinTopUp) {
  ScaffoldMessenger.of(context).showSnackBar(...);
  return;
}
```

This guard is correct but the TextField has no `inputFormatters`. Users
can type characters like `-`, `.`, or a leading `0` (e.g. `00100`) that
pass `double.tryParse` but create unexpected amounts. Razorpay receives
`0 * 100 = 0` paise for `0.001`.

**Fix:**
```dart
inputFormatters: [
  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
],
```

---

### 20. `UserStatsProvider` — `ref.watch` inside a `FutureProvider` causes unnecessary rebuilds
**File:** `lib/repositories/profile_repository.dart` line 9

```dart
final userStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  final user = await ref.watch(currentUserProvider.future);  // ← ref.watch inside FutureProvider
```

Using `ref.watch` inside a `FutureProvider` is incorrect — it should
be `ref.read`. `ref.watch` inside async providers can cause the
provider to re-run unnecessarily whenever `currentUserProvider`
invalidates, including mid-execution, potentially causing duplicate
API calls or state corruption.

**Fix:**
```dart
final userStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final user = await ref.read(currentUserProvider.future);  // ref.read, not ref.watch
  if (user == null) return {'bookings': 0, 'reviews': 0, 'saved': 0};
  return ref.read(profileRepositoryProvider).getUserStats(user.id);
});
```

---

## 🔵 UX GAPS

---

### 21. `otp_screen.dart` — auth OTP has no backspace focus handling
**File:** `lib/features/auth/otp_screen.dart` lines 160–170

```dart
onChanged: (value) {
  setState(() {});
  if (value.isNotEmpty && index < AppConfig.otpLength - 1) {
    FocusScope.of(context).nextFocus();
  }
  // ← No handling for value.isEmpty (backspace)
  // Cursor stays on current field instead of going back
},
```

Booking OTPs (arrival + completion) fixed backspace handling but the
auth login OTP still has no backspace navigation. Fixing one and not
the other creates inconsistent UX.

**Fix:** Add `else if (value.isEmpty && index > 0) { FocusScope.of(context).previousFocus(); }` 

---

### 22. `booking_screen.dart` — payment step shows wallet as option but no balance displayed
The payment step shows "UPI / Wallet" but the user has no idea how
much wallet balance they have or whether it's sufficient. Balance
check only happens on tap of "Pay & Confirm" (too late — after the
user has committed).

---

### 23. `waiting_for_worker_screen.dart` — worker avatar uses `NetworkImage` with no error handler
**File:** `lib/features/booking/waiting_for_worker_screen.dart` line 163

```dart
CircleAvatar(
  radius: 40,
  backgroundImage: NetworkImage(widget.worker.imageUrl),
  // ← no errorBuilder — shows broken image on network failure
),
```

**Fix:**
```dart
CircleAvatar(
  radius: 40,
  backgroundImage: NetworkImage(widget.worker.imageUrl),
  onBackgroundImageError: (_, __) {},
  child: widget.worker.imageUrl.isEmpty
      ? Text(widget.worker.name[0], style: const TextStyle(fontSize: 24))
      : null,
),
```

---

### 24. `home_screen.dart` — "Rentals" category button has empty `onTap: () {}`
**File:** `lib/features/home/home_screen.dart`

```dart
{
  'title': 'Rentals',
  'icon': Icons.category_rounded,
  'onTap': () {},   // ← completely dead, no navigation, no snackbar
},
```

Tapping "Rentals" does nothing with zero feedback. Users tap it
repeatedly thinking it's broken.

---

### 25. `booking_type_selector.dart` — "Continue to Checkout" enabled before any package tapped
**File:** `lib/features/booking/booking_type_selector.dart`

The `FilledButton` at the bottom is enabled when `_selectedType != null`
(i.e. when the user picks "Package" tab). But since no package card is
actually selected (issue #3), tapping "Continue to Checkout" immediately
proceeds with `_packages.first` regardless of what the user intended.
The button label says "Continue to Checkout" but the user never actually
chose a package.

---

## Fix Priority

| Priority | Issue | File | Effort |
|---|---|---|---|
| P0 | Firebase no options — init fails | `main.dart` | 2 min |
| P0 | NotificationService 3 separate instances | `main.dart` | 2 min |
| P0 | PackageCard never stores selection | `booking_type_selector.dart` | 5 min |
| P0 | Supabase removed from main but used in auth | `main.dart` | 10 min |
| P1 | devOtp auto-fills with no kDebugMode guard | `otp_screen.dart`, `login_screen.dart` | 5 min |
| P1 | NotificationsScreen import — file doesn't exist | `home_screen.dart` | 5 min |
| P1 | Location picked but never stored | `booking_type_selector.dart` | 2 min |
| P1 | WaitingForWorker — OTP button shown before OTP ready | `waiting_for_worker_screen.dart` | 5 min |
| P1 | OTP resend timer restarts before API call succeeds | `otp_screen.dart` | 5 min |
| P1 | ref.watch inside FutureProvider (stats) | `profile_repository.dart` | 2 min |
| P2 | User profile null when Razorpay opens | `wallet_screen.dart` | 5 min |
| P2 | Dispute report never sent to backend | `completion_otp_screen.dart` | Medium |
| P2 | No backspace handling in auth OTP | `otp_screen.dart` | 5 min |
| P2 | Notifications option — dead tap | `profile_screen.dart` | 2 min |
| P2 | Help & Support option — dead tap | `profile_screen.dart` | 2 min |
| P2 | Wallet top-up amount no input formatter | `wallet_screen.dart` | 5 min |
| P3 | No role selection onboarding | New screen | High |
| P3 | No registration flow | `login_screen.dart` | High |
| P3 | Payment method shows no wallet balance | `booking_screen.dart` | Medium |
| P3 | Worker avatar no error handler | `waiting_for_worker_screen.dart` | 2 min |
| P3 | Rentals category dead tap | `home_screen.dart` | 5 min |
| P3 | Continue button active before package chosen | `booking_type_selector.dart` | 5 min |
| P3 | Packages from local multipliers not backend | `booking_type_selector.dart` | High |
| P3 | Payment method not selectable | `booking_screen.dart` | Medium |
