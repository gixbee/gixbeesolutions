import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App appearance options (Profile → Appearance):
/// - gixbeeDark: the default Gixbee 2026 deep-void dark look
/// - grabLight: Grab-style light theme — white surfaces, Grab green accents
enum AppThemeChoice { gixbeeDark, grabLight }

const _kThemeKey = 'gx_theme_choice';
const _storage = FlutterSecureStorage();

class ThemeChoiceNotifier extends StateNotifier<AppThemeChoice> {
  /// The initial value is resolved BEFORE runApp (see main.dart) and injected
  /// via [initialThemeChoiceProvider] — the old async restore-in-constructor
  /// made every cold start render dark first and SNAP to Grab Light a few
  /// hundred ms later (the "first page looks different" flicker).
  ThemeChoiceNotifier(super.initial);

  /// Read the persisted choice. Called once in main() before the first frame.
  static Future<AppThemeChoice> restore() async {
    try {
      final raw = await _storage.read(key: _kThemeKey);
      if (raw == AppThemeChoice.grabLight.name) {
        return AppThemeChoice.grabLight;
      }
    } catch (e) {
      debugPrint('Theme restore failed: $e');
    }
    return AppThemeChoice.gixbeeDark;
  }

  Future<void> set(AppThemeChoice choice) async {
    state = choice;
    try {
      await _storage.write(key: _kThemeKey, value: choice.name);
    } catch (e) {
      debugPrint('Theme persist failed: $e');
    }
  }
}

/// Overridden in main() with the value restored from secure storage, so the
/// very first frame already wears the user's chosen theme.
final initialThemeChoiceProvider =
    Provider<AppThemeChoice>((_) => AppThemeChoice.gixbeeDark);

final themeChoiceProvider =
    StateNotifierProvider<ThemeChoiceNotifier, AppThemeChoice>(
        (ref) => ThemeChoiceNotifier(ref.watch(initialThemeChoiceProvider)));

/// ThemeMode derived from the choice — watched by MaterialApp in main.dart.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeChoiceProvider) == AppThemeChoice.grabLight
      ? ThemeMode.light
      : ThemeMode.dark;
});
