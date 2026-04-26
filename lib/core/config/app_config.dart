import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ─── API / Network ───────────────────────────────────────
  static String get baseUrl => const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://10.0.2.2:3000',
      );

  static String get socketUrl => const String.fromEnvironment(
        'SOCKET_URL',
        defaultValue:
            kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000',
      );

  static const int httpTimeoutSeconds = 15;

  // ─── Supabase ────────────────────────────────────────────
  static String get supabaseUrl => const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: '',
      );

  static String get supabaseAnonKey => const String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: '',
      );

  // ─── Auth / OTP ──────────────────────────────────────────
  static const int otpLength = 6;
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
  static const int bookingPollIntervalSeconds = 3;
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
