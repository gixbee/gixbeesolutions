# Firebase Removal — Migration Guide

> **Goal:** Remove all Firebase SDKs (`firebase_core`, `firebase_auth`, `firebase_messaging`,  
> `firebase_options.dart`, `google-services.json`) from the Gixbee Flutter app and replace  
> push notifications with **OneSignal**, while keeping Supabase for auth and real-time.

---

## What the zsasko repo actually teaches us

The [zsasko/flutter-push-notification-sample](https://github.com/zsasko/flutter-push-notification-sample)
demonstrates one key architectural pattern:

> **The NestJS backend calls the FCM HTTP API directly** (via a simple HTTP POST) instead of  
> using the Firebase Admin SDK. The Flutter app still uses `firebase_messaging` to receive.

That repo does **not** remove Firebase from Flutter — it still requires `google-services.json`  
and the `firebase_messaging` package on the device side.

**What we take from it:** The backend pattern — any notification service (OneSignal, FCM, APNs)  
can be triggered from NestJS via a plain HTTP REST call. We apply the same pattern but target  
OneSignal's API instead of FCM directly, which lets us drop all Firebase SDKs from Flutter entirely.

---

## Current Firebase usage in Gixbee

| File | Firebase usage | Remove? |
|---|---|---|
| `pubspec.yaml` | `firebase_core`, `firebase_auth`, `firebase_messaging` | Yes — all 3 |
| `lib/main.dart` | `Firebase.initializeApp()`, `import firebase_core` | Yes |
| `lib/firebase_options.dart` | All Firebase platform credentials | Yes — delete file |
| `android/app/google-services.json` | Firebase project config | Yes — delete file |
| `lib/main_wrapper.dart` | `FirebaseMessaging.instance`, `onMessage.listen()`, `requestPermission()` | Yes — replace |
| `lib/features/auth/otp_screen.dart` | `FirebaseMessaging.instance.getToken()` | Yes — replace |
| `lib/repositories/auth_repository.dart` | `registerFcmToken()` endpoint call | Rename to `registerPushToken()` |

**Note:** `firebase_auth` is listed in `pubspec.yaml` but never imported anywhere in the code.  
It can be removed immediately with no code changes.

---

## Replacement Architecture

```
BEFORE (Firebase):
  Flutter → firebase_messaging → FCM (Google) → Device

AFTER (OneSignal):
  Flutter → onesignal_flutter → OneSignal → FCM/APNs → Device
                                    ↑
                              NestJS backend
                         (HTTP POST to OneSignal API)
```

OneSignal sits between your backend and the platform push services (FCM for Android, APNs for iOS).  
You send one REST call to OneSignal; it handles delivery to all platforms. No google-services.json,  
no firebase_options.dart, no Firebase SDK of any kind in Flutter.

---

## Step-by-Step Migration

---

### Step 1 — Create a OneSignal Account

1. Go to [onesignal.com](https://onesignal.com) and create a free account
2. Create a new app → select **Flutter**
3. For Android: you will need to provide your **FCM Server Key** from Google Cloud Console  
   (OneSignal uses FCM as the delivery channel, but you never touch it in your Flutter code)
4. For iOS: upload your APNs `.p8` key
5. Note down your **OneSignal App ID** and **REST API Key** — you will need these

---

### Step 2 — Update `pubspec.yaml`

**Remove:**
```yaml
firebase_core: ^3.1.0
firebase_auth: ^5.1.0
firebase_messaging: ^15.0.0
```

**Add:**
```yaml
onesignal_flutter: ^5.2.6
flutter_local_notifications: ^17.2.2
```

Then run:
```bash
flutter pub get
```

---

### Step 3 — Delete Firebase files

```bash
# Delete these files entirely:
lib/firebase_options.dart
android/app/google-services.json
ios/Runner/GoogleService-Info.plist   # if it exists
```

Also remove from `android/app/build.gradle`:
```gradle
// REMOVE this line:
apply plugin: 'com.google.gms.google-services'
```

And from `android/build.gradle`:
```gradle
// REMOVE this line from dependencies:
classpath 'com.google.gms:google-services:4.x.x'
```

---

### Step 4 — Create `lib/services/notification_service.dart`

This replaces all Firebase Messaging logic currently spread across `main_wrapper.dart`  
and `otp_screen.dart`.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

final notificationServiceProvider = Provider((ref) => NotificationService());

class NotificationService {
  
  /// Call once on app startup — replaces Firebase.initializeApp() + messaging setup
  Future<void> initialize() async {
    // Set log level (disable in production)
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);

    // Set your OneSignal App ID (from --dart-define)
    OneSignal.initialize(
      const String.fromEnvironment('ONESIGNAL_APP_ID'),
    );

    // Request notification permission (replaces messaging.requestPermission())
    await OneSignal.Notifications.requestPermission(true);
  }

  /// Get the device push token to send to your NestJS backend.
  /// Replaces: FirebaseMessaging.instance.getToken()
  Future<String?> getDeviceToken() async {
    final deviceState = await OneSignal.User.pushSubscription.id;
    return deviceState;
  }

  /// Listen for foreground notifications (replaces FirebaseMessaging.onMessage.listen())
  void onForegroundNotification(
    void Function(OSNotification notification) handler,
  ) {
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      // Display the notification
      event.notification.display();
      // Pass to your handler
      handler(event.notification);
    });
  }

  /// Listen for notification taps (replaces onMessageOpenedApp)
  void onNotificationTapped(
    void Function(OSNotificationClickEvent event) handler,
  ) {
    OneSignal.Notifications.addClickListener(handler);
  }

  /// Tag this user on OneSignal for targeted notifications.
  /// Call after login with the user's ID.
  void identifyUser(String userId) {
    OneSignal.login(userId);
  }

  /// Clear user identity on logout
  void clearUser() {
    OneSignal.logout();
  }
}
```

---

### Step 5 — Update `lib/main.dart`

**Before:**
```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(...);
  registerDefaultPlugins();
  
  try {
    await Firebase.initializeApp(         // ← REMOVE
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Firebase initialization timed out or failed: $e');
  }
  
  runApp(const ProviderScope(child: GixbeeApp()));
}
```

**After:**
```dart
// No firebase imports at all
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  
  registerDefaultPlugins();
  
  // Initialize OneSignal (replaces Firebase.initializeApp)
  await NotificationService().initialize();
  
  const buildVersion = String.fromEnvironment('BUILD_VERSION', defaultValue: 'dev');
  debugPrint('GIXBEE_BUILD_VERSION: $buildVersion');
  
  runApp(const ProviderScope(child: GixbeeApp()));
}
```

---

### Step 6 — Update `lib/main_wrapper.dart`

**Before:**
```dart
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> _initMessaging() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.data['type'] == 'new_booking') {
      final bookingId = message.data['bookingId'];
      _showJobRequestPopup(
        message.notification?.title ?? AppStrings.fcmDefaultTitle,
        message.notification?.body ?? AppStrings.fcmDefaultBody,
        bookingId,
      );
    }
  });
}
```

**After:**
```dart
// No firebase import — use notification service
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'services/notification_service.dart';

Future<void> _initMessaging() async {
  final notificationService = ref.read(notificationServiceProvider);

  // Listen for foreground notifications
  notificationService.onForegroundNotification((notification) {
    final data = notification.additionalData;
    if (data != null && data['type'] == 'new_booking') {
      final bookingId = data['bookingId'] as String?;
      _showJobRequestPopup(
        notification.title ?? AppStrings.fcmDefaultTitle,
        notification.body ?? AppStrings.fcmDefaultBody,
        bookingId,
      );
    }
  });

  // Listen for notification taps (app was in background/killed)
  notificationService.onNotificationTapped((event) {
    final data = event.notification.additionalData;
    if (data != null && data['type'] == 'new_booking') {
      // Navigate to the relevant screen
    }
  });
}
```

---

### Step 7 — Update `lib/features/auth/otp_screen.dart`

**Before:**
```dart
import 'package:firebase_messaging/firebase_messaging.dart';

// After OTP verified:
try {
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken != null) {
    await ref.read(authRepositoryProvider).registerFcmToken(fcmToken);
  }
} catch (e) {
  debugPrint('FCM token registration failed: $e');
}
```

**After:**
```dart
import '../../services/notification_service.dart';

// After OTP verified:
try {
  final pushToken = await ref.read(notificationServiceProvider).getDeviceToken();
  if (pushToken != null) {
    await ref.read(authRepositoryProvider).registerPushToken(pushToken);
  }
  // Also identify the user in OneSignal for targeted pushes
  final user = await ref.read(currentUserProvider.future);
  if (user != null) {
    ref.read(notificationServiceProvider).identifyUser(user.id);
  }
} catch (e) {
  debugPrint('Push token registration failed: $e');
}
```

---

### Step 8 — Update `lib/repositories/auth_repository.dart`

Rename `registerFcmToken` to `registerPushToken` to be provider-agnostic:

```dart
// Before:
Future<void> registerFcmToken(String token) async {
  try {
    await _dio.patch('/auth/fcm-token', data: {'fcmToken': token});
  } catch (e) {
    debugPrint('FCM token save failed: $e');
  }
}

// After:
Future<void> registerPushToken(String token) async {
  try {
    await _dio.patch('/auth/push-token', data: {'pushToken': token});
  } catch (e) {
    debugPrint('Push token save failed: $e');
  }
}
```

Update the NestJS backend endpoint accordingly:  
`PATCH /auth/fcm-token` → `PATCH /auth/push-token`

---

### Step 9 — Update NestJS Backend (zsasko pattern applied to OneSignal)

This is where the zsasko repo's lesson directly applies. Instead of calling FCM HTTP API  
directly (like zsasko does), call the OneSignal REST API — same pattern, different endpoint.

**Install in NestJS:**
```bash
npm install @onesignal/node-onesignal
# or just use axios — no SDK needed
```

**Create `notifications.service.ts`:**
```typescript
import { Injectable } from '@nestjs/common';
import axios from 'axios';

@Injectable()
export class NotificationsService {
  private readonly oneSignalAppId = process.env.ONESIGNAL_APP_ID;
  private readonly oneSignalApiKey = process.env.ONESIGNAL_REST_API_KEY;
  private readonly baseUrl = 'https://onesignal.com/api/v1/notifications';

  // Send a push notification to a specific user by their OneSignal external_id
  async sendToUser(userId: string, payload: {
    title: string;
    body: string;
    data?: Record<string, unknown>;
  }): Promise<void> {
    await axios.post(
      this.baseUrl,
      {
        app_id: this.oneSignalAppId,
        include_aliases: { external_id: [userId] },
        target_channel: 'push',
        headings: { en: payload.title },
        contents: { en: payload.body },
        data: payload.data ?? {},
      },
      {
        headers: {
          Authorization: `Key ${this.oneSignalApiKey}`,
          'Content-Type': 'application/json',
        },
      },
    );
  }

  // Example: notify a worker of a new booking request
  async notifyWorkerNewBooking(workerId: string, bookingId: string): Promise<void> {
    await this.sendToUser(workerId, {
      title: 'New Job Request',
      body: 'A customer has requested your services.',
      data: {
        type: 'new_booking',
        bookingId,
      },
    });
  }
}
```

**In your booking controller/service, inject and call:**
```typescript
// When a booking is created:
await this.notificationsService.notifyWorkerNewBooking(workerId, booking.id);
```

**Environment variables to add to `.env`:**
```
ONESIGNAL_APP_ID=your-onesignal-app-id
ONESIGNAL_REST_API_KEY=your-onesignal-rest-api-key
```

---

### Step 10 — Add OneSignal App ID to dart-define

Update `AppConfig`:
```dart
static String get oneSignalAppId => const String.fromEnvironment(
  'ONESIGNAL_APP_ID',
);
```

Run the app with:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
  --dart-define=ONESIGNAL_APP_ID=your-onesignal-app-id \
  --dart-define=RAZORPAY_KEY=rzp_test_xxx \
  --dart-define=BUILD_VERSION=1.1.0
```

---

## Supabase Realtime — for in-app foreground events

Since you already have Supabase, you can supplement OneSignal push with Supabase Realtime  
for instant in-app updates when the app is foregrounded. This gives you two notification layers:

| Scenario | Mechanism |
|---|---|
| App is open (foreground) | Supabase Realtime subscription |
| App is in background | OneSignal push notification |
| App is killed | OneSignal push notification |

**Example — listen for new bookings in real-time:**
```dart
// In notification_service.dart or a dedicated realtime_service.dart
void subscribeToBookings(String workerId, void Function(Map) onNewBooking) {
  Supabase.instance.client
    .from('bookings')
    .stream(primaryKey: ['id'])
    .eq('worker_id', workerId)
    .listen((data) {
      for (final booking in data) {
        if (booking['status'] == 'PENDING') {
          onNewBooking(booking);
        }
      }
    });
}
```

---

## Files to Delete After Migration

```
lib/firebase_options.dart              ← delete entirely
android/app/google-services.json       ← delete entirely
ios/Runner/GoogleService-Info.plist    ← delete if present
```

## Files Modified

```
pubspec.yaml                           ← remove 3 firebase deps, add onesignal + local_notifications
lib/main.dart                          ← remove firebase init, add OneSignal init
lib/main_wrapper.dart                  ← remove firebase_messaging import, use NotificationService
lib/features/auth/otp_screen.dart      ← replace getToken() with OneSignal device token
lib/repositories/auth_repository.dart ← rename registerFcmToken → registerPushToken
```

## Files Created

```
lib/services/notification_service.dart ← new: wraps all OneSignal logic
```

---

## What you gain by removing Firebase

| Before | After |
|---|---|
| 3 Firebase packages (~15MB added to APK) | 1 OneSignal package (~3MB) |
| `google-services.json` must be in repo or CI | No platform config files needed |
| `firebase_options.dart` with live API keys committed | Zero credentials in Flutter code |
| Firebase project tied to Google account | OneSignal is provider-agnostic |
| iOS requires APNs setup via Firebase Console | iOS APNs configured directly in OneSignal |
| Firebase Auth listed but unused (dead dependency) | Removed |
| Android build requires `google-services` gradle plugin | Removed |

---

## Verification checklist

After completing the migration, verify each scenario:

- [ ] `flutter pub get` runs without errors
- [ ] App builds without Firebase imports
- [ ] `firebase_options.dart` is deleted and not referenced anywhere
- [ ] `google-services.json` is deleted
- [ ] On first launch, OneSignal permission prompt appears
- [ ] After OTP login, device token is sent to backend (`/auth/push-token`)
- [ ] When a booking is created, the worker receives a push notification
- [ ] Tapping the notification opens the app and handles the data payload
- [ ] Background notifications arrive when app is killed
- [ ] `flutter analyze` shows zero errors
