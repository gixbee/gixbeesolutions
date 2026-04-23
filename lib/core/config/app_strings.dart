/// Centralised UI string constants.
/// Prevents hardcoded labels scattered across widget code and
/// provides a single file for future i18n/l10n extraction.
class AppStrings {
  AppStrings._();

  // ─── FCM Notification Fallbacks ──────────────────────────
  static const String fcmDefaultTitle = 'New Job Request';
  static const String fcmDefaultBody = 'A customer requested your services.';

  // ─── Plugin Descriptions ─────────────────────────────────
  static const String jobsPluginDescription = 'Find and post hourly jobs';
  static const String rentalsPluginDescription = 'Manage rental items and bookings';
}
