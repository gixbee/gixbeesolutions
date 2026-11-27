import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ─── API / Network ───────────────────────────────────────
  // Defaults are loopback for local `flutter run` only. Release / profile
  // builds MUST pass real hosts via --dart-define (see assertReleaseNetworkConfig).
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

  /// True when [url] targets the device/emulator itself (or is unparseable).
  /// Used to refuse shipping an APK that can never reach the production API.
  static bool isLoopbackUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return true;
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host == '10.0.2.2'; // Android emulator → host machine
  }

  /// True when [url] uses cleartext `http:` (not `https:`).
  static bool isCleartextUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.isEmpty) return true;
    return uri.scheme.toLowerCase() == 'http';
  }

  /// Transitional MilesWeb escape hatch until TLS cutover
  /// (`docs/architecture/HTTPS_ROLLOUT.md`). Prefer HTTPS release builds.
  static bool get allowCleartextApi =>
      const bool.fromEnvironment('ALLOW_CLEARTEXT_API', defaultValue: false);

  /// Fail-closed for release/profile when API/socket URL is still loopback
  /// or cleartext HTTP. Debug `flutter run` keeps local HTTP working.
  ///
  /// Missing Razorpay is NOT a boot killer: it only breaks period-fee /
  /// top-up checkouts. We warn instead; payment screens surface their own
  /// errors when the key is still the placeholder.
  ///
  /// [isRelease] is overridable for unit tests; production callers omit it.
  static void assertReleaseNetworkConfig({bool? isRelease}) {
    final release = isRelease ?? (kReleaseMode || kProfileMode);
    if (!release) return;

    if (isLoopbackUrl(baseUrl) || isLoopbackUrl(socketUrl)) {
      throw StateError(
        'Release build refused to start: API_BASE_URL / SOCKET_URL must not '
        'be loopback (got API_BASE_URL=$baseUrl, SOCKET_URL=$socketUrl).\n'
        'Rebuild with --dart-define=API_BASE_URL=https://… '
        '--dart-define=SOCKET_URL=https://… '
        '(see build_apk.bat / gixbee_keys.bat).',
      );
    }

    if (!allowCleartextApi &&
        (isCleartextUrl(baseUrl) || isCleartextUrl(socketUrl))) {
      throw StateError(
        'Release build refused to start: API_BASE_URL / SOCKET_URL must use '
        'HTTPS (got API_BASE_URL=$baseUrl, SOCKET_URL=$socketUrl).\n'
        'Point DNS at the MilesWeb TLS terminator and rebuild with '
        '--dart-define=API_BASE_URL=https://api.your-domain… '
        '--dart-define=SOCKET_URL=https://api.your-domain…\n'
        'Until TLS is live, transitional MilesWeb APKs may pass '
        '--dart-define=ALLOW_CLEARTEXT_API=true.',
      );
    }

    if (razorpayKey.trim().isEmpty ||
        razorpayKey == 'rzp_test_placeholder') {
      debugPrint(
        '[AppConfig] RAZORPAY_KEY is unset/placeholder — period-fee and '
        'wallet top-up checkouts will fail until rebuilt with '
        '--dart-define=RAZORPAY_KEY=rzp_…',
      );
    }
  }

  static const int httpTimeoutSeconds = 15;

  // ─── Ola Maps (tiles + directions) ───────────────────────
  // Build with: flutter run --dart-define=OLA_MAPS_API_KEY=xxxx
  // Empty key → tracking screen shows a graceful "map unavailable" panel
  // (status/OTP logic keeps working) and skips Directions calls.
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
  /// Fast HTTP fallback when the socket is down.
  static const int bookingPollIntervalSeconds = 5;
  /// Slow HTTP fallback while Socket.IO is connected (push is primary).
  static const int bookingPollBackoffSeconds = 30;
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
