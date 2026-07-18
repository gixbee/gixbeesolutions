import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main_wrapper.dart';
import '../../repositories/auth_repository.dart';
import '../../theme.dart';
import '../auth/auth_chrome.dart';
import 'welcome_screen.dart';

/// Standard branded splash: logo fades/scales in, short pause, then routes
/// to MainWrapper (authed) or WelcomeScreen (guest).
///
/// Timing stays short (≈1.4s min). Auth resolves in parallel.
/// Always dark + brand-orange — does not follow Appearance / Grab Green.
class AnimatedSplashScreen extends ConsumerStatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  ConsumerState<AnimatedSplashScreen> createState() =>
      _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends ConsumerState<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _taglineFade;

  bool _leaving = false;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GixbeeTheme.background,
      body: AuthBackdrop(
        child: AnimatedBuilder(
          animation: _intro,
          builder: (context, _) {
            return Center(
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
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: _taglineFade,
                    child: Text(
                      'Work · Hire · Rent · near you',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
