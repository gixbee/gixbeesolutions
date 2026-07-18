import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ─── API / Network ───────────────────────────────────────
  static String get baseUrl => const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue:
            kIsWeb ? 'http://localhost:3000' : 'http://127.0.0.1:3000',
      );

  static String get socketUrl => const String.fromEnvironment(
        'SOCKET_URL',
        defaultValue:
            kIsWeb ? 'http://localhost:3000' : 'http://127.0.0.1:3000',
      );

  static const int httpTimeoutSeconds = 15;

  // ─── Ola Maps (tiles + directions) ───────────────────────
  // Build with: flutter run --dart-define=OLA_MAPS_API_KEY=xxxx
  // Empty key → tracking screen shows a graceful "map unavailable" panel
  // (status/OTP/pause logic keeps working) and skips Directions calls.
  static const String olaMapsApiKey = String.fromEnvironment(
    'OLA_MAPS_API_KEY',
    defaultValue: '',
  );

  /// MapLibre style JSON for Ola's default light style.
  static String get olaStyleUrl =>
      'https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json?api_key=$olaMapsApiKey';

  static const String olaDirectionsUrl =
      'https://api.olamaps.io/routing/v1/directions';

  // ─── Auth / OTP ──────────────────────────────────────────
  static const int otpLength = 6;           // login/auth OTP
  static const int bookingOtpLength = 4;    // arrival + completion OTP
  static const int otpResendSeconds = 30;
  static const int phoneMinLength = 13;
  static const String defaultCountryCode = '+91';

  // ─── Payments ────────────────────────────────────────────
  static String get razorpayKey => const String.fromEnvironment(
        'RAZORPAY_KEY',
        defaultValue: 'rzp_test_placeholder',
      );

  static const int paymentTimeoutSeconds = 60;
  static const double walletMinBalance = 12.0;
  static const double walletMinTopUp = 10.0;

  // ─── Booking ─────────────────────────────────────────────
  static const int jobAcceptTimeoutSeconds = 90;
  static const int bookingPollIntervalSeconds = 5;
  static const int maxRateUpdatesPerDay = 2;
  static const int movementCheckMinutes = 10;
  static const int reminderMinutes = 7;

  // ─── Branding ────────────────────────────────────────────
  static const String appName = 'Gixbee';
  static const String walletTopUpDescription = 'Wallet Top-up';
  static const String avatarBaseUrl = 'https://ui-avatars.com/api/';

  // ─── Build ───────────────────────────────────────────────
  static const String buildVersion = String.fromEnvironment(
    'BUILD_VERSION',
    defaultValue: 'dev',
  );
}
