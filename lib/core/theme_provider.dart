import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App appearance options (Profile → Appearance):
/// - gixbeeDark: the default Gixbee 2026 deep-void dark look
/// - grabLight: Grab-style light theme — white surfaces, Grab green accents
enum AppThemeChoice { gixbeeDark, grabLight }

const _kThemeKey = 'gx_theme_choice';
const _storage = FlutterSecureStorage();

class ThemeChoiceNotifier extends StateNotifier<AppThemeChoice> {
  ThemeChoiceNotifier() : super(AppThemeChoice.gixbeeDark) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _kThemeKey);
      if (raw == AppThemeChoice.grabLight.name) {
        state = AppThemeChoice.grabLight;
      }
    } catch (e) {
      debugPrint('Theme restore failed: $e');
    }
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

final themeChoiceProvider =
    StateNotifierProvider<ThemeChoiceNotifier, AppThemeChoice>(
        (ref) => ThemeChoiceNotifier());

/// ThemeMode derived from the choice — watched by MaterialApp in main.dart.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeChoiceProvider) == AppThemeChoice.grabLight
      ? ThemeMode.light
      : ThemeMode.dark;
});
