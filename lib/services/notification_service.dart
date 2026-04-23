import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final notificationServiceProvider =
    Provider((ref) => NotificationService());

/// Background message handler — must be a top-level function (Flutter requirement).
/// NestJS sends the payload; this handles it when the app is killed.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
  // No UI work here — just data processing if needed
}

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Android notification channel for high-priority job alerts.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'gixbee_high_importance',
    'Gixbee Job Alerts',
    description: 'Booking requests and job notifications',
    importance: Importance.max,
    playSound: true,
  );

  /// Call once in main() after Firebase.initializeApp().
  Future<void> initialize() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Request permission (Android 13+ and iOS)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // Create Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // On iOS — show notifications even when app is foreground
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Init local notifications (for foreground display on Android)
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    debugPrint('[FCM] NotificationService initialized');
  }

  /// Returns the FCM device token to register with your NestJS backend.
  /// Call after successful login.
  Future<String?> getDeviceToken() async {
    try {
      final token = await _messaging.getToken();
      debugPrint('[FCM] Device token: $token');
      return token;
    } catch (e) {
      debugPrint('[FCM] Failed to get token: $e');
      return null;
    }
  }

  /// Listen for token refresh — re-register with backend when token rotates.
  void onTokenRefresh(void Function(String token) handler) {
    _messaging.onTokenRefresh.listen(handler);
  }

  /// Listen for foreground messages (app is open).
  /// Displays a local notification and calls [handler] with the message.
  void addForegroundListener(void Function(RemoteMessage message) handler) {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM] Foreground message: ${message.messageId}');

      // Show a local notification so the user sees it even in foreground
      final notification = message.notification;
      final android = message.notification?.android;

      if (notification != null && android != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: android.smallIcon ?? '@mipmap/ic_launcher',
            ),
          ),
        );
      }

      handler(message);
    });
  }

  /// Listen for when the user taps a notification (app in background).
  void addClickListener(void Function(RemoteMessage message) handler) {
    FirebaseMessaging.onMessageOpenedApp.listen(handler);
  }

  /// Check if the app was launched by tapping a notification (app was killed).
  Future<RemoteMessage?> getInitialMessage() async {
    return await _messaging.getInitialMessage();
  }
}
