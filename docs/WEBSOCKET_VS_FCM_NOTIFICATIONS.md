# WebSockets vs FCM — Push Notification Architecture

> **Short answer:** WebSockets can replace FCM **only when the app is open**.  
> When the app is in the background or killed, the OS terminates the socket connection.  
> You need a hybrid approach — or accept that background notifications won't work.

---

## The Core Limitation — Why WebSockets Alone Can't Replace FCM

```
App State          WebSocket Works?    FCM Works?
─────────────────────────────────────────────────
Foreground         ✅ YES              ✅ YES
Background         ❌ NO (killed)      ✅ YES
App killed/closed  ❌ NO (no process)  ✅ YES
```

**Why the OS kills WebSockets in the background:**

- **Android:** Doze mode + battery optimization aggressively closes background network connections
  after ~1 minute of the app going to background. Even with foreground services, sockets are
  unreliable.
- **iOS:** Even stricter. Background execution time is capped at ~30 seconds. Socket connections
  are terminated immediately unless you use VoIP pushes (only for call apps).

FCM/APNs work because they go through Google/Apple's own always-on system-level push channel
that bypasses these restrictions entirely. The OS maintains this channel, not your app.

---

## Good news — You Already Have WebSockets in Gixbee

Looking at your existing `lib/services/socket_service.dart`, you already have:

```dart
// socket_service.dart — already in the project
_socket = io.io(AppConfig.socketUrl, io.OptionBuilder()
  .setTransports(['websocket'])
  .setAuth({'token': token})
  .enableAutoConnect()
  .build());
```

This means **foreground notifications via WebSocket require zero new dependencies**.  
You just need to extend `SocketService` with notification event listeners.

---

## The Hybrid Architecture (Recommended for Gixbee)

```
┌─────────────────────────────────────────────────────────┐
│                    NestJS Backend                       │
│                                                         │
│   Booking created ──► 1. Emit socket event              │
│                    ──► 2. Send FCM/OneSignal push       │
└──────────────┬────────────────────┬────────────────────┘
               │ WebSocket          │ FCM / OneSignal
               ▼                    ▼
        App is OPEN          App is BACKGROUND
        (foreground)         or KILLED
        Instant, rich        Delivered by OS
        in-app popup         System notification tray
```

**NestJS emits both simultaneously.** The Flutter app handles whichever arrives:
- If the app is open → socket event fires → show in-app dialog
- If the app is closed → FCM/OneSignal delivers to tray → user taps → app opens

This is what production apps like Swiggy, Uber, and Zomato do.

---

## Option A — WebSocket Only (Foreground Only)

Choose this if:
- Your workers are expected to always have the app open while on duty
- You are OK with workers missing notifications if the app is killed
- You want zero Firebase/OneSignal dependency

### Extend `SocketService` for notifications

```dart
// lib/services/socket_service.dart — extended
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';

// Notification payload model
class SocketNotification {
  final String type;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;

  SocketNotification({
    required this.type,
    this.title,
    this.body,
    required this.data,
  });

  factory SocketNotification.fromMap(Map<String, dynamic> map) {
    return SocketNotification(
      type: map['type'] as String,
      title: map['title'] as String?,
      body: map['body'] as String?,
      data: Map<String, dynamic>.from(map['data'] as Map? ?? {}),
    );
  }
}

final socketServiceProvider = Provider((ref) => SocketService());

// Riverpod stream for notification events — listen from UI
final socketNotificationProvider = StreamProvider<SocketNotification>((ref) {
  return ref.watch(socketServiceProvider).notificationStream;
});

class SocketService {
  io.Socket? _socket;

  // Stream controller for notification events
  final _notificationController =
      StreamController<SocketNotification>.broadcast();

  Stream<SocketNotification> get notificationStream =>
      _notificationController.stream;

  io.Socket? get socket => _socket;

  void connect(String token) {
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()          // auto-reconnect on drop
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Socket] Connected');
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Socket] Disconnected');
    });

    _socket!.onConnectError((data) {
      debugPrint('[Socket] Connection error: $data');
    });

    // ── Notification events ─────────────────────────────────
    _socket!.on('notification', (data) {
      try {
        final notification = SocketNotification.fromMap(
          Map<String, dynamic>.from(data as Map),
        );
        _notificationController.add(notification);
        debugPrint('[Socket] Notification received: ${notification.type}');
      } catch (e) {
        debugPrint('[Socket] Failed to parse notification: $e');
      }
    });

    // ── Booking-specific events ─────────────────────────────
    _socket!.on('new_booking_request', (data) {
      _notificationController.add(SocketNotification(
        type: 'new_booking',
        title: 'New Job Request',
        body: 'A customer has requested your services.',
        data: Map<String, dynamic>.from(data as Map),
      ));
    });

    _socket!.on('booking_accepted', (data) {
      _notificationController.add(SocketNotification(
        type: 'booking_accepted',
        title: 'Request Accepted!',
        body: 'Your worker is on the way.',
        data: Map<String, dynamic>.from(data as Map),
      ));
    });

    _socket!.on('booking_cancelled', (data) {
      _notificationController.add(SocketNotification(
        type: 'booking_cancelled',
        title: 'Booking Cancelled',
        body: 'The booking was cancelled.',
        data: Map<String, dynamic>.from(data as Map),
      ));
    });
  }

  // ── Existing methods (unchanged) ────────────────────────
  void updateLocation(String userId, double lat, double lng, {String? jobId}) {
    if (_socket?.connected ?? false) {
      _socket!.emit('updateLocation', {
        'userId': userId,
        'lat': lat,
        'lng': lng,
        if (jobId != null) 'jobId': jobId,
      });
    }
  }

  void joinJobRoom(String jobId) {
    _socket?.emit('joinJobRoom', {'jobId': jobId});
  }

  void onLocationUpdated(Function(Map<String, dynamic>) callback) {
    _socket?.on('locationUpdated',
        (data) => callback(data as Map<String, dynamic>));
  }

  void disconnect() {
    _notificationController.close();
    _socket?.disconnect();
  }
}
```

### Listen for notifications in `main_wrapper.dart`

```dart
// Replace _initMessaging() in main_wrapper.dart
@override
void initState() {
  super.initState();
  _initSocket();
  _listenForNotifications();  // replaces _initMessaging()
}

void _listenForNotifications() {
  // Listen to the socket notification stream via Riverpod
  ref.listen<AsyncValue<SocketNotification>>(
    socketNotificationProvider,
    (_, next) {
      next.whenData((notification) {
        if (notification.type == 'new_booking') {
          _showJobRequestPopup(
            notification.title ?? 'New Job Request',
            notification.body ?? 'A customer requested your services.',
            notification.data['bookingId'] as String?,
          );
        }
      });
    },
  );
}
```

### NestJS — emit socket events

```typescript
// In your NestJS BookingsGateway or BookingsService
@Injectable()
export class BookingsService {
  constructor(
    @InjectRepository(Booking) private bookingRepo: Repository<Booking>,
    private readonly gateway: BookingsGateway,   // your existing WS gateway
  ) {}

  async createBooking(dto: CreateBookingDto): Promise<Booking> {
    const booking = await this.bookingRepo.save(dto);

    // Emit to the worker's socket room
    this.gateway.server
      .to(`user:${booking.workerId}`)
      .emit('new_booking_request', {
        bookingId: booking.id,
        skill: booking.skill,
        customerName: booking.customerName,
        amount: booking.amount,
      });

    return booking;
  }
}
```

```typescript
// bookings.gateway.ts — room management
@WebSocketGateway({ cors: true })
export class BookingsGateway implements OnGatewayConnection {
  @WebSocketServer() server: Server;

  handleConnection(client: Socket) {
    const userId = client.handshake.auth.userId;  // from JWT
    if (userId) {
      client.join(`user:${userId}`);  // join personal room
      console.log(`User ${userId} connected and joined room`);
    }
  }
}
```

---

## Option B — Hybrid (WebSocket + local_notifications for background)

This is the closest you can get to replacing FCM without using FCM. Works for foreground
and most background cases on Android, but **not for killed app on iOS**.

Use `flutter_local_notifications` to show system tray notifications from within the app,
and use a **foreground service** on Android to keep the socket alive.

```yaml
# pubspec.yaml additions
flutter_local_notifications: ^17.2.2
flutter_foreground_task: ^8.14.0  # keeps socket alive on Android background
```

```dart
// lib/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'gixbee_channel',
      'Gixbee Notifications',
      channelDescription: 'Job and booking alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: payload.toString(),
    );
  }
}
```

Then in your socket notification listener, call `NotificationService.showNotification()`
when a socket event arrives — this displays a real system tray notification even if the
app is technically backgrounded but kept alive by the foreground service.

---

## Option C — Hybrid (WebSocket foreground + FCM/OneSignal background)

The most robust option. Keep your existing `socket_io_client` for foreground real-time
events and add OneSignal only for background delivery. Your NestJS backend sends both:

```typescript
async notifyWorker(workerId: string, bookingId: string) {
  // 1. Socket — instant if app is open
  this.gateway.server
    .to(`user:${workerId}`)
    .emit('new_booking_request', { bookingId });

  // 2. OneSignal — fallback if app is closed
  await this.oneSignalService.sendToUser(workerId, {
    title: 'New Job Request',
    body: 'A customer requested your services.',
    data: { type: 'new_booking', bookingId },
  });
}
```

The Flutter app deduplicates: if the socket event arrives, dismiss any push notification
that subsequently arrives for the same bookingId.

---

## Comparison Table

| | WebSocket Only | WebSocket + local_notifications | WebSocket + OneSignal |
|---|---|---|---|
| App open (foreground) | ✅ | ✅ | ✅ |
| App in background (Android) | ❌ | ✅ (with foreground service) | ✅ |
| App in background (iOS) | ❌ | ❌ | ✅ |
| App killed | ❌ | ❌ | ✅ |
| Firebase dependency | ❌ None | ❌ None | ❌ None |
| New Flutter packages needed | None (already have socket_io_client) | 2 packages | 1 package |
| NestJS changes needed | Minimal (emit events) | Minimal | Add OneSignal HTTP call |
| Works for Gixbee workers? | Only if app always open | Mostly yes | Yes, fully |

---

## Recommendation for Gixbee

Given that Gixbee is a **job dispatch app** where workers need to receive booking requests
even when the app is not open, the realistic options are:

**If you want zero external push services:**
→ Go with **Option B** (WebSocket + foreground service + local_notifications)
→ Acceptable tradeoff: iOS background delivery unreliable, killed app won't receive

**If you want full reliability across all states:**
→ Go with **Option C** (WebSocket foreground + OneSignal background)
→ No Firebase at all. OneSignal is free for the scale you need.
→ Your existing `socket_service.dart` handles foreground; OneSignal handles the rest.

**If your workers always keep the app open while on duty:**
→ Go with **Option A** (WebSocket only — extend existing `socket_service.dart`)
→ Zero new dependencies. Already 80% implemented in your project.

---

## What changes if you choose Option A (WebSocket Only)

Files to change:

| File | Change |
|---|---|
| `lib/services/socket_service.dart` | Add notification stream + event listeners (shown above) |
| `lib/main_wrapper.dart` | Replace `_initMessaging()` with `_listenForNotifications()` |
| `lib/features/auth/otp_screen.dart` | Remove `FirebaseMessaging.instance.getToken()` entirely |
| `lib/repositories/auth_repository.dart` | Remove `registerFcmToken()` entirely |
| `pubspec.yaml` | Remove `firebase_core`, `firebase_auth`, `firebase_messaging` |
| `lib/main.dart` | Remove `Firebase.initializeApp()` |
| `lib/firebase_options.dart` | Delete file |
| `android/app/google-services.json` | Delete file |

**No new packages needed** — `socket_io_client` is already in your `pubspec.yaml`.
