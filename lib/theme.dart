import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GixbeeTheme {
  // Legacy Hardcoded Colors (kept as fallbacks)
  static const Color primary = Color(0xFF7F5AF0); // Neon Violet
  static const Color secondary = Color(0xFF2CB67D); // Neon Green
  static const Color tertiary = Color(0xFFFF8906); // Neon Orange
  static const Color background = Color(0xFF16161A); // Deep Void
  static const Color surface = Color(0xFF242629); // Card Surface
  static const Color glassBorder = Color(0x33FFFFFF); // Glass Border (20%)
  static const Color textHigh = Color(0xFFFFFFFE);
  static const Color textMed = Color(0xFF94A1B2);

  static ThemeData lightTheme(ColorScheme? dynamicColor) {
    // Determine the color scheme to use
    final defaultScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );
    final colorScheme = dynamicColor ?? defaultScheme;

    return _buildTheme(colorScheme);
  }

  static ThemeData darkTheme(ColorScheme? dynamicColor) {
    // Determine the color scheme to use
    final defaultScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: surface, // Use custom deep void background
    );
    // Even if dynamicColor is provided, we might want to ensure background is very dark for AMOLED
    final colorScheme = (dynamicColor ?? defaultScheme).copyWith(
      surface: background, // Note: using legacy background variable for consistent deep void
      surfaceContainerLowest: surface,
    );

    return _buildTheme(colorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      
      // Typography
      textTheme: TextTheme(
        displayLarge: GoogleFonts.roboto(fontSize: 57, fontWeight: FontWeight.bold, letterSpacing: -0.25),
        displayMedium: GoogleFonts.roboto(fontSize: 45, fontWeight: FontWeight.bold, letterSpacing: 0),
        displaySmall: GoogleFonts.roboto(fontSize: 36, fontWeight: FontWeight.w400, letterSpacing: 0),
        
        headlineLarge: GoogleFonts.roboto(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 0),
        headlineMedium: GoogleFonts.roboto(fontSize: 28, fontWeight: FontWeight.w500, letterSpacing: 0),
        headlineSmall: GoogleFonts.roboto(fontSize: 24, fontWeight: FontWeight.w400, letterSpacing: 0),
        
        titleLarge: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: 0),
        titleMedium: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.15),
        titleSmall: GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        
        bodyLarge: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
        bodyMedium: GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
        bodySmall: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
        
        labelLarge: GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelMedium: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
        labelSmall: GoogleFonts.roboto(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),

      // AppBar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 2, // Slight elevation when scrolling under
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 1, // M3 relies more on color mapping than hard drop shadows
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0, // Flat M3 buttons by default until pressed/hovered
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Input Decoration (Text Fields)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

      // Bottom Sheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        elevation: 1,
      ),

      // Navigation Bar (replaces BottomNavigationBar in M3)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 12);
          }
          return TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500, fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onSecondaryContainer, size: 24);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant, size: 24);
        }),
      ),
    );
  }
}
