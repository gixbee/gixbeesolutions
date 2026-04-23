# OneSignal Push Notification — Complete Implementation Guide

> Replace all Firebase push notification dependencies with OneSignal.  
> No FCM config, no google-services.json, no firebase_options.dart.

---

## What changes

| | Before | After |
|---|---|---|
| Flutter packages | `firebase_core`, `firebase_auth`, `firebase_messaging` | `onesignal_flutter` |
| Config files | `firebase_options.dart`, `google-services.json` | None |
| Token registration | `FirebaseMessaging.instance.getToken()` | `OneSignal.User.pushSubscription.id` |
| Foreground listener | `FirebaseMessaging.onMessage.listen()` | `OneSignal.Notifications.addForegroundWillDisplayListener()` |
| Backend | No change in pattern — just different HTTP endpoint | OneSignal REST API |

---

## Step 1 — OneSignal Setup (5 minutes)

1. Go to [onesignal.com](https://onesignal.com) → Create free account → New App → name it **Gixbee**
2. Select **Google Android (FCM)**
   - Go to [console.firebase.google.com](https://console.firebase.google.com)
   - Open your project → Project Settings → Cloud Messaging
   - Copy the **Server Key** → paste into OneSignal
   - This is the only time you touch Firebase — OneSignal uses it internally, your Flutter code does not
3. Select **Apple iOS (APNs)** → upload your `.p8` key
4. Select **Flutter** as the SDK
5. Copy your **OneSignal App ID** and **REST API Key** — save these

---

## Step 2 — `pubspec.yaml`

**Remove these 3 lines:**
```yaml
firebase_core: ^3.1.0
firebase_auth: ^5.1.0
firebase_messaging: ^15.0.0
```

**Add this 1 line:**
```yaml
onesignal_flutter: ^5.2.6
```

Run:
```bash
flutter pub get
```

---

## Step 3 — Android setup

Open `android/app/build.gradle` and add inside `defaultConfig`:
```gradle
manifestPlaceholders = [
    onesignal_app_id: "<YOUR_ONESIGNAL_APP_ID>"
]
```

Remove from `android/app/build.gradle` (bottom of file):
```gradle
// REMOVE this line:
apply plugin: 'com.google.gms.google-services'
```

Remove from `android/build.gradle`:
```gradle
// REMOVE from dependencies block:
classpath 'com.google.gms:google-services:4.x.x'
```

Delete:
```
android/app/google-services.json   ← delete this file
```

---

## Step 4 — iOS setup

In `ios/Runner/AppDelegate.swift`, no changes needed — OneSignal handles this automatically.

In `ios/Podfile`, ensure minimum iOS version:
```ruby
platform :ios, '13.0'
```

Then run:
```bash
cd ios && pod install && cd ..
```

---

## Step 5 — Delete Firebase files

```
lib/firebase_options.dart              ← delete
android/app/google-services.json      ← delete
ios/Runner/GoogleService-Info.plist   ← delete if it exists
```

---

## Step 6 — Create `lib/services/notification_service.dart`

This is the single file that replaces all Firebase Messaging code:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

final notificationServiceProvider =
    Provider((ref) => NotificationService());

class NotificationService {

  /// Call once in main() — replaces Firebase.initializeApp() + messaging setup
  Future<void> initialize() async {
    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    OneSignal.initialize(
      const String.fromEnvironment('ONESIGNAL_APP_ID'),
    );

    // Request permission — replaces messaging.requestPermission()
    await OneSignal.Notifications.requestPermission(true);

    debugPrint('[OneSignal] Initialized');
  }

  /// Get the push token to register with your NestJS backend.
  /// Replaces: FirebaseMessaging.instance.getToken()
  Future<String?> getDeviceToken() async {
    return OneSignal.User.pushSubscription.id;
  }

  /// Associate this device with a user ID for targeted notifications.
  /// Call after successful login.
  void identifyUser(String userId) {
    OneSignal.login(userId);
    debugPrint('[OneSignal] User identified: $userId');
  }

  /// Clear user identity on logout.
  void clearUser() {
    OneSignal.logout();
  }

  /// Listen for notifications while the app is in the foreground.
  /// Replaces: FirebaseMessaging.onMessage.listen()
  void addForegroundListener(
    void Function(OSNotificationWillDisplayEvent event) handler,
  ) {
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.notification.display(); // show the system notification
      handler(event);
    });
  }

  /// Listen for when the user taps a notification.
  /// Replaces: FirebaseMessaging.onMessageOpenedApp.listen()
  void addClickListener(
    void Function(OSNotificationClickEvent event) handler,
  ) {
    OneSignal.Notifications.addClickListener(handler);
  }
}
```

---

## Step 7 — Update `lib/main.dart`

**Before:**
```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// inside main():
try {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ).timeout(const Duration(seconds: 5));
} catch (e) {
  debugPrint('Firebase initialization timed out or failed: $e');
}
```

**After:**
```dart
// No firebase imports
import 'services/notification_service.dart';

// inside main():
await NotificationService().initialize();
```

Full updated `main()`:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  registerDefaultPlugins();

  await NotificationService().initialize(); // ← replaces Firebase.initializeApp

  const buildVersion = String.fromEnvironment('BUILD_VERSION', defaultValue: 'dev');
  debugPrint('GIXBEE_BUILD_VERSION: $buildVersion');

  runApp(const ProviderScope(child: GixbeeApp()));
}
```

---

## Step 8 — Update `lib/main_wrapper.dart`

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
import 'services/notification_service.dart';

Future<void> _initMessaging() async {
  final notifService = ref.read(notificationServiceProvider);

  // Foreground notifications
  notifService.addForegroundListener((event) {
    final data = event.notification.additionalData;
    if (data != null && data['type'] == 'new_booking') {
      _showJobRequestPopup(
        event.notification.title ?? 'New Job Request',
        event.notification.body  ?? 'A customer requested your services.',
        data['bookingId'] as String?,
      );
    }
  });

  // Notification tapped (background / killed state)
  notifService.addClickListener((event) {
    final data = event.notification.additionalData;
    if (data != null && data['type'] == 'new_booking') {
      // TODO: navigate to the booking screen
      debugPrint('[OneSignal] Booking tapped: ${data['bookingId']}');
    }
  });
}
```

---

## Step 9 — Update `lib/features/auth/otp_screen.dart`

**Before:**
```dart
import 'package:firebase_messaging/firebase_messaging.dart';

// After OTP verified:
final fcmToken = await FirebaseMessaging.instance.getToken();
if (fcmToken != null) {
  await ref.read(authRepositoryProvider).registerFcmToken(fcmToken);
}
```

**After:**
```dart
import '../../services/notification_service.dart';

// After OTP verified:
final notifService = ref.read(notificationServiceProvider);

// Register push token with backend
final pushToken = await notifService.getDeviceToken();
if (pushToken != null) {
  await ref.read(authRepositoryProvider).registerPushToken(pushToken);
}

// Identify user in OneSignal for targeted pushes
final user = await ref.read(currentUserProvider.future);
if (user != null) {
  notifService.identifyUser(user.id);
}
```

---

## Step 10 — Update `lib/repositories/auth_repository.dart`

Rename `registerFcmToken` → `registerPushToken`:

```dart
// Remove:
Future<void> registerFcmToken(String token) async {
  await _dio.patch('/auth/fcm-token', data: {'fcmToken': token});
}

// Add:
Future<void> registerPushToken(String token) async {
  try {
    await _dio.patch('/auth/push-token', data: {'pushToken': token});
  } catch (e) {
    debugPrint('Push token registration failed: $e');
  }
}
```

---

## Step 11 — NestJS Backend

### Install
```bash
npm install axios   # already likely installed
```

### Create `src/notifications/notifications.service.ts`
```typescript
import { Injectable, Logger } from '@nestjs/common';
import axios from 'axios';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);
  private readonly appId = process.env.ONESIGNAL_APP_ID;
  private readonly apiKey = process.env.ONESIGNAL_REST_API_KEY;
  private readonly url = 'https://onesignal.com/api/v1/notifications';

  async sendToUser(
    userId: string,
    payload: {
      title: string;
      body: string;
      data?: Record<string, unknown>;
    },
  ): Promise<void> {
    try {
      await axios.post(
        this.url,
        {
          app_id: this.appId,
          include_aliases: { external_id: [userId] },
          target_channel: 'push',
          headings: { en: payload.title },
          contents: { en: payload.body },
          data: payload.data ?? {},
        },
        {
          headers: {
            Authorization: `Key ${this.apiKey}`,
            'Content-Type': 'application/json',
          },
        },
      );
      this.logger.log(`Push sent to user ${userId}`);
    } catch (error) {
      this.logger.error(`Failed to send push to ${userId}`, error);
    }
  }

  // Booking-specific helpers
  async notifyWorkerNewBooking(workerId: string, bookingId: string) {
    await this.sendToUser(workerId, {
      title: 'New Job Request',
      body: 'A customer has requested your services.',
      data: { type: 'new_booking', bookingId },
    });
  }

  async notifyCustomerBookingAccepted(customerId: string, workerName: string) {
    await this.sendToUser(customerId, {
      title: 'Request Accepted!',
      body: `${workerName} is on the way.`,
      data: { type: 'booking_accepted' },
    });
  }

  async notifyBookingCancelled(userId: string) {
    await this.sendToUser(userId, {
      title: 'Booking Cancelled',
      body: 'Your booking has been cancelled.',
      data: { type: 'booking_cancelled' },
    });
  }
}
```

### Register in `notifications.module.ts`
```typescript
import { Module } from '@nestjs/common';
import { NotificationsService } from './notifications.service';

@Module({
  providers: [NotificationsService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
```

### Use in `bookings.service.ts`
```typescript
constructor(
  private readonly notificationsService: NotificationsService,
) {}

async createBooking(dto: CreateBookingDto) {
  const booking = await this.bookingRepo.save(dto);
  
  // Notify the worker
  await this.notificationsService.notifyWorkerNewBooking(
    booking.workerId,
    booking.id,
  );

  return booking;
}
```

### Add to `.env`
```
ONESIGNAL_APP_ID=your-onesignal-app-id
ONESIGNAL_REST_API_KEY=your-onesignal-rest-api-key
```

---

## Step 12 — dart-define for local development

Update your run command:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
  --dart-define=SOCKET_URL=http://10.0.2.2:3000 \
  --dart-define=ONESIGNAL_APP_ID=your-onesignal-app-id \
  --dart-define=RAZORPAY_KEY=rzp_test_xxx \
  --dart-define=BUILD_VERSION=1.1.0
```

---

## Files deleted

```
lib/firebase_options.dart
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
```

## Files changed

```
pubspec.yaml                            remove 3 firebase deps, add onesignal_flutter
lib/main.dart                           remove Firebase.initializeApp, add NotificationService
lib/main_wrapper.dart                   replace FirebaseMessaging with NotificationService
lib/features/auth/otp_screen.dart       replace getToken() with OneSignal token
lib/repositories/auth_repository.dart  rename registerFcmToken → registerPushToken
```

## Files created

```
lib/services/notification_service.dart  OneSignal wrapper
src/notifications/notifications.service.ts  NestJS push service
src/notifications/notifications.module.ts   NestJS module
```

---

## Verification checklist

- [ ] `flutter pub get` runs clean
- [ ] `firebase_options.dart` deleted — zero compile errors
- [ ] App launches without Firebase init
- [ ] OneSignal permission dialog appears on first launch
- [ ] After OTP login, push token sent to `/auth/push-token`
- [ ] Worker receives notification when a booking is created
- [ ] Tapping notification opens app and prints bookingId
- [ ] Background notification arrives when app is minimised
- [ ] Killed-app notification arrives and opens app on tap
- [ ] `flutter analyze` — zero errors
