import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/auth_chrome.dart';
import '../auth/login_screen.dart';

/// First guest screen after splash.
///
/// Redesigned from the old empty wordmark-plus-one-line layout: an animated
/// collage of service tiles up top (a new user instantly sees WHAT Gixbee
/// is), value pills, then the brand block and CTA. Pure widgets — no image
/// assets, no new dependencies — and theme-aware via AuthPalette.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _float;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    // One slow looping controller drives every tile's gentle float; each
    // tile applies its own phase offset so the motion feels organic.
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _enter.dispose();
    _float.dispose();
    super.dispose();
  }

  void _goLogin() {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);
    return Scaffold(
      backgroundColor: p.bgBottom,
      body: AuthBackdrop(
        child: SafeArea(
          child: AuthEntrance(
            animation: _enter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Hero: floating service tiles ──
                Expanded(child: _heroCollage(p)),

                // ── Brand + copy + CTA ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: AuthWordmark(fontSize: 44)),
                      const SizedBox(height: 14),
                      Text(
                        'Everything local,\nin one place.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.22,
                          color: p.ink,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _valuePills(p),
                      const SizedBox(height: 24),
                      AuthPrimaryButton(
                        label: 'Continue with phone',
                        onPressed: _goLogin,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'By continuing you agree to Gixbee\'s Terms & Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: p.faint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Hero collage ────────────────────────────────────────────────────────

  Widget _heroCollage(AuthPalette p) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // Positions as fractions of the hero area — tuned so the layout
        // scales across phone sizes without overlap.
        final tiles = <_TileSpec>[
          _TileSpec('AC Repair', Icons.ac_unit_rounded, 0.06, 0.10, -6, 0.00),
          _TileSpec('Electrician', Icons.electrical_services_rounded, 0.56,
              0.05, 5, 0.35),
          _TileSpec('Plumbing', Icons.plumbing_rounded, 0.10, 0.42, 4, 0.60),
          _TileSpec(
              'Cleaning', Icons.cleaning_services_rounded, 0.62, 0.38, -5, 0.20),
          _TileSpec('Painting', Icons.format_paint_rounded, 0.04, 0.72, 6, 0.80),
          _TileSpec('Carpenter', Icons.carpenter_rounded, 0.58, 0.70, -4, 0.50),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AnimatedBuilder(
            animation: _float,
            builder: (context, _) {
              final t = _float.value;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final s in tiles)
                    Positioned(
                      left: s.dx * w,
                      top: s.dy * h +
                          math.sin(2 * math.pi * (t + s.phase)) * 5,
                      child: Transform.rotate(
                        angle: s.tiltDeg * math.pi / 180,
                        child: _serviceTile(p, s.label, s.icon),
                      ),
                    ),
                  // Center anchor card — the product promise.
                  Positioned(
                    left: w * 0.5 - 105,
                    top: h * 0.40 +
                        math.sin(2 * math.pi * (t + 0.9)) * 4,
                    child: _anchorCard(p),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _serviceTile(AuthPalette p, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: p.isLight
                ? Colors.black.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: kAuthGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: kAuthGreenDeep),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _anchorCard(AuthPalette p) {
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: kAuthGreenGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kAuthGreen.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.bolt_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instant Help',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Verified pros in minutes',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _valuePills(AuthPalette p) {
    Widget pill(IconData icon, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: p.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: kAuthGreenDeep),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.sub,
                ),
              ),
            ],
          ),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        pill(Icons.flash_on_rounded, 'Book help'),
        pill(Icons.work_outline_rounded, 'Earn hourly'),
        pill(Icons.handshake_outlined, 'Hire talent'),
        pill(Icons.construction_rounded, 'Rent gear'),
      ],
    );
  }
}

class _TileSpec {
  final String label;
  final IconData icon;
  final double dx;
  final double dy;
  final double tiltDeg;
  final double phase;
  const _TileSpec(
      this.label, this.icon, this.dx, this.dy, this.tiltDeg, this.phase);
}
