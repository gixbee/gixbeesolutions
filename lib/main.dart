import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dynamic_color/dynamic_color.dart';
// import 'package:supabase_flutter/supabase_flutter.dart'; // Removed Supabase dependency
// import 'firebase_options.dart';
import 'theme.dart';
import 'core/theme_provider.dart';
import 'core/config/app_config.dart';
import 'core/plugins/default_plugins.dart';
import 'features/onboarding/welcome_screen.dart';
import 'main_wrapper.dart';
import 'repositories/auth_repository.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 3. Plugin registry
  registerDefaultPlugins();

  debugPrint('GIXBEE_BUILD_VERSION: ${AppConfig.buildVersion}');

  runApp(const ProviderScope(child: GixbeeApp()));
}

class GixbeeApp extends ConsumerWidget {
  const GixbeeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final authState = ref.watch(authStateProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: GixbeeTheme.lightTheme(lightDynamic),
          darkTheme: GixbeeTheme.darkTheme(darkDynamic),
          themeMode: themeMode,
          home: authState.when(
            data: (isAuthenticated) =>
                isAuthenticated ? const MainWrapper() : const WelcomeScreen(),
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const WelcomeScreen(),
          ),
        );
      },
    );
  }
}
