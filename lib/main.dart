import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/crash_reporter.dart';
import 'theme.dart';
import 'core/config/app_config.dart';
import 'core/navigator_key.dart';
import 'core/plugins/default_plugins.dart';
import 'core/theme_provider.dart';
import 'features/onboarding/animated_splash_screen.dart';
import 'shared/widgets/location_required_host.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Fail-closed: a release APK without dart-define API/socket hosts would
    // silently talk to 127.0.0.1 on the phone ("Could not send code").
    AppConfig.assertReleaseNetworkConfig();

    // 1. Plugin registry (synchronous — must be first)
    registerDefaultPlugins();

    // 2. Global crash reporter — catches unhandled Flutter/Dart errors and
    //    POSTs them to /client-logs so they appear in the admin portal.
    CrashReporter.init();

    // 3. Firebase — must be initialized before any FCM or Firestore calls
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 4. Register FCM background handler as a top-level function BEFORE runApp().
    //    Flutter requires this to be registered here, not inside any class or widget.
    //    NotificationService.initialize() does NOT register this again.
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    debugPrint('GIXBEE_BUILD_VERSION: ${AppConfig.buildVersion}');

    // 5. Restore the saved Appearance BEFORE the first frame — otherwise the
    //    app boots in the default dark theme and visibly snaps to Grab Light a
    //    few hundred ms later. The read is a few ms; the splash isn't delayed.
    final initialTheme = await ThemeChoiceNotifier.restore();

    // 6. Start the app — all further init (permissions, channel, listeners)
    //    happens in main_wrapper._initNotifications() after login.
    runApp(ProviderScope(
      overrides: [initialThemeChoiceProvider.overrideWithValue(initialTheme)],
      child: const GixbeeApp(),
    ));
  } catch (e, st) {
    // Never leave a release install on a full black screen if boot fails
    // before runApp (missing dart-defines, Firebase init, etc.).
    debugPrint('Gixbee boot failed: $e\n$st');
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B0F),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gixbee failed to start',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$e',
                  style: const TextStyle(
                    color: Color(0xFFB8B8C0),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

/// Enables mouse/trackpad/stylus drag on every scrollable (Flutter web
/// defaults to touch-only, which froze the horizontal home strips).
class _GxScrollBehavior extends MaterialScrollBehavior {
  const _GxScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

class GixbeeApp extends ConsumerWidget {
  const GixbeeApp({super.key});

  /// Gixbee 2026 is a dark-first design — on wide windows (web/desktop)
  /// render inside a centered phone-width canvas so cards keep their
  /// intended proportions instead of stretching across the window.
  static Widget _phoneCanvas(BuildContext context, Widget? child) {
    if (child == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const maxW = 430.0;
        if (constraints.maxWidth <= 520) {
          return LocationRequiredHost(child: child);
        }
        final mq = MediaQuery.of(context);
        // Gutter follows the active theme — a hardcoded near-black frame
        // around a Grab-Light app read as "different theming" on web.
        final gutter = Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFE9ECEF)
            : const Color(0xFF050509);
        return ColoredBox(
          color: gutter,
          child: Center(
            child: SizedBox(
              width: maxW,
              height: constraints.maxHeight,
              child: MediaQuery(
                data: mq.copyWith(
                    size: Size(maxW, constraints.maxHeight)),
                child: LocationRequiredHost(child: child),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Appearance: Gixbee Dark (default) or the Grab-style light theme —
    // user-switchable in Profile → Appearance, persisted across restarts.
    final themeMode = ref.watch(themeModeProvider);
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: GixbeeTheme.lightTheme(lightDynamic),
          darkTheme: GixbeeTheme.darkTheme(darkDynamic),
          themeMode: themeMode,
          // Web/desktop: let the mouse drag horizontal strips (events,
          // deals, …) — Flutter web only enables touch drag by default.
          scrollBehavior: const _GxScrollBehavior(),
          builder: _phoneCanvas,
          // Branded opening animation (replaces the old bare spinner) —
          // resolves auth in parallel and fades into MainWrapper / Welcome.
          home: const AnimatedSplashScreen(),
        );
      },
    );
  }
}
