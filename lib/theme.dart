import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ── Theme-aware surface + ink + shell accent tokens ─────────────────────────
///
/// The app was built dark-only: screens hard-coded `GixbeeTheme.cardSurface`
/// and `Colors.white`, so switching MaterialApp to a light scheme produced
/// white-on-white. These tokens are the fix — read them through
/// `context.gx.<token>` and they resolve per theme.
///
/// Rules of thumb when migrating a screen:
///   • page background            → context.gx.bg
///   • card / tile / sheet fill   → context.gx.card  (nested/raised: card2)
///   • hairline borders           → context.gx.border
///   • text + icons ON a surface  → context.gx.ink   (alpha variants OK:
///                                   context.gx.ink.withValues(alpha: .55))
///   • text/icons ON a coloured   → context.gx.onAccent  (stays white in both
///     button, gradient or chip     themes — do NOT use ink there)
///   • shell CTAs / nav selected  → context.gx.accent / accentGradient
///     (violet in Gixbee Dark, Grab green in light — NOT brand orange)
///
/// Auth + splash intentionally stay dark + brand-orange (`brandGradient`) for
/// wordmark identity — they do not follow Appearance / Grab Green.
///
/// `ink` is near-black in the Grab light theme, so every existing
/// `Colors.white.withValues(alpha: x)` becomes a correctly-toned grey simply
/// by swapping the base colour.
@immutable
class GxColors extends ThemeExtension<GxColors> {
  final Color bg;
  final Color card;
  final Color card2;
  final Color border;
  final Color ink;
  final Color onAccent;

  /// Shell primary (nav, default CTAs, focus rings).
  final Color accent;

  /// Softer sibling for chips / selected fills (violet-2 or Grab dark green).
  final Color accentSoft;

  /// Default filled-button / FAB gradient for shell chrome.
  final List<Color> accentGradient;

  const GxColors({
    required this.bg,
    required this.card,
    required this.card2,
    required this.border,
    required this.ink,
    required this.onAccent,
    required this.accent,
    required this.accentSoft,
    required this.accentGradient,
  });

  /// Gixbee Dark (default) — deep-void surfaces + violet shell accent.
  static const dark = GxColors(
    bg: Color(0xFF08080F),
    card: Color(0xFF111118),
    card2: Color(0xFF1A1A26),
    border: Color(0xFF1E1E2E),
    ink: Colors.white,
    onAccent: Colors.white,
    accent: Color(0xFF6C3FDB), // accentPurple
    accentSoft: Color(0xFF8B5CF6), // accentViolet
    accentGradient: [Color(0xFF6C3FDB), Color(0xFF8B5CF6)],
  );

  /// Grab-style light — soft grey canvas, white cards, Grab green shell.
  static const light = GxColors(
    bg: Color(0xFFF7F7F7),
    card: Colors.white,
    card2: Color(0xFFF1F3F2),
    border: Color(0xFFE3E6E4),
    ink: Color(0xFF1C1C1C),
    onAccent: Colors.white,
    accent: Color(0xFF00B14F), // grabGreen
    accentSoft: Color(0xFF009944), // grabGreenDark
    accentGradient: [Color(0xFF00B14F), Color(0xFF009944)],
  );

  @override
  GxColors copyWith({
    Color? bg,
    Color? card,
    Color? card2,
    Color? border,
    Color? ink,
    Color? onAccent,
    Color? accent,
    Color? accentSoft,
    List<Color>? accentGradient,
  }) =>
      GxColors(
        bg: bg ?? this.bg,
        card: card ?? this.card,
        card2: card2 ?? this.card2,
        border: border ?? this.border,
        ink: ink ?? this.ink,
        onAccent: onAccent ?? this.onAccent,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        accentGradient: accentGradient ?? this.accentGradient,
      );

  @override
  GxColors lerp(ThemeExtension<GxColors>? other, double t) {
    if (other is! GxColors) return this;
    return GxColors(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      card2: Color.lerp(card2, other.card2, t)!,
      border: Color.lerp(border, other.border, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentGradient: [
        Color.lerp(accentGradient[0], other.accentGradient[0], t)!,
        Color.lerp(
          accentGradient.length > 1 ? accentGradient[1] : accentGradient[0],
          other.accentGradient.length > 1
              ? other.accentGradient[1]
              : other.accentGradient[0],
          t,
        )!,
      ],
    );
  }
}

/// `context.gx.card`, `context.gx.accent`, …
extension GxColorsX on BuildContext {
  GxColors get gx =>
      Theme.of(this).extension<GxColors>() ?? GxColors.dark;

  /// True when the Grab light theme is active — for the rare case a widget
  /// needs a structurally different look (e.g. a glow that only reads on dark).
  bool get gxIsLight => Theme.of(this).brightness == Brightness.light;
}

class GixbeeTheme {
  // ── Gixbee brand (wordmark + auth only — not shell chrome) ──
  // Auth / splash stay dark + these oranges regardless of Appearance.
  static const Color brandOrange = Color(0xFFFF8C00); // logo start
  static const Color brandFlame = Color(0xFFFF4500); // logo mid
  static const Color brandRed = Color(0xFFE8173A); // logo end

  /// Wordmark / auth CTA gradient — do not use for main-app shell chrome.
  static const List<Color> brandGradient = [brandOrange, brandFlame, brandRed];

  // ── Mockup v106 violet shell (Gixbee Dark) — prefer context.gx.accent ──
  static const Color accentPurple = Color(0xFF6C3FDB); // --pu
  static const Color accentViolet = Color(0xFF8B5CF6); // --pu2
  static const List<Color> purpleGradient = [accentPurple, accentViolet];

  // Shared dark surfaces from the mockup tokens (prefer context.gx.*).
  static const Color cardSurface = Color(0xFF111118); // --cd
  static const Color cardSurface2 = Color(0xFF1A1A26); // --c2
  static const Color cardBorder = Color(0xFF1E1E2E); // --br

  // Functional / intent accents (product areas — not shell chrome).
  static const Color accentGreen = Color(0xFF10B981); // --gn
  static const Color accentGold = Color(0xFFF59E0B); // gold
  static const Color accentPink = Color(0xFFEC4899); // --pk
  static const Color accentBlue = Color(0xFF3B82F6); // --bl
  static const Color accentTeal = Color(0xFF14B8A6); // --tl

  // Legacy aliases — dark shell primary is violet (matches UI), not orange.
  static const Color primary = accentPurple;
  static const Color secondary = Color(0xFF2CB67D); // Neon Green
  static const Color tertiary = Color(0xFFFF8906); // Neon Orange
  static const Color background = Color(0xFF08080F); // Deep Void
  static const Color surface = Color(0xFF111118); // Card Surface
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color textHigh = Color(0xFFFFFFFE);
  static const Color textMed = Color(0xFF94A1B2);

  // ── Grab-style light palette (Profile → Appearance → "Grab Green") ──────
  static const Color grabGreen = Color(0xFF00B14F);
  static const Color grabGreenDark = Color(0xFF009944);
  static const List<Color> grabGradient = [grabGreen, grabGreenDark];
  static const Color grabScaffold = Color(0xFFF7F7F7);
  static const Color grabText = Color(0xFF1C1C1C);

  /// Light mode IS the Grab-style theme: white surfaces, Grab green accents,
  /// near-black text. Dynamic (Material You) colours are deliberately ignored
  /// so the branding stays consistent.
  static ThemeData lightTheme(ColorScheme? dynamicColor) {
    final grabScheme = ColorScheme.fromSeed(
      seedColor: grabGreen,
      brightness: Brightness.light,
    ).copyWith(
      primary: grabGreen,
      secondary: grabGreenDark,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: grabText,
      surfaceContainerHighest: const Color(0xFFEFF1F0),
      outlineVariant: const Color(0xFFE3E6E4),
    );

    final base = _buildTheme(grabScheme);
    return base.copyWith(
      scaffoldBackgroundColor: grabScaffold,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        foregroundColor: grabText,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: grabGreen,
          foregroundColor: Colors.white,
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: grabGreen,
        foregroundColor: Colors.white,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? grabGreen : null),
      ),
    );
  }

  static ThemeData darkTheme(ColorScheme? dynamicColor) {
    // Shell primary = violet (matches home/nav/CTAs). Brand orange is auth-only.
    final defaultScheme = ColorScheme.fromSeed(
      seedColor: accentPurple,
      brightness: Brightness.dark,
      surface: surface,
    );
    final colorScheme = (dynamicColor ?? defaultScheme).copyWith(
      primary: accentPurple,
      secondary: accentViolet,
      onPrimary: Colors.white,
      surface: background,
      surfaceContainerLowest: surface,
    );

    return _buildTheme(colorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final isLight = colorScheme.brightness == Brightness.light;
    final gx = isLight ? GxColors.light : GxColors.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,

      extensions: <ThemeExtension<dynamic>>[gx],
      scaffoldBackgroundColor: gx.bg,

      textTheme: TextTheme(
        displayLarge: GoogleFonts.roboto(
            fontSize: 57, fontWeight: FontWeight.bold, letterSpacing: -0.25),
        displayMedium: GoogleFonts.roboto(
            fontSize: 45, fontWeight: FontWeight.bold, letterSpacing: 0),
        displaySmall: GoogleFonts.roboto(
            fontSize: 36, fontWeight: FontWeight.w400, letterSpacing: 0),
        headlineLarge: GoogleFonts.roboto(
            fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 0),
        headlineMedium: GoogleFonts.roboto(
            fontSize: 28, fontWeight: FontWeight.w500, letterSpacing: 0),
        headlineSmall: GoogleFonts.roboto(
            fontSize: 24, fontWeight: FontWeight.w400, letterSpacing: 0),
        titleLarge: GoogleFonts.roboto(
            fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: 0),
        titleMedium: GoogleFonts.roboto(
            fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.15),
        titleSmall: GoogleFonts.roboto(
            fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        bodyLarge: GoogleFonts.roboto(
            fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
        bodyMedium: GoogleFonts.roboto(
            fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
        bodySmall: GoogleFonts.roboto(
            fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
        labelLarge: GoogleFonts.roboto(
            fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelMedium: GoogleFonts.roboto(
            fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
        labelSmall: GoogleFonts.roboto(
            fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 2,
      ),

      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: gx.accent,
        foregroundColor: gx.onAccent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        elevation: 1,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: gx.accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
                color: gx.accent, fontWeight: FontWeight.w600, fontSize: 12);
          }
          return TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: gx.accent, size: 24);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant, size: 24);
        }),
      ),
    );
  }
}
