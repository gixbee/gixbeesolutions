import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main_wrapper.dart';
import '../../repositories/auth_repository.dart';
import '../auth/auth_chrome.dart';
import 'welcome_screen.dart';

/// Branded splash — the gixbee HIVE.
///
/// Thematic motion: a honeycomb cluster glows to life behind the wordmark
/// while worker bees fly looping paths around it, wings buzzing — "every
/// worker finds work here." Pure CustomPainter (no Lottie, no image assets),
/// theme-aware via AuthPalette, ~60fps cheap.
///
/// Routing unchanged: ≈1.4s minimum show, auth resolves in parallel, then
/// fade to MainWrapper (authed) or WelcomeScreen (guest).
class AnimatedSplashScreen extends ConsumerStatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  ConsumerState<AnimatedSplashScreen> createState() =>
      _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends ConsumerState<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _world; // loops: bee flight + hive pulse
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _taglineFade;

  bool _leaving = false;

  /// Flight plans — lissajous loops around the wordmark. Tuned so paths
  /// interleave without synchronizing (different speed ratios + phases).
  static const List<_BeeFlight> _flights = [
    _BeeFlight(rx: 130, ry: 78, sx: 1, sy: 2, phase: 0.00, size: 24, dy: -30),
    _BeeFlight(rx: 150, ry: 95, sx: 2, sy: 3, phase: 0.35, size: 20, dy: -10),
    _BeeFlight(rx: 105, ry: 65, sx: 1, sy: 1, phase: 0.62, size: 22, dy: -55),
    _BeeFlight(rx: 165, ry: 70, sx: 3, sy: 2, phase: 0.18, size: 17, dy: 15),
    _BeeFlight(rx: 120, ry: 88, sx: 2, sy: 1, phase: 0.80, size: 19, dy: -40),
  ];

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _world = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _logoScale = Tween(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _logoFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _taglineFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );

    _intro.forward();
    _boot();
  }

  Future<void> _boot() async {
    final minShow = Future.delayed(const Duration(milliseconds: 1400));
    var authenticated = false;
    try {
      authenticated = await ref.read(authStateProvider.future);
    } catch (_) {
      authenticated = false;
    }
    await minShow;
    if (!mounted || _leaving) return;
    _leaving = true;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) =>
            authenticated ? const MainWrapper() : const WelcomeScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    _world.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);
    return Scaffold(
      backgroundColor: p.bgBottom,
      body: AuthBackdrop(
        child: LayoutBuilder(
          builder: (context, box) {
            final center = Offset(box.maxWidth / 2, box.maxHeight * 0.44);
            return AnimatedBuilder(
              animation: Listenable.merge([_intro, _world]),
              builder: (context, _) {
                final t = _world.value; // 0..1 over 10s, looping
                return Stack(
                  children: [
                    // ── Honeycomb waking up behind the brand ──
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _HivePainter(
                          center: center.translate(0, -8),
                          t: t,
                          intro: _intro.value,
                          isLight: p.isLight,
                        ),
                      ),
                    ),

                    // ── Brand ──
                    Positioned(
                      left: 0,
                      right: 0,
                      top: center.dy - 46,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FadeTransition(
                            opacity: _logoFade,
                            child: ScaleTransition(
                              scale: _logoScale,
                              child: const AuthWordmark(fontSize: 52),
                            ),
                          ),
                          const SizedBox(height: 14),
                          FadeTransition(
                            opacity: _taglineFade,
                            child: Text(
                              'Work · Hire · Rent · near you',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.4,
                                color: p.sub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── The workers: bees on looping flights ──
                    for (final f in _flights)
                      _positionedBee(f, center, t, p.isLight),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _positionedBee(
    _BeeFlight f,
    Offset center,
    double t,
    bool isLight,
  ) {
    final tt = t + f.phase;
    final pos = Offset(
      center.dx + f.rx * math.sin(2 * math.pi * f.sx * tt),
      center.dy + f.dy + f.ry * math.sin(2 * math.pi * f.sy * tt + 1.1),
    );
    // Heading from the path derivative so the bee flies nose-first.
    final vx = f.rx * f.sx * math.cos(2 * math.pi * f.sx * tt);
    final vy = f.ry * f.sy * math.cos(2 * math.pi * f.sy * tt + 1.1);
    var heading = math.atan2(vy, vx);
    // Keep bees upright-ish: flip instead of flying upside-down leftwards.
    final flip = vx < 0;
    if (flip) heading = heading + math.pi;

    // Wing buzz: high-frequency flap derived from world time (≈14 Hz).
    final flap = math.sin(2 * math.pi * 140 * t + f.phase * 7);

    // Bees fade in slightly after the wordmark so the brand lands first.
    final appear =
        Curves.easeOut.transform((_intro.value - 0.25).clamp(0, 0.75) / 0.75);

    return Positioned(
      left: pos.dx - f.size,
      top: pos.dy - f.size,
      child: Opacity(
        opacity: appear,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ(heading)
            ..scale(flip ? -1.0 : 1.0, 1.0),
          child: CustomPaint(
            size: Size(f.size * 2, f.size * 1.6),
            painter: _BeePainter(flap: flap, isLight: isLight),
          ),
        ),
      ),
    );
  }
}

/// Parameters of one bee's looping flight path.
class _BeeFlight {
  final double rx, ry; // loop radii
  final int sx, sy; // speed ratio (lissajous)
  final double phase;
  final double size;
  final double dy; // vertical offset of the loop centre
  const _BeeFlight({
    required this.rx,
    required this.ry,
    required this.sx,
    required this.sy,
    required this.phase,
    required this.size,
    required this.dy,
  });
}

/// Honeycomb cluster: one centre cell + a ring of six, stroked, each cell
/// glowing in sequence — the hive at work.
class _HivePainter extends CustomPainter {
  final Offset center;
  final double t;
  final double intro;
  final bool isLight;

  _HivePainter({
    required this.center,
    required this.t,
    required this.intro,
    required this.isLight,
  });

  static const _hexR = 34.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (intro <= 0.05) return;
    final amber = isLight ? const Color(0xFFE0A63C) : const Color(0xFFF2BD5A);

    // Centre cell + 6 neighbours (flat-top hex grid offsets).
    final d = _hexR * math.sqrt(3);
    final cells = <Offset>[
      Offset.zero,
      for (var i = 0; i < 6; i++)
        Offset(
          d * math.cos(math.pi / 6 + i * math.pi / 3),
          d * math.sin(math.pi / 6 + i * math.pi / 3),
        ),
    ];

    for (var i = 0; i < cells.length; i++) {
      // Staggered glow: each cell pulses on its own beat.
      final pulse =
          0.5 + 0.5 * math.sin(2 * math.pi * (t * 2.2) - i * 0.9);
      final alpha = intro * (0.10 + 0.16 * pulse);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = amber.withValues(alpha: alpha);

      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = amber.withValues(alpha: alpha * 0.22);

      final path = _hexPath(center + cells[i], _hexR - 3);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, paint);
    }
  }

  Path _hexPath(Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_HivePainter old) =>
      old.t != t || old.intro != intro || old.isLight != isLight;
}

/// A stylised worker bee, drawn facing right: amber body, dark stripes,
/// buzzing translucent wings ([flap] −1..1), little head and stinger.
class _BeePainter extends CustomPainter {
  final double flap;
  final bool isLight;

  _BeePainter({required this.flap, required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bodyC = Offset(w * 0.52, h * 0.60);
    final bodyW = w * 0.56;
    final bodyH = h * 0.42;

    final amber = const Color(0xFFF4B23E);
    final dark = const Color(0xFF33261A);
    final wingColor =
        (isLight ? Colors.white : Colors.white).withValues(alpha: 0.65);

    // ── Wings (behind the body, hinged near its top) ──
    final hinge = Offset(bodyC.dx - bodyW * 0.05, bodyC.dy - bodyH * 0.55);
    for (final dir in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(hinge.dx, hinge.dy);
      // Base spread ±0.55 rad, buzzing ±0.5 rad with the flap.
      canvas.rotate(dir * (0.55 + 0.50 * flap) - 0.35);
      final wing = Rect.fromCenter(
        center: Offset(0, -h * 0.24),
        width: w * 0.30,
        height: h * 0.52,
      );
      canvas.drawOval(
        wing,
        Paint()..color = wingColor,
      );
      canvas.drawOval(
        wing,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = dark.withValues(alpha: 0.15),
      );
      canvas.restore();
    }

    // ── Body ──
    final bodyRect = Rect.fromCenter(
      center: bodyC,
      width: bodyW,
      height: bodyH,
    );
    canvas.drawOval(bodyRect, Paint()..color = amber);

    // Stripes, clipped to the body oval.
    canvas.save();
    canvas.clipPath(Path()..addOval(bodyRect));
    final stripePaint = Paint()..color = dark;
    for (final fx in const [0.44, 0.64]) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(bodyRect.left + bodyRect.width * fx, bodyC.dy),
          width: bodyW * 0.13,
          height: bodyH,
        ),
        stripePaint,
      );
    }
    canvas.restore();

    // ── Head (right = nose-first) + eye ──
    final headC = Offset(bodyRect.right - 1, bodyC.dy - bodyH * 0.05);
    canvas.drawCircle(headC, bodyH * 0.30, Paint()..color = dark);
    canvas.drawCircle(
      headC.translate(bodyH * 0.10, -bodyH * 0.08),
      bodyH * 0.07,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );

    // ── Stinger ──
    final sting = Path()
      ..moveTo(bodyRect.left + 2, bodyC.dy - 2.5)
      ..lineTo(bodyRect.left - w * 0.10, bodyC.dy)
      ..lineTo(bodyRect.left + 2, bodyC.dy + 2.5)
      ..close();
    canvas.drawPath(sting, Paint()..color = dark);
  }

  @override
  bool shouldRepaint(_BeePainter old) =>
      old.flap != flap || old.isLight != isLight;
}
