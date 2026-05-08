import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'debug_log_service.dart';

final notificationServiceProvider =
    Provider((ref) => NotificationService(ref));

/// Top-level background message handler.
/// Registered in main() ONLY — not in initialize() to avoid double registration.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
  // Firebase is already initialized by main() before this is called.
  // No heavy work here — just log. UI updates happen in onMessageOpenedApp.
}

class NotificationService {
  final Ref _ref;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  NotificationService(this._ref);

  // Guard against calling initialize() more than once.
  // Can happen if both otp_screen and main_wrapper call it.
  bool _initialized = false;

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'gixbee_high_importance',
    'Gixbee Job Alerts',
    description: 'Booking requests and job notifications',
    importance: Importance.max,
    playSound: true,
  );

  /// Initialize FCM listeners, Android channel, local notifications plugin.
  /// Called ONCE from main_wrapper._initNotifications() after login.
  /// DO NOT call from otp_screen — it runs before MainWrapper mounts.
  Future<void> initialize() async {
    if (_initialized) {
      debugPrint('[FCM] Already initialized — skipping');
      return;
    }
    _initialized = true;

    // NOTE: onBackgroundMessage is registered in main() before runApp()
    // so we do NOT register it here — doing so would register it twice.

    // Request permission (Android 13+ and iOS)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _ref.read(debugLogProvider.notifier).log('FCM Permission: ${settings.authorizationStatus}');

    // Create Android high-importance channel (required for Android 8+)
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // iOS: show notifications even when app is in foreground
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Initialize local notifications plugin (used to show foreground banners)
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = const DarwinInitializationSettings();
    await _localNotifications.initialize(
      InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    _ref.read(debugLogProvider.notifier).log('NotificationService initialized');
  }

  /// Get the FCM device token to register with the backend.
  /// Call after login (in otp_screen) and on token refresh.
  Future<String?> getDeviceToken() async {
    try {
      final token = await _messaging.getToken();
      _ref.read(debugLogProvider.notifier).log('FCM Token: ${token?.substring(0, 10)}...');
      return token;
    } catch (e) {
      _ref.read(debugLogProvider.notifier).log('FCM Token Failed: $e');
      return null;
    }
  }

  /// Re-register with backend when FCM rotates the token.
  /// Set up once in main_wrapper._initNotifications().
  void onTokenRefresh(void Function(String token) handler) {
    _messaging.onTokenRefresh.listen(handler);
  }

  /// Listen for messages arriving while app is in the FOREGROUND.
  /// Shows a local notification banner AND calls [handler] for in-app UI.
  /// Works for both data-only and notification+data FCM messages.
  void addForegroundListener(void Function(RemoteMessage message) handler) {
    FirebaseMessaging.onMessage.listen((message) {
      _ref.read(debugLogProvider.notifier).log('FCM Foreground: ${message.notification?.title ?? "Data message"}');

      // Support both notification+data and data-only FCM messages
      final title = message.notification?.title ??
          message.data['title'] as String? ??
          'New Job Request';
      final body = message.notification?.body ??
          message.data['body'] as String? ??
          'A new booking has arrived.';

      // Always show local notification banner with sound in foreground
      _localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );

      handler(message);
    });
  }

  /// Listen for notification taps when app is in the BACKGROUND.
  /// Called when user taps the system tray notification.
  void addClickListener(void Function(RemoteMessage message) handler) {
    FirebaseMessaging.onMessageOpenedApp.listen(handler);
  }

  /// Check if app was launched by tapping a notification (app was KILLED).
  /// Must be called after initialize() to be reliable.
  Future<RemoteMessage?> getInitialMessage() async {
    return _messaging.getInitialMessage();
  }
}
