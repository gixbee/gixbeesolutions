import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

final notificationServiceProvider =
    Provider((ref) => NotificationService());

/// Background message handler — top-level function required by Firebase.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'gixbee_high_importance',
    'Gixbee Job Alerts',
    description: 'Booking requests and job notifications',
    importance: Importance.max,
    playSound: true,
  );

  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

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

  void onTokenRefresh(void Function(String token) handler) {
    _messaging.onTokenRefresh.listen(handler);
  }

  /// Listen for foreground messages — always plays sound/shows banner
  /// regardless of whether the FCM payload has a `notification` block.
  void addForegroundListener(void Function(RemoteMessage message) handler) {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM] Foreground message: ${message.messageId}');

      // Read from notification block OR data block (data-only FCM support)
      final title = message.notification?.title ??
          message.data['title'] as String? ??
          'New Job Request';
      final body = message.notification?.body ??
          message.data['body'] as String? ??
          '';

      // Always show local notification with sound — even for data-only messages
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
          iOS: const DarwinNotificationDetails(
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

  void addClickListener(void Function(RemoteMessage message) handler) {
    FirebaseMessaging.onMessageOpenedApp.listen(handler);
  }

  Future<RemoteMessage?> getInitialMessage() async {
    return _messaging.getInitialMessage();
  }
}
