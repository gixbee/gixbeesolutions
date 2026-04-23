import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../features/auth/login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  // Premium gold accent color
  static const Color _gold = Color(0xFFD4A843);
  static const Color _goldMuted = Color(0x99C9A84C);
  static const Color _bgTop = Color(0xFF080C14);
  static const Color _bgBottom = Color(0xFF0E1420);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              children: [
                const Spacer(flex: 3),

                // ── LOGO with golden glow ring ──
                _buildLogoSection(),

                const SizedBox(height: 48),

                // ── TITLE ──
                Text(
                  'Gixbee',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.95),
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 300.ms, duration: 600.ms).slideY(begin: 0.15, end: 0),

                const SizedBox(height: 16),

                // ── Gold divider line ──
                Container(
                  width: 40,
                  height: 2,
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ).animate().fadeIn(delay: 500.ms, duration: 400.ms).scaleX(begin: 0, end: 1),

                const SizedBox(height: 20),

                // ── TAGLINE ──
                Text(
                  'THE  ARCHITECTURE  OF  TALENT',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _gold,
                    letterSpacing: 5.0,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

                const Spacer(flex: 4),

                // ── CTA BUTTON ──
                _buildSignInButton(context),

                const SizedBox(height: 20),

                // ── Footer text ──
                Text(
                  'PREMIUM EXECUTIVE ACCESS',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: _goldMuted,
                    letterSpacing: 3.5,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 1000.ms, duration: 500.ms),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Center(
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer golden glow
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _gold.withValues(alpha: 0.12),
                    _gold.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                  stops: const [0.4, 0.7, 1.0],
                ),
              ),
            ),

            // Subtle ring
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _gold.withValues(alpha: 0.2),
                  width: 1.0,
                ),
              ),
            ),

            // Inner dark circle with icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF151B28),
                border: Border.all(
                  color: _gold.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.15),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.hub_rounded,
                size: 40,
                color: _gold,
              ),
            ),
          ],
        ),
      ),
    ).animate()
        .scale(duration: 700.ms, curve: Curves.easeOutBack)
        .fadeIn(duration: 500.ms);
  }

  Widget _buildSignInButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const LoginScreen(),
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _gold, width: 1.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent,
        ),
        child: Text(
          'SIGN IN / REGISTER',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 3.0,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 800.ms, duration: 500.ms).slideY(begin: 0.3, end: 0);
  }
}
