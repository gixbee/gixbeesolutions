import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'auth_chrome.dart';
import 'otp_screen.dart';

/// Phone sign-in — standard layout: back, brand, title, phone field, CTA.
/// Dark + brand-orange regardless of Profile → Appearance.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _enter;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _phoneController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    var phone = _phoneController.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (!phone.startsWith('+')) {
      phone = '${AppConfig.defaultCountryCode}$phone';
    }
    if (phone.length < AppConfig.phoneMinLength) {
      showGxSnack(context, 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() => _isSending = true);
    try {
      final devOtp =
          await ref.read(authRepositoryProvider).signInWithPhone(phone);
      if (!mounted) return;

      if (kDebugMode && devOtp != null) {
        showGxSnack(
          context,
          'Dev OTP: $devOtp',
          type: GxSnackType.success,
          duration: const Duration(seconds: 6),
        );
      }

      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => OtpScreen(
            phone: phone,
            initialOtp: kDebugMode ? devOtp : null,
          ),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Could not send code. Try again.',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GixbeeTheme.background,
      body: AuthBackdrop(
        child: SafeArea(
          child: AuthEntrance(
            animation: _enter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthBackButton(),
                  const SizedBox(height: 28),
                  const AuthWordmark(fontSize: 36),
                  const SizedBox(height: 28),
                  Text(
                    'Sign in',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We’ll text you a one-time code. New numbers are registered automatically.',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _phoneField(),
                  if (kDebugMode) ...[
                    const SizedBox(height: 14),
                    _devBanner(),
                  ],
                  const Spacer(),
                  AuthPrimaryButton(
                    label: 'Send code',
                    loading: _isSending,
                    onPressed: _sendCode,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Standard SMS rates may apply.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.32),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focusNode.hasFocus
              ? GixbeeTheme.brandOrange
              : const Color(0xFF2A2A3A),
          width: _focusNode.hasFocus ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: _phoneController,
        focusNode: _focusNode,
        autofocus: true,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _sendCode(),
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: '98765 43210',
          prefixText: '${AppConfig.defaultCountryCode}  ',
          prefixStyle: GoogleFonts.outfit(
            color: GixbeeTheme.brandOrange,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          hintStyle: GoogleFonts.outfit(
            color: Colors.white.withValues(alpha: 0.28),
          ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: const Icon(
            Icons.phone_iphone_rounded,
            color: GixbeeTheme.brandOrange,
          ),
        ),
      ),
    );
  }

  Widget _devBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GixbeeTheme.brandOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: GixbeeTheme.brandOrange.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bug_report_outlined,
            size: 16,
            color: GixbeeTheme.brandOrange.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Debug build — OTP may be echoed when ALLOW_OTP_ECHO is on.',
              style: GoogleFonts.outfit(
                color: GixbeeTheme.brandOrange.withValues(alpha: 0.95),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
