import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';

/// Gixbee brand green (Grab-style) — the auth identity color.
const kAuthGreen = Color(0xFF00B14F);
const kAuthGreenDeep = Color(0xFF008D51);
const kAuthGreenGradient = [kAuthGreen, kAuthGreenDeep];

/// Theme-aware palette for the auth flow (splash / welcome / login / OTP).
///
/// The product default is Grab Light, so auth leads with the clean
/// white + grab-green look; users who explicitly chose Gixbee Dark get the
/// same green brand on the deep dark backdrop (the old orange-on-dark auth
/// chrome is retired).
class AuthPalette {
  final bool isLight;
  final Color bgTop;
  final Color bgBottom;
  final Color surface;
  final Color surfaceBorder;
  final Color ink;
  final Color sub;
  final Color faint;

  const AuthPalette._({
    required this.isLight,
    required this.bgTop,
    required this.bgBottom,
    required this.surface,
    required this.surfaceBorder,
    required this.ink,
    required this.sub,
    required this.faint,
  });

  static const light = AuthPalette._(
    isLight: true,
    bgTop: Color(0xFFE6F7EE),
    bgBottom: Colors.white,
    surface: Colors.white,
    surfaceBorder: Color(0xFFE2E8E4),
    ink: Color(0xFF10201A),
    sub: Color(0xB310201A),
    faint: Color(0x5910201A),
  );

  static const dark = AuthPalette._(
    isLight: false,
    bgTop: Color(0xFF04160D),
    bgBottom: GixbeeTheme.background,
    surface: Color(0xFF1A1A26),
    surfaceBorder: Color(0xFF2A2A3A),
    ink: Colors.white,
    sub: Color(0xB3FFFFFF),
    faint: Color(0x59FFFFFF),
  );

  static AuthPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? light : dark;
}

class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.55),
          radius: 1.2,
          colors: [p.bgTop, p.bgBottom],
          stops: const [0.0, 0.7],
        ),
      ),
      child: child,
    );
  }
}

class AuthWordmark extends StatelessWidget {
  const AuthWordmark({super.key, this.fontSize = 48});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: kAuthGreenGradient,
      ).createShader(bounds),
      child: Text(
        'gixbee',
        style: GoogleFonts.nunito(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          color: Colors.white, // masked by the green gradient
          height: 1.05,
        ),
      ),
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: kAuthGreenGradient),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: kAuthGreen.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed ?? () => Navigator.maybePop(context),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.surfaceBorder),
            boxShadow: p.isLight
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: p.ink,
            size: 18,
          ),
        ),
      ),
      ),
    );
  }
}

/// Soft fade + slight rise for welcome / login content.
class AuthEntrance extends StatelessWidget {
  const AuthEntrance({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
