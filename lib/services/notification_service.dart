import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  // ── User alert preferences (Settings → Notifications) ────────────────
  // Android 8+ makes sound/vibration CHANNEL-level and immutable after the
  // channel is created — per-notification flags are ignored. So we create
  // four channels up-front and route each alert to the one matching the
  // prefs. Applies to app-shown banners (foreground FCM + poll alerts);
  // system-rendered notifications when the app is killed follow the phone's
  // own settings for the payload's channel.
  static const _storage = FlutterSecureStorage();
  static const _kSound = 'notif_sound_enabled';
  static const _kVibration = 'notif_vibration_enabled';

  bool soundEnabled = true;
  bool vibrationEnabled = true;

  Future<void> setSoundEnabled(bool on) async {
    soundEnabled = on;
    try {
      await _storage.write(key: _kSound, value: on ? '1' : '0');
    } catch (_) {}
  }

  Future<void> setVibrationEnabled(bool on) async {
    vibrationEnabled = on;
    try {
      await _storage.write(key: _kVibration, value: on ? '1' : '0');
    } catch (_) {}
  }

  Future<void> _loadAlertPrefs() async {
    try {
      soundEnabled = (await _storage.read(key: _kSound)) != '0';
      vibrationEnabled = (await _storage.read(key: _kVibration)) != '0';
    } catch (_) {
      // Defaults (on/on) if storage is unavailable.
    }
  }

  /// The channel matching the current sound/vibration prefs.
  String get _activeChannelId => soundEnabled
      ? (vibrationEnabled ? 'gixbee_high_importance_v2' : 'gixbee_alerts_novibe_v2')
      : (vibrationEnabled
          ? 'gixbee_alerts_vibe_only_v2'
          : 'gixbee_alerts_silent_v2');

  static const List<AndroidNotificationChannel> _channels = [
    // Default: sound + vibration, with the custom Gixbee chime
    // (android/app/src/main/res/raw/gixbee_alert.wav). IDs carry a _v2
    // suffix because Android channels are IMMUTABLE after creation — the
    // old default-tone channels can't gain the chime, so new IDs replace
    // them (v1 channels are deleted at init). The backend FCM payload MUST
    // target gixbee_high_importance_v2 for background delivery.
    AndroidNotificationChannel(
      'gixbee_high_importance_v2',
      'Gixbee Job Alerts',
      description: 'Booking requests and job notifications',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('gixbee_alert'),
      enableVibration: true,
    ),
    AndroidNotificationChannel(
      'gixbee_alerts_novibe_v2',
      'Gixbee Job Alerts (no vibration)',
      description: 'Booking requests and job notifications — sound only',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('gixbee_alert'),
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      'gixbee_alerts_vibe_only_v2',
      'Gixbee Job Alerts (vibration only)',
      description: 'Booking requests and job notifications — no sound',
      importance: Importance.max,
      playSound: false,
      enableVibration: true,
    ),
    AndroidNotificationChannel(
      'gixbee_alerts_silent_v2',
      'Gixbee Job Alerts (silent)',
      description: 'Booking requests and job notifications — silent',
      importance: Importance.max,
      playSound: false,
      enableVibration: false,
    ),
  ];

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
  Future<void> initialize({
    void Function(Map<String, String> payload)? onLocalNotificationTap,
  }) async {
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

    // Load persisted sound/vibration prefs BEFORE any banner can show.
    await _loadAlertPrefs();

    // Create all four Android channels (required for Android 8+). Channels
    // are immutable once created — the prefs pick which one each alert uses.
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // Remove the pre-chime v1 channels so updated installs don't show two
    // duplicate "Gixbee Job Alerts" sets in system notification settings.
    for (final oldId in const [
      'gixbee_high_importance',
      'gixbee_alerts_novibe',
      'gixbee_alerts_vibe_only',
      'gixbee_alerts_silent',
    ]) {
      await androidPlugin?.deleteNotificationChannel(channelId: oldId).catchError((_) {});
    }
    for (final ch in _channels) {
      await androidPlugin?.createNotificationChannel(ch);
    }

    // iOS: show notifications even when app is in foreground
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Initialize local notifications plugin (used to show foreground banners)
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty || onLocalNotificationTap == null) {
          return;
        }
        final map = <String, String>{};
        for (final part in raw.split('&')) {
          final i = part.indexOf('=');
          if (i <= 0) continue;
          map[Uri.decodeComponent(part.substring(0, i))] =
              Uri.decodeComponent(part.substring(i + 1));
        }
        onLocalNotificationTap(map);
      },
    );

    _ref.read(debugLogProvider.notifier).log('NotificationService initialized');
  }

  /// Get the FCM device token to register with the backend.
  /// Call after login (in otp_screen) and on token refresh.
  Future<String?> getDeviceToken() async {
    try {
      final token = await _messaging.getToken();
      // Length-guarded: a short/null token must not RangeError.
      final tokenPreview =
          token == null ? 'null' : (token.length > 10 ? token.substring(0, 10) : token);
      _ref.read(debugLogProvider.notifier).log('FCM Token: $tokenPreview...');
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
      final payload = message.data.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
          .join('&');
      _localNotifications.show(
        id: message.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            // Channel selected by the user's sound/vibration prefs — on
            // Android 8+ the CHANNEL decides sound/vibe, not the flags below.
            _activeChannelId,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.high,
            playSound: soundEnabled,
            enableVibration: vibrationEnabled,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            // Custom chime — requires gixbee_alert.wav added to the Runner
            // bundle in Xcode; iOS silently falls back to the default tone
            // until it is.
            sound: soundEnabled ? 'gixbee_alert.wav' : null,
            presentAlert: true,
            presentBadge: true,
            presentSound: soundEnabled,
          ),
        ),
        payload: payload,
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
